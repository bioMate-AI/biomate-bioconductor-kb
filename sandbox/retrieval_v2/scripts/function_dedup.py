"""
Phase 0b — within-family function-level duplicate analysis.

The naive family-level clustering (cluster_tools.py) shows only 1.43x
compression. The hypothesis tested here: the real dedup happens at the
(family, function) level, where multiple wrappers exist for the same
function (e.g. 5 DESeq2-differential-expression wrappers from different
authors).

Method:
1. For each wrapper row, derive a (family_key, function_signature) tuple.
2. function_signature = normalize(name) — lowercase, drop "Galaxy", version
   tokens, author prefixes; collapse "Map with BWA-MEM" and "BWA-MEM Map"
   to the same signature.
3. Group by (family, signature). Groups of size ≥ 2 are function-level
   duplicates.

Output: `sandbox/retrieval_v2/output/function_duplicates.csv` and a summary
of the top duplicated functions.

Read-only against the DB.
"""
from __future__ import annotations

import csv
import re
import sqlite3
import sys
from collections import defaultdict
from pathlib import Path
from typing import Dict, List, Tuple

from sandbox.retrieval_v2.scripts.cluster_tools import _extract_family_and_function

DB_PATH = Path(__file__).resolve().parents[3] / "backend" / "database" / "galaxy_ai_tools.db"
OUT_DIR = Path(__file__).resolve().parents[1] / "output"
OUT_DIR.mkdir(parents=True, exist_ok=True)
OUT_CSV = OUT_DIR / "function_duplicates.csv"

# Function-signature normalization: strip noise, keep the verb+object.
_STOP_TOKENS = {
    "galaxy", "tool", "wrapper", "wrappers", "map", "with", "for", "from",
    "the", "and", "of", "to", "using", "via", "by", "v", "vs",
    "illumina", "solid", "454",  # platform tokens
}
_VERSION_PAT = re.compile(r"\b\d+\.\d+[\.\d]*[+a-z0-9]*\b", re.IGNORECASE)
_PUNCT_PAT = re.compile(r"[^a-z0-9]+")


def _signature(name: str) -> str:
    if not name:
        return ""
    s = name.lower()
    s = _VERSION_PAT.sub("", s)
    s = _PUNCT_PAT.sub(" ", s)
    tokens = [t for t in s.split() if t and t not in _STOP_TOKENS and not t.isdigit()]
    # Sort tokens to collapse word-order variants ("Map BWA-MEM" == "BWA-MEM Map")
    return " ".join(sorted(tokens))


def main() -> int:
    if not DB_PATH.exists():
        print(f"ERROR: DB not found at {DB_PATH}", file=sys.stderr)
        return 1

    conn = sqlite3.connect(f"file:{DB_PATH}?mode=ro", uri=True)
    rows = conn.execute(
        "SELECT tool_id, name, COALESCE(category, '') FROM tools"
    ).fetchall()
    conn.close()
    print(f"Loaded {len(rows):,} rows")

    # (family, function_signature) → list of (tool_id, name, category)
    fn_groups: Dict[Tuple[str, str], List[Tuple[str, str, str]]] = defaultdict(list)
    for tool_id, name, category in rows:
        family, fn_hint = _extract_family_and_function(tool_id or "", name or "")
        sig = _signature(name or "")
        if not sig:  # no signature available (rare); use fn_hint as fallback
            sig = fn_hint or "default"
        fn_groups[(family, sig)].append((tool_id, name, category))

    # Find duplicate (function-level) groups
    dup_groups = [
        ((family, sig), members)
        for (family, sig), members in fn_groups.items()
        if len(members) >= 2
    ]
    dup_groups.sort(key=lambda kv: -len(kv[1]))

    total_dup_rows = sum(len(m) for _, m in dup_groups)
    extra_rows = sum(len(m) - 1 for _, m in dup_groups)  # rows beyond the first canonical

    print(f"\n=== Function-level duplicate analysis ===")
    print(f"Distinct (family, function) groups: {len(fn_groups):,}")
    print(f"Groups with ≥2 wrappers (dups):     {len(dup_groups):,}")
    print(f"Total wrappers IN dup groups:       {total_dup_rows:,}")
    print(f"  → could collapse to canonicals:   {len(dup_groups):,}")
    print(f"  → 'extra' wrappers removable:     {extra_rows:,} ({100*extra_rows/len(rows):.1f}% of catalog)")
    print(f"Catalog size if (family,fn)-deduped: {len(rows) - extra_rows:,}  "
          f"(vs raw {len(rows):,} → {len(rows)/(len(rows)-extra_rows):.2f}x compression)")

    # Top 25 most-duplicated functions
    print(f"\nTop 25 most-duplicated (family, function_signature):")
    print(f"{'family':<25} {'n':>4}  {'top_category':<22}  function_signature → sample wrapper")
    print("-" * 130)
    for (family, sig), members in dup_groups[:25]:
        cat = max((m[2] for m in members), default="")
        sample = members[0][1] or ""
        print(f"{family[:24]:<25} {len(members):>4}  {cat[:21]:<22}  {sig[:35]:<35} → {sample[:35]}")

    # Write CSV
    with OUT_CSV.open("w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow([
            "family_key", "function_signature", "wrapper_count",
            "top_category", "sample_name", "all_tool_ids",
        ])
        for (family, sig), members in dup_groups:
            cat = max((m[2] for m in members), default="")
            sample = members[0][1] or ""
            ids = " | ".join(m[0] for m in members)
            w.writerow([family, sig, len(members), cat, sample, ids])

    print(f"\nFull CSV → {OUT_CSV}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
