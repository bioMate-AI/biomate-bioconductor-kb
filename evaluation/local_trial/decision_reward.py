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


def score_one(completion: str, gold: Dict[str, Any], scorer: str,
              labels: Optional[List[str]] = None) -> float:
    """Score a single completion string against a ground-truth dict with `scorer`."""
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
        gd = json.loads(g) if isinstance(g, str) else (g or {})
        s = _col(scorer, i) or "decision"
        lab = _col(labels, i)
        out.append(score_one(_text(comp), gd, s, lab))
    return out


if __name__ == "__main__":
    # smoke test against a tiny hand-built example
    gd = {"verdict": "excluded",
          "verdict_vocab": {"reaches_target": ["reaches"], "excluded": ["excluded", "efflux"]}}
    r = decision_reward(["P-gp efflux limits brain exposure.\nverdict: excluded"],
                        gold=[json.dumps(gd)], scorer=["categorical"])
    print("reward:", r)
    assert r[0] > 0.7, r
    print("OK")
