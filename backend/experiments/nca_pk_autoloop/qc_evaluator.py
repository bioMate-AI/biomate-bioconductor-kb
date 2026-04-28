"""
NCA PK QC evaluator.

Metrics from nca_summary.json (nca_pknca/main.nf population_summary block):
  auc_extrap_pct:              float  -- % AUC extrapolated (FDA: ≤ 20%)
  subjects_with_no_terminal_slope: int
  t_half_mean:                 float  -- hours
  auc_last_mean:               float
  auc_inf_mean:                float
  cmax_mean:                   float
"""
from __future__ import annotations
import math
from dataclasses import dataclass, field
from enum import Enum
from typing import Any


class QCAction(str, Enum):
    PASS = "pass"
    ADVISORY = "advisory"
    HALT = "halt"


class QCLevel(str, Enum):
    GOLD = "GOLD"
    SILVER = "SILVER"
    BRONZE = "BRONZE"
    FAIL = "FAIL"


@dataclass
class GateResult:
    gate: str
    action: QCAction
    level: QCLevel
    value: float
    threshold: float
    message: str
    suggestion: str = ""

    @property
    def passed(self) -> bool:
        return self.action != QCAction.HALT


@dataclass
class PhaseQCResult:
    phase: str
    gate_results: list[GateResult] = field(default_factory=list)

    @property
    def passed(self) -> bool:
        return all(g.passed for g in self.gate_results)

    @property
    def halts(self) -> list[GateResult]:
        return [g for g in self.gate_results if g.action == QCAction.HALT]

    @property
    def overall_level(self) -> QCLevel:
        if any(g.level == QCLevel.FAIL for g in self.gate_results):
            return QCLevel.FAIL
        if any(g.level == QCLevel.BRONZE for g in self.gate_results):
            return QCLevel.BRONZE
        if any(g.level == QCLevel.SILVER for g in self.gate_results):
            return QCLevel.SILVER
        return QCLevel.GOLD


QC_PROFILES: dict[str, dict[str, Any]] = {
    "nca_standard": {
        "max_auc_extrap_pct":            20.0,   # FDA regulatory threshold
        "max_no_slope_subjects":          2,
        "min_t_half_h":                   0.5,
        "max_t_half_h":                  72.0,
    },
    "nca_exploratory": {
        "max_auc_extrap_pct":            30.0,   # more lenient for early discovery
        "max_no_slope_subjects":          3,
        "min_t_half_h":                   0.2,
        "max_t_half_h":                 120.0,
    },
    "nca_regulatory": {
        "max_auc_extrap_pct":            15.0,   # stricter for NDA/BLA submission
        "max_no_slope_subjects":          1,
        "min_t_half_h":                   1.0,
        "max_t_half_h":                  48.0,
    },
}


class NCAPKQCEvaluator:
    def __init__(self, profile: str = "nca_standard"):
        if profile not in QC_PROFILES:
            raise ValueError(f"Unknown QC profile: {profile!r}. Options: {list(QC_PROFILES)}")
        self.profile = profile
        self.thresholds = QC_PROFILES[profile]

    def evaluate_phase_1(self, metrics: dict) -> PhaseQCResult:
        results: list[GateResult] = []
        pop = metrics.get("population_summary", metrics)

        # Gate 1: AUC extrapolation (FDA primary gate)
        extrap = float(pop.get("auc_extrap_pct", 0.0))
        thresh_extrap = self.thresholds["max_auc_extrap_pct"]
        ratio_e = extrap / thresh_extrap if thresh_extrap else 0
        action_e = QCAction.HALT if extrap > thresh_extrap else (
            QCAction.ADVISORY if ratio_e > 0.80 else QCAction.PASS
        )
        results.append(GateResult(
            gate="auc_extrapolation",
            action=action_e,
            level=QCLevel.GOLD if extrap <= thresh_extrap * 0.5 else (
                QCLevel.SILVER if extrap <= thresh_extrap else (
                    QCLevel.BRONZE if ratio_e <= 1.2 else QCLevel.FAIL
                )
            ),
            value=extrap,
            threshold=thresh_extrap,
            message=(
                f"AUC extrapolation {extrap:.1f}% (FDA limit {thresh_extrap:.0f}%); "
                f"{'exceeds' if extrap > thresh_extrap else 'within'} threshold"
            ),
            suggestion=(
                "Extend last sampling timepoint (last_sampling_time_h) to capture ≥3× t½ "
                "and reduce the extrapolated fraction of AUCinf."
            ) if action_e == QCAction.HALT else "",
        ))

        # Gate 2: subjects missing terminal slope
        n_no_slope = int(pop.get("subjects_with_no_terminal_slope", 0))
        max_no_slope = self.thresholds["max_no_slope_subjects"]
        action_s = QCAction.HALT if n_no_slope > max_no_slope else (
            QCAction.ADVISORY if n_no_slope == max_no_slope else QCAction.PASS
        )
        results.append(GateResult(
            gate="terminal_slope_coverage",
            action=action_s,
            level=QCLevel.FAIL if n_no_slope > max_no_slope else (
                QCLevel.BRONZE if n_no_slope == max_no_slope else QCLevel.GOLD
            ),
            value=float(n_no_slope),
            threshold=float(max_no_slope),
            message=f"{n_no_slope} subject(s) missing terminal slope estimate (max {max_no_slope})",
            suggestion=(
                "Add ≥3 late-time sampling points per subject or extend last_sampling_time_h "
                "to ensure the terminal log-linear phase is adequately characterized."
            ) if action_s == QCAction.HALT else "",
        ))

        # Gate 3: half-life plausibility (advisory)
        t_half = float(pop.get("t_half_mean", 5.0))
        min_th  = self.thresholds["min_t_half_h"]
        max_th  = self.thresholds["max_t_half_h"]
        th_action = (
            QCAction.ADVISORY if t_half < min_th or t_half > max_th else QCAction.PASS
        )
        results.append(GateResult(
            gate="t_half_plausibility",
            action=th_action,
            level=QCLevel.BRONZE if th_action == QCAction.ADVISORY else QCLevel.GOLD,
            value=t_half,
            threshold=max_th,
            message=f"Mean t½ {t_half:.2f} h (expected {min_th:.1f}–{max_th:.0f} h)",
            suggestion=(
                "t½ outside expected range — verify sampling schedule covers ≥3× t½; "
                "check for multi-compartmental behavior."
            ) if th_action == QCAction.ADVISORY else "",
        ))

        return PhaseQCResult(phase="phase_1_nca_analysis", gate_results=results)

    def evaluate_phase(self, phase: str, metrics: dict) -> PhaseQCResult:
        dispatch = {"phase_1_nca_analysis": self.evaluate_phase_1}
        fn = dispatch.get(phase)
        if fn is None:
            raise ValueError(f"Unknown phase: {phase!r}")
        return fn(metrics)
