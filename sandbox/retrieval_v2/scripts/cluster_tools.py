"""
Phase 0 — read-only clustering of `backend/database/galaxy_ai_tools.db`.

Goal: quantify how the 12,274 wrapper rows collapse into a smaller set of
canonical tool families. Output a CSV that a human can scan to decide whether
the 3-level (tool_family → function → wrapper) architecture is right.

Approach (deterministic, no LLM, no embeddings yet):

1. Extract a `family_key` per row from its `tool_id` path:
   - `toolshed.../repos/<owner>/<package>/<tool>/<version>` → `<package>` segment
   - `nfcore/<tool>/<function>` → `<tool>` segment (already 2-level — gold)
   - `nfcore/<tool>` → `<tool>`
   - `bioconductor/<package>` → `bioconductor:<package>`
   - bare names / other → normalize the name as the family_key (lowercase, strip
     versions, strip "map with", strip indexer/builder suffixes)

2. Normalize the family_key (lowercase, strip plugin prefixes like `aurora_`,
   `data_manager_`, `cp_`, version suffixes).

3. For each family, infer per-row `function_hint` from the display `name`
   (e.g. "BWA-MEM2 indexer" vs "BWA-MEM2" → "indexer" vs "default").

4. Write `sandbox/retrieval_v2/output/tool_clusters.csv` with one row per
   (family_key) and aggregate columns: member_count, distinct_functions,
   sample_names, sample_tool_ids, top_category. Sorted by member_count DESC.

5. Print summary statistics + 30 largest clusters as a quick visual audit.

Run:
    PYTHONPATH=. python -m sandbox.retrieval_v2.scripts.cluster_tools

Read-only — does not modify the DB.
"""
from __future__ import annotations

import csv
import re
import sqlite3
import sys
from collections import defaultdict
from pathlib import Path
from typing import Dict, List, Tuple

DB_PATH = Path(__file__).resolve().parents[3] / "backend" / "database" / "galaxy_ai_tools.db"
OUT_DIR = Path(__file__).resolve().parents[1] / "output"
OUT_DIR.mkdir(parents=True, exist_ok=True)
OUT_CSV = OUT_DIR / "tool_clusters.csv"


# ─── family-key extraction ──────────────────────────────────────────────

_PLUGIN_PREFIXES = (
    "data_manager_", "aurora_", "cp_", "ctat_", "enhanced_", "demo_",
)
_FUNCTION_SUFFIXES = (
    "_index_builder", "_indexer", "_index", "_to_bed", "_to_bedgraph",
    "_to_peaks", "_to_sam", "_wrappers", "_wrapper", "_site",
)
_MAP_WITH_PAT = re.compile(r"^map[-_ ]with[-_ ]", re.IGNORECASE)
_VERSION_PAT = re.compile(r"[-_ ](v?\d+[\.\d]*(?:\+galaxy\d*)?)$", re.IGNORECASE)


def _strip_plugin_prefix(s: str) -> str:
    for p in _PLUGIN_PREFIXES:
        if s.startswith(p):
            return s[len(p):]
    return s


def _strip_function_suffix(s: str) -> Tuple[str, str]:
    """Return (stripped_family, inferred_function). function='' if no suffix."""
    for suf in _FUNCTION_SUFFIXES:
        if s.endswith(suf):
            fn = suf.lstrip("_").rstrip("_")
            # Normalize a few common variants
            if fn in ("indexer", "index_builder", "index"):
                fn = "index"
            elif fn in ("wrappers", "wrapper"):
                fn = ""  # generic wrapper, not a real function
            return s[: -len(suf)], fn
    return s, ""


def _normalize_family(raw: str) -> str:
    s = raw.lower()
    s = _MAP_WITH_PAT.sub("", s)
    s = _VERSION_PAT.sub("", s)
    s = _strip_plugin_prefix(s)
    s, _fn = _strip_function_suffix(s)
    s = s.strip("_-. ")
    return s or raw.lower()


def _extract_family_and_function(tool_id: str, name: str) -> Tuple[str, str]:
    """
    Return (family_key, function_hint).

    family_key is the canonical group identifier (lowercase, dedup-friendly).
    function_hint is a guess at the function within the family ('' = default).
    """
    tid = tool_id.strip()

    # Galaxy toolshed: .../repos/<owner>/<package>/<tool>/<version>
    if tid.startswith("toolshed."):
        parts = tid.split("/")
        # ['toolshed.g2.bx.psu.edu', 'repos', 'owner', 'package', 'tool', 'version']
        if len(parts) >= 5 and parts[1] == "repos":
            package = parts[3]
            tool = parts[4] if len(parts) > 4 else package
            family_raw = package  # package is the strongest family signal
            tool_norm = _normalize_family(tool)
            pkg_norm = _normalize_family(family_raw)
            # If the per-tool path segment looks different from the package
            # name, it's typically a "function within the package"
            # (e.g. package='bwa', tool='bwa_mem' → family='bwa', fn='mem').
            fn = ""
            if tool_norm and tool_norm != pkg_norm:
                # Function-like suffix on the tool segment? prefer that.
                _stripped, suf_fn = _strip_function_suffix(tool_norm)
                if suf_fn:
                    fn = suf_fn
                elif tool_norm.startswith(pkg_norm + "_"):
                    fn = tool_norm[len(pkg_norm) + 1:]
                else:
                    fn = tool_norm
            return pkg_norm, fn

    # nf-core: nfcore/<tool>/<function>  OR  nfcore/<tool>
    if tid.startswith("nfcore/"):
        parts = tid.split("/", 2)
        family = _normalize_family(parts[1]) if len(parts) > 1 else "nfcore_unknown"
        fn = _normalize_family(parts[2]) if len(parts) > 2 else ""
        return family, fn

    # biomate native
    if tid.startswith("biomate/"):
        parts = tid.split("/", 2)
        family = _normalize_family(parts[1]) if len(parts) > 1 else "biomate_unknown"
        fn = _normalize_family(parts[2]) if len(parts) > 2 else ""
        return family, fn

    # Bioconductor R packages
    if tid.startswith("bioconductor/"):
        parts = tid.split("/", 1)
        return f"bioconductor:{_normalize_family(parts[1])}", ""

    # Bare name / unknown — fall back to name-based normalization
    base = name or tid.split("/")[-1] or tid
    family, fn = _strip_function_suffix(_normalize_family(base))
    return family, fn


# ─── main ───────────────────────────────────────────────────────────────

def main() -> int:
    if not DB_PATH.exists():
        print(f"ERROR: DB not found at {DB_PATH}", file=sys.stderr)
        return 1

    print(f"Reading {DB_PATH}")
    conn = sqlite3.connect(f"file:{DB_PATH}?mode=ro", uri=True)
    rows = conn.execute(
        "SELECT tool_id, name, COALESCE(category, '') FROM tools"
    ).fetchall()
    conn.close()
    print(f"  {len(rows):,} rows loaded")

    # family_key → dict(members, function_counts, category_counts)
    clusters: Dict[str, Dict] = defaultdict(
        lambda: {
            "members": [],
            "functions": defaultdict(int),
            "categories": defaultdict(int),
        }
    )

    unassigned = 0
    for tool_id, name, category in rows:
        family, fn = _extract_family_and_function(tool_id or "", name or "")
        if not family:
            unassigned += 1
            family = "__unassigned__"
        rec = clusters[family]
        rec["members"].append((tool_id, name))
        rec["functions"][fn or "default"] += 1
        if category:
            rec["categories"][category] += 1

    # Build sorted summary
    summary: List[Tuple[str, int, int, str, str, str]] = []
    for family, rec in clusters.items():
        members = rec["members"]
        n = len(members)
        n_fn = len(rec["functions"])
        top_cat = max(rec["categories"], key=rec["categories"].get) if rec["categories"] else ""
        # Sample 3 representative member names + tool_ids (deterministic: alphabetically)
        sample = sorted(members, key=lambda m: (m[1] or "", m[0]))[:3]
        sample_names = " | ".join(s[1] for s in sample if s[1])
        sample_ids = " | ".join(s[0] for s in sample)
        # Top functions
        top_fns = sorted(rec["functions"].items(), key=lambda x: -x[1])[:5]
        fns_str = ", ".join(f"{k}({v})" for k, v in top_fns)
        summary.append((family, n, n_fn, top_cat, sample_names, sample_ids, fns_str))

    summary.sort(key=lambda r: -r[1])

    # Write CSV
    with OUT_CSV.open("w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow([
            "family_key", "member_count", "n_distinct_functions",
            "top_category", "sample_names", "sample_tool_ids", "function_breakdown",
        ])
        for row in summary:
            w.writerow(row)

    # ─── Print analysis ─────────────────────────────────────────────────
    print(f"\n=== Phase 0 Clustering Results ===")
    print(f"Total wrapper rows:       {len(rows):,}")
    print(f"Distinct family_keys:     {len(clusters):,}")
    print(f"Compression ratio:        {len(rows) / max(len(clusters), 1):.2f}x")
    print(f"Unassigned (fallback):    {unassigned}")
    print(f"\nFamily size distribution:")
    sizes = [r[1] for r in summary]
    buckets = [
        ("size 1 (singletons)", sum(1 for s in sizes if s == 1)),
        ("size 2-4",             sum(1 for s in sizes if 2 <= s <= 4)),
        ("size 5-10",            sum(1 for s in sizes if 5 <= s <= 10)),
        ("size 11-50",           sum(1 for s in sizes if 11 <= s <= 50)),
        ("size 51+",             sum(1 for s in sizes if s >= 51)),
    ]
    for label, count in buckets:
        pct = 100 * count / max(len(sizes), 1)
        print(f"  {label:<25} {count:>5}  ({pct:.1f}%)")

    print(f"\nTop 30 largest families:")
    print(f"{'family_key':<35} {'n':>5} {'fns':>4}  {'top_category':<24}  sample_names")
    print("-" * 130)
    for row in summary[:30]:
        family, n, n_fn, top_cat, sample_names, _ids, _fns = row
        print(f"{family[:34]:<35} {n:>5} {n_fn:>4}  {top_cat[:23]:<24}  {sample_names[:60]}")

    print(f"\nFull CSV written → {OUT_CSV}")
    print(f"Spot-check the top 30 above + open the CSV to validate clusters.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
