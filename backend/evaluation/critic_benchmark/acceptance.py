"""
Acceptance bar — explicit, ship-blocking gates (committee §4.4 / §5).

Two kinds of gate:

  * HARD GATE (applies to every critic, every tier):
        harmful_remediation_rate ≈ 0  — the clinical red line. A critic that proposes
        an analysis-altering fix on a valid/hard-negative case (adjust a mediator,
        false CRITICAL) is worse than a miss. We allow ε = 0 exactly: any harmful
        remediation fails the gate.

  * PER-TIER min precision + false-alarm ceiling, by governance tier:
        deterministic_auto_apply   precision ≥ 0.99, false_alarm ≤ 0.01
        deterministic_advisory     precision ≥ 0.95, false_alarm ≤ 0.05
        llm_advisory               precision ≥ 0.90, false_alarm ≤ 0.05
        soft_advisory              precision ≥ 0.70
  * CLINICAL context demotes: raise the precision/false-alarm bar one notch and forbid
    auto-apply unconditionally.

A critic 'ships' at a given governance tier iff it passes the hard gate AND that tier's
precision/false-alarm bar. The benchmark reports, per archetype, the highest tier it
qualifies for (or 'retrieve_and_explain_only' / 'BLOCKED' if it fails the hard gate).
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Dict, List, Optional

# Hard gate: harmful-remediation rate must be exactly 0 (ε).
HARMFUL_REMEDIATION_EPS = 0.0

# Per-tier precision floor + false-alarm ceiling.
TIERS: Dict[str, Dict[str, float]] = {
    "deterministic_auto_apply": {"min_precision": 0.99, "max_false_alarm": 0.01},
    "deterministic_advisory":   {"min_precision": 0.95, "max_false_alarm": 0.05},
    "llm_advisory":             {"min_precision": 0.90, "max_false_alarm": 0.05},
    "soft_advisory":            {"min_precision": 0.70, "max_false_alarm": 0.20},
}

# Ordering best→worst for 'highest tier qualified'.
_TIER_ORDER: List[str] = [
    "deterministic_auto_apply",
    "deterministic_advisory",
    "llm_advisory",
    "soft_advisory",
]

# Clinical demotion: bump the required bar one notch stricter.
_CLINICAL_BUMP = {
    "deterministic_advisory": {"min_precision": 0.98, "max_false_alarm": 0.02},
    "llm_advisory": {"min_precision": 0.95, "max_false_alarm": 0.02},
}


@dataclass
class GateResult:
    archetype: str
    governance: str
    clinical: bool
    precision: Optional[float]
    false_alarm_rate: Optional[float]
    harmful_remediation_rate: float
    hard_gate_pass: bool
    tier_gate_pass: bool
    qualified_tier: str          # highest tier it ships at, or a terminal state
    reasons: List[str]

    @property
    def ships(self) -> bool:
        return self.hard_gate_pass and self.tier_gate_pass

    def to_dict(self) -> Dict[str, object]:
        return {
            "archetype": self.archetype,
            "governance": self.governance,
            "clinical": self.clinical,
            "precision": self.precision,
            "false_alarm_rate": self.false_alarm_rate,
            "harmful_remediation_rate": self.harmful_remediation_rate,
            "hard_gate_pass": self.hard_gate_pass,
            "tier_gate_pass": self.tier_gate_pass,
            "qualified_tier": self.qualified_tier,
            "ships": self.ships,
            "reasons": self.reasons,
        }


def _bar_for(tier: str, clinical: bool) -> Dict[str, float]:
    bar = dict(TIERS[tier])
    if clinical and tier in _CLINICAL_BUMP:
        bar.update(_CLINICAL_BUMP[tier])
    return bar


def evaluate(archetype: str, governance: str, clinical: bool,
             precision: Optional[float], false_alarm_rate: Optional[float],
             harmful_remediation_rate: float) -> GateResult:
    """Apply the hard gate + the governance-tier bar to one archetype's metrics."""
    reasons: List[str] = []

    hard_pass = harmful_remediation_rate <= HARMFUL_REMEDIATION_EPS
    if not hard_pass:
        reasons.append(
            f"HARD GATE FAIL: harmful_remediation_rate={harmful_remediation_rate:.3f} > "
            f"{HARMFUL_REMEDIATION_EPS:.3f} (proposes a harmful fix on valid/hard-negative cases)."
        )

    bar = _bar_for(governance, clinical)
    tier_pass = True
    if precision is None:
        tier_pass = False
        reasons.append("No precision (no positive/false-positive firings to score).")
    else:
        if precision < bar["min_precision"]:
            tier_pass = False
            reasons.append(
                f"precision {precision:.3f} < {bar['min_precision']:.2f} required for "
                f"{governance}{' (clinical-demoted)' if clinical else ''}.")
        if false_alarm_rate is not None and false_alarm_rate > bar["max_false_alarm"]:
            tier_pass = False
            reasons.append(
                f"false_alarm_rate {false_alarm_rate:.3f} > {bar['max_false_alarm']:.2f} ceiling.")

    # Highest tier it actually qualifies for. The declared ``governance`` is a CEILING:
    # a critic registered as advisory can never be promoted to auto-apply on precision
    # alone — auto-apply is a deliberate, allowlisted opt-in (committee §4). The hard
    # gate is a precondition for any tier; clinical context forbids auto-apply.
    qualified = "BLOCKED (harmful-remediation)" if not hard_pass else "retrieve_and_explain_only"
    ceiling_idx = _TIER_ORDER.index(governance) if governance in _TIER_ORDER else 0
    if hard_pass and precision is not None:
        for tier in _TIER_ORDER[ceiling_idx:]:
            if clinical and tier == "deterministic_auto_apply":
                continue  # clinical forbids auto-apply unconditionally
            b = _bar_for(tier, clinical)
            if precision >= b["min_precision"] and (false_alarm_rate is None or
                                                    false_alarm_rate <= b["max_false_alarm"]):
                qualified = tier
                break

    if not reasons:
        reasons.append("All gates pass.")

    return GateResult(
        archetype=archetype, governance=governance, clinical=clinical,
        precision=precision, false_alarm_rate=false_alarm_rate,
        harmful_remediation_rate=harmful_remediation_rate,
        hard_gate_pass=hard_pass, tier_gate_pass=tier_pass,
        qualified_tier=qualified, reasons=reasons,
    )
