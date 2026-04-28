"""
Realistic CryoSPARC job simulation for auto-loop testing.

Produces data in the EXACT SAME FORMAT as real cryosparc-tools job outputs:
  job.load_output("micrographs") → Dataset
  dataset["total_motion"] → numpy array (N per-micrograph values)
  dataset["ctf/cross_corr_ctffind"] → numpy array

This lets the MetricsExtractor and QCEvaluator be tested without a live
CryoSPARC instance. Swap SimulatedCryoSPARCJob for a real cryosparc.tools
Job object to run against a real cluster.

Reference — real column names (from cryosparc_executor.py:587–640):
  Motion job output "micrographs":
    total_motion       — total drift in pixels (multiply by pixel_size to get Å)
    average_motion     — per-frame drift in pixels

  CTF job output "micrographs":
    ctf/ctf_fit_to_A       — CTF fit resolution (Å), lower = better
    ctf/cross_corr_ctffind — FOM score 0–1, higher = better
    ctf/df1_A, ctf/df2_A   — defocus values (Å); |df1-df2| = astigmatism

  Particle picking "class_averages":
    class_num_particles    — int per class; classes < 100 particles = junk

  2D classification "particles":
    alignments3D/pose      — rotation vectors (N×3) → Euler angles

  Ab-initio "class_scores" (optional):
    class_score            — float per class (quality score)

  Ab-initio "particles":
    alignments3D/class_posterior — (N×K) softmax weights

  FSC validation "fsc":
    freq_A_inv — spatial frequency (1/Å)
    fsc_nomask — FSC curve values 0–1
"""

from __future__ import annotations

import math
import random
from dataclasses import dataclass, field
from typing import Any

import numpy as np


# ── Simulated Dataset ─────────────────────────────────────────────────────────

class SimulatedDataset:
    """Mimics the cryosparc-tools Dataset API."""

    def __init__(self, data: dict[str, np.ndarray]):
        self._data = data

    def fields(self) -> list[str]:
        return list(self._data.keys())

    def __getitem__(self, col: str) -> np.ndarray:
        if col not in self._data:
            raise KeyError(f"Column {col!r} not in dataset. Available: {list(self._data)}")
        return self._data[col]

    def __contains__(self, col: str) -> bool:
        return col in self._data

    def __len__(self) -> int:
        first = next(iter(self._data.values()), np.array([]))
        return len(first)


# ── Simulated Job ─────────────────────────────────────────────────────────────

@dataclass
class SimulatedCryoSPARCJob:
    """
    Mimics a cryosparc.tools Job object.

    Each instance is preconfigured with output Datasets matching one
    phase of the SPA pipeline. Pass a list of these to MetricsExtractor.
    """
    uid: str
    job_type: str
    status: str = "completed"
    _outputs: dict[str, SimulatedDataset] = field(default_factory=dict)

    def load_output(self, name: str) -> SimulatedDataset:
        if self.status != "completed":
            raise RuntimeError(f"Job {self.uid} is {self.status}, cannot load output")
        if name not in self._outputs:
            raise KeyError(f"Output {name!r} not available on job {self.uid} ({self.job_type})")
        return self._outputs[name]

    def refresh(self) -> None:
        pass  # no-op in simulation


# ── Factory functions — realistic synthetic data ──────────────────────────────

def make_motion_ctf_jobs(
    n_batches: int = 5,
    n_micrographs_per_batch: int = 200,
    pixel_size: float = 1.05,
    # Quality controls — tune these to simulate good/bad runs
    drift_mean_A: float = 20.0,   # good: 15–30 Å; bad: >50 Å
    drift_std_A: float = 8.0,
    ctf_fom_mean: float = 0.85,   # good: >0.70; bad: <0.65
    ctf_fom_std: float = 0.06,
    astig_mean_A: float = 400.0,  # good: <1000 Å; bad: >1500 Å
    astig_std_A: float = 150.0,
    rng_seed: int = 42,
) -> list[SimulatedCryoSPARCJob]:
    """
    Simulate N batches of motion+CTF estimation results.

    The CTF job output carries both motion AND CTF columns because in
    cryosparc_executor.py, CTF jobs use merged micrographs (motion already
    concatenated into the CTF output dataset).
    """
    rng = np.random.default_rng(rng_seed)
    jobs = []

    for i in range(n_batches):
        n = n_micrographs_per_batch
        drift_px = rng.normal(drift_mean_A / pixel_size, drift_std_A / pixel_size, n).clip(1.0)
        per_frame_px = drift_px / 40.0  # assume 40 frames
        ctf_fom = rng.normal(ctf_fom_mean, ctf_fom_std, n).clip(0.0, 1.0)
        df1 = rng.normal(15000.0, 3000.0, n).clip(5000.0, 30000.0)  # ~1.5 µm defocus
        df2 = df1 + rng.normal(astig_mean_A, astig_std_A, n)
        ctf_fit_to_A = rng.normal(4.5, 0.8, n).clip(2.0, 15.0)

        ds = SimulatedDataset({
            "total_motion": drift_px,
            "average_motion": per_frame_px,
            "ctf/cross_corr_ctffind": ctf_fom,
            "ctf/ctf_fit_to_A": ctf_fit_to_A,
            "ctf/df1_A": df1,
            "ctf/df2_A": df2,
        })
        jobs.append(SimulatedCryoSPARCJob(
            uid=f"J{100 + i:03d}",
            job_type="patch_ctf_estimation_multi",
            _outputs={"micrographs": ds},
        ))

    return jobs


def make_picking_jobs(
    n_classes: int = 200,
    n_classes_junk: int = 30,       # classes with < 100 particles
    particles_per_good_class: int = 1500,
    rng_seed: int = 42,
) -> list[SimulatedCryoSPARCJob]:
    """Simulate 2D classification output for junk-class QC gate."""
    rng = np.random.default_rng(rng_seed)
    counts = np.concatenate([
        rng.integers(1, 99, n_classes_junk),                              # junk
        rng.integers(200, particles_per_good_class * 2, n_classes - n_classes_junk),  # good
    ])
    rng.shuffle(counts)
    ds = SimulatedDataset({"class_num_particles": counts})
    return [SimulatedCryoSPARCJob(
        uid="J200",
        job_type="class_2D",
        _outputs={"class_averages": ds},
    )]


def make_2d_class_jobs(
    n_particles: int = 50_000,
    anisotropy: float = 3.5,   # good: <5; bad: >10
    rng_seed: int = 42,
) -> list[SimulatedCryoSPARCJob]:
    """
    Simulate 2D classification particle orientations for anisotropy gate.

    Generates Euler angles (uniform sphere + preferred-orientation bias).
    """
    rng = np.random.default_rng(rng_seed)
    # Generate viewing directions: random sphere with anisotropy bias
    # Uniform sphere: phi uniform [0,2π], cos(theta) uniform [-1,1]
    phi = rng.uniform(0, 2 * math.pi, n_particles)
    cos_theta = rng.uniform(-1, 1, n_particles)
    # Add preferred orientation bias (simulate high-anisotropy if anisotropy > 5)
    if anisotropy > 5.0:
        # Push most particles toward the "side view" (theta ≈ π/2)
        bias = rng.normal(0, 0.3, n_particles)
        cos_theta = np.clip(cos_theta * (1.0 / anisotropy) + bias, -1, 1)

    theta = np.arccos(cos_theta)
    pose_rotations = np.column_stack([phi, theta, rng.uniform(0, 2 * math.pi, n_particles)])

    ds = SimulatedDataset({"alignments3D/pose": pose_rotations})
    return [SimulatedCryoSPARCJob(
        uid="J300",
        job_type="class_2D",
        _outputs={"particles": ds},
    )]


def make_abinitio_jobs(
    n_classes: int = 3,
    best_class_score: float = 0.35,  # good: >0.10; bad: <0.10
    best_resolution_A: float = 16.0, # good: <25 Å; bad: >25 Å
    rng_seed: int = 42,
) -> list[SimulatedCryoSPARCJob]:
    """Simulate ab-initio reconstruction quality scores."""
    rng = np.random.default_rng(rng_seed)
    scores = np.array([best_class_score] + [
        max(0.01, best_class_score * rng.uniform(0.3, 0.9)) for _ in range(n_classes - 1)
    ])
    ds = SimulatedDataset({"class_score": scores})
    return [SimulatedCryoSPARCJob(
        uid="J400",
        job_type="homo_abinit",
        _outputs={"class_scores": ds},
    )]


def make_fsc_jobs(
    fsc_resolution_A: float = 5.5,  # good: <20; bad: >20
    rng_seed: int = 42,
) -> list[SimulatedCryoSPARCJob]:
    """Simulate FSC curve data for resolution gate."""
    rng = np.random.default_rng(rng_seed)
    # Build a synthetic FSC curve
    # Resolution cutoff at 0.143 corresponds to frequency 1/fsc_resolution_A
    n_points = 100
    freq_max = 0.5 / 1.05  # Nyquist for 1.05 Å/px
    freq_A_inv = np.linspace(0, freq_max, n_points)
    # Sigmoid-like FSC decay, crossing 0.143 at the target resolution
    k = 1.0 / fsc_resolution_A
    fsc_values = 1.0 / (1.0 + np.exp(80 * (freq_A_inv - k))) + rng.normal(0, 0.01, n_points)
    fsc_values = np.clip(fsc_values, 0.0, 1.0)

    ds = SimulatedDataset({
        "freq_A_inv": freq_A_inv,
        "fsc_nomask": fsc_values,
    })
    return [SimulatedCryoSPARCJob(
        uid="J500",
        job_type="validation_fsc",
        _outputs={"fsc": ds},
    )]


# ── Scenario builder ─────────────────────────────────────────────────────────

@dataclass
class ScenarioConfig:
    """
    Defines a full-run scenario for auto-loop testing.

    Each attempt list (e.g. motion_drift_attempts) contains per-attempt
    parameter values. Attempt 0 = initial run, attempt 1 = first retry, etc.
    The last entry repeats if attempts exceed list length.
    """
    # Phase A
    drift_per_attempt: list[float] = field(default_factory=lambda: [20.0])
    ctf_fom_per_attempt: list[float] = field(default_factory=lambda: [0.85])
    astig_per_attempt: list[float] = field(default_factory=lambda: [400.0])
    # Phase B
    junk_fraction: float = 0.25
    n_particles: int = 80_000
    # Phase C
    anisotropy: float = 3.0
    # Phase D
    best_class_score: float = 0.35
    best_resolution_A: float = 16.0
    # Phase E
    fsc_resolution_A: float = 5.5
    # Metadata
    pixel_size: float = 1.05
    n_batches: int = 3
    n_micrographs_per_batch: int = 100


class ScenarioRunner:
    """
    Wraps a ScenarioConfig into a callable that returns realistic simulated
    job lists per phase, with per-attempt parameter progression.

    Compatible with CryoEMAutoLoop's `phase_runner_fn` interface when
    the orchestrator is updated to use MetricsExtractor.

    Usage:
        runner = ScenarioRunner(config)
        jobs = runner("phase_A", params)  # returns list[SimulatedCryoSPARCJob]
    """

    def __init__(self, config: ScenarioConfig, rng_seed: int = 42):
        self.config = config
        self._attempt_counts: dict[str, int] = {}
        self._rng_seed = rng_seed

    def _attempt(self, phase: str) -> int:
        count = self._attempt_counts.get(phase, 0)
        self._attempt_counts[phase] = count + 1
        return count

    def _pick(self, lst: list, attempt: int) -> Any:
        """Pick value for current attempt (last entry repeats)."""
        idx = min(attempt, len(lst) - 1)
        return lst[idx]

    def __call__(self, phase: str, params: Any) -> list[SimulatedCryoSPARCJob]:
        attempt = self._attempt(phase)
        c = self.config
        seed = self._rng_seed + attempt * 100

        if phase == "phase_A":
            drift = self._pick(c.drift_per_attempt, attempt)
            fom = self._pick(c.ctf_fom_per_attempt, attempt)
            astig = self._pick(c.astig_per_attempt, attempt)
            return make_motion_ctf_jobs(
                n_batches=c.n_batches,
                n_micrographs_per_batch=c.n_micrographs_per_batch,
                pixel_size=c.pixel_size,
                drift_mean_A=drift,
                ctf_fom_mean=fom,
                astig_mean_A=astig,
                rng_seed=seed,
            )
        elif phase == "phase_B":
            n_junk = int(c.junk_fraction * 200)
            return make_picking_jobs(n_classes=200, n_classes_junk=n_junk, rng_seed=seed)
        elif phase == "phase_C":
            return make_2d_class_jobs(anisotropy=c.anisotropy, rng_seed=seed)
        elif phase == "phase_D":
            return make_abinitio_jobs(
                best_class_score=c.best_class_score,
                best_resolution_A=c.best_resolution_A,
                rng_seed=seed,
            )
        elif phase == "phase_E":
            return make_fsc_jobs(fsc_resolution_A=c.fsc_resolution_A, rng_seed=seed)
        else:
            raise ValueError(f"Unknown phase: {phase}")
