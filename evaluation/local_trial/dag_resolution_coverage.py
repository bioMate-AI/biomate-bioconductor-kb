#!/usr/bin/env python3
"""
dag_resolution_coverage.py
--------------------------
OFFLINE measurement of the DAG composer's RESOLUTION COVERAGE — the dominant driver of
whether `build_dag_plan` fires or falls back to single-task (ai_assistant._resolve_task_to_workflow
→ pick_workflow_match, score >= DAG_RESOLVE_MIN_SCORE). `build_dag_plan` returns None if ANY
subtask fails to resolve, so per-plan fire is upper-bounded by "every subtask resolves."

This answers the P1 question — is enabling the composer a flag-flip (resolution is high) or a
training project (resolution confidence is the gap) — WITHOUT any LLM spend. It assumes a PERFECT
decomposition (uses the gold subtasks from `decomposition_real`, 68 real nf-core/chain/GTN
topologies) and runs the REAL production resolver (UnifiedWorkflowSearch + pick_workflow_match)
over the present workflow DB.

Caveats: (1) FTS/BM25 path only — the embedding model is blocked for offline/env reasons, so
dense retrieval is off; production scores with embeddings ON may differ (report accordingly).
(2) This measures the RESOLUTION gate only; dependent steps also need a type-compatible handoff
(`_workflow_io_types`) — an ADDITIONAL gate not measured here, so true fire-rate <= all-resolve-rate.

Run: python3 evaluation/local_trial/dag_resolution_coverage.py
"""
from __future__ import annotations

# Block heavy/ABI-broken optional deps BEFORE importing the search module, so its
# embedding guard falls back to FTS/BM25 (the guard only catches ImportError; anaconda
# scipy throws TypeError at load, so we force a clean ImportError instead).
import sys
for _m in ("sentence_transformers", "torch", "scipy"):
    sys.modules[_m] = None  # `import _m` now raises ImportError → FTS-only path

import json
import statistics
from pathlib import Path

_REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(_REPO / "backend" / "lib"))

from galaxy.ai.unified_workflow_search import UnifiedWorkflowSearch  # noqa: E402
from galaxy.ai.decomposed_dag import (  # noqa: E402
    pick_workflow_match, build_dag_plan, DAG_RESOLVE_MIN_SCORE,
)
import sqlite3 as _sqlite  # noqa: E402

_DATA = _REPO / "evaluation" / "datasets" / "decomposition_real" / "decomposition_real.jsonl"
_DB = _REPO / "backend" / "database" / "galaxy_ai_tools.db"


def _descriptions(subtask: dict):
    """Candidate natural descriptions for a gold subtask, best-effort proxies for what a
    decomposition would emit. We try a role+domain phrase and the raw sub_task token."""
    role = (subtask.get("role") or "").replace("_", " ").strip()
    domain = (subtask.get("domain") or "").strip()
    sub = (subtask.get("sub_task") or subtask.get("tool_id") or "").strip()
    phrase = " ".join(x for x in (role, domain) if x) or sub
    return {"role_domain": phrase, "sub_task": sub}


def main() -> int:
    if not _DB.is_file():
        print(f"DB absent: {_DB} — this probe needs the workflow DB (present on dev/S3).")
        return 2
    search = UnifiedWorkflowSearch(db_path=_DB)
    rows = [json.loads(l) for l in _DATA.open() if l.strip()]

    # measure under two description strategies
    strategies = ["role_domain", "sub_task"]
    per_node = {s: {"resolved": 0, "total": 0, "scores": []} for s in strategies}
    per_plan = {s: {"all_resolve": 0, "total": 0} for s in strategies}
    by_structure = {s: {} for s in strategies}
    resolve_cache: dict = {}

    def resolve(desc: str):
        if desc in resolve_cache:
            return resolve_cache[desc]
        matches = search.search(desc) if desc else []
        top_score = (getattr(matches[0], "score", 0) if matches else 0) or 0
        picked = pick_workflow_match(matches)
        resolve_cache[desc] = (picked is not None, float(top_score))
        return resolve_cache[desc]

    for row in rows:
        subs = row.get("gold_subtasks") or []
        if not subs:
            continue
        struct = row.get("structure", "?")
        for strat in strategies:
            all_ok = True
            for st in subs:
                desc = _descriptions(st)[strat]
                ok, score = resolve(desc)
                per_node[strat]["total"] += 1
                per_node[strat]["scores"].append(score)
                if ok:
                    per_node[strat]["resolved"] += 1
                else:
                    all_ok = False
            per_plan[strat]["total"] += 1
            bs = by_structure[strat].setdefault(struct, {"all_resolve": 0, "total": 0})
            bs["total"] += 1
            if all_ok:
                per_plan[strat]["all_resolve"] += 1
                bs["all_resolve"] += 1

    print(f"DAG resolution coverage — {len(rows)} real topologies, DB={_DB.name}, "
          f"FTS-only (embeddings off), score bar >= {DAG_RESOLVE_MIN_SCORE}\n")
    for strat in strategies:
        n = per_node[strat]; p = per_plan[strat]; sc = n["scores"]
        node_rate = n["resolved"] / n["total"] if n["total"] else 0.0
        plan_rate = p["all_resolve"] / p["total"] if p["total"] else 0.0
        med = statistics.median(sc) if sc else 0.0
        print(f"[description = {strat}]")
        print(f"  per-SUBTASK resolution:  {n['resolved']}/{n['total']} = {node_rate:.1%}  "
              f"(top-match score: min {min(sc or [0]):.1f} / med {med:.1f} / max {max(sc or [0]):.1f})")
        print(f"  per-PLAN all-resolve:    {p['all_resolve']}/{p['total']} = {plan_rate:.1%}  "
              f"(= build_dag_plan FIRE upper bound; true fire <= this, minus type-handoff gate)")
        print(f"  by structure: " + ", ".join(
            f"{k} {v['all_resolve']}/{v['total']}" for k, v in sorted(by_structure[strat].items())))
        print()
    print("Interpretation: high per-plan all-resolve → resolution is NOT the gate; low → resolution "
          "confidence is the real gap (a retrieval/training target, not just enabling the composer).")

    # ---- SECOND GATE: full build_dag_plan with the real type_provider (handoff) ----
    # Replicate _get_workflow_types (workflow_chain.py:1167) — a plain sqlite lookup — to avoid
    # importing the heavy router module. build_dag_plan wires DEPENDENT-step handoffs by EXACT
    # output→input type-string match; this measures how often that exact match holds.
    _tp_cache: dict = {}

    def type_provider(nf_path: str):
        if nf_path in _tp_cache:
            return _tp_cache[nf_path]
        inp, out = [], []
        try:
            conn = _sqlite.connect(str(_DB))
            r = conn.execute(
                "SELECT input_types, output_types FROM workflows WHERE name=? OR filename LIKE ? LIMIT 1",
                (nf_path, f"%{nf_path.split('/')[-1]}%")).fetchone()
            conn.close()
            if r:
                inp, out = json.loads(r[0] or "[]"), json.loads(r[1] or "[]")
        except Exception:
            pass
        _tp_cache[nf_path] = (inp, out)
        return _tp_cache[nf_path]

    def resolve_full(task):
        # build_dag_plan passes the TASK; mirror production _resolve_task_to_workflow (uses .description)
        desc = task.get("description") if isinstance(task, dict) else getattr(task, "description", None)
        return pick_workflow_match(search.search(desc)) if desc else None

    fired = unresolved = handoff_fail = 0
    dependent_plans = 0
    for row in rows:
        subs = sorted(row.get("gold_subtasks") or [], key=lambda s: s.get("order", 0))
        if not subs:
            continue
        tasks, has_dep = [], False
        for i, st in enumerate(subs, start=1):
            gdep = [d for d in (st.get("depends_on") or []) if isinstance(d, int) and 1 <= d < i]
            if gdep:
                has_dep = True
            tasks.append({
                "id": st.get("tool_id") or ("step_%d" % i),
                "description": _descriptions(st)["role_domain"],
                "depends_on": gdep,
                "parallel_with": None if gdep else [1],  # empty-dep gold node = root
            })
        if has_dep:
            dependent_plans += 1
        plan = build_dag_plan(tasks, resolve_full, type_provider=type_provider)
        if plan:
            fired += 1
        elif any(resolve_full(t) is None for t in tasks):
            unresolved += 1
        else:
            handoff_fail += 1  # all resolved but a dependent step had no EXACT type match

    n = len(rows)
    print(f"\nFULL build_dag_plan (resolver + exact-match type handoff), {n} plans:")
    print(f"  FIRED (returns a plan):           {fired}/{n} = {fired/n:.1%}")
    print(f"  fallback — a subtask unresolved:  {unresolved}/{n}")
    print(f"  fallback — type-handoff no match: {handoff_fail}/{n}  ({dependent_plans} plans have dependent steps)")
    print("  NOTE: build_dag_plan uses EXACT type-string match; check_step_compatibility uses "
          "SEMANTIC (_type_satisfies). If handoff_fail is high, the exact-match gate (not resolution) "
          "is the real composer bottleneck — a harness fix (semantic handoff), not training.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
