"""
cryosparc_qc_gates.py
=====================
QC gate functions for the CryoSPARC SPA pipeline.

Each gate function returns a QCResult dataclass.

Profile names:
    "cryoem_spa_purified"   — soluble/purified proteins
    "cryoem_spa_membrane"   — membrane proteins / detergent
    "cryoem_spa_phase_plate" — Volta phase-plate datasets

Evidence citations:
  Motion  : Bharat & Scheres 2016; Zheng et al. 2017 Nature Methods
  CTF     : Rohou & Grigorieff 2015 J. Struct. Biol. (CTFFIND4)
  Junk    : Scheres 2012 J. Mol. Biol. (RELION); standard SPA practice
  Orient. : Tan et al. 2017 Nature Methods 14(8):793-796 (3DFSC)
  FSC 0.143: Henderson et al. 2012 Structure; Scheres & Chen 2012 Nature Methods
"""
from __future__ import annotations

import json
import os
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from typing import List, Optional

import numpy as np

# ---------------------------------------------------------------------------
# QCResult dataclass
# ---------------------------------------------------------------------------

@dataclass
class QCResult:
    """Result returned by every QC gate function."""
    gate: str           # machine-readable gate name, e.g. "motion_drift"
    level: str          # "GOLD" | "SILVER" | "BRONZE"
    action: str         # "pass" | "advisory" | "halt"
    metric: str         # human-readable metric name
    value: float        # observed value
    threshold: float    # relevant threshold
    message: str        # short human-readable verdict
    suggestion: str     # actionable recommendation (empty when not needed)
    evidence: str       # citation string
    profile: str        # QC profile used


# ---------------------------------------------------------------------------
# Profiles
# ---------------------------------------------------------------------------

PROFILES = {
    "cryoem_spa_purified": {
        "max_total_drift_A": 50.0,
        "max_per_frame_drift_A": 3.0,
        "min_ctf_fit_quality": 0.70,
        "max_astigmatism_A": 1000.0,
        "max_junk_fraction_halt": 0.70,
        "max_junk_fraction_advisory": 0.50,
        "max_orientation_anisotropy_halt": 10.0,
        "max_orientation_anisotropy_advisory": 5.0,
        "min_fsc_resolution_A": 20.0,
        # G9 — Ab initio quality (BRONZE — community heuristic)
        "min_abinitio_class_score": 0.10,
        "max_abinitio_resolution_A": 25.0,
        # G12 — MolProbity / model validation (GOLD — PDB deposition standard)
        "max_molprobity_score": 3.0,
        "min_ramachandran_favored": 0.90,
        "advisory_molprobity_score": 2.0,
        "advisory_ramachandran_favored": 0.97,
        "max_rotamer_outlier_pct": 0.05,
    },
    "cryoem_spa_membrane": {
        "max_total_drift_A": 80.0,
        "max_per_frame_drift_A": 5.0,
        "min_ctf_fit_quality": 0.65,
        "max_astigmatism_A": 1500.0,
        "max_junk_fraction_halt": 0.75,
        "max_junk_fraction_advisory": 0.55,
        "max_orientation_anisotropy_halt": 15.0,
        "max_orientation_anisotropy_advisory": 8.0,
        "min_fsc_resolution_A": 20.0,
        # G9 — Ab initio quality (BRONZE — community heuristic)
        "min_abinitio_class_score": 0.10,
        "max_abinitio_resolution_A": 25.0,
        # G12 — MolProbity / model validation (GOLD — PDB deposition standard)
        "max_molprobity_score": 3.0,
        "min_ramachandran_favored": 0.90,
        "advisory_molprobity_score": 2.0,
        "advisory_ramachandran_favored": 0.97,
        "max_rotamer_outlier_pct": 0.05,
    },
    "cryoem_spa_phase_plate": {
        "max_total_drift_A": 50.0,
        "max_per_frame_drift_A": 3.0,
        "min_ctf_fit_quality": 0.65,       # relaxed for Volta phase plate
        "max_astigmatism_A": 1000.0,
        "max_junk_fraction_halt": 0.70,
        "max_junk_fraction_advisory": 0.50,
        "max_orientation_anisotropy_halt": 10.0,
        "max_orientation_anisotropy_advisory": 5.0,
        "min_fsc_resolution_A": 20.0,
        # G9 — Ab initio quality (BRONZE — community heuristic)
        "min_abinitio_class_score": 0.10,
        "max_abinitio_resolution_A": 25.0,
        # G12 — MolProbity / model validation (GOLD — PDB deposition standard)
        "max_molprobity_score": 3.0,
        "min_ramachandran_favored": 0.90,
        "advisory_molprobity_score": 2.0,
        "advisory_ramachandran_favored": 0.97,
        "max_rotamer_outlier_pct": 0.05,
    },
}

_DEFAULT_PROFILE = "cryoem_spa_purified"

# Factor above threshold that triggers halt (advisory band: 1.0x – 1.30x)
_ADVISORY_FACTOR = 1.30


def _get_profile(name: str) -> dict:
    if name not in PROFILES:
        raise ValueError(
            f"Unknown QC profile '{name}'. Available: {list(PROFILES.keys())}"
        )
    return PROFILES[name]


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------


def _fsc_to_resolution_A(
    freq_inv_A,
    fsc_values,
    threshold: float = 0.143,
) -> Optional[float]:
    """Return resolution in Angstroms where FSC first crosses *threshold*.

    Parameters
    ----------
    freq_inv_A : array-like, shape (N,)
        Spatial frequencies in 1/Ang.
    fsc_values : array-like, shape (N,)
        Corresponding FSC values in [0, 1].

    Returns
    -------
    float or None

    References
    ----------
    Henderson et al. 2012 Structure; Scheres & Chen 2012 Nature Methods.
    """
    freq = np.asarray(freq_inv_A, dtype=float)
    fsc = np.asarray(fsc_values, dtype=float)

    below = np.where(fsc < threshold)[0]
    if len(below) == 0:
        return None

    idx = below[0]
    if idx == 0:
        return None

    f1, f2 = freq[idx - 1], freq[idx]
    v1, v2 = fsc[idx - 1], fsc[idx]

    if v2 == v1:
        return None

    f_cross = f1 + (threshold - v1) * (f2 - f1) / (v2 - v1)
    return round(1.0 / f_cross, 2) if f_cross > 0 else None


def _compute_orientation_anisotropy(euler_angles_rad: np.ndarray) -> float:
    """Compute anisotropy ratio from Euler angles (radians) using equal-area binning.

    Bins particles into 64 equal-area latitude bands (equal width in cos(theta))
    and returns max_bin_count / (N / N_bins).

    For a uniform sphere: ratio ≈ 1.
    For severe preferred orientation: ratio >> 10 (3DFSC criterion).

    Parameters
    ----------
    euler_angles_rad : np.ndarray, shape (N, 3)
        Columns: (phi, theta, psi) in **radians**.  theta is the polar angle.

    Returns
    -------
    float
        max_bin / (N / N_bins). 1.0 = isotropic; > 10 = severe.

    References
    ----------
    Tan et al. 2017 Nature Methods 14(8):793-796.
    """
    angles = np.asarray(euler_angles_rad, dtype=float)
    if angles.ndim != 2 or angles.shape[1] < 2:
        raise ValueError("euler_angles_rad must have shape (N, >=2): [phi, theta, ...]")

    N_bins = 64
    theta = angles[:, 1]   # polar angle in radians
    z = np.cos(theta)      # equal-area mapping: uniform z ↔ uniform sphere

    # Equal-width bins in z ∈ [-1, 1] = equal-area latitude bands
    bins = np.histogram(z, bins=N_bins, range=(-1.0, 1.0))[0]
    n_total = bins.sum()

    if n_total == 0:
        return 1.0

    mean_per_bin = n_total / N_bins
    return float(bins.max() / (mean_per_bin + 1e-9))


# ---------------------------------------------------------------------------
# Gate implementations
# ---------------------------------------------------------------------------


def check_motion_gate(
    total_drift_A: float,
    per_frame_drift_A: float,
    profile: str = _DEFAULT_PROFILE,
) -> QCResult:
    """Evaluate beam-induced motion quality for a single micrograph.

    Advisory zone: [1.0x, 1.30x] × threshold.
    Halt zone: > 1.30x × threshold.
    """
    p = _get_profile(profile)
    max_total = p["max_total_drift_A"]
    max_pf = p["max_per_frame_drift_A"]
    evidence = "Bharat & Scheres 2016; Zheng et al. 2017 Nature Methods"

    r_total = total_drift_A / max_total
    r_pf = per_frame_drift_A / max_pf
    r_max = max(r_total, r_pf)

    # Determine which metric is worst for reporting
    if r_total >= r_pf:
        metric_name, obs_value, threshold = "total_drift_A", total_drift_A, max_total
    else:
        metric_name, obs_value, threshold = "per_frame_drift_A", per_frame_drift_A, max_pf

    if r_max > _ADVISORY_FACTOR:
        return QCResult(
            gate="motion_drift", level="BRONZE", action="halt",
            metric=metric_name, value=obs_value, threshold=threshold,
            message=f"Motion {metric_name} {obs_value:.1f} Ang exceeds halt threshold ({threshold:.1f} × {_ADVISORY_FACTOR}).",
            suggestion="Discard movie or re-collect. Check grid stability.",
            evidence=evidence, profile=profile,
        )

    if r_max > 1.0:
        return QCResult(
            gate="motion_drift", level="SILVER", action="advisory",
            metric=metric_name, value=obs_value, threshold=threshold,
            message=f"Motion {metric_name} {obs_value:.1f} Ang marginally exceeds threshold {threshold:.1f} Ang.",
            suggestion="Review movie; consider tightening motion correction parameters.",
            evidence=evidence, profile=profile,
        )

    level = "GOLD" if r_max <= 0.70 else "SILVER"
    return QCResult(
        gate="motion_drift", level=level, action="pass",
        metric=metric_name, value=obs_value, threshold=threshold,
        message=f"Motion within acceptable limits ({obs_value:.1f} Ang).",
        suggestion="", evidence=evidence, profile=profile,
    )


def check_ctf_gate(
    fit_quality: float,
    defocus_A: float,
    astigmatism_A: float,
    phase_shift_rad: Optional[float] = None,
    profile: str = _DEFAULT_PROFILE,
) -> QCResult:
    """Evaluate CTF estimation quality for a micrograph.

    Halt fires when fit_quality < 0.80 × min_ctf_fit_quality.
    Advisory fires when astigmatism > max_astigmatism_A (fit quality OK).
    """
    p = _get_profile(profile)
    min_quality = p["min_ctf_fit_quality"]
    max_astig = p["max_astigmatism_A"]
    evidence = "Rohou & Grigorieff 2015 J. Struct. Biol. CTFFIND4"

    halt_threshold = 0.80 * min_quality

    if fit_quality < halt_threshold:
        return QCResult(
            gate="ctf_fit_quality", level="BRONZE", action="halt",
            metric="ctf_fit_quality", value=fit_quality, threshold=halt_threshold,
            message=f"CTF fit quality {fit_quality:.3f} below halt threshold {halt_threshold:.3f}.",
            suggestion="Exclude micrograph. Check ice thickness and beam tilt.",
            evidence=evidence, profile=profile,
        )

    if astigmatism_A > max_astig:
        return QCResult(
            gate="ctf_astigmatism", level="SILVER", action="advisory",
            metric="astigmatism_A", value=astigmatism_A, threshold=max_astig,
            message=f"Astigmatism {astigmatism_A:.0f} Ang exceeds advisory threshold {max_astig:.0f} Ang.",
            suggestion="Check objective lens stigmation.",
            evidence=evidence, profile=profile,
        )

    if fit_quality < min_quality:
        return QCResult(
            gate="ctf_fit_quality", level="SILVER", action="advisory",
            metric="ctf_fit_quality", value=fit_quality, threshold=min_quality,
            message=f"CTF fit quality {fit_quality:.3f} marginally below threshold {min_quality:.3f}.",
            suggestion="Consider excluding this micrograph.",
            evidence=evidence, profile=profile,
        )

    level = "GOLD" if fit_quality >= min_quality * 1.10 else "SILVER"
    return QCResult(
        gate="ctf_fit_quality", level=level, action="pass",
        metric="ctf_fit_quality", value=fit_quality, threshold=min_quality,
        message=f"CTF fit quality {fit_quality:.3f} is acceptable.",
        suggestion="", evidence=evidence, profile=profile,
    )


def check_junk_class_gate(
    class_particle_counts,
    total_particles: int,
    profile: str = _DEFAULT_PROFILE,
) -> QCResult:
    """Evaluate junk class fraction after 2D classification.

    Parameters
    ----------
    class_particle_counts : array-like
        Per-class particle counts.  A class is "junk" if its count < 100.
    total_particles : int
        Total particle count used as denominator for junk_fraction.
    """
    p = _get_profile(profile)
    halt_f = p["max_junk_fraction_halt"]
    adv_f = p["max_junk_fraction_advisory"]
    evidence = "Scheres 2012 J. Mol. Biol. RELION; standard SPA practice"

    counts = np.asarray(class_particle_counts, dtype=int)
    junk_particles = int(counts[counts < 100].sum())
    fraction = junk_particles / max(total_particles, 1)

    if fraction >= halt_f:
        return QCResult(
            gate="junk_class", level="BRONZE", action="halt",
            metric="junk_fraction", value=fraction, threshold=halt_f,
            message=f"Junk fraction {fraction:.1%} exceeds halt threshold {halt_f:.1%}.",
            suggestion="Re-pick or train topaz; inspect 2D class averages.",
            evidence=evidence, profile=profile,
        )

    if fraction >= adv_f:
        return QCResult(
            gate="junk_class", level="SILVER", action="advisory",
            metric="junk_fraction", value=fraction, threshold=adv_f,
            message=f"Junk fraction {fraction:.1%} in advisory range ({adv_f:.1%}–{halt_f:.1%}).",
            suggestion="Review 2D class averages and tighten selection criteria.",
            evidence=evidence, profile=profile,
        )

    level = "GOLD" if fraction < 0.20 else "SILVER"
    return QCResult(
        gate="junk_class", level=level, action="pass",
        metric="junk_fraction", value=fraction, threshold=halt_f,
        message=f"Junk fraction {fraction:.1%} is within limits.",
        suggestion="", evidence=evidence, profile=profile,
    )


def check_orientation_gate(
    euler_angles_rad: np.ndarray,
    profile: str = _DEFAULT_PROFILE,
) -> QCResult:
    """Evaluate preferred orientation bias from 2D class Euler angles (radians).

    Parameters
    ----------
    euler_angles_rad : np.ndarray, shape (N, 3)
        Columns: (phi, theta, psi) in **radians**.
    """
    p = _get_profile(profile)
    halt_r = p["max_orientation_anisotropy_halt"]
    adv_r = p["max_orientation_anisotropy_advisory"]
    evidence = "Tan et al. 2017 Nature Methods 14(8):793-796 (3DFSC)"

    ratio = _compute_orientation_anisotropy(euler_angles_rad)

    if ratio > halt_r:
        return QCResult(
            gate="orientation", level="BRONZE", action="halt",
            metric="anisotropy_ratio", value=ratio, threshold=halt_r,
            message=f"Orientation anisotropy {ratio:.1f} exceeds halt threshold {halt_r:.1f} (3DFSC).",
            suggestion="Collect tilted views; change specimen preparation.",
            evidence=evidence, profile=profile,
        )

    if ratio > adv_r:
        return QCResult(
            gate="orientation", level="SILVER", action="advisory",
            metric="anisotropy_ratio", value=ratio, threshold=adv_r,
            message=f"Orientation anisotropy {ratio:.1f} is moderate (advisory threshold {adv_r:.1f}).",
            suggestion="Consider collecting tilted-view supplements.",
            evidence=evidence, profile=profile,
        )

    return QCResult(
        gate="orientation", level="GOLD", action="pass",
        metric="anisotropy_ratio", value=ratio, threshold=halt_r,
        message=f"Orientation distribution is acceptable (ratio {ratio:.2f}).",
        suggestion="", evidence=evidence, profile=profile,
    )


def check_fsc_gate(
    fsc_freq_inv_A,
    fsc_values,
    profile: str = _DEFAULT_PROFILE,
) -> QCResult:
    """Evaluate final reconstruction quality via FSC 0.143 criterion.

    Parameters
    ----------
    fsc_freq_inv_A : array-like, shape (N,)
        Spatial frequencies in 1/Ang.
    fsc_values : array-like, shape (N,)
        FSC values in [0, 1].
    """
    p = _get_profile(profile)
    resolution_halt_A = p["min_fsc_resolution_A"]
    evidence = "Henderson et al. 2012 Structure; Scheres & Chen 2012 Nature Methods"

    resolution_A = _fsc_to_resolution_A(fsc_freq_inv_A, fsc_values)

    if resolution_A is None:
        return QCResult(
            gate="fsc_resolution", level="BRONZE", action="halt",
            metric="fsc_resolution_A", value=float("inf"), threshold=resolution_halt_A,
            message="FSC never crosses 0.143 — resolution undetermined.",
            suggestion="Check half-map independence; inspect for over-refinement.",
            evidence=evidence, profile=profile,
        )

    if resolution_A > resolution_halt_A:
        return QCResult(
            gate="fsc_resolution", level="BRONZE", action="halt",
            metric="fsc_resolution_A", value=resolution_A, threshold=resolution_halt_A,
            message=f"FSC 0.143 resolution {resolution_A:.2f} Ang exceeds halt threshold {resolution_halt_A:.2f} Ang.",
            suggestion="Collect more micrographs; improve CTF accuracy.",
            evidence=evidence, profile=profile,
        )

    level = "GOLD" if resolution_A < 4.0 else "SILVER"
    return QCResult(
        gate="fsc_resolution", level=level, action="pass",
        metric="fsc_resolution_A", value=resolution_A, threshold=resolution_halt_A,
        message=f"FSC 0.143 resolution {resolution_A:.2f} Ang meets quality threshold.",
        suggestion="", evidence=evidence, profile=profile,
    )


def check_abinitio_gate(
    best_class_score: float,
    reported_resolution_A: Optional[float],
    num_populated_classes: int,
    profile: str = _DEFAULT_PROFILE,
) -> QCResult:
    """Evaluate ab initio 3D reconstruction quality (G9).

    Fires after ab initio reconstruction completes.  The gate proxies 3D
    signal quality via the highest class score / likelihood reported by the
    ab initio job and, when available, the estimated resolution.

    Parameters
    ----------
    best_class_score : float
        Highest class score/likelihood from ab initio output (0–1).
    reported_resolution_A : float or None
        Ab initio resolution estimate in Ångströms, if available.
    num_populated_classes : int
        Number of classes with > 100 particles.

    Evidence
    --------
    BRONZE — Rosenthal & Henderson 2003; community heuristic
    (ab initio score > 0.10 = recognizable density)
    """
    p = _get_profile(profile)
    min_score = p["min_abinitio_class_score"]
    max_res_A = p["max_abinitio_resolution_A"]
    evidence = (
        "BRONZE — Rosenthal & Henderson 2003; community heuristic "
        "(ab initio score > 0.10 = recognizable density)"
    )

    # ── Halt conditions ──────────────────────────────────────────────────────
    if num_populated_classes == 0:
        return QCResult(
            gate="abinitio_quality", level="BRONZE", action="halt",
            metric="num_populated_classes", value=float(num_populated_classes),
            threshold=1.0,
            message=(
                "Ab initio 3D reconstruction failed to produce recognizable protein "
                "density. All classes are empty (0 populated). This indicates "
                "insufficient particle alignment signal — possibly too few particles, "
                "incorrect symmetry, or dominant junk classes. Suggestion: Increase "
                "particle count, review 2D class quality, or adjust pixel size."
            ),
            suggestion=(
                "Increase particle count, review 2D class quality, or adjust pixel size."
            ),
            evidence=evidence, profile=profile,
        )

    if best_class_score < min_score:
        return QCResult(
            gate="abinitio_quality", level="BRONZE", action="halt",
            metric="best_class_score", value=best_class_score,
            threshold=min_score,
            message=(
                f"Ab initio 3D reconstruction failed to produce recognizable protein "
                f"density. Best class score {best_class_score:.2f} is below threshold "
                f"{min_score:.2f}. This indicates insufficient particle alignment signal "
                f"— possibly too few particles, incorrect symmetry, or dominant junk "
                f"classes. Suggestion: Increase particle count, review 2D class quality, "
                f"or adjust pixel size."
            ),
            suggestion=(
                "Increase particle count, review 2D class quality, or adjust pixel size."
            ),
            evidence=evidence, profile=profile,
        )

    if reported_resolution_A is not None and reported_resolution_A > max_res_A:
        return QCResult(
            gate="abinitio_quality", level="BRONZE", action="halt",
            metric="reported_resolution_A", value=reported_resolution_A,
            threshold=max_res_A,
            message=(
                f"Ab initio 3D reconstruction failed to produce recognizable protein "
                f"density. Best class score {best_class_score:.2f} is below threshold "
                f"{min_score:.2f}. This indicates insufficient particle alignment signal "
                f"— possibly too few particles, incorrect symmetry, or dominant junk "
                f"classes. Suggestion: Increase particle count, review 2D class quality, "
                f"or adjust pixel size."
            ),
            suggestion=(
                "Increase particle count; improve 2D class quality; verify symmetry."
            ),
            evidence=evidence, profile=profile,
        )

    # ── Advisory conditions ───────────────────────────────────────────────────
    if best_class_score < 0.20:
        return QCResult(
            gate="abinitio_quality", level="BRONZE", action="advisory",
            metric="best_class_score", value=best_class_score,
            threshold=0.20,
            message=(
                f"Ab initio class score {best_class_score:.2f} is low (< 0.20). "
                "Signal is marginal — review 2D classes before proceeding to refinement."
            ),
            suggestion="Review 2D class quality; consider additional 2D rounds.",
            evidence=evidence, profile=profile,
        )

    if reported_resolution_A is not None and reported_resolution_A > 15.0:
        return QCResult(
            gate="abinitio_quality", level="BRONZE", action="advisory",
            metric="reported_resolution_A", value=reported_resolution_A,
            threshold=15.0,
            message=(
                f"Ab initio estimated resolution {reported_resolution_A:.1f} Å > 15 Å. "
                "Marginal ab initio quality — reconstruction may require more particles "
                "or additional refinement iterations."
            ),
            suggestion=(
                "Increase number of ab initio iterations or add more good particles."
            ),
            evidence=evidence, profile=profile,
        )

    # ── Pass ─────────────────────────────────────────────────────────────────
    return QCResult(
        gate="abinitio_quality", level="BRONZE", action="pass",
        metric="best_class_score", value=best_class_score,
        threshold=min_score,
        message=(
            f"Ab initio reconstruction passed quality check "
            f"(score {best_class_score:.2f}, {num_populated_classes} populated class(es))."
        ),
        suggestion="", evidence=evidence, profile=profile,
    )


def check_model_quality_gate(
    molprobity_score: float,
    ramachandran_favored_pct: float,
    rotamer_outlier_pct: float,
    profile: str = _DEFAULT_PROFILE,
) -> QCResult:
    """Evaluate atomic model quality via MolProbity metrics (G12).

    Fires after model refinement / post-processing.  Thresholds are the
    wwPDB/PDB deposition requirements (GOLD evidence).

    Parameters
    ----------
    molprobity_score : float
        MolProbity composite score (lower is better).  PDB requires < 2.0.
    ramachandran_favored_pct : float
        Fraction of residues in the Ramachandran favored region (0.0–1.0).
        PDB requires ≥ 0.90; excellent ≥ 0.97.
    rotamer_outlier_pct : float
        Fraction of rotamer outliers (0.0–1.0).  Advisory threshold 0.05.

    Evidence
    --------
    GOLD — PDB deposition requirement (MolProbity < 2.0);
    wwPDB validation report standards.
    """
    p = _get_profile(profile)
    max_mp_halt   = p["max_molprobity_score"]
    min_rama_halt = p["min_ramachandran_favored"]
    adv_mp        = p["advisory_molprobity_score"]
    adv_rama      = p["advisory_ramachandran_favored"]
    max_rota_adv  = p["max_rotamer_outlier_pct"]
    evidence = (
        "GOLD — PDB deposition requirement (MolProbity < 2.0); "
        "wwPDB validation report standards"
    )

    # ── Halt conditions ──────────────────────────────────────────────────────
    if molprobity_score >= max_mp_halt:
        return QCResult(
            gate="model_quality", level="GOLD", action="halt",
            metric="molprobity_score", value=molprobity_score,
            threshold=max_mp_halt,
            message=(
                f"MolProbity score {molprobity_score:.2f} ≥ {max_mp_halt:.1f} — "
                "unacceptable geometry. Model will not pass PDB deposition."
            ),
            suggestion=(
                "Run additional refinement rounds in PHENIX real_space_refine "
                "before attempting deposition."
            ),
            evidence=evidence, profile=profile,
        )

    if ramachandran_favored_pct < min_rama_halt:
        return QCResult(
            gate="model_quality", level="GOLD", action="halt",
            metric="ramachandran_favored_pct", value=ramachandran_favored_pct,
            threshold=min_rama_halt,
            message=(
                f"Ramachandran favored {ramachandran_favored_pct:.1%} < "
                f"{min_rama_halt:.0%} — fails PDB deposition requirement."
            ),
            suggestion=(
                "Run PHENIX real_space_refine with Ramachandran restraints enabled."
            ),
            evidence=evidence, profile=profile,
        )

    # ── Advisory conditions ───────────────────────────────────────────────────
    if molprobity_score >= adv_mp:
        return QCResult(
            gate="model_quality", level="GOLD", action="advisory",
            metric="molprobity_score", value=molprobity_score,
            threshold=adv_mp,
            message=(
                f"MolProbity {molprobity_score:.2f} ≥ {adv_mp:.1f} — will fail PDB "
                "deposition. Run additional refinement rounds in PHENIX real_space_refine."
            ),
            suggestion=(
                "Run additional refinement rounds in PHENIX real_space_refine."
            ),
            evidence=evidence, profile=profile,
        )

    if ramachandran_favored_pct < adv_rama:
        return QCResult(
            gate="model_quality", level="GOLD", action="advisory",
            metric="ramachandran_favored_pct", value=ramachandran_favored_pct,
            threshold=adv_rama,
            message=(
                f"Ramachandran favored {ramachandran_favored_pct:.1%} < "
                f"{adv_rama:.0%} — below excellent threshold."
            ),
            suggestion=(
                "Apply Ramachandran restraints in additional refinement cycles."
            ),
            evidence=evidence, profile=profile,
        )

    if rotamer_outlier_pct > max_rota_adv:
        return QCResult(
            gate="model_quality", level="GOLD", action="advisory",
            metric="rotamer_outlier_pct", value=rotamer_outlier_pct,
            threshold=max_rota_adv,
            message=(
                f"Rotamer outliers {rotamer_outlier_pct:.1%} > "
                f"{max_rota_adv:.0%} — above advisory threshold."
            ),
            suggestion=(
                "Inspect and manually fix rotamer outliers in Coot before deposition."
            ),
            evidence=evidence, profile=profile,
        )

    # ── Pass ─────────────────────────────────────────────────────────────────
    level = "GOLD" if molprobity_score < 1.5 else "SILVER"
    return QCResult(
        gate="model_quality", level=level, action="pass",
        metric="molprobity_score", value=molprobity_score,
        threshold=adv_mp,
        message=(
            f"Model quality passed (MolProbity {molprobity_score:.2f}, "
            f"Ramachandran favored {ramachandran_favored_pct:.1%}, "
            f"rotamer outliers {rotamer_outlier_pct:.1%})."
        ),
        suggestion="", evidence=evidence, profile=profile,
    )


# ---------------------------------------------------------------------------
# Audit trail
# ---------------------------------------------------------------------------


def write_audit_event(
    run_id: str,
    step: str,
    batch_idx: int,
    result: QCResult,
    outdir: str,
) -> None:
    """Append a QC gate event to <outdir>/qc_audit.jsonl.

    Parameters
    ----------
    run_id : str
        CryoSPARC / BioMate run identifier.
    step : str
        Pipeline step name (e.g. "motion_correction").
    batch_idx : int
        Micrograph batch index.
    result : QCResult
        Gate result to record.
    outdir : str
        Output directory.  File ``qc_audit.jsonl`` is created/appended.
    """
    os.makedirs(outdir, exist_ok=True)
    audit_path = os.path.join(outdir, "qc_audit.jsonl")

    record = {
        "ts": datetime.now(timezone.utc).isoformat(),
        "run_id": run_id,
        "step": step,
        "batch": batch_idx,
        **asdict(result),
    }

    with open(audit_path, "a", encoding="utf-8") as fh:
        fh.write(json.dumps(record, default=str) + "\n")
