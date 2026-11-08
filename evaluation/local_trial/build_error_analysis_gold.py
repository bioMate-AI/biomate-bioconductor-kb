#!/usr/bin/env python3
"""
build_error_analysis_gold.py
----------------------------
Convert the MODEL-owned error-analysis candidates (error_analysis_gold_candidates.jsonl) into an
ADDITIVE SFT + GRPO pool. These are REAL benchmark items the on-prem model got wrong while the
catalog/harness could NOT fix them (routing: gold IS in the catalog, 0 data-gap) — i.e. the genuine
trainable slice.

Outputs (additive; does NOT touch decision_*/decomp_* pools):
  docs/20260912_onprem_llm/data_pool_v2/error_analysis_sft.jsonl   ({messages:[sys,user,asst]})
  docs/20260912_onprem_llm/data_pool_v2/error_analysis_grpo.jsonl  ({prompt,gold,scorer,task,id})
  docs/20260912_onprem_llm/data_pool_v2/error_analysis_gold_manifest.json

LEAK DISCIPLINE: these ARE RealBio items — training on them means they MUST be held out of any
future RealBio eval of the trained model (noted in the manifest). Cross-benchmark leak vs
decision_eval / decomposition_real is nil (disjoint id-spaces, asserted). Run:
    python3 evaluation/local_trial/build_error_analysis_gold.py [--selftest]
"""
from __future__ import annotations
import json, os, sys
from pathlib import Path

_REPO = Path(__file__).resolve().parents[2]
_PE = _REPO / "evaluation" / "datasets" / "public_export"
sys.path.insert(0, str(_PE))
import score as S  # noqa: E402
_norm = getattr(S, "norm", lambda x: str(x or "").strip().lower())

CAND = Path(__file__).resolve().parent / "error_analysis_gold_candidates.jsonl"
OUT = _REPO / "docs" / "20260912_onprem_llm" / "data_pool_v2"

SYS = {
 "cross_domain_routing": "You are BioMate's workflow router. Given a bioinformatics request, reply with the single best workflow identifier.",
 "param_prefill": "You are BioMate's parameter pre-fill. Given a request, emit ONLY the parameters that are specified; never invent inputs/accessions that were not given. Reply with a JSON object.",
 "autofix": "You are BioMate's execution auto-repair. Given an error log, reply with the fix category.",
}


def _lit(x):
    import ast, json as _j
    if isinstance(x, (dict, list)): return x
    for parse in (_j.loads, ast.literal_eval):   # json first (handles JSON true/false), then Python repr
        try: return parse(x)
        except Exception: pass
    return {}


def _assistant(task, cand, goldrec):
    if task == "cross_domain_routing":
        return str(cand["gold"])
    if task == "param_prefill":
        return json.dumps(_lit(cand["gold"]))              # expected_params only (excludes must_not_fill by construction)
    if task == "autofix":
        return str(cand["gold"])
    return ""


def _valid(task, asst, goldrec, cand):
    """Does the gold completion score CORRECT under the task's logic?"""
    if task == "cross_domain_routing":
        gold = {_norm(goldrec.get("correct_workflow"))} | {_norm(a) for a in (goldrec.get("acceptable_alts") or [])}
        return _norm(asst) in gold
    if task == "param_prefill":
        got = _lit(asst); exp = _lit(goldrec.get("expected_params")); forb = set(_lit(goldrec.get("must_not_fill")) or [])
        return isinstance(got, dict) and set(exp).issubset(got) and not (set(got) & forb)
    if task == "autofix":
        return _norm(asst) in {_norm(goldrec.get("category")), _norm(goldrec.get("expected_fix"))}
    return False


def _grpo_gold(task, goldrec):
    if task == "cross_domain_routing":
        return {"correct_workflow": goldrec.get("correct_workflow"), "acceptable_alts": goldrec.get("acceptable_alts") or []}
    if task == "param_prefill":
        return {"expected_params": _lit(goldrec.get("expected_params")), "must_not_fill": _lit(goldrec.get("must_not_fill")) or []}
    if task == "autofix":
        return {"category": goldrec.get("category"), "expected_fix": goldrec.get("expected_fix")}
    return {}


def build():
    cands = [json.loads(l) for l in CAND.open() if l.strip()]
    GT = {"cross_domain_routing": S.load("cross_domain_routing"),
          "param_prefill": S.load("param_prefill"),
          "autofix": S.load("autofix_benchmark")}
    sft, grpo, report, failures, seen = [], [], [], [], set()
    for c in cands:
        task, cid = c["task"], c["id"]
        key = (task, cid)
        if key in seen:      # dedup
            continue
        seen.add(key)
        goldrec = GT[task].get(cid, {})
        asst = _assistant(task, c, goldrec)
        ok = _valid(task, asst, goldrec, c)
        if not ok:
            failures.append(key)
        sft.append({"messages": [{"role": "system", "content": SYS[task]},
                                 {"role": "user", "content": c.get("prompt") or ""},
                                 {"role": "assistant", "content": asst}],
                    "task": task, "id": cid, "owner": c.get("owner"), "src": "error_analysis"})
        grpo.append({"prompt": f"{SYS[task]}\n\n{c.get('prompt') or ''}", "gold": json.dumps(_grpo_gold(task, goldrec)),
                     "scorer": task, "task": task, "id": cid, "src": "error_analysis"})
        report.append({"task": task, "id": cid, "valid": ok})
    return {"sft": sft, "grpo": grpo, "report": report, "failures": failures}


def _eval_leak_ids():
    ids = set()
    for f in ("decision_eval.jsonl",):
        p = OUT / f
        if p.exists():
            ids |= {json.loads(l).get("task_id") or json.loads(l).get("id") for l in p.open() if l.strip()}
    dr = _REPO / "evaluation" / "datasets" / "decomposition_real" / "decomposition_real.jsonl"
    if dr.exists():
        ids |= {json.loads(l).get("id") for l in dr.open() if l.strip()}
    return {x for x in ids if x}


def main():
    import collections
    res = build()
    n = len(res["sft"])
    by = collections.Counter(r["task"] for r in res["report"])
    valid = sum(1 for r in res["report"] if r["valid"])
    leak = {r["id"] for r in res["report"]} & _eval_leak_ids()
    print(f"error-analysis gold: {n} rows  valid={valid}/{n}  per-task={dict(by)}")
    print(f"cross-benchmark leak vs decision_eval/decomposition_real: {len(leak)} (expect 0)")
    if res["failures"]:
        print("FAIL — gold completions not scoring correct:", res["failures"][:10]); return 1
    if leak:
        print("FAIL — id overlap with a held-out eval:", sorted(leak)[:10]); return 1
    if "--selftest" in sys.argv:
        print("selftest OK (no files written)"); return 0
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "error_analysis_sft.jsonl").write_text("".join(json.dumps(r) + "\n" for r in res["sft"]))
    (OUT / "error_analysis_grpo.jsonl").write_text("".join(json.dumps(r) + "\n" for r in res["grpo"]))
    (OUT / "error_analysis_gold_manifest.json").write_text(json.dumps({
        "n_rows": n, "valid": valid, "per_task": dict(by),
        "source": "evaluation/local_trial/error_analysis_gold_candidates.jsonl (model-owned failures)",
        "routing_data_gap_subtracted": 0,
        "cross_benchmark_leak": len(leak),
        "CAVEAT": ("These ARE RealBio benchmark items (routing/param/autofix). Training on them means "
                   "they MUST be excluded from any RealBio eval of the trained model (train=test leak "
                   "otherwise) — hold them out or eval on fresh items. GRPO rows carry {gold,scorer}; "
                   "the per-task reward reuses score.py's per-item logic (wire in the GPU trainer, "
                   "like decision_reward). value/missing param items are NOT included (flagged only)."),
        "files": ["error_analysis_sft.jsonl", "error_analysis_grpo.jsonl"],
    }, indent=2))
    print("wrote error_analysis_sft.jsonl + error_analysis_grpo.jsonl + manifest to data_pool_v2/")
    return 0


if __name__ == "__main__":
    sys.exit(main())
