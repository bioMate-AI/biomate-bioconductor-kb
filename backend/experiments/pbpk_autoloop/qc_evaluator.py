"""
PBPK QC evaluator.

Mirrors the gate API used by admet/docking/cyp_ddi/nca_pk autoloops:
  evaluate_phase(phase, metrics) -> PhaseQCResult

Profile thresholds mirror qc_trace_monitor.py lines 690-733 (pbpk_ind_submission
and pbpk_screening) and add two gates the existing QC layer does NOT emit
today (mass_balance, auc_fold_error) — those are the gaps the audit found.

Metrics expected (synthesised by autoloop_bridge._adapt_pbpk):
  {
    "tmax_h":                 float,   # observed Tmax (hours)
    "simulation_duration_h":  float,   # total sim window
    "cl_l_per_h":             float,   # systemic clearance (L/h)
    "thalf_estimable":        bool,    # True iff terminal-phase regression OK
    "mass_balance_recovery":  float,   # 0.0–1.0+ (1.0 = perfect)
    "auc_pred_h_ug_per_mL":   float,   # predicted AUC (None if N/A)
    "auc_obs_h_ug_per_mL":    float,   # observed AUC (None if N/A)
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


# ── QC profiles (mirror qc_trace_monitor.py:690-733) ─────────────────────────

QC_PROFILES: dict[str, dict[str, Any]] = {
    "pbpk_ind_submission": {
        # IND/NDA-grade; HALTs on any gate failure
        "tmax_fraction_max":      0.80,   # Tmax within first 80% of sim window
        "cl_min_L_h":             0.01,
        "mass_balance_tol":       0.05,   # ±5% recovery
        "auc_fold_error_max":     2.0,    # |log2(pred/obs)| ≤ 1
        "advisory_only":          False,
    },
    "pbpk_screening": {
        # Lead-opt mode; ADVISORY only (no HALTs) per qc_trace_monitor convention
        "tmax_fraction_max":      0.90,
        "cl_min_L_h":             0.001,
        "mass_balance_tol":       0.10,
        "auc_fold_error_max":     3.0,
        "advisory_only":          True,
    },
}


class PBPKQCEvaluator:
    """Evaluates PBPK simulation metrics against profile thresholds."""

    def __init__(self, profile: str = "pbpk_screening"):
        if profile not in QC_PROFILES:
            raise ValueError(
                f"Unknown QC profile: {profile!r}. Options: {list(QC_PROFILES)}"
            )
        self.profile = profile
        self.thresholds = QC_PROFILES[profile]

    # Single phase — PBPK simulation produces one result blob per run
    def evaluate_phase(self, phase: str, metrics: dict) -> PhaseQCResult:
        gates: list[GateResult] = []
        gates.extend(self._tmax_fraction_gate(metrics))
        gates.extend(self._cl_min_gate(metrics))
        gates.extend(self._mass_balance_gate(metrics))
        gates.extend(self._auc_fold_error_gate(metrics))
        return PhaseQCResult(phase=phase, gate_results=gates)

    # ─── individual gates ────────────────────────────────────────────────

    def _action(self, fail: bool) -> QCAction:
        """Map fail → HALT (or ADVISORY in screening profile)."""
        if not fail:
            return QCAction.PASS
        if self.thresholds.get("advisory_only", False):
            return QCAction.ADVISORY
        return QCAction.HALT

    def _tmax_fraction_gate(self, m: dict) -> list[GateResult]:
        tmax = float(m.get("tmax_h", 0.0) or 0.0)
        dur = float(m.get("simulation_duration_h", 0.0) or 0.0)
        if dur <= 0:
            return []
        fraction = tmax / dur
        threshold = float(self.thresholds["tmax_fraction_max"])
        fail = fraction > threshold
        level = QCLevel.FAIL if fail else (
            QCLevel.BRONZE if fraction > threshold * 0.9 else QCLevel.GOLD
        )
        msg = (
            f"Tmax at {fraction*100:.1f}% of sim window "
            f"(threshold ≤{threshold*100:.0f}%)"
            if fail else
            f"Tmax at {fraction*100:.1f}% of sim window — OK"
        )
        return [GateResult(
            gate="pbpk_tmax_fraction",
            action=self._action(fail),
            level=level,
            value=fraction,
            threshold=threshold,
            message=msg,
        )]

    def _cl_min_gate(self, m: dict) -> list[GateResult]:
        cl = float(m.get("cl_l_per_h", 0.0) or 0.0)
        threshold = float(self.thresholds["cl_min_L_h"])
        fail = cl < threshold
        level = QCLevel.FAIL if fail else QCLevel.GOLD
        msg = (
            f"CL={cl:.4f} L/h below lower bound {threshold} L/h"
            if fail else
            f"CL={cl:.3f} L/h — OK"
        )
        return [GateResult(
            gate="pbpk_cl_min",
            action=self._action(fail),
            level=level,
            value=cl,
            threshold=threshold,
            message=msg,
        )]

    def _mass_balance_gate(self, m: dict) -> list[GateResult]:
        recov = m.get("mass_balance_recovery", None)
        if recov is None:
            return []  # gate not applicable for this run
        recov = float(recov)
        tol = float(self.thresholds["mass_balance_tol"])
        deviation = abs(recov - 1.0)
        fail = deviation > tol
        level = QCLevel.FAIL if fail else (
            QCLevel.BRONZE if deviation > tol * 0.6 else QCLevel.GOLD
        )
        msg = (
            f"Mass recovery {recov:.3f} ({deviation*100:.1f}% off from 1.0; "
            f"tol ±{tol*100:.0f}%)"
            if fail else
            f"Mass recovery {recov:.3f} within ±{tol*100:.0f}%"
        )
        return [GateResult(
            gate="pbpk_mass_balance",
            action=self._action(fail),
            level=level,
            value=recov,
            threshold=tol,
            message=msg,
        )]

    def _auc_fold_error_gate(self, m: dict) -> list[GateResult]:
        pred = m.get("auc_pred_h_ug_per_mL", None)
        obs = m.get("auc_obs_h_ug_per_mL", None)
        if pred is None or obs is None or float(obs) == 0:
            return []  # no observed reference — skip gate
        pred, obs = float(pred), float(obs)
        if pred <= 0:
            return []
        log2_ratio = abs(math.log2(pred / obs))
        threshold = float(self.thresholds["auc_fold_error_max"])
        # threshold is in fold-error space (e.g. 2.0) — convert to log2 space
        log2_threshold = math.log2(threshold)
        fail = log2_ratio > log2_threshold
        level = QCLevel.FAIL if fail else (
            QCLevel.BRONZE if log2_ratio > log2_threshold * 0.6 else QCLevel.GOLD
        )
        fold = 2 ** log2_ratio
        msg = (
            f"AUC fold-error {fold:.2f}× exceeds {threshold:.1f}×"
            if fail else
            f"AUC fold-error {fold:.2f}× within {threshold:.1f}×"
        )
        return [GateResult(
            gate="pbpk_auc_fold_error",
            action=self._action(fail),
            level=level,
            value=fold,
            threshold=threshold,
            message=msg,
        )]
