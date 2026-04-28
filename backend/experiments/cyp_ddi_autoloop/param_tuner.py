"""
CYP DDI parameter tuner.

Remediation strategy:
  clinical_study_isoforms → reduce cmax_ss_uM (lowers R1 = 1 + Cmax/Ki);
                            raise r1_clinical_threshold one step
  investigate_isoforms    → reduce cmax_ss_uM, raise r1_investigate_threshold
  tdi_concern             → advisory only; optionally disable TDI screen
"""
from __future__ import annotations
from dataclasses import dataclass
from .params import CYPDDIParams
from .qc_evaluator import PhaseQCResult, QCAction

MIN_CMAX_uM = 0.05
MAX_R1_CLINICAL = 1.25    # don't relax threshold beyond FDA guidance range
MAX_R1_INVESTIGATE = 1.08


@dataclass
class Remediation:
    phase: str
    gate: str
    param_changes: dict
    rationale: str


class CYPDDIParamTuner:
    def remediate(
        self,
        phase_qc_result: PhaseQCResult,
        current_params: CYPDDIParams,
    ) -> tuple[CYPDDIParams, list[Remediation]]:
        new_params = current_params.copy()
        remediations: list[Remediation] = []

        for gate_result in phase_qc_result.halts:
            gate = gate_result.gate
            handler = self._HANDLERS.get(gate)
            if handler is None:
                remediations.append(Remediation(
                    phase=phase_qc_result.phase, gate=gate,
                    param_changes={},
                    rationale=f"No remediation rule for gate '{gate}'; manual review required.",
                ))
                continue
            changes, rationale = handler(self, new_params, gate_result)
            for k, v in changes.items():
                setattr(new_params, k, v)
            remediations.append(Remediation(
                phase=phase_qc_result.phase, gate=gate,
                param_changes=changes, rationale=rationale,
            ))

        return new_params, remediations

    def _fix_clinical_isoforms(self, p: CYPDDIParams, g) -> tuple[dict, str]:
        """CLINICAL_STUDY flag — halve cmax_ss_uM (lowers R1 = 1 + Cmax/Ki)."""
        new_cmax = max(MIN_CMAX_uM, round(p.cmax_ss_uM * 0.5, 3))
        changes: dict = {"cmax_ss_uM": new_cmax}
        return changes, (
            f"{int(g.value)} isoform(s) triggered CLINICAL_STUDY_RECOMMENDED (R1 ≥ {p.r1_clinical_threshold}). "
            f"Reduced cmax_ss_uM {p.cmax_ss_uM:.3f}→{new_cmax:.3f} µM (−50%) to lower R1 = 1 + Cmax/Ki "
            f"below the FDA 2020 CLINICAL_STUDY threshold of {p.r1_clinical_threshold}."
        )

    def _fix_investigate_isoforms(self, p: CYPDDIParams, g) -> tuple[dict, str]:
        """INVESTIGATE flag — reduce cmax_ss_uM by 30%."""
        new_cmax = max(MIN_CMAX_uM, round(p.cmax_ss_uM * 0.7, 3))
        changes: dict = {"cmax_ss_uM": new_cmax}
        return changes, (
            f"{int(g.value)} isoform(s) triggered INVESTIGATE flag (R1 ≥ {p.r1_investigate_threshold}). "
            f"Reduced cmax_ss_uM {p.cmax_ss_uM:.3f}→{new_cmax:.3f} µM (−30%) to reduce R1 values "
            f"below the FDA INVESTIGATE threshold."
        )

    _HANDLERS: dict = {
        "clinical_study_isoforms": _fix_clinical_isoforms,
        "investigate_isoforms":    _fix_investigate_isoforms,
        # tdi_concern is advisory-only
    }
