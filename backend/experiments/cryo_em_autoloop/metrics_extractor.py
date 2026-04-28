"""
MetricsExtractor — bridges real (or simulated) CryoSPARC job outputs
into the scalar metrics dicts that CryoEMQCEvaluator expects.

Usage with simulated jobs::

    from simulation import ScenarioRunner, ScenarioConfig
    from metrics_extractor import MetricsExtractor

    runner = ScenarioRunner(ScenarioConfig())
    extractor = MetricsExtractor()

    jobs = runner("phase_A", params)
    metrics = extractor.extract_phase_A(jobs)
    # → {"mean_total_drift_A": ..., "mean_ctf_fit_quality": ..., ...}

Usage with real cryosparc-tools jobs::

    from cryosparc.tools import CryoSPARC
    cs = CryoSPARC(host=..., base_port=...)
    jobs = [cs.find_job("P1", uid) for uid in job_uids]
    metrics = MetricsExtractor().extract_phase_A(jobs)

Real column names from cryosparc_executor.py:587–640:
  Motion / CTF job output "micrographs":
    total_motion           — total drift in pixels (multiply by pixel_size → Å)
    average_motion         — per-frame drift in pixels
    ctf/ctf_fit_to_A       — CTF fit resolution (Å) — lower is better
    ctf/cross_corr_ctffind — FOM score 0–1 — higher is better
    ctf/df1_A, ctf/df2_A   — defocus (Å); |df1−df2| = astigmatism

  Particle picking / 2-D classification output "class_averages":
    class_num_particles    — int per class

  2-D classification output "particles":
    alignments3D/pose      — rotation vectors (N×3)

  Ab-initio output "class_scores":
    class_score            — float per class

  FSC validation output "fsc":
    freq_A_inv  — spatial frequency (1/Å)
    fsc_nomask  — FSC values 0–1
"""

from __future__ import annotations

import math
from typing import Any, Protocol, runtime_checkable

import numpy as np


# ── Minimal interface expected of a Job object ────────────────────────────────

@runtime_checkable
class JobLike(Protocol):
    """
    Duck-type protocol for a CryoSPARC job object.
    Both SimulatedCryoSPARCJob and a real cryosparc.tools.Job satisfy this.
    """
    uid: str
    job_type: str

    def load_output(self, name: str) -> Any:  # returns Dataset-like
        ...


# ── MetricsExtractor ──────────────────────────────────────────────────────────

class MetricsExtractor:
    """
    Extracts aggregated scalar metrics from a list of job objects.

    One instance can be reused across phases; it is stateless.
    """

    def __init__(self, pixel_size: float = 1.05) -> None:
        """
        Parameters
        ----------
        pixel_size:
            Å/pixel for the dataset (used to convert pixel-unit motion to Å).
        """
        self.pixel_size = pixel_size

    # ── Phase dispatchers ─────────────────────────────────────────────────────

    def extract(self, phase: str, jobs: list) -> dict[str, Any]:
        """Dispatch to the appropriate per-phase extractor."""
        dispatch = {
            "phase_A": self.extract_phase_A,
            "phase_B": self.extract_phase_B,
            "phase_C": self.extract_phase_C,
            "phase_D": self.extract_phase_D,
            "phase_E": self.extract_phase_E,
        }
        fn = dispatch.get(phase)
        if fn is None:
            raise ValueError(f"Unknown phase: {phase!r}")
        return fn(jobs)

    # ── Phase A — motion correction + CTF estimation ──────────────────────────

    def extract_phase_A(self, jobs: list) -> dict[str, float]:
        """
        Aggregate motion and CTF columns across all micrographs in all jobs.

        Expected job output: ``load_output("micrographs")``
        Columns used:
          total_motion           (pixels)
          average_motion         (pixels/frame)
          ctf/cross_corr_ctffind (FOM, 0–1)
          ctf/ctf_fit_to_A       (Å resolution fit)
          ctf/df1_A, ctf/df2_A   (defocus, Å)
        """
        total_motion_px: list[np.ndarray] = []
        avg_motion_px: list[np.ndarray] = []
        ctf_fom: list[np.ndarray] = []
        ctf_fit: list[np.ndarray] = []
        astig: list[np.ndarray] = []

        for job in jobs:
            ds = _load_output(job, "micrographs")
            if ds is None:
                continue

            if "total_motion" in ds:
                total_motion_px.append(np.asarray(ds["total_motion"]))
            if "average_motion" in ds:
                avg_motion_px.append(np.asarray(ds["average_motion"]))
            if "ctf/cross_corr_ctffind" in ds:
                ctf_fom.append(np.asarray(ds["ctf/cross_corr_ctffind"]))
            if "ctf/ctf_fit_to_A" in ds:
                ctf_fit.append(np.asarray(ds["ctf/ctf_fit_to_A"]))
            if "ctf/df1_A" in ds and "ctf/df2_A" in ds:
                astig.append(np.abs(
                    np.asarray(ds["ctf/df1_A"]) - np.asarray(ds["ctf/df2_A"])
                ))

        def _median_or_nan(arrays: list[np.ndarray]) -> float:
            if not arrays:
                return float("nan")
            return float(np.median(np.concatenate(arrays)))

        px = self.pixel_size
        return {
            "mean_total_drift_A":    _median_or_nan(total_motion_px) * px,
            "mean_per_frame_drift_A": _median_or_nan(avg_motion_px) * px,
            "mean_ctf_fit_quality":  _median_or_nan(ctf_fom),
            "mean_ctf_fit_to_A":     _median_or_nan(ctf_fit),
            "mean_astigmatism_A":    _median_or_nan(astig),
        }

    # ── Phase B — particle picking ────────────────────────────────────────────

    def extract_phase_B(
        self,
        jobs: list,
        junk_threshold: int = 100,
        min_particles_required: int = 5_000,
    ) -> dict[str, Any]:
        """
        Aggregate 2-D class outputs to compute junk fraction and particle count.

        Expected job output: ``load_output("class_averages")``
        Column used: ``class_num_particles`` (int per class)
        """
        counts_all: list[np.ndarray] = []

        for job in jobs:
            ds = _load_output(job, "class_averages")
            if ds is None:
                continue
            if "class_num_particles" in ds:
                counts_all.append(np.asarray(ds["class_num_particles"]))

        if not counts_all:
            return {
                "junk_fraction": float("nan"),
                "num_particles_selected": 0,
                "min_particles_required": min_particles_required,
            }

        counts = np.concatenate(counts_all)
        n_junk = int(np.sum(counts < junk_threshold))
        n_total_classes = len(counts)
        junk_fraction = n_junk / n_total_classes if n_total_classes > 0 else 0.0

        # Particles selected = sum of counts in non-junk classes
        num_particles_selected = int(np.sum(counts[counts >= junk_threshold]))

        return {
            "junk_fraction": junk_fraction,
            "num_particles_selected": num_particles_selected,
            "min_particles_required": min_particles_required,
        }

    # ── Phase C — 2-D classification / orientation anisotropy ────────────────

    def extract_phase_C(self, jobs: list) -> dict[str, float]:
        """
        Compute orientation anisotropy from particle rotation vectors.

        Expected job output: ``load_output("particles")``
        Column used: ``alignments3D/pose`` — N×3 rotation vectors
          (Rodrigues / axis-angle representation, first column = phi,
           second = theta, third = psi — as stored by CryoSPARC)

        Anisotropy = max_count_bin / mean_count_bin across 36 longitude bins.
        A perfectly isotropic distribution gives ≈ 1.0.
        """
        pose_all: list[np.ndarray] = []

        for job in jobs:
            ds = _load_output(job, "particles")
            if ds is None:
                continue
            if "alignments3D/pose" in ds:
                pose_all.append(np.asarray(ds["alignments3D/pose"]))

        if not pose_all:
            return {"orientation_anisotropy": float("nan"), "mean_class_quality": 0.0}

        pose = np.vstack(pose_all)  # (N, 3)

        # Extract polar angle (theta) — second column.
        # CryoSPARC stores pose as (phi, theta, psi); theta is the inclination
        # angle from the z-axis (north pole).  Preferred-orientation bias shows
        # up as a non-uniform theta distribution (too many side views at ~π/2).
        theta = pose[:, 1]

        # Bin into 18 polar bins (10° each, 0..π)
        bins = np.linspace(0, math.pi, 19)
        counts, _ = np.histogram(theta, bins=bins)
        # Weight by expected counts for uniform sphere (proportional to sin θ)
        bin_centers = 0.5 * (bins[:-1] + bins[1:])
        expected_weights = np.sin(bin_centers)
        expected_weights = expected_weights / expected_weights.sum() * len(theta)
        # Avoid division by zero in low-count bins
        norm_counts = counts / np.where(expected_weights > 0.5, expected_weights, 1.0)
        mean_count = norm_counts.mean()
        anisotropy = float(norm_counts.max() / mean_count) if mean_count > 0 else float("nan")

        return {
            "orientation_anisotropy": anisotropy,
            "mean_class_quality": 1.0 / anisotropy if anisotropy > 0 else 0.0,
        }

    # ── Phase D — ab-initio reconstruction ───────────────────────────────────

    def extract_phase_D(self, jobs: list) -> dict[str, float]:
        """
        Extract best class score and estimated resolution from ab-initio jobs.

        Expected job output: ``load_output("class_scores")``
        Column used: ``class_score`` — float per class

        Resolution is not directly stored in ab-initio class_scores; we proxy
        it from the best class score (higher score → better resolution proxy).
        Use 25.0 Å as the proxy floor for poor scores.
        """
        scores_all: list[np.ndarray] = []

        for job in jobs:
            ds = _load_output(job, "class_scores")
            if ds is None:
                continue
            if "class_score" in ds:
                scores_all.append(np.asarray(ds["class_score"]))

        if not scores_all:
            return {
                "best_abinitio_class_score": float("nan"),
                "best_abinitio_resolution_A": float("nan"),
            }

        scores = np.concatenate(scores_all)
        best_score = float(scores.max())

        # Proxy resolution: good score (>0.3) → ~10–20 Å, bad (<0.1) → >25 Å
        # Linear interpolation: score 0 → 30 Å, score 0.5 → 5 Å
        proxy_resolution = max(5.0, 30.0 - best_score * 50.0)

        return {
            "best_abinitio_class_score": best_score,
            "best_abinitio_resolution_A": proxy_resolution,
        }

    # ── Phase E — FSC validation ──────────────────────────────────────────────

    def extract_phase_E(self, jobs: list) -> dict[str, float]:
        """
        Determine the gold-standard resolution (FSC @ 0.143 criterion).

        Expected job output: ``load_output("fsc")``
        Columns used:
          freq_A_inv — spatial frequencies (1/Å)
          fsc_nomask — FSC values 0–1
        """
        fsc_resolution_A = float("nan")

        for job in jobs:
            ds = _load_output(job, "fsc")
            if ds is None:
                continue
            if "freq_A_inv" not in ds or "fsc_nomask" not in ds:
                continue

            freq = np.asarray(ds["freq_A_inv"])
            fsc = np.asarray(ds["fsc_nomask"])

            # Find where FSC drops below 0.143
            below = np.where(fsc < 0.143)[0]
            if len(below) == 0:
                # Never drops below threshold — resolution better than Nyquist
                fsc_resolution_A = 1.0 / freq[-1] if freq[-1] > 0 else float("nan")
            else:
                crossing_idx = below[0]
                if crossing_idx == 0:
                    fsc_resolution_A = float("inf")  # immediately below threshold
                else:
                    # Linear interpolation for sub-bin precision
                    f1, f2 = freq[crossing_idx - 1], freq[crossing_idx]
                    v1, v2 = fsc[crossing_idx - 1], fsc[crossing_idx]
                    if abs(v2 - v1) > 1e-9:
                        frac = (0.143 - v1) / (v2 - v1)
                        f_cross = f1 + frac * (f2 - f1)
                        fsc_resolution_A = float(1.0 / f_cross) if f_cross > 0 else float("inf")
                    else:
                        fsc_resolution_A = float(1.0 / f1) if f1 > 0 else float("nan")
            # Take the first (best-resolution) job's result
            break

        return {"fsc_resolution_A": fsc_resolution_A}


# ── Helper ────────────────────────────────────────────────────────────────────

def _load_output(job: Any, output_name: str) -> Any | None:
    """
    Try to load an output from a job object, returning None on failure.
    Handles both completed and failed jobs gracefully.
    """
    try:
        return job.load_output(output_name)
    except (KeyError, RuntimeError, AttributeError):
        return None
