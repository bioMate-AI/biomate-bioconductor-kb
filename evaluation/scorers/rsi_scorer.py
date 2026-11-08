"""
rsi_scorer.py
-------------
Pure, stdlib scorers for BioMate's RECURSIVE SELF-IMPROVEMENT (RSI) benchmark — does the system
improve its OWN success rate ACROSS runs/iterations by modifying its substrate (memory, catalog,
model weights)? This is longitudinal improvement, distinct from the WITHIN-run QC convergence that
`autoloop_benchmark_adapter.py` already measures (gate-pass@1 / converge ≤3 iters). RSI composes
*over* episodes; the auto-loop operates *inside* one.

Prior art this is modeled on (Δ-over-iterations on a held-out downstream benchmark):
  STOP (Zelikman 2023), ADAS (Hu 2024), Darwin-Gödel Machine / SICA (2025), AlphaEvolve, Gödel Agent.
Their shared failure mode — and ours, already burned once (decomposition_v2 leak, retracted 0.73 vs
real 0.016) — is measuring memorization instead of improvement. So the ONE non-negotiable rule here:

    the improvement must show on an OUT-OF-GENERATOR held-out set, or it scores ZERO (leakage firewall).

Three axes (each returns {"score", ...diagnostics}, matching the decision scorers' shape):
  A. learning_curve     — cross-episode success trajectory, net of a no-learning control
  B. capability_growth  — Δcoverage from composer-generated workflows, GATED on executes-for-real
  C. self_improvement   — Δ on a clean held-out after a self-training loop, with a forgetting guard
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional


def _clamp(x: float, lo: float = 0.0, hi: float = 1.0) -> float:
    return max(lo, min(hi, x))


def score_learning_curve(scores: List[float], control: Optional[List[float]] = None,
                         target_gain: float = 0.2) -> Dict[str, Any]:
    """Axis A. `scores` = per-episode success (e.g. gate-pass@1 or routing acc) over a SEQUENCE of
    related tasks as the system accumulates memory/gold. Real RSI = the final beats the first by
    more than a no-learning `control` trajectory (same tasks, memory/learning OFF) would — that
    nets out task-order and noise. Score = net improvement normalized to `target_gain`, so a
    `target_gain` lift over control = full credit. Monotonic fraction reported, not folded."""
    if not scores or len(scores) < 2:
        return {"score": 0.0, "reason": "need ≥2 episodes", "delta": 0.0}
    delta = scores[-1] - scores[0]
    ctrl_delta = (control[-1] - control[0]) if control and len(control) >= 2 else 0.0
    net = delta - ctrl_delta
    mono = sum(1 for i in range(1, len(scores)) if scores[i] >= scores[i - 1] - 1e-9) / (len(scores) - 1)
    return {
        "score": round(_clamp(net / target_gain), 4),
        "delta": round(delta, 4), "control_delta": round(ctrl_delta, 4),
        "net_delta": round(net, 4), "monotonic_frac": round(mono, 4),
        "final": scores[-1], "initial": scores[0],
    }


def score_capability_growth(coverage_before: float, coverage_after: float,
                            exec_ok_frac: float, target_gain: float = 0.1) -> Dict[str, Any]:
    """Axis B. The composer is seeded with intents the catalog can't route, generates+indexes new
    workflows, and routing coverage is re-measured on a HELD-OUT intent set. A capability that does
    not EXECUTE is worthless, so Δcoverage is multiplicatively GATED by `exec_ok_frac` (fraction of
    newly generated workflows with real_exec_status ∈ {ok, ok_warnings}). Coverages are fractions."""
    dcov = coverage_after - coverage_before
    raw = _clamp(dcov / target_gain)
    return {
        "score": round(raw * _clamp(exec_ok_frac), 4),
        "coverage_delta": round(dcov, 4), "exec_ok_frac": round(_clamp(exec_ok_frac), 4),
        "coverage_before": coverage_before, "coverage_after": coverage_after,
    }


def score_self_improvement(start: float, improved: float, out_of_generator: bool,
                           sibling_before: Optional[float] = None,
                           sibling_after: Optional[float] = None,
                           target_gain: float = 0.05) -> Dict[str, Any]:
    """Axis C. After a self-training loop (error-analysis → owner-bucketed gold → GRPO), measure the
    lift on a CLEAN held-out vs the SFT start policy. LEAKAGE FIREWALL: if the held-out is NOT
    out-of-generator, score is 0.0 regardless of the measured lift (the decomposition_v2 trap).
    A `sibling` task pair guards against catastrophic forgetting — improving the target must not
    regress a sibling capability; regression scales the score down."""
    if not out_of_generator:
        return {"score": 0.0, "reason": "held-out is NOT out-of-generator — leakage firewall",
                "delta": round(improved - start, 4), "firewall_tripped": True}
    delta = improved - start
    raw = _clamp(delta / target_gain)
    forget = 0.0
    if sibling_before is not None and sibling_after is not None and sibling_before > 0:
        forget = _clamp((sibling_before - sibling_after) / sibling_before)
    return {
        "score": round(raw * (1.0 - forget), 4),
        "delta": round(delta, 4), "forgetting": round(forget, 4),
        "firewall_tripped": False, "out_of_generator": True,
    }


# dispatch (mirrors decision_scorer usage: scorer name → fn)
def score_rsi(axis: str, payload: Dict[str, Any]) -> Dict[str, Any]:
    if axis == "learning_curve":
        return score_learning_curve(payload["scores"], payload.get("control"),
                                     payload.get("target_gain", 0.2))
    if axis == "capability_growth":
        return score_capability_growth(payload["coverage_before"], payload["coverage_after"],
                                       payload["exec_ok_frac"], payload.get("target_gain", 0.1))
    if axis == "self_improvement":
        return score_self_improvement(payload["start"], payload["improved"],
                                      payload["out_of_generator"], payload.get("sibling_before"),
                                      payload.get("sibling_after"), payload.get("target_gain", 0.05))
    return {"score": 0.0, "reason": f"unknown axis {axis}"}


def _selftest() -> int:
    R = []
    ck = lambda n, c: (R.append(bool(c)), print(("PASS" if c else "FAIL"), "-", n))
    # A: genuine learning net of control
    a = score_learning_curve([0.4, 0.5, 0.65, 0.8], control=[0.4, 0.42, 0.41, 0.45], target_gain=0.2)
    ck("learning: net>0 scores high", a["score"] >= 0.9 and a["net_delta"] > 0)
    # A: improvement fully explained by control → net≈0 → low
    a2 = score_learning_curve([0.4, 0.6, 0.8], control=[0.4, 0.6, 0.8])
    ck("learning: all-from-control → ~0", a2["score"] == 0.0)
    # A: flat/declining → 0
    ck("learning: no gain → 0", score_learning_curve([0.6, 0.6, 0.5])["score"] == 0.0)
    # B: coverage gain but nothing executes → gated to 0
    b0 = score_capability_growth(0.6, 0.8, exec_ok_frac=0.0)
    ck("capability: 0 exec → 0 despite +cov", b0["score"] == 0.0 and b0["coverage_delta"] == 0.2)
    b1 = score_capability_growth(0.6, 0.7, exec_ok_frac=1.0, target_gain=0.1)
    ck("capability: +10pp all-exec → full", b1["score"] == 1.0)
    # C: leakage firewall — big lift but in-generator → 0
    c0 = score_self_improvement(0.30, 0.73, out_of_generator=False)
    ck("self-improve: in-generator → firewall 0", c0["score"] == 0.0 and c0["firewall_tripped"])
    # C: real out-of-generator lift, no forgetting → high
    c1 = score_self_improvement(0.30, 0.36, out_of_generator=True, target_gain=0.05)
    ck("self-improve: +6pp OOG → full", c1["score"] == 1.0)
    # C: lift but catastrophic forgetting of sibling → scaled down
    c2 = score_self_improvement(0.30, 0.40, out_of_generator=True, sibling_before=0.8,
                                sibling_after=0.4, target_gain=0.05)
    ck("self-improve: forgetting penalizes", c2["score"] < 1.0 and c2["forgetting"] == 0.5)
    p = sum(R)
    print(f"\n{p}/{len(R)} passed")
    return 0 if p == len(R) else 1


if __name__ == "__main__":
    import sys
    sys.exit(_selftest())
