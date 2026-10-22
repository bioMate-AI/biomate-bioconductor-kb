#!/usr/bin/env python3
"""
build_decision_sft.py
---------------------
Turn the DrugDev *decision* benchmark (9 archetypes / 30 tasks) into training data:

  (1) SFT rows   — {"messages":[system,user,assistant]} with a synthesized GOLD completion
                   (a correct decision that SCORES ~1.0 under its own scorer — verified,
                   fail-closed, so no non-winning target is ever emitted).
  (2) GRPO rows  — {"prompt", "gold"(json ground_truth), "scorer", "labels", ...} fed to
                   decision_reward.decision_reward as the verifiable RL reward.

Policy tag per task:
  * learn_decision     — judgment/knowledge/composition tasks the on-prem model SHOULD learn
  * route_not_compute  — numeric/deterministic (dose projection): keep as ROUTE+interpret
                         exemplars; the engine computes, the model must not learn arithmetic.

Outputs (under docs/20260912_onprem_llm/data_pool_v2/, next to the decomp pool):
  decision_sft.jsonl, decision_grpo.jsonl, decision_sft_manifest.json

Run:   python3 evaluation/local_trial/build_decision_sft.py
       python3 evaluation/local_trial/build_decision_sft.py --selftest   # build + verify only
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path
from typing import Any, Dict, List

_REPO = Path(__file__).resolve().parents[2]
if str(_REPO) not in sys.path:
    sys.path.insert(0, str(_REPO))

from evaluation.adapters.decision_benchmark_adapter import (  # noqa: E402
    DecisionBenchmarkAdapter, DECISION_DATASETS,
)
from evaluation.local_trial.decision_reward import score_one  # noqa: E402

OUT_DIR = _REPO / "docs" / "20260912_onprem_llm" / "data_pool_v2"

SYS = (
    "You are BioMate, a drug-development decision assistant. Given a project vignette, make "
    "the specific decision asked for, justify it from the data, and end with the exact "
    "structured block the task requests (DECISION/verdict/action/answer/required/chain). "
    "Route deterministic computation (dose arithmetic, PK) to the engine rather than guessing."
)

# numeric/deterministic archetypes: keep as route+interpret exemplars, not arithmetic to learn
_ROUTE_NOT_COMPUTE = {"numeric"}


def _first_alias(vocab: Dict[str, Any], canon: str) -> str:
    aliases = vocab.get(canon) or []
    return aliases[0] if aliases else canon


def _gold_completion(gt: Dict[str, Any], scorer: str, meta: Dict[str, Any]) -> str:
    """Synthesize a correct, natural answer that scores ~1.0 under `scorer`."""
    must = gt.get("rationale_must_mention", []) or []

    if scorer == "decision":
        adv, dep = gt["advance_best"], gt["deprioritize"]
        lib = gt.get("primary_liability", "")
        lib_tok = (gt.get("liability_aliases") or [lib])[0]
        why = (f"Weighing the measured profiles, {', '.join(dep)} carries the dominant "
               f"{lib} liability ({lib_tok}); {', '.join(adv)} have the cleaner profiles and "
               f"advance.")
        why = _ensure_terms(why, must)
        return (f"{why}\nDECISION:\n  advance: {', '.join(adv)}\n"
                f"  deprioritize: {', '.join(dep)}\n  primary_liability: {lib}")

    if scorer == "categorical":
        v = gt["verdict"]
        key = "action" if "action" in meta.get("decision_required_key", "action") else "verdict"
        num = gt.get("numeric")
        why = f"Based on the evidence, the correct call is {v.replace('_', ' ')}."
        if num:
            why += f" The relevant threshold is {num.get('cue', '').upper()} {num['true_value']}."
        why = _ensure_terms(why, must)
        return f"{why}\n{key}: {v}"

    if scorer == "set":
        vocab = gt.get("item_vocab", {})
        items = [_first_alias(vocab, c) for c in gt["required"]]
        why = _ensure_terms("These are the deliverables that gate the next step.", must)
        return f"{why}\nrequired: {', '.join(items)}"

    if scorer == "numeric":
        tv, unit, cue = gt["true_value"], gt.get("unit", ""), gt.get("cue", "value")
        why = _ensure_terms(
            f"Applying the standard method/engine, the {cue} resolves to {tv} {unit}.".strip(),
            must)
        return f"{why}\nanswer: {tv} {unit}".strip()

    if scorer == "mtd":
        lvl, mg = gt.get("true_MTD_level"), gt.get("true_MTD_mg")
        flags = gt.get("safety_flags", []) or []
        if lvl is None:
            body = "All tested doses stayed below target; the MTD was not reached in this range."
        else:
            body = f"The MTD is dose level {lvl} ({mg} mg)."
        if "HIGH_DLT_AT_STARTING_DOSE" in flags:
            body += " The starting dose already sits at target DLT — flag high DLT at the starting dose."
        if lvl is None:
            return body + "\nmtd_level: none\nmtd_mg: none"
        return body + f"\nmtd_level: {lvl}\nmtd_mg: {mg}"

    if scorer == "chain":
        vocab = gt.get("step_vocab", {})
        steps = [_first_alias(vocab, c) for c in gt["reference_chain"]]
        why = _ensure_terms("The pipeline proceeds stage by stage, each gating the next.", must)
        return f"{why}\nchain: {' -> '.join(steps)}"

    return ""


def _ensure_terms(text: str, must: List[str]) -> str:
    """Guarantee the rationale references each must-mention term (woven, else appended)."""
    low = text.lower()
    missing = [t for t in must if t.lower() not in low]
    if missing:
        text += " (" + "; ".join(missing) + ")"
    return text


def _norm(q: str) -> str:
    import re
    return " ".join(re.sub(r"[^a-z0-9 ]", " ", (q or "").lower()).split())


def _toks(q: str) -> set:
    return set(_norm(q).split())


def _jaccard(a: str, b: str) -> float:
    A, B = _toks(a), _toks(b)
    return len(A & B) / len(A | B) if (A and B) else 0.0


def build_records() -> Dict[str, Any]:
    """Build one verified record per task (NOT yet split into train/eval)."""
    records: List[dict] = []
    failures: List[dict] = []
    for name in DECISION_DATASETS:
        adapter = DecisionBenchmarkAdapter({"dataset": name})
        for task in adapter.load_tasks():
            gt = task.ground_truth
            scorer = task.metadata.get("scorer", "decision")
            labels = task.metadata.get("labels")
            gold = _gold_completion(gt, scorer, task.metadata)
            s = score_one(gold, gt, scorer, labels)      # VERIFY gold wins its own scorer
            if s < 0.9:
                failures.append({"task_id": task.task_id, "scorer": scorer, "score": s})
            records.append({
                "dataset": name, "task_id": task.task_id,
                "archetype": task.metadata.get("archetype"), "scorer": scorer,
                "labels": labels, "prompt": task.question, "gold_completion": gold,
                "gold_score": round(s, 4), "ground_truth": gt,
                "policy": "route_not_compute" if scorer in _ROUTE_NOT_COMPUTE else "learn_decision",
            })
    return {"records": records, "failures": failures}


def _split(records: List[dict], mode: str, holdout_dataset: Optional[str]):
    """Split into DISJOINT train/eval, grouping by DATASET (the template source).
    Returns (train, eval, split_meta).

    mode='stratified'  : hold out the last task_id of each dataset that has >=3 items.
                         Item-disjoint, but the held-out item shares its dataset's TEMPLATE
                         with its train siblings -> an IN-DISTRIBUTION holdout (disclosed, not
                         a clean OOD eval). A clean OOD eval needs newly-authored vignettes.
    mode='leave_dataset_out' : the named dataset is fully held out (genuine cross-template
                         generalization probe); it then gets NO training signal.
    """
    by_ds: Dict[str, List[dict]] = {}
    for r in records:
        by_ds.setdefault(r["dataset"], []).append(r)
    train, ev = [], []
    if mode == "leave_dataset_out":
        for ds, items in by_ds.items():
            (ev if ds == holdout_dataset else train).extend(items)
        split_type = f"leave_dataset_out:{holdout_dataset} (OOD cross-template)"
    else:
        for ds, items in by_ds.items():
            items = sorted(items, key=lambda r: r["task_id"])
            if len(items) >= 3:
                ev.append(items[-1]); train.extend(items[:-1])
            else:
                train.extend(items)
        split_type = "stratified_in_distribution_holdout (directional; shares dataset template)"
    return train, ev, split_type


def _sft_row(r: dict) -> dict:
    return {"messages": [{"role": "system", "content": SYS},
                         {"role": "user", "content": r["prompt"]},
                         {"role": "assistant", "content": r["gold_completion"]}],
            "task_id": r["task_id"], "archetype": r["archetype"],
            "scorer": r["scorer"], "policy": r["policy"], "gold_score": r["gold_score"]}


def _grpo_row(r: dict) -> dict:
    return {"prompt": f"{SYS}\n\n{r['prompt']}", "gold": json.dumps(r["ground_truth"]),
            "scorer": r["scorer"], "labels": r["labels"], "task_id": r["task_id"],
            "policy": r["policy"]}


def _eval_row(r: dict) -> dict:
    # held-out eval: NO gold_completion (don't leak the target); scored via decision_reward
    return {"prompt": f"{SYS}\n\n{r['prompt']}", "gold": json.dumps(r["ground_truth"]),
            "scorer": r["scorer"], "labels": r["labels"], "task_id": r["task_id"],
            "archetype": r["archetype"], "policy": r["policy"]}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--mode", choices=["stratified", "leave_dataset_out"],
                    default="stratified")
    ap.add_argument("--holdout-dataset", default=None,
                    help="dataset name to fully hold out (leave_dataset_out mode)")
    ap.add_argument("--selftest", action="store_true",
                    help="build + verify + split + leak-check in memory; do not write files")
    args = ap.parse_args()

    res = build_records()
    recs = res["records"]
    n = len(recs)
    n_ok = sum(1 for r in recs if r["gold_score"] >= 0.9)
    if res["failures"]:
        print(f"FAIL: {len(res['failures'])} synthesized gold completions scored < 0.9 — "
              f"not emitting non-winning targets. Fix templates first.")
        return 1

    train, ev, split_type = _split(recs, args.mode, args.holdout_dataset)
    train_ids = {r["task_id"] for r in train}
    eval_ids = {r["task_id"] for r in ev}

    # --- LEAK GUARD (fail-closed on true leaks; DISCLOSE in-distribution similarity) ---
    overlap = train_ids & eval_ids
    exact_dup = []
    nearest = []  # per eval item: nearest train prompt Jaccard (honesty disclosure)
    for e in ev:
        sims = [( _jaccard(e["prompt"], t["prompt"]), t["task_id"]) for t in train]
        best = max(sims, default=(0.0, None))
        nearest.append({"eval": e["task_id"], "nearest_train": best[1],
                        "jaccard": round(best[0], 3)})
        if any(_norm(e["prompt"]) == _norm(t["prompt"]) for t in train):
            exact_dup.append(e["task_id"])
    if overlap or exact_dup:
        print(f"FAIL (leak): task-id overlap={sorted(overlap)} exact-dup={exact_dup}")
        return 1

    learn = sum(1 for r in train if r["policy"] == "learn_decision")
    route = len(train) - learn
    print(f"decision gold: {n} tasks (gold-verified {n_ok}/{n}); split={split_type}")
    print(f"  TRAIN {len(train)} (learn_decision {learn}, route_not_compute {route})  "
          f"EVAL {len(ev)} (held out, disjoint)")
    max_sim = max((x["jaccard"] for x in nearest), default=0.0)
    print(f"  leak guard: no task-id overlap, no exact-dup; max eval→train Jaccard={max_sim:.3f} "
          f"(within-archetype template overlap is expected for the stratified holdout)")
    for x in nearest:
        print(f"    eval {x['eval']:18} nearest-train {str(x['nearest_train']):18} J={x['jaccard']:.3f}")

    if args.selftest:
        print("\nselftest OK (split + leak-check passed; no files written)")
        return 0

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    sft_path = OUT_DIR / "decision_sft.jsonl"
    grpo_path = OUT_DIR / "decision_grpo.jsonl"
    eval_path = OUT_DIR / "decision_eval.jsonl"
    man_path = OUT_DIR / "decision_sft_manifest.json"
    with sft_path.open("w") as f:
        for r in train:
            f.write(json.dumps(_sft_row(r)) + "\n")
    with grpo_path.open("w") as f:
        for r in train:
            f.write(json.dumps(_grpo_row(r)) + "\n")
    with eval_path.open("w") as f:
        for r in ev:
            f.write(json.dumps(_eval_row(r)) + "\n")
    with man_path.open("w") as f:
        json.dump({
            "n_tasks": n, "gold_verified": n_ok,
            "split_mode": args.mode, "split_type": split_type,
            "n_train": len(train), "n_eval": len(ev),
            "train_learn_decision": learn, "train_route_not_compute": route,
            "leak_guard": {"task_id_overlap": sorted(overlap), "exact_dup": exact_dup,
                           "max_eval_to_train_jaccard": max_sim, "per_eval_nearest": nearest},
            "CAVEAT": ("Train/eval are ITEM-disjoint. In 'stratified' mode the held-out item "
                       "shares its archetype TEMPLATE with train siblings, so it is an "
                       "IN-DISTRIBUTION holdout (directional only) — do NOT cite it as clean "
                       "generalization. For a clean OOD eval, author new vignettes or use "
                       "--mode leave_archetype_out. reward==scorer is intended (verifiable-reward "
                       "RL); the fixed defect was training on the evaluated items. n is a seed."),
            "sft_file": str(sft_path.relative_to(_REPO)),
            "grpo_file": str(grpo_path.relative_to(_REPO)),
            "eval_file": str(eval_path.relative_to(_REPO)),
            "reward_module": "evaluation/local_trial/decision_reward.py",
            "train_task_ids": sorted(train_ids), "eval_task_ids": sorted(eval_ids),
        }, f, indent=2)
    print(f"\nwrote:\n  {sft_path} (train)\n  {grpo_path} (train)\n  {eval_path} (held-out)\n  {man_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
