"""
decision_reward.py
------------------
Verifiable GRPO reward for the DrugDev *decision* benchmark (the practical archetypes:
lead-op triage, FEP selection, dose MTD, tissue exposure, special-population, process
knowledge, workflow chains, dose projection/schedule). Mirrors decomp_reward.py: TRL
forwards the dataset's `gold` / `scorer` columns to this fn as kwargs, and it scores each
sampled rollout against that task's ground truth with the matching decision scorer.

The reward is the scorer's composite in [0,1] — the SAME objective, verifiable signal the
offline leaderboard uses, so GRPO optimizes exactly the benchmarked decision quality (no
proxy, no reward model). Arithmetic/deterministic tasks (scorer == 'numeric', policy ==
'route_not_compute') are included only so the policy learns to ROUTE+interpret; do not
over-weight them (the engine computes, the model should not learn to do arithmetic).

Usage in a TRL GRPOTrainer:
    from decision_reward import decision_reward
    trainer = GRPOTrainer(..., reward_funcs=[decision_reward])
    # dataset rows must carry columns: prompt, gold (json str), scorer (str), labels (opt)
"""
from __future__ import annotations

import json
import os
import sys
from typing import Any, Dict, List, Optional

_REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
if _REPO not in sys.path:
    sys.path.insert(0, _REPO)

from evaluation.scorers.decision_scorer import (  # noqa: E402
    score_decision, score_categorical_decision, score_set_decision, score_numeric_decision,
)
from evaluation.scorers.boin_scorer import score_mtd_decision  # noqa: E402
from evaluation.scorers.chain_scorer import score_chain  # noqa: E402
from evaluation.scorers.agent_task_scorers import (  # noqa: E402
    score_routing, score_param_select, score_autofix,
)


def score_one(completion: str, gold: Any, scorer: str,
              labels: Optional[List[str]] = None) -> float:
    """Score a single completion string against a ground-truth dict with `scorer`.

    Covers BOTH the DrugDev decision scorers (decision/categorical/set/numeric/mtd/chain) AND the
    DB-generated + error-mined agent-task pool (routing/cross_domain_routing/param_select/autofix),
    so ONE TRL reward fn trains the whole ~12K-row corpus. The agent-task scorers take gold in its
    native shape (a filename string, or a {required_params,…} / {correct_workflow,…} dict), so they
    are passed `gold` as-is rather than the dict-coerced form the decision scorers expect."""
    if scorer == "decision":
        return float(score_decision(completion, gold, labels)["score"])
    if scorer == "categorical":
        return float(score_categorical_decision(completion, gold)["score"])
    if scorer == "set":
        return float(score_set_decision(completion, gold)["score"])
    if scorer == "numeric":
        return float(score_numeric_decision(completion, gold)["score"])
    if scorer == "mtd":
        return float(score_mtd_decision(completion, gold)["score"])
    if scorer == "chain":
        return float(score_chain(completion, gold)["score"])
    # agent-task pool (gold passed in its native shape, not dict-coerced)
    if scorer in ("routing", "cross_domain_routing"):
        return float(score_routing(completion, gold))
    if scorer in ("param_select", "param_prefill"):
        return float(score_param_select(completion, gold))
    if scorer == "autofix":
        return float(score_autofix(completion, gold))
    return 0.0


def _text(completion: Any) -> str:
    if isinstance(completion, str):
        return completion
    # chat-format rollout: list of {role, content}
    if isinstance(completion, list) and completion and isinstance(completion[-1], dict):
        return completion[-1].get("content", "")
    return str(completion)


def _col(v: Any, i: int):
    return v[i] if isinstance(v, list) else v


def decision_reward(completions: List[Any], gold=None, scorer=None,
                    labels=None, **kwargs) -> List[float]:
    """TRL reward fn. `completions` is the batch of rollouts; `gold`/`scorer`/`labels`
    are per-prompt dataset columns (lists aligned to completions, or scalars)."""
    out: List[float] = []
    for i, comp in enumerate(completions):
        g = _col(gold, i)
        # Parse JSON gold, but pass a bare string (e.g. routing filename gold) through unchanged —
        # the agent-task scorers accept gold in its native shape.
        if isinstance(g, str) and g.strip()[:1] in "{[":
            try:
                gd: Any = json.loads(g)
            except Exception:
                gd = g
        else:
            gd = g if g is not None else {}
        s = _col(scorer, i) or "decision"
        lab = _col(labels, i)
        out.append(score_one(_text(comp), gd, s, lab))
    return out


def build_reward_fn(args=None):
    """Standard hook a GRPO launcher calls to get the TRL reward callable. decision_reward is
    already TRL-shaped (reads gold/scorer/labels from forwarded dataset columns), so there is
    nothing to bind — unlike decomp_reward.make_trl_reward_fn which binds db_path/weights."""
    return decision_reward


def _selftest() -> int:
    """De-risk the GATED decision-GRPO run OFFLINE: verify the data+reward contract end-to-end on
    the real committed gold (no TRL/GPU). The gold completion for each GRPO prompt must score high;
    a trivial wrong completion must score low. Leaves only the TRL trainer wiring for the GPU env."""
    import json as _json
    from pathlib import Path
    pool = Path(__file__).resolve().parents[2] / "docs" / "20260912_onprem_llm" / "data_pool_v2"
    grpo = [_json.loads(l) for l in (pool / "decision_grpo.jsonl").open() if l.strip()]
    sft_gold = {}
    for l in (pool / "decision_sft.jsonl").open():
        if l.strip():
            r = _json.loads(l); sft_gold[r["task_id"]] = r["messages"][2]["content"]
    assert grpo, "no GRPO rows"
    R = []
    for row in grpo:
        gold = decision_reward([sft_gold[row["task_id"]]], gold=[row["gold"]],
                               scorer=[row["scorer"]], labels=[row.get("labels")])[0]
        wrong = decision_reward(["I'm not sure; let's just run everything."], gold=[row["gold"]],
                                scorer=[row["scorer"]], labels=[row.get("labels")])[0]
        ok = gold >= 0.9 and wrong < gold
        R.append(ok)
        print(("PASS" if ok else "FAIL"), f"{row['task_id']:16} gold={gold:.2f} wrong={wrong:.2f}")
    p = sum(R)
    print(f"\n{p}/{len(R)} GRPO rows: gold-completion rewards high, wrong rewards lower")
    # also confirm the launcher hook returns a callable
    assert callable(build_reward_fn()), "build_reward_fn must return a callable"
    ok_decision = (p == len(R))
    ok_pool = _selftest_pool(pool)
    return 0 if (ok_decision and ok_pool) else 1


def _oracle(gold: Any, scorer: str) -> str:
    """Synthesize the correct completion from a verifiable-task row's gold, so the selftest tests the
    scorer+dispatch contract directly (no fuzzy SFT-file join). Mirrors what a perfect model emits."""
    g = json.loads(gold) if isinstance(gold, str) and gold.strip()[:1] in "{[" else gold
    if scorer in ("routing", "cross_domain_routing"):
        return (g.get("correct_workflow") if isinstance(g, dict) else g) or ""
    if scorer in ("param_select", "param_prefill"):
        req = (g.get("required_params") if isinstance(g, dict) else None) or \
              list((g.get("expected_params") or {}).keys() if isinstance(g, dict) else [])
        return json.dumps({"required_params": req})
    if scorer == "autofix":
        return str(g)
    return str(g)


def _anti(gold: Any, scorer: str) -> str:
    """A genuinely-WRONG completion per scorer, so the selftest tests a real gradient (oracle >
    anti). For a restraint-only param task, the anti NAMES the forbidden params (over-fill) — that
    is the actual failure mode, unlike a 'fill nothing' answer which is correct there."""
    g = json.loads(gold) if isinstance(gold, str) and gold.strip()[:1] in "{[" else gold
    if scorer in ("routing", "cross_domain_routing"):
        return "nfcore/__nonexistent__/main.nf"
    if scorer in ("param_select", "param_prefill"):
        forb = (g.get("must_not_fill") if isinstance(g, dict) else None) or []
        return json.dumps({k: "x" for k in forb}) if forb else "nonexistent_param_zzz"
    if scorer == "autofix":
        return "unrelated_category_zzz"
    return "none / not applicable"


def _selftest_pool(pool) -> bool:
    """Verify the SAME reward fn covers the whole agent-task pool (routing / param / autofix). These
    are verifiable tasks, so both the oracle and a genuinely-wrong completion are derivable from each
    row's gold. The reward fn's job for GRPO is to RANK the oracle strictly above the wrong answer
    (the training gradient) — assert that on EVERY real GRPO row. Absolute calibration (oracle≥0.9)
    is reported separately as a data-quality signal: rows below it are the generator's
    must_not_fill ∩ required_params contradictions, surfaced not masked."""
    import json as _json
    files = ["db_generated_routing_grpo.jsonl", "db_generated_param_grpo.jsonl",
             "error_analysis_grpo.jsonl"]
    print("\n=== agent-task pool (one reward fn, whole corpus; oracle vs anti-oracle) ===")
    all_ok = True
    for grpo_f in files:
        gp = pool / grpo_f
        if not gp.exists():
            print(f"SKIP {grpo_f} (missing)")
            continue
        grpo = [_json.loads(l) for l in gp.open() if l.strip()]
        ranked = low = contradictions = 0
        for row in grpo:
            sc = row["scorer"]
            g = _json.loads(row["gold"]) if isinstance(row["gold"], str) and row["gold"].strip()[:1] in "{[" else row["gold"]
            gold_r = decision_reward([_oracle(row["gold"], sc)], gold=[row["gold"]], scorer=[sc])[0]
            anti_r = decision_reward([_anti(row["gold"], sc)], gold=[row["gold"]], scorer=[sc])[0]
            if gold_r > anti_r:
                ranked += 1
            if gold_r < 0.9:
                low += 1
                if isinstance(g, dict):
                    req = set(g.get("required_params") or (g.get("expected_params") or {}).keys())
                    if req & set(g.get("must_not_fill") or []):
                        contradictions += 1
        ok = ranked == len(grpo)
        all_ok = all_ok and ok
        note = f"  [{low} rows oracle<0.9; {contradictions} = must_not_fill∩required data contradictions]" if low else ""
        print(("PASS" if ok else "FAIL"),
              f"{grpo_f:34} {ranked}/{len(grpo)} oracle ranks > wrong{note}")
    return all_ok


if __name__ == "__main__":
    import sys as _sys
    if "--selftest" in _sys.argv:
        _sys.exit(_selftest())
    # tiny hand-built smoke
    gd = {"verdict": "excluded",
          "verdict_vocab": {"reaches_target": ["reaches"], "excluded": ["excluded", "efflux"]}}
    r = decision_reward(["P-gp efflux limits brain exposure.\nverdict: excluded"],
                        gold=[json.dumps(gd)], scorer=["categorical"])
    print("reward:", r); assert r[0] > 0.7, r; print("OK")
