"""
Docking parameter tuner.

Remediation strategy:
  valid_poses HALT     → expand binding box + increase exhaustiveness
  best_binding_score   → increase exhaustiveness; switch Glide SP→XP
"""
from __future__ import annotations
from dataclasses import dataclass
from .params import DockingParams
from .qc_evaluator import PhaseQCResult, QCAction

MAX_EXHAUSTIVENESS = 32
MAX_BOX_EXPAND_A   = 5.0


@dataclass
class Remediation:
    phase: str
    gate: str
    param_changes: dict
    rationale: str


class DockingParamTuner:
    def remediate(self, phase_qc_result: PhaseQCResult, current_params: DockingParams):
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

    def _fix_valid_poses(self, p: DockingParams, g) -> tuple[dict, str]:
        new_exhaust = min(MAX_EXHAUSTIVENESS, p.exhaustiveness * 2)
        new_expand  = min(MAX_BOX_EXPAND_A, p.center_box_expand_A + 1.0)
        changes: dict = {"exhaustiveness": new_exhaust, "center_box_expand_A": new_expand}
        return changes, (
            f"No valid poses generated. Doubled exhaustiveness {p.exhaustiveness}→{new_exhaust} "
            f"and expanded binding box by +1.0 Å ({p.center_box_expand_A:.1f}→{new_expand:.1f} Å) "
            f"to improve conformational sampling coverage."
        )

    def _fix_binding_score(self, p: DockingParams, g) -> tuple[dict, str]:
        new_exhaust = min(MAX_EXHAUSTIVENESS, p.exhaustiveness + 4)
        changes: dict = {"exhaustiveness": new_exhaust}
        # Upgrade Glide precision if using SP
        if p.docking_precision == "SP":
            changes["docking_precision"] = "XP"
            return changes, (
                f"Best score {g.value:.2f} kcal/mol above hit threshold {g.threshold:.1f}. "
                f"Increased exhaustiveness {p.exhaustiveness}→{new_exhaust} and upgraded "
                f"Glide precision SP→XP for more accurate scoring of near-threshold poses."
            )
        return changes, (
            f"Best score {g.value:.2f} kcal/mol above hit threshold {g.threshold:.1f}. "
            f"Increased Vina exhaustiveness {p.exhaustiveness}→{new_exhaust} for better "
            f"global search coverage of the binding pocket."
        )

    _HANDLERS: dict = {
        "valid_poses":         _fix_valid_poses,
        "best_binding_score":  _fix_binding_score,
    }
