#!/usr/bin/env python3
"""
Pass-2 grounded enrichment.

For each SKILL.md in the public bundle (except the 23 hand-curated rich
ones — skill_content > 8 KB already), do a second-pass rewrite where
the Gemini call is grounded in the cached Bioconductor vignettes
fetched by fetch_authoritative_sources.py.

Verification step: after Gemini emits the new SKILL.md, extract every
R function name mentioned (pattern `\\bfunc(`) and check what fraction
appear verbatim in the fetched vignette text. If < FACT_FLOOR the
output is rejected and the package is flagged for human review.

Tags:
  - "auto-generated" → "vignette-grounded" on success
  - Skips packages with no cached vignette content

Cost: ~$15 with gemini-3-pro-preview as default (Pass-2 is verification-
critical → Pro is the right choice). Batch=3 + workers=6 keeps total
wall ~30 min.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, UTC
from pathlib import Path
from typing import Any

REPO       = Path(__file__).parent.parent
CACHE      = REPO / ".source_cache"
SKILLS     = REPO / "skills"
AUDIT_OUT  = REPO / "docs" / "enrich_v2_audit.json"
MANIFEST   = REPO / "MANIFEST.json"

BATCH_SIZE     = int(os.environ.get("V2_BATCH_SIZE", 3))
MAX_WORKERS    = int(os.environ.get("V2_WORKERS", 6))
SKIP_ABOVE     = int(os.environ.get("V2_SKIP_ABOVE", 8000))   # don't re-touch curated
FACT_FLOOR     = float(os.environ.get("V2_FACT_FLOOR", 0.5))  # min function-name verify rate
MAX_VIGNETTE_C = int(os.environ.get("V2_MAX_VIGNETTE", 30000))
ENRICH_MODEL_DEFAULT = os.environ.get("V2_MODEL", "gemini-3-pro-preview")
ENRICH_MODEL_FALLBACK= os.environ.get("V2_MODEL_FALLBACK", "gemini-3.5-flash")

EXEC_BLOCKLIST = (
    "docker_image", "biocontainer_url", "nextflow_path",
    "galaxy_tool_id", "biomate_workflow_id", "aws_batch",
    "s3://", "biomate.ai/cloud", "biomate cloud",
)

PROMPT = """You are a Bioconductor expert curating a public skill library. I'll give you a BATCH of (existing SKILL.md, Bioconductor vignette text) pairs. Rewrite each SKILL.md grounded in the vignette so every fact is verifiable.

# HARD RULES
- Every R function name you name must appear verbatim somewhere in the supplied vignette text. Do not invent or hallucinate functions.
- Preserve the YAML frontmatter EXACTLY as given (same fields/order/values). Replace tag `auto-generated` with `vignette-grounded`.
- Do NOT reference: docker images, Nextflow pipeline paths, Galaxy tool IDs, AWS Batch, S3 URIs, BioMate Cloud / execution platform.
- Output ONLY the SKILL.md content for each package wrapped in delimiters (see OUTPUT FORMAT). No prose, no fences, no chatter.

# SKILL.md TEMPLATE (use exactly these 9 sections after the frontmatter + `# Pkg` heading)

## When to Use
2-5 concrete scenarios. Cite specific functions or data types from the vignette.

## When NOT to Use
2-4 bullets each pointing at an explicit alternative ("For X use Y because Z").

## Data Requirements
Bullet list of input format, structure, normalization state. Use vignette code examples as ground truth.

## Key Parameters
Up to 8 parameters as `- **param_name** (default): guidance`. Only parameters that actually appear in the vignette.

## Best Practices
3-6 bullets of recommended workflow ordering / quality checks visible in the vignette.

## Common Pitfalls
3-5 bullets with cause + fix in one sentence each.

## Alternatives
3-8 alternative R/Bioconductor packages with a 1-clause why-they-differ.

## Citations
- Primary publication (author year, journal) — use the vignette's BibTeX if present
- 1-2 benchmark/review references if vignette cites them

## References
- Homepage: bioconductor.org/packages/<pkg>
- Vignette: <the vignette URL we gave you>

# OUTPUT FORMAT (STRICT)
For each input package, emit:

<<<SKILL:{pkg_id}>>>
---
<verbatim frontmatter with `auto-generated`→`vignette-grounded`>
---

# <PackageName>

<sections>
<<<END>>>

The {pkg_id} markers must match the input ids exactly.

# INPUT BATCH BEGINS BELOW
"""


def _read_vignettes(pkg_name: str) -> tuple[str, list[str]]:
    """Returns (concatenated_text, source_urls). Pulls all cached vignettes
    for this package; truncates total to MAX_VIGNETTE_C chars."""
    pkg_cache = CACHE / pkg_name.lower()
    text_parts: list[str] = []
    urls: list[str] = []
    if pkg_cache.is_dir():
        for f in sorted(pkg_cache.glob("vignette_*.txt")):
            t = f.read_text()
            if not t: continue
            text_parts.append(f"### Vignette: {f.name}\n{t}")
            urls.append(f"(local cache: {f.name})")
    text = "\n\n".join(text_parts)
    if len(text) > MAX_VIGNETTE_C:
        text = text[:MAX_VIGNETTE_C] + "\n... [vignette text truncated]"
    return text, urls


def _call_gemini(prompt: str, model: str) -> str:
    import google.generativeai as genai
    api_key = os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY")
    if not api_key: raise RuntimeError("GEMINI_API_KEY not set")
    genai.configure(api_key=api_key)
    m = genai.GenerativeModel(model)
    r = m.generate_content(prompt, generation_config={"max_output_tokens": 16384, "temperature": 0.25})
    return r.text if hasattr(r, "text") else ""


def _split_batch_output(text: str) -> dict[str, str]:
    out: dict[str, str] = {}
    p = re.compile(r"<<<SKILL:([a-zA-Z0-9_.-]+)>>>(.*?)<<<END>>>", re.DOTALL)
    for m in p.finditer(text):
        body = m.group(2).strip()
        if body.startswith("```"):
            body = re.sub(r"^```(?:markdown|md)?\s*", "", body)
            body = re.sub(r"\s*```$", "", body)
        out[m.group(1).strip()] = body.strip() + "\n"
    return out


def _extract_r_functions(skill: str) -> set[str]:
    """Find every R function reference in the SKILL.md (e.g. `DESeq()`,
    `lfcShrink()`, `pkg::fn()`)."""
    funcs: set[str] = set()
    # Pattern: identifier followed by `(`, possibly with pkg:: prefix
    for m in re.finditer(r"\b([A-Za-z_][A-Za-z0-9_.]*::)?([A-Za-z_][A-Za-z0-9_.]+)\s*\(", skill):
        fn = m.group(2)
        # Filter common prose words that look like function calls
        if fn.lower() in {"e", "g", "ie", "etc", "vs", "if", "for", "while", "in",
                          "see", "use", "run", "load", "save", "set", "get"}:
            continue
        if len(fn) < 3: continue
        funcs.add(fn)
    return funcs


def _verify_facts(skill: str, vignette: str) -> tuple[float, list[str]]:
    """Return (verification_rate, missing_functions)."""
    fns = _extract_r_functions(skill)
    if not fns: return 1.0, []
    missing = [fn for fn in fns if fn not in vignette]
    return 1.0 - (len(missing) / len(fns)), missing


def _validate(out: str) -> tuple[bool, str]:
    if not out or len(out.strip()) < 800:
        return False, f"too short ({len(out.strip())})"
    if not out.lstrip().startswith("---"):
        return False, "no YAML frontmatter"
    lc = out.lower()
    for term in EXEC_BLOCKLIST:
        if term.lower() in lc:
            return False, f"exec-leak: {term!r}"
    sections = ["When to Use", "When NOT to Use", "Data Requirements",
                "Key Parameters", "Best Practices", "Common Pitfalls",
                "Alternatives", "Citations", "References"]
    hits = sum(1 for s in sections if f"## {s}" in out)
    if hits < 5:
        return False, f"only {hits}/9 sections"
    return True, "ok"


def _build_batch_prompt(items: list[dict]) -> str:
    parts = [PROMPT]
    for it in items:
        parts.append(f"\n<<<INPUT_SKILL:{it['pkg_id']}>>>\n")
        parts.append(it["current"])
        parts.append(f"\n<<<VIGNETTE>>>\n{it['vignette']}\n")
        parts.append(f"<<<END_INPUT_SKILL:{it['pkg_id']}>>>\n")
    parts.append("\n# Now emit the rewritten SKILL.md for each package using the strict output format.\n")
    return "".join(parts)


def _process_batch(items: list[dict], model: str) -> list[dict[str, Any]]:
    prompt = _build_batch_prompt(items)
    try:
        raw = _call_gemini(prompt, model)
    except Exception as exc:
        return [{"pkg": it["pkg_id"], "ok": False, "reason": f"LLM error ({model}): {exc}",
                 "orig_size": it["orig_size"], "new_size": 0,
                 "verify_rate": 0.0, "missing_fns": [], "model_used": model}
                for it in items]
    by_id = _split_batch_output(raw)

    rows: list[dict[str, Any]] = []
    retry_items: list[dict] = []
    for it in items:
        body = by_id.get(it["pkg_id"], "")
        if not body:
            retry_items.append(it); continue
        ok, reason = _validate(body)
        if not ok:
            retry_items.append(it); continue
        # Fact verification against vignette
        rate, missing = _verify_facts(body, it["vignette"])
        if rate < FACT_FLOOR:
            retry_items.append(it); continue
        # Accept
        it["path"].write_text(body)
        rows.append({"pkg": it["pkg_id"], "ok": True, "reason": "grounded-ok",
                     "orig_size": it["orig_size"], "new_size": len(body),
                     "verify_rate": round(rate, 3),
                     "n_missing_fns": len(missing),
                     "model_used": model})
    # Retry tier
    if retry_items and model != ENRICH_MODEL_FALLBACK:
        for it in retry_items:
            rows.extend(_process_batch([it], ENRICH_MODEL_FALLBACK))
    else:
        for it in retry_items:
            body = by_id.get(it["pkg_id"], "")
            ok, reason = _validate(body) if body else (False, "missing in response")
            rate, missing = _verify_facts(body, it["vignette"]) if body else (0.0, [])
            rows.append({"pkg": it["pkg_id"], "ok": False,
                         "reason": reason if not ok else f"fact verify {rate:.0%} < {FACT_FLOOR:.0%}",
                         "orig_size": it["orig_size"], "new_size": len(body),
                         "verify_rate": round(rate, 3),
                         "n_missing_fns": len(missing),
                         "missing_fns_sample": missing[:6],
                         "model_used": model})
    return rows


def _read_skill(path: Path) -> tuple[str, str | None]:
    text = path.read_text()
    m = re.search(r"^name:\s*bioconductor-([a-z0-9_.-]+)", text, re.I | re.M)
    return text, (m.group(1) if m else None)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0, help="0 = all")
    ap.add_argument("--retry-only", action="store_true",
                    help="only re-process packages currently flagged as auto-generated")
    args = ap.parse_args()

    items_all: list[dict] = []
    skipped: dict[str, int] = {"no_vignette": 0, "already_curated": 0,
                                "no_pkg_name": 0, "already_grounded": 0}
    for skill_path in sorted(SKILLS.rglob("SKILL.md")):
        size = skill_path.stat().st_size
        if size > SKIP_ABOVE:
            skipped["already_curated"] += 1; continue
        text, pkg = _read_skill(skill_path)
        if not pkg: skipped["no_pkg_name"] += 1; continue
        if args.retry_only and "vignette-grounded" in (text.split("---", 2)[1] if "---" in text else ""):
            skipped["already_grounded"] += 1; continue
        vignette, vurls = _read_vignettes(pkg)
        if len(vignette) < 500:
            skipped["no_vignette"] += 1
            continue
        items_all.append({"path": skill_path, "pkg_id": pkg, "current": text,
                           "orig_size": size, "vignette": vignette,
                           "vignette_urls": vurls})
        if args.limit and len(items_all) >= args.limit: break

    print(f"[enrich-v2] {len(items_all)} packages to process")
    print(f"[enrich-v2] skipped: {skipped}")
    if not items_all: return 0

    batches = [items_all[i:i+BATCH_SIZE] for i in range(0, len(items_all), BATCH_SIZE)]
    print(f"[enrich-v2] {len(batches)} batches × {BATCH_SIZE} pkgs, workers={MAX_WORKERS}")
    print(f"[enrich-v2] default model: {ENRICH_MODEL_DEFAULT}")
    print(f"[enrich-v2] fallback model: {ENRICH_MODEL_FALLBACK}")
    print(f"[enrich-v2] fact verify floor: {FACT_FLOOR}")
    print()

    results: list[dict] = []
    t0 = time.time()
    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as ex:
        futures = {ex.submit(_process_batch, b, ENRICH_MODEL_DEFAULT): i
                   for i, b in enumerate(batches)}
        done = 0
        for fut in as_completed(futures):
            rows = fut.result()
            results.extend(rows)
            done += 1
            ok = sum(1 for r in rows if r["ok"])
            ver = [r["verify_rate"] for r in rows if r["ok"]]
            avg_ver = sum(ver)/len(ver) if ver else 0
            print(f"  [batch {done:3d}/{len(batches)}] {ok}/{len(rows)} ok  avg_verify={avg_ver:.2f}",
                  flush=True)
    elapsed = time.time() - t0

    ok = sum(1 for r in results if r["ok"])
    rates = [r["verify_rate"] for r in results if r["ok"]]
    avg_rate = sum(rates)/len(rates) if rates else 0
    from collections import Counter
    mc = Counter(r.get("model_used","?") for r in results if r["ok"])
    print(f"\n[enrich-v2] done in {elapsed/60:.1f} min — ok={ok} failed={len(results)-ok}")
    print(f"[enrich-v2] mean verify rate (passed): {avg_rate:.2f}")
    print(f"[enrich-v2] models used (success): {dict(mc)}")

    AUDIT_OUT.parent.mkdir(parents=True, exist_ok=True)
    AUDIT_OUT.write_text(json.dumps({
        "ran_at": datetime.now(UTC).isoformat(),
        "model_default": ENRICH_MODEL_DEFAULT,
        "model_fallback": ENRICH_MODEL_FALLBACK,
        "fact_floor": FACT_FLOOR,
        "batch_size": BATCH_SIZE,
        "max_workers": MAX_WORKERS,
        "total_processed": len(items_all),
        "ok": ok,
        "failed": len(items_all) - ok,
        "mean_verify_rate": round(avg_rate, 4),
        "models_used_success": dict(mc),
        "skipped": skipped,
        "elapsed_minutes": round(elapsed/60, 2),
        "results": results,
    }, indent=2, default=str))
    print(f"[enrich-v2] audit → {AUDIT_OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
