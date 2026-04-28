"""
CryoEM QC evaluator — wraps the existing QC gate logic.

Rather than importing the Galaxy-embedded cryosparc_qc_gates directly
(which pulls in the full Galaxy stack), this module defines a thin
standalone version of the gate logic so the prototype can run without
the live backend.  When merged into BioMate, swap the gate calls to use
the real `cryosparc_qc_gates.py` module.
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


# ── Profile thresholds (from cryosparc_qc_gates.py) ──────────────────────────

QC_PROFILES: dict[str, dict[str, Any]] = {
    "cryoem_spa_purified": {
        "max_total_drift_A": 50.0,
        "max_per_frame_drift_A": 3.0,
        "min_ctf_fit_quality": 0.70,
        "max_astigmatism_A": 1000.0,
        "max_junk_fraction_halt": 0.70,
        "max_junk_fraction_advisory": 0.50,
        "max_anisotropy_halt": 10.0,
        "max_anisotropy_advisory": 5.0,
        "min_fsc_resolution_A": 20.0,
        "min_abinitio_class_score": 0.10,
        "max_abinitio_resolution_A": 25.0,
    },
    "cryoem_spa_membrane": {
        "max_total_drift_A": 80.0,
        "max_per_frame_drift_A": 5.0,
        "min_ctf_fit_quality": 0.65,
        "max_astigmatism_A": 1500.0,
        "max_junk_fraction_halt": 0.75,
        "max_junk_fraction_advisory": 0.55,
        "max_anisotropy_halt": 15.0,
        "max_anisotropy_advisory": 8.0,
        "min_fsc_resolution_A": 20.0,
        "min_abinitio_class_score": 0.10,
        "max_abinitio_resolution_A": 25.0,
    },
    "cryoem_spa_phase_plate": {
        "max_total_drift_A": 50.0,
        "max_per_frame_drift_A": 3.0,
        "min_ctf_fit_quality": 0.65,
        "max_astigmatism_A": 1000.0,
        "max_junk_fraction_halt": 0.70,
        "max_junk_fraction_advisory": 0.50,
        "max_anisotropy_halt": 10.0,
        "max_anisotropy_advisory": 5.0,
        "min_fsc_resolution_A": 20.0,
        "min_abinitio_class_score": 0.10,
        "max_abinitio_resolution_A": 25.0,
    },
}

ADVISORY_BAND = 1.30  # value / threshold > 1.30 → HALT; ≤ 1.30 → ADVISORY


def _level_for_ratio(ratio: float, higher_is_worse: bool = True) -> QCLevel:
    """Map a metric / threshold ratio to a QC level."""
    if not higher_is_worse:
        ratio = 1 / ratio if ratio != 0 else math.inf
    if ratio <= 0.7:
        return QCLevel.GOLD
    if ratio <= 1.0:
        return QCLevel.SILVER
    if ratio <= ADVISORY_BAND:
        return QCLevel.BRONZE
    return QCLevel.FAIL


class CryoEMQCEvaluator:
    """
    Evaluates QC metrics against profile thresholds.

    In production, `metrics` dicts come from CryoSPARC job outputs.
    In tests, pass synthetic metric dicts directly.
    """

    def __init__(self, profile: str = "cryoem_spa_purified"):
        if profile not in QC_PROFILES:
            raise ValueError(f"Unknown QC profile: {profile}. Options: {list(QC_PROFILES)}")
        self.profile = profile
        self.thresholds = QC_PROFILES[profile]

    # ── Per-phase evaluation entry points ────────────────────────────────────

    def evaluate_phase_A(self, metrics: dict) -> PhaseQCResult:
        """Evaluate motion correction and CTF estimation results."""
        results: list[GateResult] = []

        # Motion drift gate
        total_drift = metrics.get("mean_total_drift_A", 0.0)
        thresh = self.thresholds["max_total_drift_A"]
        ratio = total_drift / thresh if thresh else 0
        results.append(GateResult(
            gate="motion_drift",
            action=QCAction.HALT if ratio > 1.0 else (QCAction.ADVISORY if ratio > 1 / ADVISORY_BAND else QCAction.PASS),
            level=_level_for_ratio(ratio),
            value=total_drift,
            threshold=thresh,
            message=f"Mean total drift {total_drift:.1f} Å (limit {thresh:.0f} Å)",
            suggestion="Reduce micrograph_batch_size or enable dose_weighting" if ratio > 1.0 else "",
        ))

        # Per-frame drift gate
        per_frame = metrics.get("mean_per_frame_drift_A", 0.0)
        thresh_pf = self.thresholds["max_per_frame_drift_A"]
        ratio_pf = per_frame / thresh_pf if thresh_pf else 0
        results.append(GateResult(
            gate="per_frame_drift",
            action=QCAction.HALT if ratio_pf > 1.0 else (QCAction.ADVISORY if ratio_pf > 1 / ADVISORY_BAND else QCAction.PASS),
            level=_level_for_ratio(ratio_pf),
            value=per_frame,
            threshold=thresh_pf,
            message=f"Per-frame drift {per_frame:.2f} Å/frame (limit {thresh_pf:.1f} Å/frame)",
        ))

        # CTF fit quality gate (higher is better → invert ratio)
        ctf_quality = metrics.get("mean_ctf_fit_quality", 1.0)
        thresh_ctf = self.thresholds["min_ctf_fit_quality"]
        ctf_ratio = thresh_ctf / ctf_quality if ctf_quality else math.inf
        results.append(GateResult(
            gate="ctf_fit_quality",
            action=QCAction.HALT if ctf_quality < thresh_ctf else QCAction.PASS,
            level=_level_for_ratio(ctf_ratio),
            value=ctf_quality,
            threshold=thresh_ctf,
            message=f"CTF fit quality {ctf_quality:.3f} (min {thresh_ctf:.2f})",
            suggestion="Broaden ctf_fitting_resolution_min / tighten _max" if ctf_quality < thresh_ctf else "",
        ))

        # Astigmatism gate
        astig = metrics.get("mean_astigmatism_A", 0.0)
        thresh_a = self.thresholds["max_astigmatism_A"]
        ratio_a = astig / thresh_a if thresh_a else 0
        results.append(GateResult(
            gate="astigmatism",
            action=QCAction.HALT if ratio_a > 1.0 else (QCAction.ADVISORY if ratio_a > 1 / ADVISORY_BAND else QCAction.PASS),
            level=_level_for_ratio(ratio_a),
            value=astig,
            threshold=thresh_a,
            message=f"Astigmatism {astig:.0f} Å (limit {thresh_a:.0f} Å)",
        ))

        return PhaseQCResult(phase="phase_A", gate_results=results)

    def evaluate_phase_B(self, metrics: dict) -> PhaseQCResult:
        """Evaluate particle picking quality."""
        results: list[GateResult] = []

        junk_frac = metrics.get("junk_fraction", 0.0)
        thresh_halt = self.thresholds["max_junk_fraction_halt"]
        thresh_adv = self.thresholds["max_junk_fraction_advisory"]
        if junk_frac >= thresh_halt:
            action = QCAction.HALT
        elif junk_frac >= thresh_adv:
            action = QCAction.ADVISORY
        else:
            action = QCAction.PASS
        results.append(GateResult(
            gate="junk_fraction",
            action=action,
            level=_level_for_ratio(junk_frac / thresh_halt if thresh_halt else 0),
            value=junk_frac,
            threshold=thresh_halt,
            message=f"Junk fraction {junk_frac:.1%} (halt at {thresh_halt:.0%})",
            suggestion="Re-estimate particle_diameter_angstroms or adjust blob picker bounds" if action == QCAction.HALT else "",
        ))

        particle_count = metrics.get("num_particles_selected", 0)
        min_particles = metrics.get("min_particles_required", 5_000)
        count_ok = particle_count >= min_particles
        results.append(GateResult(
            gate="particle_yield",
            action=QCAction.PASS if count_ok else QCAction.HALT,
            level=QCLevel.GOLD if particle_count >= min_particles * 3 else (QCLevel.SILVER if count_ok else QCLevel.FAIL),
            value=float(particle_count),
            threshold=float(min_particles),
            message=f"{particle_count:,} particles selected (min {min_particles:,})",
            suggestion="Loosen blob_picker_min_diameter or re-survey micrograph subset" if not count_ok else "",
        ))

        return PhaseQCResult(phase="phase_B", gate_results=results)

    def evaluate_phase_C(self, metrics: dict) -> PhaseQCResult:
        """Evaluate 2D classification quality."""
        results: list[GateResult] = []

        anisotropy = metrics.get("orientation_anisotropy", 0.0)
        thresh_halt = self.thresholds["max_anisotropy_halt"]
        thresh_adv = self.thresholds["max_anisotropy_advisory"]
        if anisotropy >= thresh_halt:
            action = QCAction.HALT
        elif anisotropy >= thresh_adv:
            action = QCAction.ADVISORY
        else:
            action = QCAction.PASS
        results.append(GateResult(
            gate="orientation_anisotropy",
            action=action,
            level=_level_for_ratio(anisotropy / thresh_halt if thresh_halt else 0),
            value=anisotropy,
            threshold=thresh_halt,
            message=f"Orientation anisotropy {anisotropy:.1f} (halt at {thresh_halt:.0f})",
            suggestion="Force symmetry=C1 or increase num_2d_classes" if action == QCAction.HALT else "",
        ))

        class_quality = metrics.get("mean_class_quality", 1.0)
        min_quality = 0.4
        results.append(GateResult(
            gate="class_quality",
            action=QCAction.PASS if class_quality >= min_quality else QCAction.ADVISORY,
            level=QCLevel.GOLD if class_quality >= 0.7 else (QCLevel.SILVER if class_quality >= 0.4 else QCLevel.BRONZE),
            value=class_quality,
            threshold=min_quality,
            message=f"Mean 2D class quality {class_quality:.3f} (min {min_quality})",
        ))

        return PhaseQCResult(phase="phase_C", gate_results=results)

    def evaluate_phase_D(self, metrics: dict) -> PhaseQCResult:
        """Evaluate ab-initio and homogeneous refinement quality."""
        results: list[GateResult] = []

        # Ab-initio class score
        class_score = metrics.get("best_abinitio_class_score", 0.0)
        thresh = self.thresholds["min_abinitio_class_score"]
        results.append(GateResult(
            gate="abinitio_class_score",
            action=QCAction.PASS if class_score >= thresh else QCAction.HALT,
            level=QCLevel.GOLD if class_score >= 0.5 else (QCLevel.SILVER if class_score >= thresh else QCLevel.FAIL),
            value=class_score,
            threshold=thresh,
            message=f"Best ab-initio class score {class_score:.3f} (min {thresh})",
            suggestion="Increase num_ab_initio_classes or go back and improve 2D classes" if class_score < thresh else "",
        ))

        # Ab-initio resolution
        abinitio_res = metrics.get("best_abinitio_resolution_A", 999.0)
        thresh_res = self.thresholds["max_abinitio_resolution_A"]
        results.append(GateResult(
            gate="abinitio_resolution",
            action=QCAction.PASS if abinitio_res <= thresh_res else QCAction.HALT,
            level=QCLevel.GOLD if abinitio_res <= thresh_res * 0.5 else (QCLevel.SILVER if abinitio_res <= thresh_res else QCLevel.FAIL),
            value=abinitio_res,
            threshold=thresh_res,
            message=f"Ab-initio resolution {abinitio_res:.1f} Å (limit {thresh_res:.0f} Å)",
            suggestion="Relax max_resolution_refinement or increase num_ab_initio_classes" if abinitio_res > thresh_res else "",
        ))

        return PhaseQCResult(phase="phase_D", gate_results=results)

    def evaluate_phase_E(self, metrics: dict) -> PhaseQCResult:
        """Evaluate final map quality via FSC resolution."""
        results: list[GateResult] = []

        fsc_res = metrics.get("fsc_resolution_A", 999.0)
        thresh = self.thresholds["min_fsc_resolution_A"]
        # For resolution: lower Å = better; gate passes if fsc_res <= thresh
        results.append(GateResult(
            gate="fsc_resolution",
            action=QCAction.PASS if fsc_res <= thresh else QCAction.HALT,
            level=QCLevel.GOLD if fsc_res <= 4.0 else (QCLevel.SILVER if fsc_res <= 8.0 else (QCLevel.BRONZE if fsc_res <= thresh else QCLevel.FAIL)),
            value=fsc_res,
            threshold=thresh,
            message=f"FSC 0.143 resolution {fsc_res:.1f} Å (limit {thresh:.0f} Å)",
        ))

        return PhaseQCResult(phase="phase_E", gate_results=results)

    def evaluate_phase(self, phase: str, metrics: dict) -> PhaseQCResult:
        """Dispatch to the correct per-phase evaluator."""
        dispatch = {
            "phase_A": self.evaluate_phase_A,
            "phase_B": self.evaluate_phase_B,
            "phase_C": self.evaluate_phase_C,
            "phase_D": self.evaluate_phase_D,
            "phase_E": self.evaluate_phase_E,
        }
        fn = dispatch.get(phase)
        if fn is None:
            raise ValueError(f"Unknown phase: {phase}")
        return fn(metrics)
