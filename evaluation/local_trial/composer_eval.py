#!/usr/bin/env python3
"""
composer_eval.py
----------------
CORRECT-GRANULARITY composer evaluation — multi-nf-core-WORKFLOW requests (not GTN
tool-chains). For each pipeline it runs the real production path (UnifiedWorkflowSearch +
pick_workflow_match → build_dag_plan with the real type_provider) and reports whether the
composer FIRES, and WHY it falls back, with a per-step clean-vs-dirty type diagnosis.

This is the eval `decomposition_real` could NOT be (that dataset is GTN Galaxy-tool chains,
16% in the workflow DB — wrong granularity; see 20261021_DAG_RESOLUTION_COVERAGE_RESULT.md).
It isolates the REAL composer blocker: ~66% of workflows carry free-text `input_types`
(parameter descriptions, not type tokens) so their handoff can never wire — a DATA-QUALITY
gate, independent of the matcher or resolution.

Gold: evaluation/datasets/composer_eval/pipelines.jsonl (each: query, stages[{desc,
depends_on, parallel_with}], expected_fire).
Run:  python3 evaluation/local_trial/composer_eval.py
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

_DB = _REPO / "backend" / "database" / "galaxy_ai_tools.db"
_GOLD = _REPO / "evaluation" / "datasets" / "composer_eval" / "pipelines.jsonl"


def _dirty(toks):
    """A type token is 'dirty' if it is free text (space/paren) rather than a clean type id."""
    return any((" " in t or "(" in t) for t in (toks or []))


def main() -> int:
    search = UnifiedWorkflowSearch(db_path=_DB)
    conn = sqlite3.connect(str(_DB))

    def types(nf):
        r = conn.execute("SELECT input_types, output_types FROM workflows WHERE filename=? OR name=? "
                         "OR filename LIKE ? LIMIT 1", (nf, nf, f"%{nf.split('/')[-1]}%")).fetchone()
        return (json.loads(r[0] or "[]"), json.loads(r[1] or "[]")) if r else ([], [])

    pipes = [json.loads(l) for l in _GOLD.open() if l.strip()]
    fired = correct = 0
    print(f"Composer eval — {len(pipes)} multi-workflow pipelines (real resolver + type handoff)\n")
    for p in pipes:
        stages = p["stages"]
        picks, dirty_dst = {}, []
        for i, st in enumerate(stages, 1):
            pm = pick_workflow_match(search.search(st["desc"]))
            picks[i] = pm
            if pm and st.get("depends_on"):  # dependent step → its input types matter
                din = types(pm["nextflow_path"])[0]
                if _dirty(din):
                    dirty_dst.append(i)

        def resolver(task, _picks=picks, _stages=stages):
            # match the task back to its stage by description
            for i, st in enumerate(_stages, 1):
                if st["desc"] == (task.get("description") if isinstance(task, dict) else ""):
                    return _picks.get(i)
            return None

        tasks = [{"id": "s%d" % i, "description": st["desc"],
                  "depends_on": st.get("depends_on") or [],
                  "parallel_with": st.get("parallel_with")} for i, st in enumerate(stages, 1)]
        plan = build_dag_plan(tasks, resolver, type_provider=lambda nf: types(nf))
        did_fire = plan is not None
        unresolved = [i for i, pm in picks.items() if pm is None]
        exp = p.get("expected_fire")
        ok = "—" if exp is None else ("✓" if did_fire == exp else "✗")
        if did_fire:
            fired += 1
        if exp is not None and did_fire == exp:
            correct += 1
        reason = ("fired" if did_fire
                  else ("unresolved steps %s" % unresolved if unresolved
                        else "type-handoff: dirty/free-text input_types at steps %s" % dirty_dst
                        if dirty_dst else "type-handoff: no compatible types"))
        print(f"  [{ok}] {p['id']:20} fire={str(did_fire):5} (expected {exp})  {reason}")
        if dirty_dst and not did_fire:
            print(f"        └ {len(dirty_dst)} dependent step(s) have FREE-TEXT input_types (data-quality gate)")

    graded = [p for p in pipes if p.get("expected_fire") is not None]
    print(f"\n  fired: {fired}/{len(pipes)}   |   matches expected_fire: {correct}/{len(graded)} graded")
    print("  Takeaway: clean-type workflows (genomics/pharma) compose; Bioconductor chains fall back on\n"
          "  FREE-TEXT input_types (66% of catalog) — the next composer fix is DATA (clean the type\n"
          "  columns), not the matcher/model. Fan-out (shared-input roots) composes with no handoff.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
