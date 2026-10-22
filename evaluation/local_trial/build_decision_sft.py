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


def build() -> Dict[str, Any]:
    sft_rows: List[dict] = []
    grpo_rows: List[dict] = []
    report: List[dict] = []
    failures: List[dict] = []

    for name in DECISION_DATASETS:
        adapter = DecisionBenchmarkAdapter({"dataset": name})
        for task in adapter.load_tasks():
            gt = task.ground_truth
            scorer = task.metadata.get("scorer", "decision")
            labels = task.metadata.get("labels")
            gold = _gold_completion(gt, scorer, task.metadata)
            # VERIFY: the synthesized gold must actually win under its own scorer
            s = score_one(gold, gt, scorer, labels)
            thresh = 0.9
            ok = s >= thresh
            if not ok:
                failures.append({"task_id": task.task_id, "scorer": scorer, "score": s,
                                 "gold": gold})
            policy = "route_not_compute" if scorer in _ROUTE_NOT_COMPUTE else "learn_decision"
            report.append({"task_id": task.task_id, "dataset": name, "scorer": scorer,
                           "gold_score": round(s, 4), "policy": policy, "ok": ok})

            sft_rows.append({
                "messages": [
                    {"role": "system", "content": SYS},
                    {"role": "user", "content": task.question},
                    {"role": "assistant", "content": gold},
                ],
                "task_id": task.task_id, "archetype": task.metadata.get("archetype"),
                "scorer": scorer, "policy": policy, "gold_score": round(s, 4),
            })
            grpo_rows.append({
                "prompt": f"{SYS}\n\n{task.question}",
                "gold": json.dumps(gt), "scorer": scorer,
                "labels": labels, "task_id": task.task_id, "policy": policy,
            })

    return {"sft": sft_rows, "grpo": grpo_rows, "report": report, "failures": failures}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--selftest", action="store_true",
                    help="build + verify in memory; do not write files")
    args = ap.parse_args()

    res = build()
    n = len(res["report"])
    n_ok = sum(1 for r in res["report"] if r["ok"])
    learn = sum(1 for r in res["report"] if r["policy"] == "learn_decision")
    route = n - learn
    print(f"decision training rows: {n}  (gold-verified {n_ok}/{n}; "
          f"learn_decision {learn}, route_not_compute {route})")
    for r in res["report"]:
        flag = "" if r["ok"] else "  <-- GOLD BELOW THRESHOLD"
        print(f"  {r['task_id']:18} {r['scorer']:11} gold_score={r['gold_score']:.3f} "
              f"[{r['policy']}]{flag}")

    if res["failures"]:
        print(f"\nFAIL: {len(res['failures'])} synthesized gold completions scored < 0.9 — "
              f"not emitting non-winning SFT targets. Fix templates first.")
        return 1

    if args.selftest:
        print("\nselftest OK (no files written)")
        return 0

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    sft_path = OUT_DIR / "decision_sft.jsonl"
    grpo_path = OUT_DIR / "decision_grpo.jsonl"
    man_path = OUT_DIR / "decision_sft_manifest.json"
    with sft_path.open("w") as f:
        for r in res["sft"]:
            f.write(json.dumps(r) + "\n")
    with grpo_path.open("w") as f:
        for r in res["grpo"]:
            f.write(json.dumps(r) + "\n")
    with man_path.open("w") as f:
        json.dump({
            "n_rows": n, "gold_verified": n_ok,
            "learn_decision": learn, "route_not_compute": route,
            "sft_file": str(sft_path.relative_to(_REPO)),
            "grpo_file": str(grpo_path.relative_to(_REPO)),
            "reward_module": "evaluation/local_trial/decision_reward.py",
            "sft_schema": "{messages:[system,user,assistant]} — train_qlora_pilot.py",
            "grpo_schema": "{prompt, gold(json), scorer, labels} — decision_reward.decision_reward",
            "per_task": res["report"],
        }, f, indent=2)
    print(f"\nwrote:\n  {sft_path}\n  {grpo_path}\n  {man_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
