"""Confidence scoring for chain surfacing decisions.

Pure function. Takes a `ConfidenceSignals` object and returns:
  - a scalar `confidence ∈ [0, 1]`
  - a surfacing mode (`upfront` | `stepwise` | `reactive`)
  - the per-signal contributions, for debuggability

Thresholds are operational settings, not part of the data model. Adjustable
via env vars so tuning doesn't require a code change.

Design reference: docs/20260608_CHAIN_GENERATION_DESIGN.md §3.
"""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from typing import Dict, Literal, Optional


SurfacingMode = Literal["upfront", "stepwise", "reactive"]


@dataclass
class ConfidenceSignals:
    """Inputs to the confidence scorer.

    All values are caller-computed at routing time. The scorer does NOT
    look anything up — keeps it pure and unit-testable.
    """

    # 0..1 — best curated-chain match (L1) similarity, normalized.
    curated_chain_score: float = 0.0
    # 0..1 — best pattern-library (L2) match similarity, normalized.
    pattern_match_score: float = 0.0
    # 0..1 — how specifically the user's query names entities (organism,
    # modality, contrast, etc.). Caller computes via NER or heuristics.
    query_specificity: float = 0.0
    # 0..1 — does the chain have one obvious "what next" (high), or many
    # plausible continuations (low). Caller derives from chain-library lookup.
    downstream_determinism: float = 0.5
    # -1..+1 — user explicitly opted in (+) or out (-) of upfront proposals.
    # E.g. "do the whole analysis" → +0.3; "let's start with…" → -0.3.
    user_signal: float = 0.0
    # -1..+1 — user profile hint from memory (e.g. PI → +, beginner → -).
    user_profile_bias: float = 0.0


def _env_float(name: str, default: float) -> float:
    try:
        return float(os.environ.get(name, default))
    except (TypeError, ValueError):
        return default


# Weights — sum to 1.0 for the additive component. user_signal +
# user_profile_bias are added on top (can push score outside the additive
# sum), clamped to [0, 1] at the end.
_WEIGHTS = {
    "curated_chain_score": 0.30,
    "pattern_match_score": 0.20,
    "query_specificity": 0.20,
    "downstream_determinism": 0.30,
}

# Default thresholds. Override via env.
def _upfront_threshold() -> float:
    return _env_float("BIOMATE_CONFIDENCE_UPFRONT", 0.75)


def _stepwise_threshold() -> float:
    return _env_float("BIOMATE_CONFIDENCE_STEPWISE", 0.45)


@dataclass
class ConfidenceResult:
    confidence: float
    mode: SurfacingMode
    contributions: Dict[str, float] = field(default_factory=dict)
    thresholds: Dict[str, float] = field(default_factory=dict)


def score_confidence(signals: ConfidenceSignals) -> ConfidenceResult:
    """Compute scalar confidence + chosen surfacing mode."""
    contributions = {
        "curated_chain_score": _WEIGHTS["curated_chain_score"] * _clip01(signals.curated_chain_score),
        "pattern_match_score": _WEIGHTS["pattern_match_score"] * _clip01(signals.pattern_match_score),
        "query_specificity": _WEIGHTS["query_specificity"] * _clip01(signals.query_specificity),
        "downstream_determinism": _WEIGHTS["downstream_determinism"] * _clip01(signals.downstream_determinism),
    }
    base = sum(contributions.values())
    # user_signal and user_profile_bias are corrections on top of base.
    adjustment = _clip(signals.user_signal, -0.5, 0.5) + _clip(signals.user_profile_bias, -0.2, 0.2)
    contributions["user_signal"] = _clip(signals.user_signal, -0.5, 0.5)
    contributions["user_profile_bias"] = _clip(signals.user_profile_bias, -0.2, 0.2)

    confidence = _clip01(base + adjustment)
    mode = choose_surfacing_mode(confidence)

    return ConfidenceResult(
        confidence=confidence,
        mode=mode,
        contributions=contributions,
        thresholds={
            "upfront": _upfront_threshold(),
            "stepwise": _stepwise_threshold(),
        },
    )


def choose_surfacing_mode(confidence: float) -> SurfacingMode:
    if confidence >= _upfront_threshold():
        return "upfront"
    if confidence >= _stepwise_threshold():
        return "stepwise"
    return "reactive"


def _clip01(x: float) -> float:
    return max(0.0, min(1.0, x))


def _clip(x: float, lo: float, hi: float) -> float:
    return max(lo, min(hi, x))
