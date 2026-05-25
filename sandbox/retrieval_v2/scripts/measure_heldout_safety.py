"""
Held-out safety eval for family_dedup library.

For each of 30 queries about tool families NOT in tool_family_canonical.yaml
or tool_family_aliases.yaml, run baseline (raw FTS) and treatment
(prioritize_query_family). Both must produce IDENTICAL output — any
difference is a false positive and indicates the library reordered or
injected something on an uncovered query.

Pass criterion: zero differences, zero false positives.

Output: sandbox/retrieval_v2/output/heldout_safety_results.md
"""
from __future__ import annotations

import re
import sqlite3
import sys
from pathlib import Path
from typing import Any, Dict, List

import yaml

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))

from backend.lib.galaxy.ai.retrievers.family_dedup import (
    prioritize_query_family, load_alias_map, load_canonical_map,
)

DB = ROOT / "backend" / "database" / "galaxy_ai_tools.db"
EVAL_YAML = Path(__file__).resolve().parents[1] / "tests" / "suite_eval_heldout.yaml"
OUT_DOC = Path(__file__).resolve().parents[1] / "output" / "heldout_safety_results.md"

_FTS_SAFE = re.compile(r"[^a-zA-Z0-9_ ]+")


def _fts_query(q: str) -> str:
    cleaned = _FTS_SAFE.sub(" ", q).strip()
    tokens = [t for t in cleaned.split() if len(t) >= 2]
    if not tokens: return '""'
    return " OR ".join(tokens) if len(tokens) > 1 else tokens[0]


def baseline_search(query: str, limit: int = 10) -> List[Dict]:
    conn = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)
    conn.row_factory = sqlite3.Row
    try:
        rows = conn.execute("""
            SELECT t.tool_id, t.name, t.category
            FROM tools t JOIN tools_fts fts ON t.tool_id = fts.tool_id
            WHERE tools_fts MATCH ?
            LIMIT ?
        """, (_fts_query(query), limit)).fetchall()
    except sqlite3.OperationalError:
        conn.close(); return []
    conn.close()
    return [dict(r) for r in rows]


def main() -> int:
    cases = yaml.safe_load(EVAL_YAML.read_text())
    alias_map = load_alias_map()
    canon_map = load_canonical_map()
    print(f"Loaded {len(cases)} held-out cases")
    print(f"Alias map: {len(alias_map)} entries; Canonical map: {len(canon_map)} entries")

    # Sanity check: each family_keyword must NOT be in covered set
    covered = set(canon_map.keys())
    for k in list(alias_map.keys()) + list(alias_map.values()):
        covered.add(k.lower())
    bleed = [c for c in cases if c["family_keyword"].lower() in covered]
    if bleed:
        print(f"WARNING: {len(bleed)} family_keywords leaked into covered set:")
        for b in bleed: print(f"  {b['id']}: {b['family_keyword']}")

    identical = 0
    diffs: List[Dict] = []
    promotion_into_keyword: List[Dict] = []
    for c in cases:
        raw = baseline_search(c["query"], limit=10)
        treated = prioritize_query_family(c["query"], raw)
        raw_top1 = raw[0]["name"] if raw else None
        treated_top1 = treated[0].get("name") if treated else None
        baseline_names = [r["name"] for r in raw]
        treated_names = [r.get("name") for r in treated]
        if baseline_names == treated_names:
            identical += 1
        else:
            diffs.append({
                "id": c["id"], "query": c["query"], "family": c["family_keyword"],
                "baseline_top1": raw_top1, "treated_top1": treated_top1,
                "baseline_top3": baseline_names[:3], "treated_top3": treated_names[:3],
            })

    print(f"\n=== Held-out safety result (n={len(cases)}) ===")
    print(f"  Identical to baseline: {identical}/{len(cases)} ({100*identical/len(cases):.0f}%)")
    print(f"  Differences:           {len(diffs)}")
    if diffs:
        print("  FAILURES — library modified output on uncovered queries:")
        for d in diffs[:5]:
            print(f"    {d['id']} ({d['family']}): {d['baseline_top1']} → {d['treated_top1']}")

    OUT_DOC.parent.mkdir(parents=True, exist_ok=True)
    with OUT_DOC.open("w", encoding="utf-8") as f:
        f.write("# family_dedup Held-Out Safety Eval (n=30)\n\n")
        f.write("**Date:** 2026-05-20\n")
        f.write("**Source:** `sandbox/retrieval_v2/tests/suite_eval_heldout.yaml`\n")
        f.write("**Library:** `backend/lib/galaxy/ai/retrievers/family_dedup.py`\n")
        f.write("**Maps:** alias (155 rules) + canonical (60 entries) — both PRODUCTION YAMLs\n\n")
        f.write("## What this measures\n\n")
        f.write("Each query is about a tool family NOT in `tool_family_canonical.yaml` "
                "or `tool_family_aliases.yaml`. For uncovered queries, "
                "`prioritize_query_family()` should leave the candidate list unchanged. "
                "Any difference is a false positive (library acting on queries it "
                "wasn't curated for).\n\n")
        f.write("## Headline\n\n")
        f.write("| Metric | Value |\n|---|---|\n")
        f.write(f"| Queries identical to baseline | {identical}/{len(cases)} "
                f"({100*identical/len(cases):.0f}%) |\n")
        f.write(f"| False-positive differences | {len(diffs)} |\n\n")

        if not diffs:
            f.write("✅ **Library passes held-out safety.** Zero behavior change on 30 "
                    "uncovered families. The disqualifier discipline holds: "
                    "`_infer_target_family()` correctly returns None when no known "
                    "family-keyword appears in the query.\n\n")
        else:
            f.write(f"❌ **{len(diffs)} false positives on held-out.** Library is "
                    f"acting on queries it wasn't curated for.\n\n")
            f.write("### Failure cases\n\n")
            for d in diffs:
                f.write(f"- **{d['id']}** ({d['family']}) `{d['query'][:70]}`\n")
                f.write(f"  - baseline top-3: `{d['baseline_top3']}`\n")
                f.write(f"  - treated top-3: `{d['treated_top3']}`\n")

        f.write("## Interpretation\n\n")
        f.write("This is the same honest-measurement discipline applied to the memory "
                "adapter (`docs/20260520_memory_heldout_results.md`). For the wrapper-"
                "level family_dedup library, 'safety on held-out' means: when the YAML "
                "doesn't know about a family, the library returns input unchanged. "
                "No magic generalization, no false promotion.\n\n")
        f.write("Combined with the earlier 40-query covered-set lift (25% → 90%), "
                "this completes the honest evaluation of family_dedup:\n\n")
        f.write("| Subset | n | Result |\n|---|---|---|\n")
        f.write(f"| covered (canonical YAML) | 40 | top-1 25% → 90% (+65pp) |\n")
        f.write(f"| **held-out (no YAML entry)** | **30** | "
                f"**{identical}/{len(cases)} identical, {len(diffs)} false positives** |\n")

    print(f"\nWrote {OUT_DOC.relative_to(ROOT)}")
    return 0 if not diffs else 1


if __name__ == "__main__":
    sys.exit(main())
