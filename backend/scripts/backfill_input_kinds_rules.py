"""Deterministic rule-based backfill of workflows.input_kinds (the FREE, no-LLM pass).

This applies the same rule_classify_kinds() the write path uses (index_all_workflows,
register_ai_tool_workflows) to every EXISTING row, so the data-shape gate (step 8a) and the
relevance floor's input_compatible veto go live for the rows the rules can label with high
precision. Rows the rules cannot label confidently are left NULL for the LLM refinement pass:

    PYTHONPATH=lib python3 -m galaxy.ai.chain_composer.input_kinds_classifier \\
        --openrouter-model google/gemini-3.8-flash --workers 16 --output kinds.jsonl
    PYTHONPATH=lib python3 -m galaxy.ai.chain_composer.input_kinds_classifier \\
        --apply <db> --output kinds.jsonl

Usage:
    PYTHONPATH=lib python3 scripts/backfill_input_kinds_rules.py <db>            # dry-run: report only
    PYTHONPATH=lib python3 scripts/backfill_input_kinds_rules.py <db> --apply    # write (NULL rows only)
"""
from __future__ import annotations

import argparse
import collections
import json
import sqlite3
import sys
from pathlib import Path

from galaxy.ai.chain_composer.input_kinds_classifier import rule_classify_kinds


def backfill(db_path: Path, apply: bool) -> dict:
    conn = sqlite3.connect(str(db_path))
    has_col = "input_kinds" in {r[1] for r in conn.execute("PRAGMA table_info(workflows)")}
    if not has_col and apply:
        conn.execute("ALTER TABLE workflows ADD COLUMN input_kinds TEXT")
        has_col = True
    ik_select = "COALESCE(input_kinds,'')" if has_col else "''"
    rows = conn.execute(
        f"SELECT id, name, COALESCE(description,''), COALESCE(annotation,''), "
        f"COALESCE(input_types,'[]'), COALESCE(tags,'[]'), {ik_select} FROM workflows"
    ).fetchall()

    total = len(rows)
    labelled = already = newly = 0
    hist: collections.Counter = collections.Counter()
    for wid, name, desc, ann, inp, tags, existing in rows:
        if existing:  # respect any existing (e.g. LLM) label
            already += 1
            for k in json.loads(existing):
                hist[k] += 1
            continue
        kinds = rule_classify_kinds({"name": name, "description": desc, "annotation": ann,
                                     "input_types": inp, "tags": tags})
        if not kinds:
            continue
        labelled += 1
        newly += 1
        for k in kinds:
            hist[k] += 1
        if apply:
            conn.execute("UPDATE workflows SET input_kinds=? WHERE id=?", (json.dumps(kinds), wid))
    if apply:
        conn.commit()
    conn.close()
    return {"total": total, "already_labelled": already, "newly_labelled": newly,
            "total_labelled": already + newly, "by_kind": dict(hist.most_common())}


def _main(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("db", type=Path)
    p.add_argument("--apply", action="store_true", help="write input_kinds (NULL rows only)")
    a = p.parse_args(argv)
    res = backfill(a.db, a.apply)
    mode = "APPLIED" if a.apply else "DRY-RUN"
    print(f"[{mode}] {a.db}")
    print(f"  total rows        : {res['total']}")
    print(f"  already labelled  : {res['already_labelled']}")
    print(f"  newly labelled    : {res['newly_labelled']}")
    print(f"  total labelled    : {res['total_labelled']} "
          f"({100.0 * res['total_labelled'] / max(1, res['total']):.1f}%)")
    print("  by kind (label occurrences):")
    for k, n in res["by_kind"].items():
        print(f"    {k:18s} {n}")
    return 0


if __name__ == "__main__":
    sys.exit(_main(sys.argv[1:]))
