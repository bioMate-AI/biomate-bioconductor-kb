#!/usr/bin/env python3
"""
Systematic workflow description enrichment.

Fixes sparse descriptions (< DESC_THRESHOLD chars) in the workflows table:

  biomni_nextflow: parse .nf file on disk → extract processes, params, outputs
                   → generate structured description from template
  nfcore:          fetch README from GitHub (raw.githubusercontent.com)
                   → extract first substantive paragraph (skip badges/images)

Runs idempotently: skips workflows whose description is already long enough,
or whose description was manually enriched (flagged by 'enriched:manual' tag).

Usage:
    python3 scripts/enrich_workflow_descriptions.py [--dry-run] [--source nfcore|biomni_nextflow] [--limit N]
"""

import argparse
import re
import sqlite3
import sys
import time
import urllib.request
from pathlib import Path

DB_PATH = Path(__file__).parent.parent / "galaxy_ai_tools.db"
NF_ROOT = Path(__file__).parent.parent / "biomni_workflows"

DESC_THRESHOLD = 200   # descriptions shorter than this are enriched
BATCH_DELAY = 0.3      # seconds between GitHub requests (rate limit courtesy)


# ---------------------------------------------------------------------------
# biomni_nextflow: parse .nf file content
# ---------------------------------------------------------------------------

def _nf_resolve(filename: str) -> Path | None:
    """Resolve a DB filename to an absolute .nf path."""
    for root in [NF_ROOT, NF_ROOT.parent]:
        p = root / filename
        if p.is_file():
            return p
    return None


def _extract_nf_header_description(text: str) -> str | None:
    """Extract human-written description from a Nextflow file.

    Priority order:
      1. manifest.description field
      2. First /* ... */ block comment (skipping shebang line)
      3. Consecutive // comment lines at the top of the file
    """
    # 1. manifest block: description = '...' or description = "..."
    manifest_match = re.search(
        r'manifest\s*\{[^}]*\bdescription\s*=\s*[\'"]([^\'"]{20,})[\'"]',
        text, re.DOTALL
    )
    if manifest_match:
        return manifest_match.group(1).strip()

    # 2. Block comment: first /* ... */ (skip shebang)
    _BOILERPLATE = re.compile(
        r'nf-core style|generated from|galaxy wrapper|nextflow pipeline|'
        r'nf-core pipeline|TODO|FIXME|copyright|license|all rights reserved',
        re.IGNORECASE
    )
    block_match = re.search(r'/\*(.*?)\*/', text, re.DOTALL)
    if block_match:
        raw = block_match.group(1)
        # Strip leading * per line, collapse whitespace
        lines = [re.sub(r'^\s*\*\s?', '', l).strip() for l in raw.splitlines()]
        lines = [l for l in lines if l and not l.startswith('@') and '====' not in l
                 and not _BOILERPLATE.search(l)
                 and not re.match(r'^[\w-]+/[\w-]+\s*$', l)]  # skip bare path lines
        if lines:
            candidate = " ".join(lines[:6])  # at most 6 lines
            if len(candidate) > 40:
                return candidate[:500].rstrip(", ") + ("." if not candidate[:500].endswith(".") else "")

    # 3. Leading // comment block (after shebang)
    comment_lines = []
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("#!"):
            continue
        if stripped.startswith("//"):
            content = stripped.lstrip("/ ").strip()
            # Skip decorative separators and boilerplate
            if re.fullmatch(r'[=\-_*#~]{3,}', content):
                continue
            if _BOILERPLATE.search(content) or re.match(r'^[\w-]+/[\w-]+\s*$', content):
                continue
            if content:
                comment_lines.append(content)
        elif stripped == "" and not comment_lines:
            continue
        else:
            break  # first non-comment line ends the block
    if comment_lines:
        candidate = " ".join(comment_lines[:6])
        if len(candidate) > 40:
            return candidate[:500].rstrip(", ") + ("." if not candidate[:500].endswith(".") else "")

    return None


def _parse_nf_file(path: Path) -> dict:
    """Extract structured info from a Nextflow .nf file without LLM."""
    text = path.read_text(errors="replace")

    # Human-written description (manifest or header comment)
    header_description = _extract_nf_header_description(text)

    # Workflow name from 'workflow NAME {' or anonymous 'workflow {'
    wf_name_match = re.search(r'^workflow\s+([A-Z_][A-Z0-9_]*)\s*\{', text, re.MULTILINE)
    wf_name = wf_name_match.group(1) if wf_name_match else None

    # Process names (top-level 'process NAME {')
    process_names = re.findall(r'^process\s+([A-Z_][A-Z0-9_]+)\s*\{', text, re.MULTILINE)
    # Remove MOCK/TEST processes
    process_names = [p for p in process_names if not re.search(r'MOCK|TEST|DEBUG', p)]

    # Params block: collect param keys from 'params.xxx' or 'params { xxx = '
    param_keys = set(re.findall(r'params\.([a-z_][a-z0-9_]*)', text))
    # Remove Nextflow built-ins
    _BUILTIN_PARAMS = {"outdir", "tracedir", "publish_dir_mode", "enable_conda",
                       "singularity_pull_docker_container", "max_memory", "max_cpus",
                       "max_time", "help"}
    param_keys -= _BUILTIN_PARAMS

    # Docker/conda containers mentioned
    containers = re.findall(r'container\s+[\'"]([^\'"\s]+)[\'"]', text)
    containers = list(dict.fromkeys(containers))[:3]  # unique, max 3

    # Input/output file types from process input/output blocks
    input_types = set(re.findall(r'\b(fastq|bam|cram|vcf|fasta|fa|gtf|gff|bed|h5ad|csv|tsv|pdb|smiles|sdf)\b',
                                 text.lower()))
    output_types = set(re.findall(r'\b(vcf|bam|html|txt|tsv|csv|pdf|png|json|h5ad|anndata|multiqc)\b',
                                  text.lower()))

    return {
        "header_description": header_description,
        "wf_name": wf_name,
        "process_names": process_names,
        "param_keys": sorted(param_keys)[:12],
        "containers": containers,
        "input_types": sorted(input_types),
        "output_types": sorted(output_types),
    }


def _generate_biomni_description(db_name: str, nf_info: dict) -> str:
    """Build a structured description from parsed .nf info.

    If the file contains a manifest.description or header comment, that becomes
    the opening sentence. Otherwise falls back to the name-derived readable label.
    Structural facts (steps, inputs, outputs, params) are always appended.
    """
    steps = nf_info["process_names"]
    params = nf_info["param_keys"]
    inputs = nf_info["input_types"]
    outputs = nf_info["output_types"]
    header = nf_info.get("header_description")

    # Human-readable name from DB name (e.g. "Wgs Germline Gatk" → readable)
    readable = db_name.replace("_", " ").title()

    # Lead with author-written description if available; else use name
    if header:
        parts = [header if header.endswith(".") else header + "."]
    else:
        parts = [readable + "."]

    if steps:
        step_str = " → ".join(steps[:8])
        if len(steps) > 8:
            step_str += f" (+ {len(steps)-8} more)"
        parts.append(f"{len(steps)}-step pipeline: {step_str}.")

    if inputs:
        parts.append(f"Inputs: {', '.join(inputs)}.")

    if outputs:
        parts.append(f"Outputs: {', '.join(outputs)}.")

    if params:
        parts.append(f"Key parameters: {', '.join(params)}.")

    if nf_info["containers"]:
        c = nf_info["containers"][0]
        # Shorten image name
        if "/" in c:
            c = c.split("/")[-1].split(":")[0]
        parts.append(f"Container: {c}.")

    return " ".join(parts)


# ---------------------------------------------------------------------------
# nfcore: fetch README from GitHub
# ---------------------------------------------------------------------------

def _fetch_github_readme(pipeline_name: str) -> str | None:
    """Fetch first substantive paragraph from nf-core/{pipeline} README on GitHub."""
    for branch in ("master", "main", "dev"):
        url = (f"https://raw.githubusercontent.com/nf-core/{pipeline_name}"
               f"/{branch}/README.md")
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "BioMate/1.0"})
            with urllib.request.urlopen(req, timeout=8) as resp:
                content = resp.read().decode("utf-8", errors="replace")
            return _extract_readme_description(content)
        except Exception:
            continue
    return None


def _extract_readme_description(readme: str) -> str | None:
    """Extract first substantive paragraph from a Markdown README."""
    lines = readme.splitlines()
    paragraphs = []
    current = []

    for line in lines:
        # Skip badge lines, images, HTML, blank section headers
        stripped = line.strip()
        if (stripped.startswith("[![") or stripped.startswith("![") or
                stripped.startswith("<") or stripped.startswith("<!--") or
                stripped.startswith("#") or stripped.startswith("|") or
                stripped.startswith(">")):
            if current:
                paragraphs.append(" ".join(current))
                current = []
            continue
        if not stripped:
            if current:
                paragraphs.append(" ".join(current))
                current = []
            continue
        current.append(stripped)

    if current:
        paragraphs.append(" ".join(current))

    # Return first paragraph with substance (> 80 chars, not a badge line)
    for para in paragraphs:
        if len(para) > 80 and not para.startswith("[!"):
            # Trim to ~500 chars to avoid very long blocks
            return para[:500].rstrip(",. ") + ("." if not para[:500].endswith(".") else "")

    return None


# ---------------------------------------------------------------------------
# FTS index update
# ---------------------------------------------------------------------------

def _update_fts(conn: sqlite3.Connection, row_id: int, name: str,
                description: str, annotation: str | None) -> None:
    conn.execute("DELETE FROM workflows_fts WHERE rowid=?", (row_id,))
    conn.execute(
        "INSERT INTO workflows_fts(rowid, name, description, tags, annotation) "
        "SELECT id, name, ?, tags, ? FROM workflows WHERE id=?",
        (description, annotation, row_id),
    )


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    ap = argparse.ArgumentParser(description="Enrich sparse workflow descriptions")
    ap.add_argument("--dry-run", action="store_true",
                    help="Print what would change without modifying DB")
    ap.add_argument("--source", choices=["nfcore", "biomni_nextflow", "all"],
                    default="all", help="Which source to process")
    ap.add_argument("--limit", type=int, default=0,
                    help="Max entries to process (0 = unlimited)")
    ap.add_argument("--threshold", type=int, default=DESC_THRESHOLD,
                    help=f"Description length threshold (default {DESC_THRESHOLD})")
    args = ap.parse_args()

    conn = sqlite3.connect(str(DB_PATH))

    sources_filter = {
        "nfcore": "'nfcore','nfcore_subwf'",
        "biomni_nextflow": "'biomni_nextflow'",
        "all": "'nfcore','nfcore_subwf','biomni_nextflow'",
    }[args.source]

    rows = conn.execute(f"""
        SELECT id, name, filename, description, annotation, source, tags
        FROM workflows
        WHERE source IN ({sources_filter})
          AND (description IS NULL OR length(description) < ?)
          AND (tags NOT LIKE '%enriched:manual%')
        ORDER BY source, length(COALESCE(description,'')) ASC
    """, (args.threshold,)).fetchall()

    print(f"Found {len(rows)} workflows with sparse descriptions (threshold={args.threshold})")
    if args.limit:
        rows = rows[:args.limit]
        print(f"Processing first {len(rows)} (--limit {args.limit})")

    updated = skipped = failed = 0

    for row_id, name, filename, old_desc, annotation, source, tags in rows:
        print(f"\n[{source}] {name} (id={row_id}, current_len={len(old_desc or '')})")

        new_desc = None

        if source in ("nfcore", "nfcore_subwf"):
            # Extract pipeline short-name from filename
            # e.g. "nfcore/sarek/main.nf" → "sarek"
            #      "nfcore/subworkflows/bcl_demultiplex" → need subworkflow README
            parts = (filename or "").replace("\\", "/").split("/")
            if "subworkflows" in parts:
                idx = parts.index("subworkflows")
                subwf_name = parts[idx + 1] if idx + 1 < len(parts) else None
                if subwf_name:
                    # Try nf-core/modules README
                    for branch in ("master", "main"):
                        url = (f"https://raw.githubusercontent.com/nf-core/modules"
                               f"/{branch}/subworkflows/nf-core/{subwf_name}/README.md")
                        try:
                            req = urllib.request.Request(url, headers={"User-Agent": "BioMate/1.0"})
                            with urllib.request.urlopen(req, timeout=8) as resp:
                                content = resp.read().decode("utf-8", errors="replace")
                            new_desc = _extract_readme_description(content)
                            break
                        except Exception:
                            pass
            else:
                # Full pipeline: pick name component after "nfcore/"
                try:
                    nfcore_idx = parts.index("nfcore")
                    pipeline_name = parts[nfcore_idx + 1]
                    new_desc = _fetch_github_readme(pipeline_name)
                    time.sleep(BATCH_DELAY)
                except (ValueError, IndexError):
                    pass

        elif source == "biomni_nextflow":
            nf_path = _nf_resolve(filename or "")
            if nf_path:
                try:
                    nf_info = _parse_nf_file(nf_path)
                    new_desc = _generate_biomni_description(name, nf_info)
                except Exception as exc:
                    print(f"  ✗ parse error: {exc}")
            else:
                print(f"  ✗ file not found: {filename}")

        if not new_desc or len(new_desc) <= len(old_desc or ""):
            print(f"  - skipped (no improvement)")
            skipped += 1
            continue

        print(f"  ✓ {len(old_desc or '')} → {len(new_desc)} chars: {new_desc[:80]}…")

        if not args.dry_run:
            conn.execute(
                "UPDATE workflows SET description=? WHERE id=?",
                (new_desc, row_id),
            )
            _update_fts(conn, row_id, name, new_desc, annotation)
            updated += 1
        else:
            print("    (dry-run: not written)")
            updated += 1

    if not args.dry_run:
        conn.commit()

    conn.close()
    print(f"\nDone: updated={updated} skipped={skipped} failed={failed}")


if __name__ == "__main__":
    main()
