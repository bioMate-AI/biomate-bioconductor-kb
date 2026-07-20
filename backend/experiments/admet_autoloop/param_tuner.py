"""
ADMET parameter tuner — maps QC gate failures to parameter adjustments.

Confidence tiers (see docs/20260715_QC_AUTOLOOP_THRESHOLD_TUNING_DESIGN.md):

  CONFIDENT (auto-applied):
    ames_mutagenicity  → ames_strict=True.  Kazius 2005 structural alerts ARE
                         the prediction mechanism — enabling the pre-filter
                         directly removes the flagged compounds.  GOLD evidence,
                         categorical fix, no step-size uncertainty.
    dili_probability   → logp_max=4.0, mw_max_da=400.  Lammert 2010 boundary
    dili_risk_level      is a categorical line; the fix is "move below the line."
                         No step-size optimisation required.

  HEURISTIC (applied with stated uncertainty):
    herg_ic50          → gap-proportional logP reduction with target margin.
                         Direction is supported (Waring & Johnstone 2007);
                         magnitude is calibrated to the gap, not to a
                         population curve.  Becomes confident once failing
                         compound descriptors from herg_risk.json are wired in
                         (see _fix_herg_analytical for the planned upgrade).

  NOT AUTO-TUNED (manual input required):
    logp / molecular_weight  advisory-only; no auto-tune defined.
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Optional, TYPE_CHECKING

from .params import ADMETParams
from .qc_evaluator import PhaseQCResult, QCAction

if TYPE_CHECKING:
    from .calibration_logger import CalibrationLogger


# ── Constants ─────────────────────────────────────────────────────────────────

# Lammert 2010: logP > 4.0 AND MW > 400 Da → elevated DILI risk zone.
# Setting both at or below these values moves compounds out of the risk zone.
# These are categorical targets, not step sizes.
LOGP_LAMMERT_BOUNDARY = 4.0
MW_LAMMERT_BOUNDARY   = 400.0

# hERG heuristic: aim for threshold × this margin so the next run lands safely
# above the gate, not right at it.  1.5× = target 15 µM when threshold is 10 µM.
HERG_SAFETY_MARGIN = 1.5

# BioMate's own QSAR model coefficient (herg_cardiac_safety_qsar/main.nf, line 119).
# log_ic50 = HERG_QSAR_INTERCEPT + HERG_QSAR_LOGP_COEFF * logP + (other terms)
# Used for analytical inversion when compound descriptors are available.
HERG_QSAR_LOGP_COEFF  = -0.35
HERG_QSAR_INTERCEPT   = -1.2     # baseline at logP=0, cationic_flag=0, others=0

# Gap-proportional hERG heuristic: base step when gap_ratio=1 (barely failing).
# Scales as BASE_STEP * log10(gap_ratio) so a 10× gap → ~BASE_STEP logP units.
HERG_BASE_STEP = 0.5

MIN_LOGP          = 0.5     # floor: avoid filtering out all drug-like compounds
MIN_NUM_CANDIDATES = 10


# ── Data classes ──────────────────────────────────────────────────────────────

@dataclass
class Remediation:
    """Records a single parameter-change decision made in response to a gate failure."""
    phase: str
    gate: str
    param_changes: dict
    rationale: str
    # Whether the auto-loop can apply this confidently or only as a heuristic.
    # "confident" → categorical fix with GOLD/SILVER evidence and no step-size uncertainty.
    # "heuristic" → directionally supported but magnitude is estimated.
    # "manual"    → system cannot determine the correct value; user input required.
    confidence: str = "confident"


# ── Tuner ─────────────────────────────────────────────────────────────────────

class ADMETParamTuner:
    """
    Maps PhaseQCResult HALT gates to parameter adjustments.

    All gate handlers collect their logP/MW bounds BEFORE writing any change,
    then the joint minimum is applied once.  This prevents hERG and DILI
    handlers from overwriting each other when both gates fail simultaneously.

    Usage::

        tuner = ADMETParamTuner()
        new_params, remediations = tuner.remediate(phase_qc_result, current_params)

    Optional compound descriptors for analytical hERG inversion::

        new_params, remediations = tuner.remediate(
            phase_qc_result, current_params,
            herg_compound_descriptors={
                "logP": 4.8, "cationic_flag": 1, "mw": 420,
                "ring_count": 3, "hbd": 2,
            }
        )

    Optional calibration logging::

        from experiments.admet_autoloop.calibration_logger import CalibrationLogger
        logger = CalibrationLogger("/data/admet_calibration.jsonl")
        tuner  = ADMETParamTuner(calibration_logger=logger)
        # Each hERG remediation will append a record to the file.
    """

    def __init__(
        self,
        calibration_logger: "Optional[CalibrationLogger]" = None,
        profile: str = "admet_standard",
    ) -> None:
        self._calibration_logger = calibration_logger
        self._profile = profile

    def remediate(
        self,
        phase_qc_result: PhaseQCResult,
        current_params: ADMETParams,
        herg_compound_descriptors: Optional[dict] = None,
    ) -> tuple[ADMETParams, list[Remediation]]:
        new_params = current_params.copy()
        remediations: list[Remediation] = []

        # ── Pass 1: compute bounds from all failing gates ─────────────────────
        # Collect logP and MW targets before writing anything, so gates that both
        # constrain logP don't overwrite each other.
        logp_bounds: list[float] = []
        mw_bounds:   list[float] = []

        for gate_result in phase_qc_result.halts:
            gate = gate_result.gate
            if gate == "herg_ic50":
                logp_bounds.append(
                    self._herg_logp_target(gate_result, current_params, herg_compound_descriptors)
                )
            elif gate in ("dili_probability", "dili_risk_level"):
                logp_bounds.append(LOGP_LAMMERT_BOUNDARY)
                mw_bounds.append(MW_LAMMERT_BOUNDARY)

        # Apply the most restrictive bound that satisfies all gates simultaneously.
        if logp_bounds:
            new_logp = max(MIN_LOGP, min(logp_bounds))
            new_params.logp_max = round(new_logp, 1)
        if mw_bounds:
            new_params.mw_max_da = round(min(mw_bounds), 0)

        # ── Pass 2: build Remediation records and apply non-logP changes ──────
        for gate_result in phase_qc_result.halts:
            gate = gate_result.gate
            handler = self._HANDLERS.get(gate)
            if handler is None:
                remediations.append(Remediation(
                    phase=phase_qc_result.phase,
                    gate=gate,
                    param_changes={},
                    rationale=(
                        f"No remediation rule defined for gate '{gate}'. "
                        f"Manual inspection required."
                    ),
                    confidence="manual",
                ))
                continue

            changes, rationale, confidence = handler(
                self, new_params, gate_result, current_params, herg_compound_descriptors
            )
            for param, value in changes.items():
                setattr(new_params, param, value)
            remediations.append(Remediation(
                phase=phase_qc_result.phase,
                gate=gate,
                param_changes=changes,
                rationale=rationale,
                confidence=confidence,
            ))

        return new_params, remediations

    # ── hERG ──────────────────────────────────────────────────────────────────

    def _herg_logp_target(
        self,
        gate_result,
        current_params: ADMETParams,
        descriptors: Optional[dict],
    ) -> float:
        """
        Compute the target logP_max for a failing hERG gate.

        Two paths:
        1. Analytical (confident): failing compound descriptors available →
           invert BioMate's own QSAR model exactly.
        2. Heuristic (estimated): no descriptors → gap-proportional step
           scaled to the distance from threshold.
        """
        target_ic50 = gate_result.threshold * HERG_SAFETY_MARGIN

        if descriptors:
            return self._herg_logp_analytical(target_ic50, descriptors, current_params)
        else:
            return self._herg_logp_heuristic(gate_result, target_ic50, current_params)

    def _herg_logp_analytical(
        self,
        target_ic50: float,
        descriptors: dict,
        current_params: ADMETParams,
    ) -> float:
        """
        Invert BioMate's own QSAR model (herg_cardiac_safety_qsar/main.nf):
          log_ic50 = -1.2 - 0.35*logP - 1.0*cationic_flag + 0.003*mw
                     - 0.15*ring_count + 0.4*hbd

        Solve for the logP that achieves target_ic50, holding all other
        descriptors fixed at the failing compound's values.
        """
        cf    = float(descriptors.get("cationic_flag", 0))
        mw    = float(descriptors.get("mw", 400.0))
        rings = float(descriptors.get("ring_count", 3))
        hbd   = float(descriptors.get("hbd", 2))

        other_terms = -1.0 * cf + 0.003 * mw - 0.15 * rings + 0.4 * hbd
        target_log_ic50 = math.log10(max(target_ic50, 0.001))
        # Rearrange: target_log_ic50 = INTERCEPT + COEFF*logP + other_terms
        # → logP = (target_log_ic50 - INTERCEPT - other_terms) / COEFF
        target_logp = (target_log_ic50 - HERG_QSAR_INTERCEPT - other_terms) / HERG_QSAR_LOGP_COEFF
        return max(MIN_LOGP, min(current_params.logp_max, target_logp))

    def _herg_logp_heuristic(
        self,
        gate_result,
        target_ic50: float,
        current_params: ADMETParams,
    ) -> float:
        """
        Gap-proportional step when compound descriptors are unavailable.

        Step = BASE_STEP * log10(gap_ratio), where gap_ratio = target / observed.
        A 3× gap → step ≈ 0.5 * 0.48 = 0.24 logP units.
        A 10× gap → step ≈ 0.5 * 1.0  = 0.50 logP units.

        Direction is supported by Waring & Johnstone 2007; magnitude is estimated.
        """
        observed_ic50 = max(gate_result.value, 0.001)
        gap_ratio = target_ic50 / observed_ic50
        step = HERG_BASE_STEP * math.log10(max(gap_ratio, 1.0))
        return max(MIN_LOGP, current_params.logp_max - step)

    def _fix_herg(
        self, new_params: ADMETParams, gate_result, orig: ADMETParams, descriptors
    ) -> tuple[dict, str, str]:
        """Build the Remediation record for hERG after logP has been computed in Pass 1."""
        changes: dict = {}
        if new_params.logp_max != orig.logp_max:
            changes["logp_max"] = new_params.logp_max
        if new_params.mw_max_da != orig.mw_max_da:
            changes["mw_max_da"] = new_params.mw_max_da

        target_ic50  = gate_result.threshold * HERG_SAFETY_MARGIN
        observed_ic50 = max(gate_result.value, 0.001)
        gap_ratio     = target_ic50 / observed_ic50

        if descriptors:
            confidence = "confident"
            rationale = (
                f"hERG IC50 {gate_result.value:.2f} µM below threshold "
                f"{gate_result.threshold:.0f} µM. "
                f"Analytically inverted BioMate QSAR model "
                f"(herg_cardiac_safety_qsar coeff −0.35/logP unit) "
                f"for target IC50 {target_ic50:.0f} µM ({HERG_SAFETY_MARGIN}× margin): "
                f"logp_max {orig.logp_max:.1f}→{new_params.logp_max:.1f}."
            )
        else:
            confidence = "heuristic"
            rationale = (
                f"hERG IC50 {gate_result.value:.2f} µM below threshold "
                f"{gate_result.threshold:.0f} µM (gap {gap_ratio:.1f}×). "
                f"Gap-proportional step applied (direction: Waring & Johnstone 2007; "
                f"magnitude: estimated from gap ratio). "
                f"logp_max {orig.logp_max:.1f}→{new_params.logp_max:.1f}. "
                f"Confidence: heuristic — override if you know the compound class."
            )

        # ── Calibration log ───────────────────────────────────────────────────
        # Record (observed_ic50, logp_max_suggested) for future recalibration of
        # HERG_QSAR_LOGP_COEFF / HERG_BASE_STEP. ts and run_id must be injected
        # by the caller (not here) to keep this method deterministic.
        if self._calibration_logger is not None:
            self._calibration_logger.log(
                observed_ic50_uM=gate_result.value,
                logp_max_before=orig.logp_max,
                logp_max_suggested=new_params.logp_max,
                target_ic50_uM=target_ic50,
                gap_ratio=gap_ratio,
                confidence=confidence,
                profile=self._profile,
            )

        return changes, rationale, confidence

    # ── DILI ──────────────────────────────────────────────────────────────────

    def _fix_dili_probability(
        self, new_params: ADMETParams, gate_result, orig: ADMETParams, _descriptors
    ) -> tuple[dict, str, str]:
        """
        DILI probability HALT — categorical fix: set both params to the Lammert
        boundary.  This is confident because the action is 'move below the line',
        not 'reduce by some amount'.
        """
        changes: dict = {}
        if new_params.logp_max != orig.logp_max:
            changes["logp_max"] = new_params.logp_max
        if new_params.mw_max_da != orig.mw_max_da:
            changes["mw_max_da"] = new_params.mw_max_da
        rationale = (
            f"DILI probability {gate_result.value:.3f} exceeds threshold "
            f"{gate_result.threshold:.2f}. "
            f"Set logp_max={LOGP_LAMMERT_BOUNDARY:.1f} and "
            f"mw_max_da={MW_LAMMERT_BOUNDARY:.0f} Da — the categorical Lammert 2010 "
            f"risk-zone boundary (logP>4.0 AND MW>400 Da → elevated DILI risk). "
            f"Moving below both limits removes compounds from the high-risk zone."
        )
        return changes, rationale, "confident"

    def _fix_dili_risk_level(
        self, new_params: ADMETParams, gate_result, orig: ADMETParams, _descriptors
    ) -> tuple[dict, str, str]:
        """
        DILI risk-level HALT — categorical logP-only fix (MW already below boundary).
        """
        changes: dict = {}
        if new_params.logp_max != orig.logp_max:
            changes["logp_max"] = new_params.logp_max
        rationale = (
            f"DILI risk level exceeds maximum. "
            f"Set logp_max={LOGP_LAMMERT_BOUNDARY:.1f} — the Lammert 2010 logP boundary. "
            f"MW is already ≤ {MW_LAMMERT_BOUNDARY:.0f} Da so no MW change needed."
        )
        return changes, rationale, "confident"

    # ── Ames ──────────────────────────────────────────────────────────────────

    def _fix_ames(
        self, new_params: ADMETParams, gate_result, orig: ADMETParams, _descriptors
    ) -> tuple[dict, str, str]:
        """
        Ames HALT — enable structural alert pre-filter.

        This is the highest-confidence remediation in the system: the Kazius 2005
        structural alerts ARE the mechanism behind the prediction.  Enabling
        ames_strict=True removes compounds matching those same alerts before the
        Ames probability model runs, directly eliminating the source of the flag.

        Confidence: GOLD.  No step-size uncertainty; the fix is categorical.
        """
        changes: dict = {}
        if not orig.ames_strict:
            new_params.ames_strict = True
            changes["ames_strict"] = True

        new_n = max(MIN_NUM_CANDIDATES, orig.num_candidates - 10)
        if new_n != orig.num_candidates:
            new_params.num_candidates = new_n
            changes["num_candidates"] = new_n

        rationale = (
            f"Ames mutagenicity flag (probability {gate_result.value:.3f}, "
            f"threshold {gate_result.threshold:.2f}). "
            f"Enabled ames_strict=True — the Kazius 2005 structural alert pre-filter "
            f"(29 toxicophores covering ~89% of Ames-positive compounds). "
            f"This directly removes the compounds driving the flag before the "
            f"probability model runs."
        )
        if "num_candidates" in changes:
            rationale += (
                f" Reduced num_candidates {orig.num_candidates}→{new_n} to concentrate "
                f"budget on structurally clean scaffolds."
            )
        return changes, rationale, "confident"

    # ── Gate → handler dispatch ────────────────────────────────────────────────

    _HANDLERS: dict = {
        "herg_ic50":         _fix_herg,
        "dili_probability":  _fix_dili_probability,
        "dili_risk_level":   _fix_dili_risk_level,
        "ames_mutagenicity": _fix_ames,
    }
