#!/usr/bin/env python3
"""
Regenerate broken Bioconductor main.nf step blocks using an LLM + rule hybrid.

A "broken" file is one where trim_code() cut a code block mid-expression,
leaving unclosed parentheses/brackets in the R script section.

Pipeline per package:
  1. (Rules) Load vignette from local cache or fetch from Bioconductor
  2. (Rules) Parse code blocks using multi-format extractor
  3. (LLM)   Generate 3-6 complete, syntactically valid step blocks
  4. (Validate) Check bracket balance; write back only if all steps pass

Usage:
    cd /path/to/biomate
    python3 backend/scripts/regenerate_broken_bioc_llm.py \
        [--vignette-dir /path/to/local/vignette/cache] \
        [--model claude-haiku-4-5-20251001] \
        [--batch-size 5] \
        [--workers 4] \
        [--dry-run] \
        [--limit N] \
        [--pkg PKGNAME] \
        [--only-broken]

Environment:
    ANTHROPIC_API_KEY   Required for LLM calls

Local vignette cache layout (--vignette-dir):
    <dir>/<pkg>.R          Compiled R vignette (.R from knitr/Rmd)
    <dir>/<pkg>.html       HTML vignette (fallback)
    <dir>/<pkg>/<any>.R    Alternative layout
"""

from __future__ import annotations

import json
import os
import re
import sys
import time
import urllib.request
import urllib.error
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import Optional

sys.path.insert(0, str(Path(__file__).resolve().parent))
try:
    from fix_bioc_versions_heredoc import sanitize_text as _sanitize_versions
except Exception:                                  # pragma: no cover
    def _sanitize_versions(t):  # noqa: E704 - no-op fallback
        return t

# ── Paths ─────────────────────────────────────────────────────────────────────

BIOC_DIR = Path(__file__).resolve().parents[1] / \
    "biomni_workflows/nextflow_nfcore/subworkflows/bioconductor"

# ── Config ─────────────────────────────────────────────────────────────────────

DEFAULT_MODEL   = os.environ.get("REGEN_MODEL", "claude-haiku-4-5-20251001")
DEFAULT_BATCH   = int(os.environ.get("REGEN_BATCH_SIZE", "5"))
DEFAULT_WORKERS = int(os.environ.get("REGEN_WORKERS", "4"))
MAX_VIGNETTE_CHARS = 6000   # max chars of vignette code fed to LLM per package

# ── Bracket-balance helpers ────────────────────────────────────────────────────

def net_depth(text: str) -> int:
    return (text.count("(") + text.count("[") + text.count("{")
          - text.count(")") - text.count("]") - text.count("}"))


def is_balanced(code: str) -> bool:
    """Return True if all bracket types are balanced in code."""
    depth = 0
    for line in code.split("\n"):
        depth += net_depth(line)
        if depth < 0:
            return False
    return depth == 0


# ── Vignette fetching ──────────────────────────────────────────────────────────

def fetch_url(url: str, retries: int = 3) -> Optional[str]:
    headers = {"User-Agent": "Mozilla/5.0 BioMate-KB/1.0"}
    for _ in range(retries):
        try:
            req = urllib.request.Request(url, headers=headers)
            with urllib.request.urlopen(req, timeout=20) as resp:
                raw = resp.read()
                try:
                    return raw.decode("utf-8")
                except UnicodeDecodeError:
                    return raw.decode("latin-1")
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return None
            time.sleep(1)
        except Exception:
            time.sleep(1)
    return None


def load_vignette_local(pkg: str, vignette_dir: Optional[Path]) -> Optional[str]:
    """Try to load vignette from local cache directory."""
    if not vignette_dir or not vignette_dir.exists():
        return None
    candidates = [
        vignette_dir / f"{pkg}.R",
        vignette_dir / f"{pkg}.html",
        vignette_dir / pkg / f"{pkg}.R",
        vignette_dir / pkg / "vignette.R",
        vignette_dir / pkg / "index.html",
    ]
    # Also try any .R file in a pkg subdirectory
    pkg_dir = vignette_dir / pkg
    if pkg_dir.is_dir():
        for f in pkg_dir.glob("*.R"):
            candidates.append(f)
    for c in candidates:
        if c.exists():
            try:
                return c.read_text(encoding="utf-8", errors="replace")
            except Exception:
                pass
    return None


def fetch_vignette_remote(pkg: str, source_url: str) -> Optional[str]:
    """Fetch vignette from Bioconductor using source URL or discovery."""
    # Try the exact URL from the file first
    if source_url:
        text = fetch_url(source_url)
        if text and len(text) > 100:
            return text

    # Try common URL patterns
    pkg_canonical = source_url.split("/")[8] if len(source_url.split("/")) > 8 else pkg
    base = f"https://bioconductor.org/packages/3.20/bioc/vignettes/{pkg_canonical}/inst/doc/"
    for name in [pkg_canonical, pkg, f"{pkg_canonical}Vignette", "vignette", "introduction"]:
        for ext in [".R", ".html"]:
            text = fetch_url(f"{base}{name}{ext}")
            if text and len(text) > 100:
                return text
    return None


# ── Code block extraction (multi-format) ──────────────────────────────────────

def extract_r_blocks(text: str) -> list[tuple[str, str]]:
    """
    Extract (name, code) pairs from a vignette in any format:
      - Compiled Rmd  (## ----name,opts----)
      - Classic Rnw   (### code chunk number N: name)
      - HTML vignette (<pre><code> blocks)
      - Fallback      (## == headings)

    Returns list of (name, code) tuples, longest/most-informative first.
    """
    # Strip HTML entities first
    text = (text.replace("&lt;", "<").replace("&gt;", ">")
                .replace("&amp;", "&").replace("&quot;", '"')
                .replace("&#39;", "'"))

    # ── Format 1: Compiled Rmd (## ----name,...)
    rmd_pat = re.compile(r'^## ----([^,\n-][^\n-]*?)(?:,.*?)?-{3,}\s*$', re.MULTILINE)
    if rmd_pat.search(text):
        parts = rmd_pat.split(text)
        chunks = []
        for i in range(1, len(parts) - 1, 2):
            name = parts[i].strip()
            code = parts[i + 1].strip()
            if code:
                chunks.append((name, code))
        if chunks:
            return chunks

    # ── Format 2: Classic Rnw (### code chunk number N: name)
    if "code chunk number" in text:
        sep = re.compile(r'^#{3,}\s*$', re.MULTILINE)
        sections = sep.split(text)
        chunks = []
        i = 0
        while i < len(sections) - 1:
            sec = sections[i].strip()
            m = re.match(r'^#{2,4}\s+(?:code chunk number \d+:\s*)?(\w+)\s*$', sec)
            if m:
                code = sections[i + 1].strip()
                if code:
                    chunks.append((m.group(1), code))
                i += 2
            else:
                i += 1
        if chunks:
            return chunks

    # ── Format 3: HTML <pre><code> blocks
    if "<pre" in text or "<code" in text:
        blocks = re.findall(
            r'<pre[^>]*><code[^>]*>(.*?)</code></pre>', text, re.DOTALL)
        if not blocks:
            blocks = re.findall(r'<pre[^>]*>(.*?)</pre>', text, re.DOTALL)
        chunks = []
        for i, block in enumerate(blocks):
            code = re.sub(r'<[^>]+>', '', block).strip()
            lines = [l for l in code.split('\n')
                     if l.strip() and not re.match(r'^#+\s*\[', l.strip())]
            if lines and len('\n'.join(lines)) > 20:
                chunks.append((f"block_{i+1}", '\n'.join(lines)))
        if chunks:
            return chunks

    # ── Fallback: ## == headings
    lines = text.split("\n")
    current_name, current_code = "main", []
    chunks = []
    for line in lines:
        m = re.match(r'^##\s*[-=]+\s*(.+?)\s*[-=]*\s*$', line)
        if m:
            if current_code:
                chunks.append((current_name, "\n".join(current_code).strip()))
            current_name = m.group(1).strip()
            current_code = []
        else:
            current_code.append(line)
    if current_code:
        chunks.append((current_name, "\n".join(current_code).strip()))
    return chunks


# ── Noise filtering ────────────────────────────────────────────────────────────

SKIP_CODE_PATS = [
    r'^library\(\w+\)\s*$', r'^require\(\w+\)\s*$',
    r'BiocManager::install', r'knitr::opts_chunk',
    r'^suppressMessages', r'^suppressWarnings',
    r'^set\.seed', r'sessionInfo\(\)', r'options\(width',
]

def is_trivial_block(code: str) -> bool:
    lines = [l for l in code.strip().split("\n")
             if l.strip() and not l.strip().startswith("#")]
    if not lines:
        return True
    substantive = [l for l in lines
                   if not any(re.search(p, l) for p in SKIP_CODE_PATS)]
    if not substantive:
        return True
    if all(re.match(r'(?:library|require)\s*\(', l.strip()) for l in lines):
        return True
    return False


# ── Broken-file detection ──────────────────────────────────────────────────────

def is_broken(nf_path: Path) -> bool:
    """Return True if the script section has unbalanced brackets."""
    content = nf_path.read_text()
    m = re.search(r'#!/usr/bin/env Rscript\n(.*?)# --- Save outputs ---',
                  content, re.DOTALL)
    if not m:
        return False
    script = m.group(1)
    return (script.count("(") + script.count("[") + script.count("{")
          > script.count(")") + script.count("]") + script.count("}"))


# ── LLM call (Anthropic) ───────────────────────────────────────────────────────

def call_anthropic(prompt: str, model: str) -> Optional[str]:
    """Call Anthropic Messages API. Returns response text or None."""
    api_key = os.environ.get("ANTHROPIC_API_KEY", "")
    if not api_key:
        raise RuntimeError("ANTHROPIC_API_KEY not set")

    import json as _json
    payload = _json.dumps({
        "model": model,
        "max_tokens": 4096,
        "messages": [{"role": "user", "content": prompt}],
    }).encode()

    req = urllib.request.Request(
        "https://api.anthropic.com/v1/messages",
        data=payload,
        headers={
            "Content-Type": "application/json",
            "x-api-key": api_key,
            "anthropic-version": "2023-06-01",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            data = _json.loads(resp.read())
            return data["content"][0]["text"]
    except urllib.error.HTTPError as e:
        body = e.read().decode()
        print(f"    [LLM error {e.code}] {body[:200]}", file=sys.stderr)
        return None
    except Exception as e:
        print(f"    [LLM error] {e}", file=sys.stderr)
        return None


# ── LLM prompt + response parsing ─────────────────────────────────────────────

BATCH_PROMPT_TEMPLATE = """\
You are a Bioconductor expert writing R code stubs for Nextflow workflow wrappers.

I will give you a batch of Bioconductor packages. For each, write 3-6 workflow step \
blocks in a strict format (see below). Each block must be syntactically complete, \
valid R code — never end a block mid-expression (unclosed parenthesis, bracket, or brace).

FORMAT FOR EACH PACKAGE:
<<<PKG:{{pkg_id}}>>>
    # --- {{Step Name}} [] ---
    # Key functions: fn1, fn2, fn3
    <complete R code — 5-15 lines, all expressions closed>

    # --- {{Step Name 2}} [] ---
    # Key functions: fn4, fn5
    <complete R code>

[repeat for all steps, then end with:]
<<<END:{{pkg_id}}>>>

RULES:
- Every parenthesis opened must be closed WITHIN the same step block.
- Use only functions from the package (not base R noise like print/cat/library).
- Step names must be human-readable biology (e.g. "Normalisation", "Differential Expression",
  "Visualisation") — NOT raw chunk IDs like "R-001" or "block_3".
- Key functions: list up to 5 real function names from the package that the code uses.
- Code lines: indent with 4 spaces. Trim long arguments to keep lines under 80 chars.
- Do NOT include library() calls, set.seed(), sessionInfo(), or install.packages().
- Do NOT output anything outside the <<<PKG:...>>> ... <<<END:...>>> delimiters.
- Replace {{pkg_id}} with the actual package name, {{Step Name}} with a real step name.

PACKAGES IN THIS BATCH:
{packages_block}
"""

PKG_BLOCK_TEMPLATE = """\
--- Package: {pkg} ---
Description: {description}
Vignette code excerpts (raw, may be incomplete — you must fix any broken expressions):
{code_excerpt}
"""


def build_prompt(batch: list[dict]) -> str:
    packages_block = "\n\n".join(
        PKG_BLOCK_TEMPLATE.format(
            pkg=item["pkg"],
            description=item["description"],
            code_excerpt=item["code_excerpt"],
        )
        for item in batch
    )
    return BATCH_PROMPT_TEMPLATE.format(packages_block=packages_block)


def parse_llm_response(response: str) -> dict[str, list[str]]:
    """
    Parse LLM output into {pkg_id: [step_block_text, ...]} dict.
    Each step_block_text is the raw indented lines for one step.
    """
    result: dict[str, list[str]] = {}
    pkg_blocks = re.findall(
        r'<<<PKG:(\S+?)>>>(.*?)<<<END:\1>>>',
        response, re.DOTALL
    )
    for pkg_id, body in pkg_blocks:
        # Split body into step blocks at # --- Name [] ---
        step_pat = re.compile(
            r'(    # --- .+ \[\] ---\n    # Key functions: [^\n]+\n)',
            re.MULTILINE
        )
        parts = step_pat.split(body.strip())
        steps = []
        i = 1
        while i < len(parts) - 1:
            header = parts[i]
            code   = parts[i + 1] if i + 1 < len(parts) else ""
            steps.append(header + code)
            i += 2
        if steps:
            result[pkg_id] = steps
    return result


def validate_steps(steps: list[str]) -> tuple[bool, str]:
    """
    Validate a list of step block strings.
    Returns (ok, reason).
    """
    if not steps:
        return False, "no steps generated"
    for i, step in enumerate(steps):
        if not is_balanced(step):
            return False, f"step {i+1} has unbalanced brackets"
        if not re.search(r'\b[a-zA-Z][a-zA-Z0-9_.]+\s*\(', step):
            return False, f"step {i+1} has no function calls"
    return True, "ok"


# ── main.nf rewriting ──────────────────────────────────────────────────────────

def rewrite_main_nf(pkg: str, steps: list[str]) -> bool:
    """
    Replace the script body in main.nf with the new step blocks.
    Returns True on success.
    """
    nf_path = BIOC_DIR / pkg / "main.nf"
    content = nf_path.read_text()

    script_start = re.search(r'\n\s*"""\s*\n\s*#!/usr/bin/env Rscript', content)
    save_m = re.search(r'\n    # --- Save outputs ---', content)
    if not script_start or not save_m:
        return False

    # Get the library lines (preserve from original)
    lib_m = re.search(r'(    library\([^\n]+\)\n(?:    library\([^\n]+\)\n)*)',
                      content[script_start.end():save_m.start()])
    lib_lines = lib_m.group(1) if lib_m else "    library(jsonlite)\n"
    # Ensure the package's own library() is included
    install_m = re.search(r'BiocManager::install\("([^"]+)"\)', content)
    pkg_canonical = install_m.group(1) if install_m else pkg
    if f"library({pkg_canonical})" not in lib_lines:
        lib_lines = f"    library({pkg_canonical})\n" + lib_lines

    new_body = "\n" + lib_lines + "\n" + "\n".join(steps) + "\n"
    new_content = (content[:script_start.end()]
                   + new_body
                   + content[save_m.start():])

    # Never leave a bash versions.yml heredoc inside the Rscript block (R-evaluated -> crash).
    new_content = _sanitize_versions(new_content)
    nf_path.write_text(new_content)
    return True


# ── Package context builder ────────────────────────────────────────────────────

def build_pkg_context(
    pkg: str,
    vignette_dir: Optional[Path],
    max_chars: int = MAX_VIGNETTE_CHARS,
) -> dict:
    """
    Build the context dict for one package to include in the LLM prompt.
    Returns {"pkg", "description", "code_excerpt"}.
    """
    nf_path = BIOC_DIR / pkg / "main.nf"
    content = nf_path.read_text()

    # Extract description from header comment (// line 4-ish)
    desc_m = re.search(r"// '([^']+)'", content)
    if not desc_m:
        desc_m = re.search(r'// (\w[^\n]{10,80})', content)
    description = desc_m.group(1)[:200] if desc_m else pkg

    # Source URL
    url_m = re.search(r'// Source\s*:\s*(https?://\S+)', content)
    source_url = url_m.group(1) if url_m else ""

    # Load vignette
    vignette_text = load_vignette_local(pkg, vignette_dir)
    if not vignette_text:
        vignette_text = fetch_vignette_remote(pkg, source_url)
        if vignette_text:
            time.sleep(0.3)  # be polite to Bioconductor

    if not vignette_text:
        # Fall back to the existing (broken) code as context
        m = re.search(r'#!/usr/bin/env Rscript\n(.*?)# --- Save outputs ---',
                      content, re.DOTALL)
        vignette_text = m.group(1) if m else ""

    # Extract code blocks
    blocks = extract_r_blocks(vignette_text)
    # Filter trivial blocks
    blocks = [(name, code) for name, code in blocks if not is_trivial_block(code)]

    # Concatenate up to max_chars, keeping complete blocks
    code_excerpt = ""
    for name, code in blocks:
        snippet = f"# chunk: {name}\n{code}\n\n"
        if len(code_excerpt) + len(snippet) > max_chars:
            # Try to fit a truncated version that ends at a balanced point
            remaining = max_chars - len(code_excerpt)
            if remaining > 200:
                lines = code.split("\n")
                depth = 0
                last_safe = 0
                for i, line in enumerate(lines):
                    depth += net_depth(line)
                    if depth <= 0:
                        depth = 0
                        last_safe = i + 1
                    if sum(len(l) + 1 for l in lines[:i+1]) > remaining:
                        break
                if last_safe > 0:
                    truncated = "\n".join(lines[:last_safe])
                    code_excerpt += f"# chunk: {name}\n{truncated}\n\n"
            break
        code_excerpt += snippet

    return {
        "pkg": pkg,
        "description": description,
        "code_excerpt": code_excerpt.strip() or "(no vignette available)",
    }


# ── Batch processor ────────────────────────────────────────────────────────────

def process_batch(
    batch: list[dict],
    model: str,
    dry_run: bool,
) -> list[tuple[str, str]]:
    """
    Process one batch of packages with a single LLM call.
    Returns list of (pkg, status) pairs.
    """
    prompt = build_prompt(batch)
    pkg_ids = [item["pkg"] for item in batch]

    if dry_run:
        return [(pkg, "dry-run") for pkg in pkg_ids]

    response = call_anthropic(prompt, model)
    if not response:
        return [(pkg, "llm-error") for pkg in pkg_ids]

    parsed = parse_llm_response(response)
    results = []
    for pkg in pkg_ids:
        if pkg not in parsed:
            results.append((pkg, "llm-no-output"))
            continue
        steps = parsed[pkg]
        ok, reason = validate_steps(steps)
        if not ok:
            results.append((pkg, f"validation-fail:{reason}"))
            continue
        if rewrite_main_nf(pkg, steps):
            results.append((pkg, f"ok:{len(steps)}"))
        else:
            results.append((pkg, "write-fail"))
    return results


# ── Main ───────────────────────────────────────────────────────────────────────

def main():
    import argparse
    parser = argparse.ArgumentParser(
        description="Regenerate broken Bioconductor main.nf step blocks via LLM")
    parser.add_argument("--vignette-dir", type=Path, default=None,
                        help="Local directory of pre-downloaded vignette files")
    parser.add_argument("--model", default=DEFAULT_MODEL,
                        help=f"Anthropic model ID (default: {DEFAULT_MODEL})")
    parser.add_argument("--batch-size", type=int, default=DEFAULT_BATCH,
                        help="Packages per LLM call (default: 5)")
    parser.add_argument("--workers", type=int, default=DEFAULT_WORKERS,
                        help="Parallel worker threads (default: 4)")
    parser.add_argument("--only-broken", action="store_true", default=True,
                        help="Only process files with unbalanced brackets (default: True)")
    parser.add_argument("--all", dest="only_broken", action="store_false",
                        help="Process all files, not just broken ones")
    parser.add_argument("--dry-run", action="store_true",
                        help="Parse and prompt but do not call LLM or write files")
    parser.add_argument("--limit", type=int, default=None,
                        help="Process at most N packages")
    parser.add_argument("--pkg", type=str, default=None,
                        help="Process only this package (lowercase name)")
    args = parser.parse_args()

    if not os.environ.get("ANTHROPIC_API_KEY") and not args.dry_run:
        print("ERROR: ANTHROPIC_API_KEY not set. Export it before running.",
              file=sys.stderr)
        sys.exit(1)

    # Collect packages to process
    if args.pkg:
        pkgs = [args.pkg]
    else:
        pkgs = sorted(p.name for p in BIOC_DIR.iterdir() if p.is_dir())

    if args.only_broken:
        pkgs = [p for p in pkgs if is_broken(BIOC_DIR / p / "main.nf")]

    if args.limit:
        pkgs = pkgs[:args.limit]

    print(f"Packages to process: {len(pkgs)}")
    print(f"Model: {args.model}  |  Batch: {args.batch_size}  |  Workers: {args.workers}")
    if args.dry_run:
        print("DRY RUN — no LLM calls, no file writes")
    if args.vignette_dir:
        print(f"Local vignette dir: {args.vignette_dir}")
    print()

    # Build context for all packages (can be parallelised)
    print("Building package contexts...")
    contexts: list[dict] = []
    for i, pkg in enumerate(pkgs, 1):
        print(f"  [{i:4d}/{len(pkgs)}] {pkg}", end="\r", flush=True)
        try:
            ctx = build_pkg_context(pkg, args.vignette_dir)
            contexts.append(ctx)
        except Exception as e:
            print(f"  [{i:4d}/{len(pkgs)}] {pkg}: context error — {e}")
    print(f"\nContexts built: {len(contexts)}")

    # Batch up and run LLM
    batches = [
        contexts[i:i + args.batch_size]
        for i in range(0, len(contexts), args.batch_size)
    ]
    print(f"Batches: {len(batches)}  (workers: {args.workers})\n")

    ok_count = fail_count = 0
    fail_log: list[tuple[str, str]] = []

    def run_batch(batch):
        return process_batch(batch, args.model, args.dry_run)

    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        futures = {pool.submit(run_batch, b): b for b in batches}
        done = 0
        for fut in as_completed(futures):
            done += 1
            batch_results = fut.result()
            for pkg, status in batch_results:
                if status.startswith("ok:") or status == "dry-run":
                    n = status.split(":")[1] if ":" in status else "?"
                    print(f"  ✓ {pkg}  ({n} steps)")
                    ok_count += 1
                else:
                    print(f"  ✗ {pkg}  [{status}]")
                    fail_count += 1
                    fail_log.append((pkg, status))
            print(f"  --- batch {done}/{len(batches)} complete ---", flush=True)

    print(f"\nDone: {ok_count} ok, {fail_count} failed")
    if fail_log:
        print("\nFailed packages:")
        for pkg, reason in fail_log:
            print(f"  {pkg}: {reason}")

        # Write failed list for retry
        fail_path = Path("/tmp/bioc_regen_failed.txt")
        fail_path.write_text("\n".join(pkg for pkg, _ in fail_log) + "\n")
        print(f"\nFailed package list written to {fail_path}")
        print("Retry with: python3 regenerate_broken_bioc_llm.py "
              "--pkg ... OR filter /tmp/bioc_regen_failed.txt")


if __name__ == "__main__":
    main()
