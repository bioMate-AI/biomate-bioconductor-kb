"""
Unit tests for the CryoEM auto-loop prototype.

Run with: python -m pytest tests/test_autoloop.py -v
(from backend/experiments/cryo_em_autoloop/ directory)
or: python -m pytest backend/experiments/cryo_em_autoloop/tests/ -v
(from biomate root)
"""

import sys
import tempfile
from pathlib import Path

import pytest

# Make the package importable regardless of working directory
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from cryo_em_autoloop import (
    CryoEMAutoLoop,
    CryoEMParams,
    CryoEMQCEvaluator,
    MockPhaseRunner,
    ParamTuner,
    AuditLogger,
    QCAction,
)
from cryo_em_autoloop.qc_evaluator import PhaseQCResult


# ── Fixtures ──────────────────────────────────────────────────────────────────

@pytest.fixture
def tmpdir():
    with tempfile.TemporaryDirectory() as d:
        yield Path(d)


@pytest.fixture
def good_metrics():
    """Metrics that pass all QC gates."""
    return {
        "phase_A": {
            "mean_total_drift_A": 20.0,
            "mean_per_frame_drift_A": 1.0,
            "mean_ctf_fit_quality": 0.88,
            "mean_astigmatism_A": 300.0,
        },
        "phase_B": {
            "junk_fraction": 0.25,
            "num_particles_selected": 80_000,
            "min_particles_required": 5_000,
        },
        "phase_C": {
            "orientation_anisotropy": 2.5,
            "mean_class_quality": 0.65,
        },
        "phase_D": {
            "best_abinitio_class_score": 0.35,
            "best_abinitio_resolution_A": 15.0,
        },
        "phase_E": {
            "fsc_resolution_A": 5.5,
        },
    }


# ── CryoEMParams ──────────────────────────────────────────────────────────────

def test_params_defaults():
    p = CryoEMParams()
    assert p.pixel_size == 1.05
    assert p.voltage == 300
    assert p.micrograph_batch_size == 200
    assert p.num_ab_initio_classes == 3


def test_params_copy_is_independent():
    p = CryoEMParams()
    p2 = p.copy()
    p2.pixel_size = 9.99
    assert p.pixel_size == 1.05


def test_params_to_dict():
    p = CryoEMParams(pixel_size=2.0)
    d = p.to_dict()
    assert d["pixel_size"] == 2.0
    assert "micrograph_batch_size" in d


# ── QC Evaluator ─────────────────────────────────────────────────────────────

def test_phase_A_pass(good_metrics):
    ev = CryoEMQCEvaluator()
    result = ev.evaluate_phase_A(good_metrics["phase_A"])
    assert result.passed
    assert result.phase == "phase_A"


def test_phase_A_drift_halt():
    ev = CryoEMQCEvaluator()
    result = ev.evaluate_phase_A({
        "mean_total_drift_A": 80.0,  # > 50 Å threshold
        "mean_per_frame_drift_A": 1.0,
        "mean_ctf_fit_quality": 0.85,
        "mean_astigmatism_A": 300.0,
    })
    assert not result.passed
    halts = result.halts
    assert any(g.gate == "motion_drift" for g in halts)


def test_phase_A_ctf_halt():
    ev = CryoEMQCEvaluator()
    result = ev.evaluate_phase_A({
        "mean_total_drift_A": 20.0,
        "mean_per_frame_drift_A": 1.0,
        "mean_ctf_fit_quality": 0.50,  # < 0.70 threshold
        "mean_astigmatism_A": 300.0,
    })
    assert not result.passed
    assert any(g.gate == "ctf_fit_quality" for g in result.halts)


def test_phase_B_junk_halt():
    ev = CryoEMQCEvaluator()
    result = ev.evaluate_phase_B({
        "junk_fraction": 0.80,  # > 0.70 threshold
        "num_particles_selected": 50_000,
        "min_particles_required": 5_000,
    })
    assert not result.passed
    assert any(g.gate == "junk_fraction" for g in result.halts)


def test_phase_C_anisotropy_halt():
    ev = CryoEMQCEvaluator()
    result = ev.evaluate_phase_C({
        "orientation_anisotropy": 15.0,  # > 10.0 threshold
        "mean_class_quality": 0.6,
    })
    assert not result.passed
    assert any(g.gate == "orientation_anisotropy" for g in result.halts)


def test_phase_D_abinitio_halt():
    ev = CryoEMQCEvaluator()
    result = ev.evaluate_phase_D({
        "best_abinitio_class_score": 0.05,  # < 0.10 threshold
        "best_abinitio_resolution_A": 30.0,
    })
    assert not result.passed


def test_phase_E_fsc_pass():
    ev = CryoEMQCEvaluator()
    result = ev.evaluate_phase_E({"fsc_resolution_A": 3.5})
    assert result.passed


def test_phase_E_fsc_fail():
    ev = CryoEMQCEvaluator()
    result = ev.evaluate_phase_E({"fsc_resolution_A": 25.0})  # > 20.0 threshold
    assert not result.passed


def test_membrane_profile_relaxed():
    """Membrane profile allows more drift than purified."""
    ev_purified = CryoEMQCEvaluator("cryoem_spa_purified")
    ev_membrane = CryoEMQCEvaluator("cryoem_spa_membrane")
    metrics = {"mean_total_drift_A": 65.0, "mean_per_frame_drift_A": 2.0,
               "mean_ctf_fit_quality": 0.75, "mean_astigmatism_A": 400.0}
    assert not ev_purified.evaluate_phase_A(metrics).passed  # fails purified (>50)
    assert ev_membrane.evaluate_phase_A(metrics).passed      # passes membrane (≤80)


def test_unknown_profile_raises():
    with pytest.raises(ValueError, match="Unknown QC profile"):
        CryoEMQCEvaluator("nonexistent_profile")


# ── ParamTuner ────────────────────────────────────────────────────────────────

def test_tuner_motion_drift_remediation():
    ev = CryoEMQCEvaluator()
    qc = ev.evaluate_phase_A({
        "mean_total_drift_A": 80.0,
        "mean_per_frame_drift_A": 1.0,
        "mean_ctf_fit_quality": 0.85,
        "mean_astigmatism_A": 300.0,
    })
    params = CryoEMParams(micrograph_batch_size=200)
    tuner = ParamTuner()
    new_params, remediations = tuner.remediate(qc, params)
    assert new_params.micrograph_batch_size == 100  # halved
    assert new_params.motion_correction_dose_weighting is True
    assert any(r.gate == "motion_drift" for r in remediations)


def test_tuner_batch_size_floor():
    """batch_size should not go below 50."""
    ev = CryoEMQCEvaluator()
    qc = ev.evaluate_phase_A({
        "mean_total_drift_A": 80.0,
        "mean_per_frame_drift_A": 1.0,
        "mean_ctf_fit_quality": 0.85,
        "mean_astigmatism_A": 300.0,
    })
    params = CryoEMParams(micrograph_batch_size=60)
    tuner = ParamTuner()
    new_params, _ = tuner.remediate(qc, params)
    assert new_params.micrograph_batch_size >= 50


def test_tuner_abinitio_cap():
    """num_ab_initio_classes should not exceed 8."""
    ev = CryoEMQCEvaluator()
    qc = ev.evaluate_phase_D({
        "best_abinitio_class_score": 0.05,
        "best_abinitio_resolution_A": 30.0,
    })
    params = CryoEMParams(num_ab_initio_classes=7)
    tuner = ParamTuner()
    new_params, _ = tuner.remediate(qc, params)
    assert new_params.num_ab_initio_classes <= 8


def test_tuner_no_changes_on_pass(good_metrics):
    ev = CryoEMQCEvaluator()
    qc = ev.evaluate_phase_A(good_metrics["phase_A"])
    params = CryoEMParams()
    tuner = ParamTuner()
    new_params, remediations = tuner.remediate(qc, params)
    assert remediations == []
    assert new_params.micrograph_batch_size == params.micrograph_batch_size


# ── AuditLogger ───────────────────────────────────────────────────────────────

def test_audit_logger_creates_files(tmpdir):
    logger = AuditLogger("run_test_001", tmpdir)
    ev = CryoEMQCEvaluator()
    qc = ev.evaluate_phase_A({
        "mean_total_drift_A": 20.0, "mean_per_frame_drift_A": 1.0,
        "mean_ctf_fit_quality": 0.85, "mean_astigmatism_A": 300.0,
    })
    logger.log_attempt("phase_A", 1, CryoEMParams(), qc, [])
    logger.log_phase_final("phase_A", 1, "pass")
    summary_path = logger.write_summary_report()

    assert logger.audit_path.exists()
    assert summary_path.exists()
    lines = logger.audit_path.read_text().strip().splitlines()
    assert len(lines) == 2  # one attempt + one phase_final


def test_audit_logger_jsonl_schema(tmpdir):
    import json
    logger = AuditLogger("run_schema_test", tmpdir)
    ev = CryoEMQCEvaluator()
    qc = ev.evaluate_phase_A({
        "mean_total_drift_A": 20.0, "mean_per_frame_drift_A": 1.0,
        "mean_ctf_fit_quality": 0.85, "mean_astigmatism_A": 300.0,
    })
    logger.log_attempt("phase_A", 1, CryoEMParams(), qc, [])
    line = json.loads(logger.audit_path.read_text().splitlines()[0])
    for key in ("ts", "run_id", "phase", "attempt", "params", "gate_results", "remediations"):
        assert key in line, f"Missing key: {key}"


# ── Full orchestrator ─────────────────────────────────────────────────────────

def test_all_phases_pass(good_metrics, tmpdir):
    runner = MockPhaseRunner(good_metrics)
    loop = CryoEMAutoLoop("test_all_pass", CryoEMParams(), output_dir=tmpdir)
    result = loop.run(runner)

    assert result.phases_passed == ["phase_A", "phase_B", "phase_C", "phase_D", "phase_E"]
    assert result.phases_failed == []
    assert result.phases_escalated == []
    assert result.total_attempts == 5
    assert result.audit_path.exists()
    assert result.summary_path.exists()


def test_phase_A_retry_then_pass(tmpdir):
    """phase_A fails attempt 1, passes attempt 2 after param adjustment."""
    metrics_by_attempt = {
        "phase_A": [
            # attempt 1 — bad drift
            {"mean_total_drift_A": 80.0, "mean_per_frame_drift_A": 2.0,
             "mean_ctf_fit_quality": 0.85, "mean_astigmatism_A": 300.0},
            # attempt 2 — good after tuning
            {"mean_total_drift_A": 25.0, "mean_per_frame_drift_A": 1.0,
             "mean_ctf_fit_quality": 0.85, "mean_astigmatism_A": 300.0},
        ],
        "phase_B": {"junk_fraction": 0.2, "num_particles_selected": 80_000, "min_particles_required": 5_000},
        "phase_C": {"orientation_anisotropy": 2.0, "mean_class_quality": 0.7},
        "phase_D": {"best_abinitio_class_score": 0.4, "best_abinitio_resolution_A": 15.0},
        "phase_E": {"fsc_resolution_A": 4.5},
    }
    runner = MockPhaseRunner(metrics_by_attempt)
    loop = CryoEMAutoLoop("test_retry", CryoEMParams(), output_dir=tmpdir)
    result = loop.run(runner)

    assert "phase_A" in result.phases_passed
    assert result.phases_escalated == []
    assert result.total_attempts == 6  # 2 for phase_A + 1 each for B/C/D/E


def test_phase_escalates_after_max_retries(tmpdir):
    """phase_A always fails → escalated; other phases still run."""
    always_bad_A = {"mean_total_drift_A": 200.0, "mean_per_frame_drift_A": 10.0,
                    "mean_ctf_fit_quality": 0.3, "mean_astigmatism_A": 5000.0}
    metrics = {
        "phase_A": always_bad_A,
        "phase_B": {"junk_fraction": 0.2, "num_particles_selected": 80_000, "min_particles_required": 5_000},
        "phase_C": {"orientation_anisotropy": 2.0, "mean_class_quality": 0.7},
        "phase_D": {"best_abinitio_class_score": 0.4, "best_abinitio_resolution_A": 15.0},
        "phase_E": {"fsc_resolution_A": 4.5},
    }
    runner = MockPhaseRunner(metrics)
    loop = CryoEMAutoLoop("test_escalate", CryoEMParams(), max_retries_per_phase=2, output_dir=tmpdir)
    result = loop.run(runner)

    assert "phase_A" in result.phases_escalated
    # Downstream phases still ran
    assert len(result.phases_passed) >= 3


def test_custom_qc_profile(tmpdir):
    """Membrane profile passes where purified would fail."""
    metrics = {
        "phase_A": {"mean_total_drift_A": 65.0, "mean_per_frame_drift_A": 2.5,
                    "mean_ctf_fit_quality": 0.68, "mean_astigmatism_A": 1200.0},
        "phase_B": {"junk_fraction": 0.2, "num_particles_selected": 80_000, "min_particles_required": 5_000},
        "phase_C": {"orientation_anisotropy": 2.0, "mean_class_quality": 0.7},
        "phase_D": {"best_abinitio_class_score": 0.4, "best_abinitio_resolution_A": 15.0},
        "phase_E": {"fsc_resolution_A": 4.5},
    }
    runner = MockPhaseRunner(metrics)
    loop_membrane = CryoEMAutoLoop("test_membrane", CryoEMParams(),
                                   qc_profile="cryoem_spa_membrane", output_dir=tmpdir)
    result = loop_membrane.run(runner)
    assert "phase_A" in result.phases_passed  # membrane thresholds are relaxed


if __name__ == "__main__":
    import subprocess, sys
    sys.exit(subprocess.call(["python", "-m", "pytest", __file__, "-v"]))
