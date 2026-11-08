#!/usr/bin/env python3
"""
composer_eval_curated.py  (READ-ONLY)
-------------------------------------
The KEYSTONE composer eval: each stage carries a curated EXPECTED workflow (anchor), so it
SEPARATES the composer's compounding gates instead of conflating them:

  (A) resolver PRECISION   — does the live search's top pick match the curated expected workflow?
  (B) fire | EXPECTED + current types   — if resolution were perfect, does the handoff wire today?
  (C) fire | EXPECTED + DERIVED input types — + the input_types cleanup (retype_dryrun derivation)?

This isolates "the resolver picks the wrong workflow" from "the types don't chain" from "cleaning
input_types helps", and distinguishes a real representation gap (counts_matrix vs ExpressionSet
across the nf-core↔Bioconductor universe boundary) from a metadata bug. Writes NOTHING.

Run: python3 evaluation/local_trial/composer_eval_curated.py
"""
from __future__ import annotations

import sys
for _m in ("sentence_transformers", "torch", "scipy"):
    sys.modules[_m] = None

import json
import sqlite3
from pathlib import Path

_REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(_REPO / "backend" / "lib"))
from galaxy.ai.unified_workflow_search import UnifiedWorkflowSearch  # noqa: E402
from galaxy.ai.decomposed_dag import pick_workflow_match, build_dag_plan  # noqa: E402
from evaluation.local_trial.retype_dryrun import derive_input_tokens, _jl, _clean  # noqa: E402

_DB = _REPO / "backend" / "database" / "galaxy_ai_tools.db"
_GOLD = _REPO / "evaluation" / "datasets" / "composer_eval" / "curated_pipelines.jsonl"


def main() -> int:
    search = UnifiedWorkflowSearch(db_path=_DB)
    conn = sqlite3.connect(str(_DB))

    def expected_row(anchor):
        return conn.execute(
            "SELECT filename, input_types, output_types, params_schema FROM workflows "
            "WHERE filename LIKE ? ORDER BY length(filename) LIMIT 1", (f"%{anchor}%",)).fetchone()

    def types_of(anchor, derived=False):
        r = expected_row(anchor)
        if not r:
            return ([], [])
        cin = _jl(r[1])
        din = cin if (_clean(cin) or not derived) else (derive_input_tokens(r[3]) or cin)
        return (din, _jl(r[2]))

    pipes = [json.loads(l) for l in _GOLD.open() if l.strip()]
    prec_hit = prec_tot = 0
    fire_pick = fire_exp_cur = fire_exp_der = 0

    for p in pipes:
        stages = p["stages"]
        print(f"\n{p['id']}  [{p['universe']}]")
        # (A) precision: live top pick vs curated expected
        picks = {}
        for i, st in enumerate(stages, 1):
            pm = pick_workflow_match(search.search(st["desc"]))
            picks[i] = pm
            got = pm["nextflow_path"] if pm else None
            ok = bool(got and st["expected"] in got)
            prec_tot += 1; prec_hit += int(ok)
            er = expected_row(st["expected"])
            print(f"  s{i} {st['desc'][:40]:42} pick={'/'.join((got or '—').split('/')[-2:]):26} "
                  f"expected~{st['expected']:24} {'HIT' if ok else 'MISS'}")

        def mk_resolver(mode):  # mode: 'pick' | 'expected'
            def r(task, _s=stages):
                for i, st in enumerate(_s, 1):
                    if st["desc"] == (task.get("description") if isinstance(task, dict) else ""):
                        if mode == "pick":
                            return picks.get(i)
                        er = expected_row(st["expected"])
                        return {"nextflow_path": er[0], "parameters": {}} if er else None
                return None
            return r

        tasks = [{"id": "s%d" % i, "description": st["desc"],
                  "depends_on": st.get("depends_on") or [],
                  "parallel_with": st.get("parallel_with")} for i, st in enumerate(stages, 1)]
        anchor_by_path = {expected_row(st["expected"])[0]: st["expected"]
                          for st in stages if expected_row(st["expected"])}

        def tp(nf, derived):
            anc = anchor_by_path.get(nf)
            return types_of(anc, derived=derived) if anc else ([], [])

        f_pick = build_dag_plan(tasks, mk_resolver("pick"), type_provider=lambda nf: tp(nf, False)) is not None
        f_cur = build_dag_plan(tasks, mk_resolver("expected"), type_provider=lambda nf: tp(nf, False)) is not None
        f_der = build_dag_plan(tasks, mk_resolver("expected"), type_provider=lambda nf: tp(nf, True)) is not None
        fire_pick += f_pick; fire_exp_cur += f_cur; fire_exp_der += f_der
        print(f"    FIRE: resolver-picks={f_pick}  expected+current-types={f_cur}  expected+DERIVED-inputs={f_der}")

    n = len(pipes)
    print(f"\n==== summary ({n} curated pipelines) ====")
    print(f"(A) resolver precision (top pick == expected): {prec_hit}/{prec_tot} = {100*prec_hit/max(prec_tot,1):.0f}%")
    print(f"(B) fire with resolver's actual picks:          {fire_pick}/{n}")
    print(f"(C) fire with CORRECT (expected) workflows:     {fire_exp_cur}/{n}  (current types)")
    print(f"(D) fire with expected + DERIVED clean inputs:  {fire_exp_der}/{n}")
    print("\nReads: (A) low → resolver precision is a gate. (C)>(B) → precision is the gate, not types.\n"
          "(D)>(C) → input_types cleanup helps once resolution is correct. A chain still failing at (D)\n"
          "is a REAL representation gap (e.g. counts_matrix vs ExpressionSet across nf-core↔Bioconductor),\n"
          "needing an adapter step, not a metadata fix. READ-ONLY; nothing written.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
