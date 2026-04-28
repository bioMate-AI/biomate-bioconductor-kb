"""
ADMET parameter tuner — maps QC gate failures to parameter adjustments.

Each HALT gate has exactly one remediation rule.  The tuner returns a new
ADMETParams copy and a list of Remediation records explaining what changed
and why.

Remediation strategy per gate:
  herg_ic50       → tighten logP/MW filters; compounds with lower logP tend
                    to have weaker hERG affinity (Aronov 2008 model)
  dili_probability → tighten logP + MW filters (Lammert 2010: logP>4 AND MW>400)
  dili_risk_level  → reduce logP_max from 5→4 (crosses the Lammert high-risk boundary)
  ames_mutagenicity→ enable structural alert filtering (Kazius 2005); reduce
                    num_candidates to force stricter library selection
"""

from __future__ import annotations

from dataclasses import dataclass

from .params import ADMETParams
from .qc_evaluator import PhaseQCResult, QCAction


# ── Constants ─────────────────────────────────────────────────────────────────

LOGP_LAMMERT_HIGH_RISK = 4.0      # Above this + MW>400 → "high" DILI (Lammert 2010)
MW_LAMMERT_HIGH_RISK = 400.0

MIN_LOGP = 0.5                    # Guard floor so we don't filter out everything
MIN_HERG_THRESHOLD_uM = 1.0       # Guard — don't raise above a meaningful ceiling
MAX_HERG_THRESHOLD_uM = 50.0
MIN_NUM_CANDIDATES = 10


# ── Data classes ──────────────────────────────────────────────────────────────

@dataclass
class Remediation:
    """Records a single parameter-change decision made in response to a gate failure."""
    phase: str
    gate: str
    param_changes: dict
    rationale: str


# ── Tuner ─────────────────────────────────────────────────────────────────────

class ADMETParamTuner:
    """
    Maps PhaseQCResult HALT gates to parameter adjustments.

    Usage::

        tuner = ADMETParamTuner()
        new_params, remediations = tuner.remediate(phase_qc_result, current_params)
    """

    def remediate(
        self,
        phase_qc_result: PhaseQCResult,
        current_params: ADMETParams,
    ) -> tuple[ADMETParams, list[Remediation]]:
        """
        Apply one remediation per HALT gate in *phase_qc_result*.

        Returns a NEW ADMETParams copy (original never mutated) and a list
        of Remediation objects, one per halted gate.
        """
        new_params = current_params.copy()
        remediations: list[Remediation] = []

        for gate_result in phase_qc_result.halts:
            gate = gate_result.gate
            handler = self._HANDLERS.get(gate)
            if handler is None:
                remediations.append(Remediation(
                    phase=phase_qc_result.phase,
                    gate=gate,
                    param_changes={},
                    rationale=f"No remediation rule defined for gate '{gate}'; manual inspection required.",
                ))
                continue

            changes, rationale = handler(self, new_params, gate_result)
            for param, value in changes.items():
                setattr(new_params, param, value)
            remediations.append(Remediation(
                phase=phase_qc_result.phase,
                gate=gate,
                param_changes=changes,
                rationale=rationale,
            ))

        return new_params, remediations

    # ── Private gate handlers ─────────────────────────────────────────────────

    def _fix_herg(self, p: ADMETParams, gate_result) -> tuple[dict, str]:
        """
        hERG HALT — reduce logP_max by 0.5 to select compounds with lower
        hERG affinity.  Aronov 2008: log10(IC50) ≈ 1.4 - 0.30 * logP →
        reducing logP by 0.5 increases mean IC50 by ≈ 10^(0.15) ≈ 41%.
        """
        new_logp = max(MIN_LOGP, round(p.logp_max - 0.5, 1))
        changes: dict = {"logp_max": new_logp}
        # Also tighten MW if the current limit is above the Lammert risk zone
        if p.mw_max_da > MW_LAMMERT_HIGH_RISK:
            new_mw = round(p.mw_max_da * 0.9, 0)
            changes["mw_max_da"] = new_mw
            mw_note = f"; mw_max_da {p.mw_max_da:.0f}→{new_mw:.0f} Da (−10%)"
        else:
            mw_note = ""
        return changes, (
            f"hERG IC50 {gate_result.value:.2f} µM below safety threshold "
            f"{gate_result.threshold:.0f} µM. "
            f"Reduced logp_max {p.logp_max:.1f}→{new_logp:.1f} (−0.5)"
            f"{mw_note}. "
            f"Per Aronov 2008, lower logP compounds have weaker hERG channel affinity "
            f"(≈+41% IC50 improvement per 0.5 logP unit reduction)."
        )

    def _fix_dili_probability(self, p: ADMETParams, gate_result) -> tuple[dict, str]:
        """
        DILI probability HALT — push logP below the Lammert 2010 high-risk
        threshold (logP > 4.0 AND MW > 400 → "high" risk).
        """
        new_logp = min(p.logp_max, LOGP_LAMMERT_HIGH_RISK)
        new_mw = min(p.mw_max_da, MW_LAMMERT_HIGH_RISK)
        changes: dict = {"logp_max": new_logp, "mw_max_da": new_mw}
        return changes, (
            f"DILI probability {gate_result.value:.3f} exceeds threshold "
            f"{gate_result.threshold:.2f}. "
            f"Set logp_max={new_logp:.1f}, mw_max_da={new_mw:.0f} to stay below "
            f"the Lammert 2010 high-risk zone (logP>4.0 AND MW>400 Da)."
        )

    def _fix_dili_risk_level(self, p: ADMETParams, gate_result) -> tuple[dict, str]:
        """
        DILI risk-level HALT — reduce logP_max to ≤4 (Lammert boundary).
        """
        new_logp = min(p.logp_max, LOGP_LAMMERT_HIGH_RISK)
        changes: dict = {"logp_max": new_logp}
        return changes, (
            f"DILI risk level '{gate_result.gate}' exceeds allowed maximum. "
            f"Capping logp_max at {new_logp:.1f} to remain below the Lammert "
            f"logP > 4.0 high-risk boundary."
        )

    def _fix_ames(self, p: ADMETParams, gate_result) -> tuple[dict, str]:
        """
        Ames HALT — enable structural alert filtering and reduce num_candidates
        to force tighter selection.  Kazius 2005: 29 structural alerts cover
        89% of Ames-positive compounds; flag and remove from library before
        ADMET prediction.
        """
        new_n = max(MIN_NUM_CANDIDATES, p.num_candidates - 10)
        changes: dict = {
            "ames_strict": True,
            "num_candidates": new_n,
        }
        return changes, (
            f"Ames mutagenicity flag raised (probability {gate_result.value:.3f}, "
            f"threshold {gate_result.threshold:.2f}). "
            f"Enabled ames_strict=True (Kazius structural alert pre-filter) and "
            f"reduced num_candidates {p.num_candidates}→{new_n} to concentrate "
            f"screening budget on structurally clean scaffolds."
        )

    # ── Gate → handler dispatch table ─────────────────────────────────────────

    _HANDLERS: dict = {
        "herg_ic50":         _fix_herg,
        "dili_probability":  _fix_dili_probability,
        "dili_risk_level":   _fix_dili_risk_level,
        "ames_mutagenicity": _fix_ames,
        # logp / molecular_weight are advisory-only — no auto-tune defined
    }
