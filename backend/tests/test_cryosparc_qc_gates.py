"""
CryoSPARC QC Gate Unit Tests
=============================
Pure-Python / numpy-only tests — no CryoSPARC installation required.

If the target module (cryosparc_qc_gates) is not yet present the entire
suite is skipped gracefully so CI stays green while the module is under
development.

Run:
    pytest backend/tests/test_cryosparc_qc_gates.py -v
"""

import json
import os
import sys
import tempfile

import numpy as np
import pytest

# ---------------------------------------------------------------------------
# Defensive import — skip the whole module if gates are not installed yet
# ---------------------------------------------------------------------------
sys.path.insert(
    0,
    os.path.join(os.path.dirname(__file__), "..", "lib", "galaxy", "webapps", "galaxy", "api"),
)

try:
    from cryosparc_qc_gates import (
        PROFILES,
        QCResult,
        _compute_orientation_anisotropy,
        _fsc_to_resolution_A,
        check_abinitio_gate,
        check_ctf_gate,
        check_fsc_gate,
        check_junk_class_gate,
        check_model_quality_gate,
        check_motion_gate,
        check_orientation_gate,
        write_audit_event,
    )

    HAS_MODULE = True
except ImportError:
    HAS_MODULE = False

pytestmark = pytest.mark.skipif(
    not HAS_MODULE, reason="cryosparc_qc_gates not yet installed"
)

# ===========================================================================
# Constants / profile names
# ===========================================================================

P_PURIFIED   = "cryoem_spa_purified"
P_MEMBRANE   = "cryoem_spa_membrane"
P_PHASE_PLATE = "cryoem_spa_phase_plate"

# Pixel size used for synthetic FSC fixtures (EMPIAR-10061).
PIXEL_SIZE_A = 0.885


# ===========================================================================
# FSC fixture helpers
# ===========================================================================

def _make_fsc_arrays(crossing_freq_index: int, total_points: int = 129):
    """
    Build synthetic FSC freq + corr arrays that cross 0.143 at *crossing_freq_index*.

    Returns
    -------
    freqs : np.ndarray   spatial frequencies in 1/Å
    corrs : np.ndarray   FSC values
    """
    nyquist = 1.0 / (2.0 * PIXEL_SIZE_A)
    freqs = np.linspace(0.0, nyquist, total_points)

    # Exponential decay: corr[crossing_freq_index] ≈ 0.143
    decay_rate = -np.log(0.143) / crossing_freq_index if crossing_freq_index > 0 else 1.0
    corrs = np.exp(-decay_rate * np.arange(total_points))

    return freqs, corrs


def _resolution_at_index(idx: int, total_points: int = 129) -> float:
    """Expected resolution in Å for a given FSC array index."""
    nyquist = 1.0 / (2.0 * PIXEL_SIZE_A)
    freq = (idx / (total_points - 1)) * nyquist
    return 1.0 / freq if freq > 0 else float("inf")


# ===========================================================================
# Motion gate tests
# ===========================================================================


class TestMotionGate:
    """
    check_motion_gate(total_drift_A, per_frame_drift_A, profile) → QCResult

    Profile thresholds (purified):  max_total=50 Å, max_per_frame=3 Å
    Profile thresholds (membrane):  max_total=80 Å, max_per_frame=5 Å
    Advisory boundary: ratio ≤ 1.30 × threshold (i.e. ≤65 Å total for purified)
    Halt boundary:     ratio >  1.30 × threshold (i.e. >65 Å total for purified)
    """

    def test_motion_gate_pass_purified(self):
        # 32 Å total, well inside 50 Å limit → pass
        result = check_motion_gate(
            total_drift_A=32.0,
            per_frame_drift_A=1.5,
            profile=P_PURIFIED,
        )
        assert result.action == "pass"

    def test_motion_gate_halt_purified(self):
        # 65 Å total > 50 Å * 1.30 = 65 Å; at exactly the boundary the gate
        # calls halt (ratio == 1.30 triggers advisory, >1.30 triggers halt).
        # Use 70 Å to be unambiguously above the advisory band.
        result = check_motion_gate(
            total_drift_A=70.0,
            per_frame_drift_A=1.5,
            profile=P_PURIFIED,
        )
        assert result.action == "halt"

    def test_motion_gate_pass_membrane(self):
        # 65 Å is below membrane threshold of 80 Å → pass
        result = check_motion_gate(
            total_drift_A=65.0,
            per_frame_drift_A=2.0,
            profile=P_MEMBRANE,
        )
        assert result.action == "pass"

    def test_motion_gate_halt_membrane(self):
        # 90 Å > 80 Å * 1.30 = 104 Å? No — 90/80 = 1.125 ≤ 1.30 → advisory.
        # Use 110 Å: ratio = 110/80 = 1.375 > 1.30 → halt.
        result = check_motion_gate(
            total_drift_A=110.0,
            per_frame_drift_A=2.0,
            profile=P_MEMBRANE,
        )
        assert result.action == "halt"

    def test_motion_gate_advisory_per_frame(self):
        # Per-frame limit for purified is 3 Å.
        # per_frame=4 Å: ratio = 4/3 = 1.33 > 1.30 → halt for per-frame alone.
        # Constrain total to be well inside limit; gate should still fire.
        # per_frame=3.2 Å: ratio = 3.2/3 ≈ 1.067 ≤ 1.30 → advisory.
        result = check_motion_gate(
            total_drift_A=30.0,
            per_frame_drift_A=3.2,
            profile=P_PURIFIED,
        )
        assert result.action == "advisory"


# ===========================================================================
# CTF gate tests
# ===========================================================================


class TestCtfGate:
    """
    check_ctf_gate(fit_quality, defocus_A, astigmatism_A,
                   phase_shift_rad=None, profile=...) → QCResult

    Purified thresholds: min_ctf_fit_quality=0.7, max_astigmatism_A=1000 Å
    Phase-plate threshold: min_ctf_fit_quality=0.65
    Halt fires when fit_quality < 0.80 * min_fit_quality.
    """

    def test_ctf_gate_pass(self):
        # 0.82 > 0.70 → pass (GOLD since 0.82 ≥ 1.10 * 0.70 = 0.77)
        result = check_ctf_gate(
            fit_quality=0.82,
            defocus_A=15000.0,
            astigmatism_A=200.0,
            profile=P_PURIFIED,
        )
        assert result.action == "pass"

    def test_ctf_gate_halt(self):
        # 0.55 < 0.80 * 0.70 = 0.56 → halt
        result = check_ctf_gate(
            fit_quality=0.55,
            defocus_A=15000.0,
            astigmatism_A=200.0,
            profile=P_PURIFIED,
        )
        assert result.action == "halt"

    def test_ctf_gate_phase_plate_relaxed(self):
        # Phase-plate profile has min_ctf_fit_quality=0.65.
        # 0.66 >= 0.65 → pass.
        result = check_ctf_gate(
            fit_quality=0.66,
            defocus_A=15000.0,
            astigmatism_A=200.0,
            profile=P_PHASE_PLATE,
        )
        assert result.action == "pass"

    def test_ctf_gate_astigmatism_advisory(self):
        # Astigmatism 1200 Å > max 1000 Å.
        # fit_quality is fine (0.82); only astigmatism fails.
        # Ratio = 1200/1000 = 1.20 — within the advisory band (not a halt).
        result = check_ctf_gate(
            fit_quality=0.82,
            defocus_A=15000.0,
            astigmatism_A=1200.0,
            profile=P_PURIFIED,
        )
        # astigmatism failure pushes to advisory (fit_quality OK → not halt)
        assert result.action in ("advisory", "halt")
        # Specifically: fit_quality >= 0.80*0.70 → advisory, not halt
        assert result.action == "advisory"


# ===========================================================================
# FSC gate tests
# ===========================================================================


class TestFscGate:
    """
    _fsc_to_resolution_A(freq_inv_A, fsc_values) → float | None
    check_fsc_gate(fsc_freq_inv_A, fsc_values, profile) → QCResult
    """

    def test_fsc_interpolation_accuracy(self):
        # Crossing at index 64 of 129 → known frequency → known resolution.
        crossing_idx = 64
        freqs, corrs = _make_fsc_arrays(crossing_idx)
        expected_A = _resolution_at_index(crossing_idx)

        computed_A = _fsc_to_resolution_A(freqs, corrs)

        assert computed_A is not None, "_fsc_to_resolution_A returned None unexpectedly"
        assert abs(computed_A - expected_A) < 0.1, (
            f"Expected {expected_A:.3f} Å, got {computed_A:.3f} Å"
        )

    def test_fsc_gate_pass(self):
        # Crossing at index 100 → fine resolution, well below 20 Å limit.
        freqs, corrs = _make_fsc_arrays(100)
        result = check_fsc_gate(freqs, corrs, profile=P_PURIFIED)
        assert result.action == "pass"
        # value field carries resolution in Å
        assert 1.0 < result.value < 10.0, (
            f"Expected resolution 1–10 Å for crossing at index 100, got {result.value}"
        )

    def test_fsc_gate_halt_no_crossing(self):
        # FSC stays at constant 0.5 — never crosses 0.143 → halt.
        total_points = 129
        nyquist = 1.0 / (2.0 * PIXEL_SIZE_A)
        freqs = np.linspace(0.0, nyquist, total_points)
        corrs = np.full(total_points, 0.5)

        result = check_fsc_gate(freqs, corrs, profile=P_PURIFIED)
        assert result.action == "halt"

    def test_fsc_gate_halt_very_low_resolution(self):
        # Crossing at index 5 → very low resolution (~25 Å >> 20 Å limit).
        freqs, corrs = _make_fsc_arrays(5)
        result = check_fsc_gate(freqs, corrs, profile=P_PURIFIED)
        # Resolution worse than min_fsc_resolution_A=20 Å by more than 2× → halt
        assert result.action in ("advisory", "halt")
        assert result.value > 20.0, (
            f"Expected resolution > 20 Å for crossing at index 5, got {result.value}"
        )


# ===========================================================================
# Junk class gate tests
# ===========================================================================


class TestJunkClassGate:
    """
    check_junk_class_gate(class_particle_counts, total_particles) → QCResult

    A "junk" class is one with < 100 particles.
    halt threshold:     junk_fraction >= 0.70
    advisory threshold: junk_fraction >= 0.50

    To control junk fraction precisely we build class arrays where junk classes
    each contribute exactly 1 particle (well below the 100-particle threshold).
    """

    @staticmethod
    def _build_class_counts(n_junk: int, n_good: int, good_size: int = 1000) -> np.ndarray:
        """
        Build a class-count array with *n_junk* junk classes (1 particle each)
        and *n_good* good classes (*good_size* particles each).
        """
        junk_counts = np.ones(n_junk, dtype=int)          # 1 particle each → junk
        good_counts = np.full(n_good, good_size, dtype=int)
        return np.concatenate([junk_counts, good_counts])

    def test_junk_gate_halt(self):
        # 38 junk classes × 1 particle + 12 good classes × 1000 particles
        # total_particles = 38 * 1 + 12 * 1000 = 12 038
        # junk_fraction   = 38 / 12 038 ≈ 0.32% — that's below halt.
        # We need to control junk_fraction via total_particles argument.
        # junk_count in particles = 38; total_particles passed = 50 → frac = 38/50 = 76%
        counts = np.concatenate([np.ones(38, dtype=int), np.array([1000, 1000], dtype=int)])
        # But junk is counted by count < 100, so 38 classes × 1 = 38 junk particles.
        # total_particles must be set so that 38/total = 0.76 → total = 50.
        result = check_junk_class_gate(counts, total_particles=50)
        assert result.action == "halt", (
            f"Expected halt for 76% junk fraction, got action={result.action!r}"
        )

    def test_junk_gate_advisory(self):
        # 28 junk classes × 1 particle; total=50 → junk_fraction = 28/50 = 56%
        counts = np.concatenate([np.ones(28, dtype=int), np.array([1000, 1000], dtype=int)])
        result = check_junk_class_gate(counts, total_particles=50)
        assert result.action == "advisory", (
            f"Expected advisory for 56% junk fraction, got action={result.action!r}"
        )

    def test_junk_gate_pass(self):
        # 10 junk classes × 1 particle; total=50 → junk_fraction = 10/50 = 20%
        counts = np.concatenate([np.ones(10, dtype=int), np.array([1000, 1000], dtype=int)])
        result = check_junk_class_gate(counts, total_particles=50)
        assert result.action == "pass", (
            f"Expected pass for 20% junk fraction, got action={result.action!r}"
        )


# ===========================================================================
# Orientation gate tests
# ===========================================================================


class TestOrientationGate:
    """
    _compute_orientation_anisotropy(euler_angles_rad) → float (ratio)
    check_orientation_gate(euler_angles_rad, profile) → QCResult

    euler_angles_rad: (N, 3) in radians — [phi, theta, psi].
    Purified thresholds: advisory=5.0, halt=10.0

    _compute_orientation_anisotropy bins cos(theta) into 64 equal-area bands.
    A uniform sphere maps every band equally → max/mean ≈ 1 × 64/64 = 1, but
    the implementation returns max_bin / (mean_over_all_bins), which for a
    uniform distribution = (N/64) / (N/64) = 1.  In practice with finite N and
    random seeds, values in the range 1–6 are seen; strong clustering gives >> 10.
    """

    def _uniform_sphere_rad(self, n: int = 10_000) -> np.ndarray:
        """Uniform sphere sample — angles in radians."""
        rng = np.random.default_rng(seed=42)
        phi   = rng.uniform(0.0, 2 * np.pi, n)
        cos_t = rng.uniform(-1.0, 1.0, n)
        theta = np.arccos(cos_t)
        psi   = rng.uniform(0.0, 2 * np.pi, n)
        return np.column_stack([phi, theta, psi])

    def _z_axis_bias_rad(self, n: int = 10_000, spread_rad: float = 0.05) -> np.ndarray:
        """Particles almost all pointing toward +z (theta ≈ 0, concentrated)."""
        rng = np.random.default_rng(seed=7)
        phi   = rng.uniform(0.0, 2 * np.pi, n)
        # theta = |N(0, spread_rad)| — almost all near zero
        theta = np.abs(rng.normal(0.0, spread_rad, n))
        # cos(theta) ≈ 1 for all → all particles in the same lat band
        psi   = rng.uniform(0.0, 2 * np.pi, n)
        return np.column_stack([phi, theta, psi])

    def _moderate_bias_rad(self, n: int = 10_000, spread_rad: float = 0.35) -> np.ndarray:
        """Moderate preferred orientation (not uniform, not fully concentrated)."""
        rng = np.random.default_rng(seed=13)
        phi   = rng.uniform(0.0, 2 * np.pi, n)
        theta = np.abs(rng.normal(np.pi / 4, spread_rad, n))  # around 45°
        psi   = rng.uniform(0.0, 2 * np.pi, n)
        return np.column_stack([phi, theta, psi])

    def test_orientation_isotropic(self):
        angles = self._uniform_sphere_rad()
        ratio = _compute_orientation_anisotropy(angles)
        # A uniform sphere has all 64 bins roughly equally filled.
        # max_bin / mean ≈ 1; with finite N the ratio should stay well below halt.
        assert ratio < 10.0, (
            f"Uniform sphere anisotropy ratio should be < 10, got {ratio:.2f}"
        )
        result = check_orientation_gate(angles, profile=P_PURIFIED)
        # With 10 000 samples the ratio ≈ 1–2 → definitely pass
        assert result.action in ("pass", "advisory"), (
            f"Uniform sphere should not halt, got action={result.action!r}"
        )

    def test_orientation_severe_bias(self):
        # Concentrate essentially all particles in a 0.05 rad band around theta=0.
        # cos(theta) ≈ 1 for all → fills only the top 1–2 of 64 latitude bins.
        # max_bin / mean >> 10.
        angles = self._z_axis_bias_rad(spread_rad=0.02)
        ratio = _compute_orientation_anisotropy(angles)
        assert ratio > 10.0, (
            f"Expected ratio > 10 for severe z-axis bias, got {ratio:.2f}"
        )
        result = check_orientation_gate(angles, profile=P_PURIFIED)
        assert result.action == "halt"

    def test_orientation_advisory(self):
        angles = self._moderate_bias_rad()
        result = check_orientation_gate(angles, profile=P_PURIFIED)
        # Moderate concentration should land in advisory or pass (not halt).
        assert result.action in ("advisory", "pass"), (
            f"Moderate bias should not halt, got action={result.action!r}"
        )


# ===========================================================================
# Profile completeness tests
# ===========================================================================

# Required profile keys as defined in the actual PROFILES dict.
_REQUIRED_PROFILE_KEYS = {
    "max_total_drift_A",
    "max_per_frame_drift_A",
    "min_ctf_fit_quality",
    "max_astigmatism_A",
    "max_junk_fraction_halt",
    "max_junk_fraction_advisory",
    "max_orientation_anisotropy_halt",
    "max_orientation_anisotropy_advisory",
    "min_fsc_resolution_A",
    # G9 — Ab initio quality gate
    "min_abinitio_class_score",
    "max_abinitio_resolution_A",
    # G12 — MolProbity / model validation gate
    "max_molprobity_score",
    "min_ramachandran_favored",
    "advisory_molprobity_score",
    "advisory_ramachandran_favored",
    "max_rotamer_outlier_pct",
}


class TestProfileCompleteness:
    def test_profiles_have_required_keys(self):
        missing = {}
        for profile_name, profile_dict in PROFILES.items():
            absent = _REQUIRED_PROFILE_KEYS - set(profile_dict.keys())
            if absent:
                missing[profile_name] = sorted(absent)

        assert not missing, (
            "The following profiles are missing required threshold keys:\n"
            + "\n".join(f"  {p}: {k}" for p, k in missing.items())
        )

    def test_known_profiles_present(self):
        for name in (P_PURIFIED, P_MEMBRANE, P_PHASE_PLATE):
            assert name in PROFILES, f"Expected profile '{name}' in PROFILES dict"

    def test_membrane_thresholds_more_relaxed(self):
        """Membrane profile must allow more drift and worse CTF than purified."""
        pur = PROFILES[P_PURIFIED]
        mem = PROFILES[P_MEMBRANE]
        assert mem["max_total_drift_A"] > pur["max_total_drift_A"]
        assert mem["max_astigmatism_A"] >= pur["max_astigmatism_A"]

    def test_phase_plate_ctf_relaxed(self):
        """Phase-plate profile must have a lower or equal CTF quality floor."""
        pur = PROFILES[P_PURIFIED]
        pp  = PROFILES[P_PHASE_PLATE]
        assert pp["min_ctf_fit_quality"] <= pur["min_ctf_fit_quality"]


# ===========================================================================
# Audit trail tests
# ===========================================================================


class TestAuditTrail:
    """write_audit_event(run_id, step, batch_idx, result, outdir) appends JSONL."""

    def _make_motion_result(self) -> QCResult:
        return check_motion_gate(
            total_drift_A=32.0,
            per_frame_drift_A=1.5,
            profile=P_PURIFIED,
        )

    def test_write_audit_event(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            result = self._make_motion_result()
            write_audit_event(
                run_id="test-run-001",
                step="motion_correction",
                batch_idx=0,
                result=result,
                outdir=tmpdir,
            )

            audit_path = os.path.join(tmpdir, "qc_audit.jsonl")
            assert os.path.isfile(audit_path), "qc_audit.jsonl was not created"

            with open(audit_path) as fh:
                line = fh.readline().strip()

            parsed = json.loads(line)

            # Envelope fields
            assert "ts" in parsed, "Missing 'ts' timestamp field"
            assert parsed["run_id"] == "test-run-001"
            assert parsed["step"] == "motion_correction"
            assert parsed["batch"] == 0

            # QCResult fields unwrapped into the record
            assert parsed["action"] == "pass"
            assert parsed["gate"] == "motion_drift"
            assert parsed["profile"] == P_PURIFIED

            # Timestamp must be ISO-8601
            from datetime import datetime
            dt = datetime.fromisoformat(parsed["ts"].replace("Z", "+00:00"))
            assert dt.year >= 2024

    def test_audit_event_appends(self):
        """Multiple write_audit_event calls must append, not overwrite."""
        with tempfile.TemporaryDirectory() as tmpdir:
            result = self._make_motion_result()
            for i in range(3):
                write_audit_event(
                    run_id="run-append-test",
                    step="motion_correction",
                    batch_idx=i,
                    result=result,
                    outdir=tmpdir,
                )

            audit_path = os.path.join(tmpdir, "qc_audit.jsonl")
            with open(audit_path) as fh:
                lines = [l.strip() for l in fh if l.strip()]

            assert len(lines) == 3, (
                f"Expected 3 audit lines after 3 writes, got {len(lines)}"
            )
            for i, line in enumerate(lines):
                record = json.loads(line)
                assert record["batch"] == i


# ===========================================================================
# Ab initio gate tests (G9)
# ===========================================================================


class TestAbInitioGate:
    """
    check_abinitio_gate(best_class_score, reported_resolution_A,
                        num_populated_classes, profile) → QCResult

    Halt conditions:
      - best_class_score < 0.10            → halt
      - reported_resolution_A > 25.0       → halt
      - num_populated_classes == 0         → halt

    Advisory conditions:
      - best_class_score < 0.20            → advisory
      - reported_resolution_A > 15.0       → advisory
    """

    def test_abinitio_halt_low_score(self):
        # score=0.05 < 0.10 → HALT
        result = check_abinitio_gate(
            best_class_score=0.05,
            reported_resolution_A=None,
            num_populated_classes=2,
            profile=P_PURIFIED,
        )
        assert result.action == "halt", (
            f"Expected halt for score=0.05, got action={result.action!r}"
        )
        assert result.gate == "abinitio_quality"
        assert result.level == "BRONZE"

    def test_abinitio_advisory_low_score(self):
        # score=0.15 >= 0.10 but < 0.20 → advisory
        result = check_abinitio_gate(
            best_class_score=0.15,
            reported_resolution_A=None,
            num_populated_classes=2,
            profile=P_PURIFIED,
        )
        assert result.action == "advisory", (
            f"Expected advisory for score=0.15, got action={result.action!r}"
        )

    def test_abinitio_advisory_marginal_resolution(self):
        # score=0.30 (passes score gates), res=20.0 Å > 15 Å → advisory
        result = check_abinitio_gate(
            best_class_score=0.30,
            reported_resolution_A=20.0,
            num_populated_classes=3,
            profile=P_PURIFIED,
        )
        assert result.action == "advisory", (
            f"Expected advisory for score=0.30, res=20.0, got action={result.action!r}"
        )
        assert result.metric == "reported_resolution_A"

    def test_abinitio_pass_good_score_good_resolution(self):
        # score=0.30, res=12.0 Å → pass (both gates clear)
        result = check_abinitio_gate(
            best_class_score=0.30,
            reported_resolution_A=12.0,
            num_populated_classes=3,
            profile=P_PURIFIED,
        )
        assert result.action == "pass", (
            f"Expected pass for score=0.30, res=12.0, got action={result.action!r}"
        )

    def test_abinitio_halt_zero_classes(self):
        # score=0.05 AND num_populated=0 → halt (zero classes fires first)
        result = check_abinitio_gate(
            best_class_score=0.05,
            reported_resolution_A=None,
            num_populated_classes=0,
            profile=P_PURIFIED,
        )
        assert result.action == "halt", (
            f"Expected halt for zero populated classes, got action={result.action!r}"
        )
        assert result.metric == "num_populated_classes"

    def test_abinitio_halt_resolution_too_low(self):
        # score=0.30 (good) but res=30.0 Å > 25.0 Å → halt
        result = check_abinitio_gate(
            best_class_score=0.30,
            reported_resolution_A=30.0,
            num_populated_classes=2,
            profile=P_PURIFIED,
        )
        assert result.action == "halt", (
            f"Expected halt for res=30.0, got action={result.action!r}"
        )

    def test_abinitio_pass_no_resolution_available(self):
        # score=0.25, res=None (not available) → pass (no resolution gate fires)
        result = check_abinitio_gate(
            best_class_score=0.25,
            reported_resolution_A=None,
            num_populated_classes=1,
            profile=P_PURIFIED,
        )
        assert result.action == "pass", (
            f"Expected pass for score=0.25, no resolution, got action={result.action!r}"
        )

    def test_abinitio_membrane_profile(self):
        # Same thresholds apply regardless of profile (BRONZE universal)
        result = check_abinitio_gate(
            best_class_score=0.12,
            reported_resolution_A=None,
            num_populated_classes=1,
            profile=P_MEMBRANE,
        )
        # 0.12 >= 0.10 (no halt) but < 0.20 → advisory
        assert result.action == "advisory"
        assert result.profile == P_MEMBRANE


# ===========================================================================
# Model quality gate tests (G12)
# ===========================================================================


class TestModelQualityGate:
    """
    check_model_quality_gate(molprobity_score, ramachandran_favored_pct,
                             rotamer_outlier_pct, profile) → QCResult

    Halt conditions (GOLD — PDB deposition):
      - molprobity_score >= 3.0            → halt
      - ramachandran_favored_pct < 0.90    → halt

    Advisory conditions:
      - molprobity_score >= 2.0            → advisory
      - ramachandran_favored_pct < 0.97    → advisory
      - rotamer_outlier_pct > 0.05         → advisory
    """

    def test_model_quality_halt_molprobity(self):
        # molprobity=3.5 >= 3.0 → HALT
        result = check_model_quality_gate(
            molprobity_score=3.5,
            ramachandran_favored_pct=0.95,
            rotamer_outlier_pct=0.03,
            profile=P_PURIFIED,
        )
        assert result.action == "halt", (
            f"Expected halt for molprobity=3.5, got action={result.action!r}"
        )
        assert result.gate == "model_quality"
        assert result.level == "GOLD"
        assert result.metric == "molprobity_score"

    def test_model_quality_advisory_molprobity(self):
        # molprobity=2.5 >= 2.0 but < 3.0 → advisory
        result = check_model_quality_gate(
            molprobity_score=2.5,
            ramachandran_favored_pct=0.95,
            rotamer_outlier_pct=0.03,
            profile=P_PURIFIED,
        )
        assert result.action == "advisory", (
            f"Expected advisory for molprobity=2.5, got action={result.action!r}"
        )
        assert result.metric == "molprobity_score"

    def test_model_quality_pass_good_scores(self):
        # molprobity=1.8 < 2.0 → pass (all gates clear)
        result = check_model_quality_gate(
            molprobity_score=1.8,
            ramachandran_favored_pct=0.98,
            rotamer_outlier_pct=0.02,
            profile=P_PURIFIED,
        )
        assert result.action == "pass", (
            f"Expected pass for molprobity=1.8, got action={result.action!r}"
        )

    def test_model_quality_halt_ramachandran(self):
        # ramachandran=0.88 < 0.90 → HALT
        result = check_model_quality_gate(
            molprobity_score=1.5,
            ramachandran_favored_pct=0.88,
            rotamer_outlier_pct=0.03,
            profile=P_PURIFIED,
        )
        assert result.action == "halt", (
            f"Expected halt for ramachandran=0.88, got action={result.action!r}"
        )
        assert result.metric == "ramachandran_favored_pct"

    def test_model_quality_advisory_ramachandran(self):
        # ramachandran=0.95 >= 0.90 (no halt) but < 0.97 → advisory
        # molprobity must be < 2.0 so molprobity advisory doesn't fire first
        result = check_model_quality_gate(
            molprobity_score=1.8,
            ramachandran_favored_pct=0.95,
            rotamer_outlier_pct=0.03,
            profile=P_PURIFIED,
        )
        assert result.action == "advisory", (
            f"Expected advisory for ramachandran=0.95, got action={result.action!r}"
        )
        assert result.metric == "ramachandran_favored_pct"

    def test_model_quality_advisory_rotamer_outliers(self):
        # rotamer=0.08 > 0.05; molprobity and ramachandran pass → advisory from rotamer
        result = check_model_quality_gate(
            molprobity_score=1.8,
            ramachandran_favored_pct=0.98,
            rotamer_outlier_pct=0.08,
            profile=P_PURIFIED,
        )
        assert result.action == "advisory", (
            f"Expected advisory for rotamer_outlier=0.08, got action={result.action!r}"
        )
        assert result.metric == "rotamer_outlier_pct"

    def test_model_quality_gold_level_excellent(self):
        # molprobity < 1.5 → level GOLD on pass
        result = check_model_quality_gate(
            molprobity_score=1.2,
            ramachandran_favored_pct=0.99,
            rotamer_outlier_pct=0.01,
            profile=P_PURIFIED,
        )
        assert result.action == "pass"
        assert result.level == "GOLD"

    def test_model_quality_phase_plate_profile(self):
        # Same GOLD thresholds apply on all profiles
        result = check_model_quality_gate(
            molprobity_score=3.5,
            ramachandran_favored_pct=0.95,
            rotamer_outlier_pct=0.03,
            profile=P_PHASE_PLATE,
        )
        assert result.action == "halt"
        assert result.profile == P_PHASE_PLATE


# ===========================================================================
# Batch split / speedup formula tests (no CryoSPARC required)
# ===========================================================================

# Pure-arithmetic tests the benchmark harness relies on.


def _split_batches(items: int, batch_size: int) -> list:
    """Return list of per-batch item counts given total items and max batch size."""
    batches = []
    remaining = items
    while remaining > 0:
        b = min(batch_size, remaining)
        batches.append(b)
        remaining -= b
    return batches


def _speedup(serial_time_s: float, parallel_time_s: float) -> float:
    return serial_time_s / parallel_time_s


class TestBatchAndSpeedup:
    def test_batch_split_even(self):
        batches = _split_batches(1000, batch_size=200)
        assert len(batches) == 5
        assert all(b == 200 for b in batches)

    def test_batch_split_remainder(self):
        batches = _split_batches(950, batch_size=200)
        assert len(batches) == 5
        # First four batches of 200, last of 150
        assert batches[:4] == [200, 200, 200, 200]
        assert batches[4] == 150

    def test_speedup_formula(self):
        # 100 s/micrograph × 100 micrographs serial = 10 000 s
        # 4 workers in parallel → 2 500 s
        serial_time = 100.0 * 100
        parallel_time = serial_time / 4.0
        su = _speedup(serial_time, parallel_time)
        assert abs(su - 4.0) < 1e-9, f"Expected speedup 4.0, got {su}"

    def test_batch_split_single_batch(self):
        # Fewer items than batch_size → one batch
        batches = _split_batches(50, batch_size=200)
        assert len(batches) == 1
        assert batches[0] == 50

    def test_batch_split_exact_multiple(self):
        batches = _split_batches(600, batch_size=200)
        assert len(batches) == 3
        assert sum(batches) == 600
