"""
CryoEM parameter tuner — maps QC gate failures to parameter adjustments.

Each HALT gate has exactly one remediation rule.  The tuner returns a new
CryoEMParams copy and a list of Remediation records explaining what changed
and why.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import TYPE_CHECKING

from .params import CryoEMParams
from .qc_evaluator import PhaseQCResult, QCAction

# ── Constants ────────────────────────────────────────────────────────────────

MIN_MICROGRAPH_BATCH_SIZE = 50
MAX_AB_INITIO_CLASSES = 8


# ── Data classes ─────────────────────────────────────────────────────────────

@dataclass
class Remediation:
    """Records a single parameter-change decision made in response to a gate failure."""
    phase: str
    gate: str
    param_changes: dict   # {param_name: new_value}
    rationale: str


# ── Tuner ────────────────────────────────────────────────────────────────────

class ParamTuner:
    """
    Maps PhaseQCResult HALT gates to parameter adjustments.

    Usage::

        tuner = ParamTuner()
        new_params, remediations = tuner.remediate(phase_qc_result, current_params)
    """

    def remediate(
        self,
        phase_qc_result: PhaseQCResult,
        current_params: CryoEMParams,
    ) -> tuple[CryoEMParams, list[Remediation]]:
        """
        Apply one remediation per HALT gate found in *phase_qc_result*.

        Returns a *new* CryoEMParams copy (the original is never mutated) and
        a list of Remediation objects, one per halted gate.  Gates that only
        produce an advisory are ignored.
        """
        new_params = current_params.copy()
        remediations: list[Remediation] = []

        for gate_result in phase_qc_result.halts:
            gate = gate_result.gate
            handler = self._HANDLERS.get(gate)
            if handler is None:
                # Unknown gate — record an advisory-style remediation with no changes
                remediations.append(Remediation(
                    phase=phase_qc_result.phase,
                    gate=gate,
                    param_changes={},
                    rationale=f"No remediation rule defined for gate '{gate}'; manual inspection required.",
                ))
                continue

            changes, rationale = handler(self, new_params)
            # Apply changes to the running params copy
            for param, value in changes.items():
                setattr(new_params, param, value)
            remediations.append(Remediation(
                phase=phase_qc_result.phase,
                gate=gate,
                param_changes=changes,
                rationale=rationale,
            ))

        return new_params, remediations

    # ── Private gate handlers ────────────────────────────────────────────────
    # Each handler receives the *current* (already-accumulating) new_params so
    # that multiple gates in the same phase stack their adjustments.
    # Returns (param_changes_dict, rationale_string).

    def _fix_motion_drift(self, p: CryoEMParams) -> tuple[dict, str]:
        """motion_drift HALT — reduce batch size by half, enable dose weighting."""
        new_batch = max(MIN_MICROGRAPH_BATCH_SIZE, p.micrograph_batch_size // 2)
        changes: dict = {"micrograph_batch_size": new_batch, "motion_correction_dose_weighting": True}
        return changes, (
            f"Total drift exceeded threshold. Reduced micrograph_batch_size "
            f"{p.micrograph_batch_size} → {new_batch} (min {MIN_MICROGRAPH_BATCH_SIZE}) "
            f"and enabled dose_weighting to improve frame alignment stability."
        )

    def _fix_per_frame_drift(self, p: CryoEMParams) -> tuple[dict, str]:
        """per_frame_drift HALT — reduce batch size by half."""
        new_batch = max(MIN_MICROGRAPH_BATCH_SIZE, p.micrograph_batch_size // 2)
        changes: dict = {"micrograph_batch_size": new_batch}
        return changes, (
            f"Per-frame drift exceeded threshold. Reduced micrograph_batch_size "
            f"{p.micrograph_batch_size} → {new_batch} (min {MIN_MICROGRAPH_BATCH_SIZE}) "
            f"to reduce inter-frame motion during alignment."
        )

    def _fix_ctf_fit_quality(self, p: CryoEMParams) -> tuple[dict, str]:
        """ctf_fit_quality HALT — broaden the CTF fit window (min 20→30 Å, max 5→3 Å)."""
        new_min = 30.0   # Å — extend low-res end of fit window
        new_max = 3.0    # Å — tighten high-res end (more signal, less noise)
        changes: dict = {
            "ctf_fitting_resolution_min": new_min,
            "ctf_fitting_resolution_max": new_max,
        }
        return changes, (
            f"CTF fit quality below threshold. Broadened fit window: "
            f"ctf_fitting_resolution_min {p.ctf_fitting_resolution_min:.0f}→{new_min:.0f} Å, "
            f"ctf_fitting_resolution_max {p.ctf_fitting_resolution_max:.0f}→{new_max:.0f} Å "
            f"to increase the number of Thon rings used for fitting."
        )

    def _fix_astigmatism(self, p: CryoEMParams) -> tuple[dict, str]:
        """astigmatism HALT — no direct parameter fix; log advisory for operator review."""
        return {}, (
            "Astigmatism exceeded threshold. No automated parameter adjustment is available. "
            "Advisory: inspect objective lens stigmators and CTF estimation results manually. "
            "Consider discarding heavily astigmatic micrographs before proceeding."
        )

    def _fix_junk_fraction(self, p: CryoEMParams) -> tuple[dict, str]:
        """junk_fraction HALT — scale particle_diameter_angstroms down by 10%."""
        if p.particle_diameter_angstroms is not None:
            new_diameter = round(p.particle_diameter_angstroms * 0.9, 1)
            changes: dict = {"particle_diameter_angstroms": new_diameter}
            return changes, (
                f"Junk fraction at or above halt threshold. Reduced "
                f"particle_diameter_angstroms {p.particle_diameter_angstroms:.1f}→{new_diameter:.1f} Å "
                f"(−10%) to improve template/blob picker selectivity."
            )
        else:
            return {}, (
                "Junk fraction at or above halt threshold, but particle_diameter_angstroms "
                "is not set (auto-mode). Flagged for manual review: consider providing an "
                "explicit particle diameter or adjusting blob picker bounds."
            )

    def _fix_particle_yield(self, p: CryoEMParams) -> tuple[dict, str]:
        """particle_yield HALT — reduce blob_picker_min_diameter by 20%."""
        if p.blob_picker_min_diameter is not None:
            new_min = round(p.blob_picker_min_diameter * 0.8, 1)
            changes: dict = {"blob_picker_min_diameter": new_min}
            return changes, (
                f"Particle yield below minimum. Reduced blob_picker_min_diameter "
                f"{p.blob_picker_min_diameter:.1f}→{new_min:.1f} Å (−20%) to capture "
                f"smaller/fainter particles and increase overall yield."
            )
        else:
            return {}, (
                "Particle yield below minimum, but blob_picker_min_diameter is not set. "
                "Consider setting explicit blob picker bounds to recover more particles."
            )

    def _fix_orientation_anisotropy(self, p: CryoEMParams) -> tuple[dict, str]:
        """orientation_anisotropy HALT — force C1 symmetry, increase num_2d_classes to 150."""
        changes: dict = {"symmetry": "C1", "num_2d_classes": 150}
        return changes, (
            f"Orientation anisotropy exceeded halt threshold (preferred views detected). "
            f"Forcing symmetry=C1 (was '{p.symmetry}') to avoid artificially inflating "
            f"apparent symmetry, and increasing num_2d_classes {p.num_2d_classes}→150 to "
            f"better sample under-represented orientations."
        )

    def _fix_abinitio_class_score(self, p: CryoEMParams) -> tuple[dict, str]:
        """abinitio_class_score HALT — increase num_ab_initio_classes by 2."""
        new_n = min(p.num_ab_initio_classes + 2, MAX_AB_INITIO_CLASSES)
        changes: dict = {"num_ab_initio_classes": new_n}
        return changes, (
            f"Best ab-initio class score below threshold. Increased "
            f"num_ab_initio_classes {p.num_ab_initio_classes}→{new_n} "
            f"(cap {MAX_AB_INITIO_CLASSES}) to give the reconstruction more "
            f"compositional diversity and improve class separation."
        )

    def _fix_abinitio_resolution(self, p: CryoEMParams) -> tuple[dict, str]:
        """abinitio_resolution HALT — relax max_resolution_refinement by 1.0 Å."""
        new_res = p.max_resolution_refinement + 1.0
        changes: dict = {"max_resolution_refinement": new_res}
        return changes, (
            f"Ab-initio resolution exceeded limit. Relaxed "
            f"max_resolution_refinement {p.max_resolution_refinement:.1f}→{new_res:.1f} Å "
            f"(+1.0 Å) to allow convergence at lower resolution before refinement."
        )

    def _fix_fsc_resolution(self, p: CryoEMParams) -> tuple[dict, str]:
        """fsc_resolution HALT — no tunable params in phase_E; advisory only."""
        # Phase E owns no parameters — FSC resolution failure reflects upstream
        # data quality.  Returning empty changes prevents silent no-op retries
        # and lets the escalation path provide a clear signal to the operator.
        return {}, (
            "FSC 0.143 resolution failed the quality gate. Phase E owns no tunable "
            "parameters — FSC quality is determined by upstream phases (motion "
            "correction, CTF estimation, picking, classification). "
            "Recommendation: review phase_D output quality; consider re-running "
            "the pipeline with a stricter QC profile or a denser particle set."
        )

    # ── Gate → handler dispatch table ───────────────────────────────────────

    _HANDLERS: dict = {
        "motion_drift":           _fix_motion_drift,
        "per_frame_drift":        _fix_per_frame_drift,
        "ctf_fit_quality":        _fix_ctf_fit_quality,
        "astigmatism":            _fix_astigmatism,
        "junk_fraction":          _fix_junk_fraction,
        "particle_yield":         _fix_particle_yield,
        "orientation_anisotropy": _fix_orientation_anisotropy,
        "abinitio_class_score":   _fix_abinitio_class_score,
        "abinitio_resolution":    _fix_abinitio_resolution,
        "fsc_resolution":         _fix_fsc_resolution,
    }
