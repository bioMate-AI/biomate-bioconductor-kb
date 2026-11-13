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


def backfill(db_path: Path, apply: bool, overwrite_rule: bool = False) -> dict:
    """Rule-based (re)labelling with provenance.

    Default: label ONLY NULL rows (never touch an existing value — rule or LLM).
    overwrite_rule=True: also RECOMPUTE rows whose input_kinds_method is NULL (legacy rule-origin)
    or 'rule', overwriting changed labels and clearing stale ones to NULL. Rows with method='llm'
    are NEVER touched in either mode."""
    conn = sqlite3.connect(str(db_path))
    cols = {r[1] for r in conn.execute("PRAGMA table_info(workflows)")}
    has_col = "input_kinds" in cols
    if apply and not has_col:
        conn.execute("ALTER TABLE workflows ADD COLUMN input_kinds TEXT")
        has_col = True
    if apply and "input_kinds_method" not in cols:
        conn.execute("ALTER TABLE workflows ADD COLUMN input_kinds_method TEXT")
    has_method = ("input_kinds_method" in cols) or apply
    ik_select = "COALESCE(input_kinds,'')" if has_col else "''"
    m_select = "COALESCE(input_kinds_method,'')" if has_method else "''"
    rows = conn.execute(
        f"SELECT id, name, COALESCE(description,''), COALESCE(annotation,''), "
        f"COALESCE(input_types,'[]'), COALESCE(tags,'[]'), {ik_select}, {m_select} FROM workflows"
    ).fetchall()

    total = len(rows)
    already = newly = corrected = cleared = 0
    hist: collections.Counter = collections.Counter()
    for wid, name, desc, ann, inp, tags, existing, method in rows:
        is_llm = (method == 'llm')
        if existing and (is_llm or not overwrite_rule):
            # respect LLM labels always; respect rule labels unless overwrite_rule
            already += 1
            for k in json.loads(existing):
                hist[k] += 1
            continue
        kinds = rule_classify_kinds({"name": name, "description": desc, "annotation": ann,
                                     "input_types": inp, "tags": tags})
        new = json.dumps(kinds) if kinds else None
        if new == (existing or None):
            if existing:
                already += 1
                for k in json.loads(existing):
                    hist[k] += 1
                if apply and (method or '') == '':
                    # stamp provenance on a legacy (pre-provenance) rule label, unchanged value
                    conn.execute("UPDATE workflows SET input_kinds_method='rule' WHERE id=? "
                                 "AND input_kinds_method IS NULL", (wid,))
            continue
        if not existing and kinds:
            newly += 1
        elif existing and kinds:
            corrected += 1
        elif existing and not kinds:
            cleared += 1
        if kinds:
            for k in kinds:
                hist[k] += 1
        if apply:
            conn.execute(
                "UPDATE workflows SET input_kinds=?, input_kinds_method=? WHERE id=? "
                "AND (input_kinds_method IS NULL OR input_kinds_method='rule')",
                (new, ('rule' if kinds else None), wid))
    if apply:
        conn.commit()
    conn.close()
    return {"total": total, "already_labelled": already, "newly_labelled": newly,
            "corrected": corrected, "cleared": cleared,
            "total_labelled": already + newly + corrected, "by_kind": dict(hist.most_common())}


def _main(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("db", type=Path)
    p.add_argument("--apply", action="store_true", help="write input_kinds")
    p.add_argument("--overwrite-rule", action="store_true",
                   help="recompute + overwrite rule-origin rows (method NULL/'rule'); never touches 'llm'")
    a = p.parse_args(argv)
    res = backfill(a.db, a.apply, overwrite_rule=a.overwrite_rule)
    mode = "APPLIED" if a.apply else "DRY-RUN"
    print(f"[{mode}{' +overwrite-rule' if a.overwrite_rule else ''}] {a.db}")
    print(f"  total rows        : {res['total']}")
    print(f"  already labelled  : {res['already_labelled']}")
    print(f"  newly labelled    : {res['newly_labelled']}")
    print(f"  corrected (rule)  : {res['corrected']}")
    print(f"  cleared to NULL   : {res['cleared']}")
    print(f"  total labelled    : {res['total_labelled']} "
          f"({100.0 * res['total_labelled'] / max(1, res['total']):.1f}%)")
    print("  by kind (label occurrences):")
    for k, n in res["by_kind"].items():
        print(f"    {k:18s} {n}")
    return 0


if __name__ == "__main__":
    sys.exit(_main(sys.argv[1:]))
