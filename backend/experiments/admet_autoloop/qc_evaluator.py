"""
ADMET QC evaluator.

Gate thresholds mirror BioMate's existing drug discovery QC logic:
  - assay_ingestion.py: _HERG_SAFETY_THRESHOLD_uM=10.0, _SAFETY_FLAG_TYPES
  - qc_trace_monitor.py: ADMET toxicity safety gate (lines 1033-1036)
  - ADMET_pred/main.nf: toxicity_report.json schema

In production, metrics come from toxicity_report.json produced by the
pharmacology/ADMET_pred Nextflow process.  In tests, pass synthetic dicts.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field
from enum import Enum
from typing import Any


# ── Shared result types (identical API to cryo_em_autoloop) ──────────────────

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


# ── QC profiles (mirrors assay_ingestion.py constants) ───────────────────────

QC_PROFILES: dict[str, dict[str, Any]] = {
    "admet_standard": {
        # hERG — ICH S7B empirical threshold (assay_ingestion.py line 25)
        "herg_ic50_threshold_uM": 10.0,
        # DILI — Lammert 2010 model threshold
        "dili_probability_max": 0.5,
        "dili_risk_level_max": "medium",
        # Ames — Kazius structural alerts; treat positive as HALT
        "ames_probability_max": 0.5,
        # Lipinski Rule of Five
        "logp_max": 5.0,
        "mw_max_da": 500.0,
        # CNS penetration profile (stricter)
        "tpsa_max_A2": 140.0,
    },
    "admet_cns": {
        "herg_ic50_threshold_uM": 10.0,
        "dili_probability_max": 0.4,
        "dili_risk_level_max": "low",
        "ames_probability_max": 0.3,
        "logp_max": 4.0,
        "mw_max_da": 450.0,
        "tpsa_max_A2": 90.0,      # CNS: TPSA < 90 Å² for BBB penetration
    },
    "admet_oncology": {
        # Oncology compounds often tolerate higher toxicity burden
        "herg_ic50_threshold_uM": 5.0,   # stricter — narrow therapeutic window
        "dili_probability_max": 0.6,
        "dili_risk_level_max": "high",
        "ames_probability_max": 0.6,
        "logp_max": 6.0,
        "mw_max_da": 700.0,
        "tpsa_max_A2": 180.0,
    },
}

# Advisory band: metric/threshold between 1.0 and 1.15 → ADVISORY (not HALT)
ADVISORY_BAND = 1.15

_DILI_RISK_ORDER = {"low": 0, "medium": 1, "high": 2}


def _level_for_ratio(ratio: float, higher_is_worse: bool = True) -> QCLevel:
    """Map a metric / threshold ratio to a QC level (same as cryo_em_autoloop)."""
    if not higher_is_worse:
        ratio = 1 / ratio if ratio != 0 else math.inf
    if ratio <= 0.7:
        return QCLevel.GOLD
    if ratio <= 1.0:
        return QCLevel.SILVER
    if ratio <= ADVISORY_BAND:
        return QCLevel.BRONZE
    return QCLevel.FAIL


class ADMETQCEvaluator:
    """
    Evaluates ADMET safety metrics against profile thresholds.

    Metrics come from toxicity_report.json (pharmacology/ADMET_pred/main.nf):
      {
        "herg_ic50_uM":       float,   # hERG IC50 in µM (worst compound)
        "dili_risk":          str,     # "high" | "medium" | "low"
        "dili_probability":   float,   # 0-1
        "ames_positive":      bool,    # True = mutagenicity predicted
        "ames_probability":   float,   # 0-1
        "logP":               float,   # worst-case logP across compounds
        "mw":                 float,   # worst-case MW (Da)
      }
    """

    def __init__(self, profile: str = "admet_standard"):
        if profile not in QC_PROFILES:
            raise ValueError(
                f"Unknown QC profile: {profile!r}. Options: {list(QC_PROFILES)}"
            )
        self.profile = profile
        self.thresholds = QC_PROFILES[profile]

    # ── Phase evaluators ──────────────────────────────────────────────────────

    def evaluate_phase_2(self, metrics: dict) -> PhaseQCResult:
        """Full ADMET evaluation (hERG + DILI + Ames + physicochemical)."""
        results: list[GateResult] = []
        results.extend(self._herg_gates(metrics))
        results.extend(self._dili_gates(metrics))
        results.extend(self._ames_gates(metrics))
        results.extend(self._physicochemical_gates(metrics))
        return PhaseQCResult(phase="phase_2_admet_prediction", gate_results=results)

    def evaluate_phase_3(self, metrics: dict) -> PhaseQCResult:
        """hERG-only safety screen."""
        return PhaseQCResult(
            phase="phase_3_herg_screen",
            gate_results=self._herg_gates(metrics),
        )

    def evaluate_phase_4(self, metrics: dict) -> PhaseQCResult:
        """DILI + Ames flags only."""
        results = self._dili_gates(metrics) + self._ames_gates(metrics)
        return PhaseQCResult(phase="phase_4_dili_ames", gate_results=results)

    def evaluate_phase(self, phase: str, metrics: dict) -> PhaseQCResult:
        """Dispatch to the correct per-phase evaluator."""
        dispatch = {
            "phase_2_admet_prediction": self.evaluate_phase_2,
            "phase_3_herg_screen":      self.evaluate_phase_3,
            "phase_4_dili_ames":        self.evaluate_phase_4,
        }
        fn = dispatch.get(phase)
        if fn is None:
            raise ValueError(f"Unknown phase: {phase!r}")
        return fn(metrics)

    # ── Private gate builders ─────────────────────────────────────────────────

    def _herg_gates(self, metrics: dict) -> list[GateResult]:
        results = []
        herg_ic50 = metrics.get("herg_ic50_uM", 999.0)
        thresh = self.thresholds["herg_ic50_threshold_uM"]
        # Lower IC50 = more cardiotoxic → higher is better
        ratio = thresh / herg_ic50 if herg_ic50 > 0 else math.inf
        action = QCAction.HALT if herg_ic50 < thresh else (
            QCAction.ADVISORY if herg_ic50 < thresh * ADVISORY_BAND else QCAction.PASS
        )
        results.append(GateResult(
            gate="herg_ic50",
            action=action,
            level=_level_for_ratio(ratio, higher_is_worse=True),
            value=herg_ic50,
            threshold=thresh,
            message=(
                f"hERG IC50 {herg_ic50:.2f} µM "
                f"({'below' if herg_ic50 < thresh else 'above'} safety threshold {thresh:.0f} µM)"
            ),
            suggestion=(
                "Increase herg_ic50_threshold_uM or tighten logP/MW filters to select "
                "compounds with lower hERG affinity (higher IC50)."
            ) if action == QCAction.HALT else "",
        ))
        return results

    def _dili_gates(self, metrics: dict) -> list[GateResult]:
        results = []

        # Probability gate (quantitative)
        dili_prob = metrics.get("dili_probability", 0.0)
        thresh_prob = self.thresholds["dili_probability_max"]
        ratio = dili_prob / thresh_prob if thresh_prob else 0.0
        action = QCAction.HALT if dili_prob > thresh_prob else (
            QCAction.ADVISORY if ratio > 0.85 else QCAction.PASS
        )
        results.append(GateResult(
            gate="dili_probability",
            action=action,
            level=_level_for_ratio(ratio),
            value=dili_prob,
            threshold=thresh_prob,
            message=f"DILI probability {dili_prob:.3f} (max {thresh_prob:.2f})",
            suggestion=(
                "Reduce dili_probability_max threshold or lower logP/MW filters "
                "to select compounds with better hepatic safety profiles."
            ) if action == QCAction.HALT else "",
        ))

        # Risk-level gate (categorical: high > medium > low)
        dili_risk = str(metrics.get("dili_risk", "low")).lower()
        max_risk = str(self.thresholds.get("dili_risk_level_max", "medium")).lower()
        risk_num = _DILI_RISK_ORDER.get(dili_risk, 0)
        max_risk_num = _DILI_RISK_ORDER.get(max_risk, 1)
        risk_action = QCAction.HALT if risk_num > max_risk_num else (
            QCAction.ADVISORY if risk_num == max_risk_num else QCAction.PASS
        )
        results.append(GateResult(
            gate="dili_risk_level",
            action=risk_action,
            level=QCLevel.GOLD if risk_num == 0 else (
                QCLevel.SILVER if risk_num == 1 else QCLevel.FAIL
            ),
            value=float(risk_num),
            threshold=float(max_risk_num),
            message=f"DILI risk level '{dili_risk}' (max allowed '{max_risk}')",
            suggestion=(
                "Apply stricter logP ≤ 4.0 and MW ≤ 400 Da filters to reduce "
                "Lammert 2010 model high-risk compound fraction."
            ) if risk_action == QCAction.HALT else "",
        ))

        return results

    def _ames_gates(self, metrics: dict) -> list[GateResult]:
        results = []
        ames_prob = metrics.get("ames_probability", 0.0)
        ames_positive = metrics.get("ames_positive", False)
        thresh = self.thresholds["ames_probability_max"]
        ratio = ames_prob / thresh if thresh else 0.0
        action = QCAction.HALT if ames_positive or ames_prob > thresh else (
            QCAction.ADVISORY if ratio > 0.85 else QCAction.PASS
        )
        results.append(GateResult(
            gate="ames_mutagenicity",
            action=action,
            level=_level_for_ratio(ratio) if not ames_positive else QCLevel.FAIL,
            value=ames_prob,
            threshold=thresh,
            message=(
                f"Ames {'positive' if ames_positive else 'negative'}, "
                f"probability {ames_prob:.3f} (max {thresh:.2f})"
            ),
            suggestion=(
                "Enable Ames structural alerts filter (Kazius 2005) to remove "
                "mutagenic scaffolds before ADMET prediction."
            ) if action == QCAction.HALT else "",
        ))
        return results

    def _physicochemical_gates(self, metrics: dict) -> list[GateResult]:
        """Lipinski Rule of Five gates (advisory only — no auto-tune defined)."""
        results = []

        logp = metrics.get("logP", 0.0)
        logp_max = self.thresholds["logp_max"]
        logp_ratio = logp / logp_max if logp_max else 0.0
        results.append(GateResult(
            gate="logp",
            action=QCAction.ADVISORY if logp > logp_max else QCAction.PASS,
            level=_level_for_ratio(logp_ratio),
            value=logp,
            threshold=logp_max,
            message=f"logP {logp:.2f} (Lipinski limit {logp_max:.1f})",
            suggestion="Reduce logP filter to improve aqueous solubility and reduce DILI risk." if logp > logp_max else "",
        ))

        mw = metrics.get("mw", 0.0)
        mw_max = self.thresholds["mw_max_da"]
        mw_ratio = mw / mw_max if mw_max else 0.0
        results.append(GateResult(
            gate="molecular_weight",
            action=QCAction.ADVISORY if mw > mw_max else QCAction.PASS,
            level=_level_for_ratio(mw_ratio),
            value=mw,
            threshold=mw_max,
            message=f"MW {mw:.1f} Da (Lipinski limit {mw_max:.0f} Da)",
        ))

        return results
