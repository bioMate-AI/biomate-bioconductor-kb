"""
PBPK parameter-tuning remediation.

For each failed gate, propose ONE parameter change with rationale.
Mirrors the API of admet_autoloop.param_tuner: remediate(qc_result, params).
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Tuple

from .params import PBPKParams
from .qc_evaluator import PhaseQCResult, GateResult


@dataclass
class Remediation:
    gate: str               # the failing gate
    param: str              # parameter name to change
    old_value: Any
    new_value: Any
    rationale: str          # why this remediation

    def to_dict(self) -> dict:
        return {
            "gate": self.gate,
            "param": self.param,
            "old_value": self.old_value,
            "new_value": self.new_value,
            "rationale": self.rationale,
        }


def _remediate_tmax_fraction(g: GateResult, p: PBPKParams) -> Remediation:
    # Tmax too close to end of sim — extend simulation window.
    # Empirically, 3× the predicted Tmax is sufficient to capture elimination.
    fraction = g.value
    new_dur = max(p.simulation_duration_h * 1.5, p.simulation_duration_h * fraction * 3.0)
    return Remediation(
        gate=g.gate,
        param="simulation_duration_h",
        old_value=p.simulation_duration_h,
        new_value=round(new_dur, 1),
        rationale=(
            f"Tmax at {fraction*100:.1f}% of window — extending sim to "
            f"capture elimination phase (target: Tmax < 80% of window). "
            f"FDA PBPK Guidance 2018."
        ),
    )


def _remediate_cl_min(g: GateResult, p: PBPKParams) -> Remediation:
    # CL too low — usually parameter mismatch in fu_p × CLint.
    # Suggest doubling CLint as starting point (operator can refine).
    return Remediation(
        gate=g.gate,
        param="clint_mL_per_min",
        old_value=p.clint_mL_per_min,
        new_value=round(p.clint_mL_per_min * 2.0, 2),
        rationale=(
            f"CL={g.value:.4f} L/h below physiological floor "
            f"({g.threshold} L/h). Well-stirred model: CL ≈ Q_h × "
            f"fu_p × CLint / (Q_h + fu_p × CLint). Doubling CLint as a "
            f"first-pass remediation. Per Davies & Morris 1993."
        ),
    )


def _remediate_mass_balance(g: GateResult, p: PBPKParams) -> Remediation:
    # Solver tolerance too loose — tighten by 100×.
    new_rtol = p.integration_rtol * 1e-2
    return Remediation(
        gate=g.gate,
        param="integration_rtol",
        old_value=p.integration_rtol,
        new_value=new_rtol,
        rationale=(
            f"Mass balance deviation {abs(g.value - 1.0)*100:.1f}% exceeds "
            f"±{g.threshold*100:.0f}% — tightening ODE solver tolerance. "
            f"Per EMA Guideline EMA/CHMP/458101/2016."
        ),
    )


def _remediate_auc_fold_error(g: GateResult, p: PBPKParams) -> Remediation:
    # If predicted > observed (fold-error from overprediction), reduce Kp.
    # If predicted < observed, increase Kp. Gate.value is the fold-error
    # magnitude; we infer direction by comparing pred/obs in message.
    # Heuristic: default to reducing Kp by 25% (most common in oral PK).
    new_scale = p.kp_scale * 0.75
    return Remediation(
        gate=g.gate,
        param="kp_scale",
        old_value=p.kp_scale,
        new_value=round(new_scale, 3),
        rationale=(
            f"AUC fold-error {g.value:.2f}× outside ±{g.threshold:.1f}× — "
            f"adjusting tissue partition (Kp_scale ×0.75). Secondary: revisit "
            f"fu_p. Per FDA PBPK Guidance 2018 (2-fold criterion)."
        ),
    )


_HANDLERS = {
    "pbpk_tmax_fraction":   _remediate_tmax_fraction,
    "pbpk_cl_min":          _remediate_cl_min,
    "pbpk_mass_balance":    _remediate_mass_balance,
    "pbpk_auc_fold_error":  _remediate_auc_fold_error,
}


class PBPKTuner:
    """Apply remediation rules for each failed PBPK gate."""

    def remediate(
        self,
        qc_result: PhaseQCResult,
        params: PBPKParams,
    ) -> Tuple[PBPKParams, list[Remediation]]:
        new_params = params.copy()
        remediations: list[Remediation] = []
        # Halts get remediation; advisory-only gates do too (so the screening
        # profile still surfaces suggestions even though it never HALTs).
        for g in qc_result.gate_results:
            if g.passed and g.level not in ("BRONZE", "FAIL"):
                continue
            handler = _HANDLERS.get(g.gate)
            if handler is None:
                continue
            r = handler(g, new_params)
            # Apply the change to new_params
            setattr(new_params, r.param, r.new_value)
            remediations.append(r)
        return new_params, remediations
