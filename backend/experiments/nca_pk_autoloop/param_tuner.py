"""
NCA PK parameter tuner.

Remediation strategy:
  auc_extrapolation HALT      → extend last_sampling_time_h by 1.5×
  terminal_slope_coverage HALT → increase terminal_phase_points + extend sampling
"""
from __future__ import annotations
from dataclasses import dataclass
from .params import NCAPKParams
from .qc_evaluator import PhaseQCResult, QCAction

MAX_LAST_SAMPLING_H = 168.0   # 1 week — outer limit for sampling window
MIN_LAST_SAMPLING_H = 4.0


@dataclass
class Remediation:
    phase: str
    gate: str
    param_changes: dict
    rationale: str


class NCAPKParamTuner:
    def remediate(self, phase_qc_result: PhaseQCResult, current_params: NCAPKParams):
        new_params = current_params.copy()
        remediations = []
        for gate_result in phase_qc_result.halts:
            handler = self._HANDLERS.get(gate_result.gate)
            if handler is None:
                remediations.append(Remediation(
                    phase=phase_qc_result.phase, gate=gate_result.gate,
                    param_changes={}, rationale=f"No handler for gate '{gate_result.gate}'."))
                continue
            changes, rationale = handler(self, new_params, gate_result)
            for k, v in changes.items():
                setattr(new_params, k, v)
            remediations.append(Remediation(
                phase=phase_qc_result.phase, gate=gate_result.gate,
                param_changes=changes, rationale=rationale))
        return new_params, remediations

    def _fix_auc_extrapolation(self, p: NCAPKParams, g) -> tuple[dict, str]:
        """AUC extrap > FDA limit → extend sampling window by 1.5×."""
        new_last = min(MAX_LAST_SAMPLING_H, round(p.last_sampling_time_h * 1.5, 1))
        changes: dict = {"last_sampling_time_h": new_last}
        return changes, (
            f"AUC extrapolation {g.value:.1f}% exceeds FDA limit {g.threshold:.0f}%. "
            f"Extended last_sampling_time_h {p.last_sampling_time_h:.1f}→{new_last:.1f} h "
            f"(×1.5) to capture more terminal phase and reduce extrapolated AUC fraction."
        )

    def _fix_terminal_slope(self, p: NCAPKParams, g) -> tuple[dict, str]:
        """Too many subjects missing terminal slope — add sampling points + extend window."""
        new_pts  = min(p.terminal_phase_points + 2, 8)
        new_last = min(MAX_LAST_SAMPLING_H, round(p.last_sampling_time_h * 1.3, 1))
        changes: dict = {"terminal_phase_points": new_pts, "last_sampling_time_h": new_last}
        return changes, (
            f"{int(g.value)} subject(s) missing terminal slope (max {int(g.threshold)}). "
            f"Increased terminal_phase_points {p.terminal_phase_points}→{new_pts} (+2) "
            f"and extended last_sampling_time_h {p.last_sampling_time_h:.1f}→{new_last:.1f} h "
            f"to ensure ≥{new_pts} points in the log-linear decline phase per subject."
        )

    _HANDLERS: dict = {
        "auc_extrapolation":     _fix_auc_extrapolation,
        "terminal_slope_coverage": _fix_terminal_slope,
    }
