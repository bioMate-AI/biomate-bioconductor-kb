"""
CryoEM parameter schema and phase ownership map.

Parameters are partitioned by phase so the tuner knows which subset
to adjust when a given phase fails QC.
"""

from dataclasses import dataclass, field, asdict
from typing import Optional


@dataclass
class CryoEMParams:
    """All tunable parameters for a CryoSPARC SPA run."""

    # ── Global / acquisition ──────────────────────────────────────────────────
    pixel_size: float = 1.05          # Å/px
    voltage: int = 300                # kV
    spherical_aberration: float = 2.7 # mm
    total_dose: float = 50.0          # e-/Å²
    amp_contrast: float = 0.1
    phase_plate: bool = False

    # ── Phase A: motion correction & CTF ─────────────────────────────────────
    motion_correction_dose_weighting: bool = True
    micrograph_batch_size: int = 200
    dose_per_frame: Optional[float] = None   # None = auto-calculated
    ctf_fitting_resolution_min: float = 30.0 # Å  (low-res end of fit window)
    ctf_fitting_resolution_max: float = 5.0  # Å  (high-res end of fit window)

    # ── Phase B: particle picking & extraction ────────────────────────────────
    particle_diameter_angstroms: Optional[float] = None  # None = from MW
    particle_box_size: Optional[int] = None              # None = auto
    blob_picker_min_diameter: Optional[float] = None     # Å
    blob_picker_max_diameter: Optional[float] = None     # Å

    # ── Phase C: 2D classification ────────────────────────────────────────────
    num_2d_classes: int = 100
    class2d_similarity_threshold: float = 0.3
    class2d_iterations: int = 100
    particle_batch_size: int = 10_000

    # ── Phase D: 3D reconstruction ────────────────────────────────────────────
    num_ab_initio_classes: int = 3
    max_resolution_refinement: float = 2.5  # Å
    symmetry: str = "C1"

    # ── Parallelism ───────────────────────────────────────────────────────────
    num_gpu_workers: int = 1
    max_parallel_jobs: int = 20
    num_gpu: int = 4
    gpu_memory_gb: int = 16

    def to_dict(self) -> dict:
        return asdict(self)

    def copy(self) -> "CryoEMParams":
        return CryoEMParams(**asdict(self))


# Which parameters belong to (and can be adjusted by) each phase.
# Used by ParamTuner to scope adjustments.
PHASE_PARAM_OWNERS: dict[str, list[str]] = {
    "phase_A": [
        "motion_correction_dose_weighting",
        "micrograph_batch_size",
        "dose_per_frame",
        "ctf_fitting_resolution_min",
        "ctf_fitting_resolution_max",
    ],
    "phase_B": [
        "particle_diameter_angstroms",
        "particle_box_size",
        "blob_picker_min_diameter",
        "blob_picker_max_diameter",
    ],
    "phase_C": [
        "num_2d_classes",
        "class2d_similarity_threshold",
        "class2d_iterations",
        "particle_batch_size",
    ],
    "phase_D": [
        "num_ab_initio_classes",
        "max_resolution_refinement",
        "symmetry",
    ],
    "phase_E": [],  # Post-processing — no tunable params; driven by upstream
}
