"""
CYP DDI QC evaluator.

Metrics from cyp_panel_summary.json (cyp_ddi_panel/main.nf):
  {
    "summary": {
      "n_clinical":          int,   -- isoforms with CLINICAL_STUDY_RECOMMENDED
      "n_investigate":       int,   -- isoforms with INVESTIGATE flag
      "n_tdi":               int,   -- isoforms with TDI concern
      "overall_recommendation": str -- CLINICAL_STUDY_RECOMMENDED | INVESTIGATE | NOT_EXPECTED
    },
    "cyp_inhibition": {
      "CYP3A4": {"predicted_IC50_uM": float, "flag_at_1uM": bool, "flag_at_10uM": bool},
      ...
    }
  }
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


_FLAG_ORDER = {"NOT_EXPECTED": 0, "NOT_ASSESSED": 0, "INVESTIGATE": 1, "CLINICAL_STUDY_RECOMMENDED": 2}

QC_PROFILES: dict[str, dict[str, Any]] = {
    "cyp_ddi_standard": {
        "max_clinical_isoforms": 0,    # zero CLINICAL_STUDY isoforms allowed
        "max_investigate_isoforms": 2, # up to 2 INVESTIGATE is acceptable
        "min_ic50_flagged_uM": 1.0,    # IC50 < 1 µM = high risk
    },
    "cyp_ddi_strict": {
        "max_clinical_isoforms": 0,
        "max_investigate_isoforms": 0, # no INVESTIGATE either
        "min_ic50_flagged_uM": 10.0,   # IC50 < 10 µM = flag
    },
    "cyp_ddi_oncology": {
        "max_clinical_isoforms": 1,    # one CLINICAL_STUDY allowed (narrow window)
        "max_investigate_isoforms": 3,
        "min_ic50_flagged_uM": 0.1,
    },
}


class CYPDDIQCEvaluator:
    def __init__(self, profile: str = "cyp_ddi_standard"):
        if profile not in QC_PROFILES:
            raise ValueError(f"Unknown QC profile: {profile!r}. Options: {list(QC_PROFILES)}")
        self.profile = profile
        self.thresholds = QC_PROFILES[profile]

    def evaluate_phase_2(self, metrics: dict) -> PhaseQCResult:
        results: list[GateResult] = []
        summary = metrics.get("summary", metrics)
        n_clinical    = int(summary.get("n_clinical", 0))
        n_investigate = int(summary.get("n_investigate", 0))
        n_tdi         = int(summary.get("n_tdi", 0))
        max_clinical  = self.thresholds["max_clinical_isoforms"]
        max_invest    = self.thresholds["max_investigate_isoforms"]

        # Gate 1: clinical-study isoforms
        action_c = QCAction.HALT if n_clinical > max_clinical else (
            QCAction.ADVISORY if n_clinical == max_clinical and max_clinical > 0 else QCAction.PASS
        )
        results.append(GateResult(
            gate="clinical_study_isoforms",
            action=action_c,
            level=QCLevel.FAIL if n_clinical > max_clinical else (
                QCLevel.BRONZE if (n_clinical == max_clinical and max_clinical > 0) else QCLevel.GOLD
            ),
            value=float(n_clinical),
            threshold=float(max_clinical),
            message=f"{n_clinical} isoform(s) with CLINICAL_STUDY_RECOMMENDED flag (max {max_clinical})",
            suggestion=(
                "Reduce cmax_ss_uM or increase fu_mic to lower R1 values below 1.1 threshold."
            ) if action_c == QCAction.HALT else "",
        ))

        # Gate 2: investigate isoforms
        ratio_i = n_investigate / max(max_invest, 1)
        action_i = QCAction.HALT if n_investigate > max_invest else (
            QCAction.ADVISORY if ratio_i > 0.75 else QCAction.PASS
        )
        results.append(GateResult(
            gate="investigate_isoforms",
            action=action_i,
            level=QCLevel.FAIL if n_investigate > max_invest else (
                QCLevel.BRONZE if ratio_i > 0.75 else (QCLevel.SILVER if ratio_i > 0.5 else QCLevel.GOLD)
            ),
            value=float(n_investigate),
            threshold=float(max_invest),
            message=f"{n_investigate} isoform(s) with INVESTIGATE flag (max {max_invest})",
            suggestion=(
                "Lower cmax_ss_uM or adjust fu_mic to reduce R1 values below 1.02 threshold."
            ) if action_i == QCAction.HALT else "",
        ))

        # Gate 3: TDI concern (advisory only)
        results.append(GateResult(
            gate="tdi_concern",
            action=QCAction.ADVISORY if n_tdi > 0 else QCAction.PASS,
            level=QCLevel.BRONZE if n_tdi > 0 else QCLevel.GOLD,
            value=float(n_tdi),
            threshold=0.0,
            message=f"{n_tdi} isoform(s) with time-dependent inhibition concern",
            suggestion="Disable run_tdi_screen to exclude TDI analysis if structural alerts are known false positives." if n_tdi > 1 else "",
        ))

        return PhaseQCResult(phase="phase_2_ddi_risk", gate_results=results)

    def evaluate_phase(self, phase: str, metrics: dict) -> PhaseQCResult:
        dispatch = {
            "phase_2_ddi_risk": self.evaluate_phase_2,
        }
        fn = dispatch.get(phase)
        if fn is None:
            raise ValueError(f"Unknown phase: {phase!r}")
        return fn(metrics)
