"""
Integration tests: ScenarioRunner (simulated CryoSPARC jobs) →
                   MetricsExtractor →
                   CryoEMQCEvaluator →
                   CryoEMAutoLoop

These tests validate the FULL realistic pipeline with numpy-array job outputs,
matching the real cryosparc-tools interface. Swap ScenarioRunner for a real
cryosparc.tools job runner to test against a live cluster.

Run with:
    python -m pytest tests/test_simulation_integration.py -v
(from backend/experiments/cryo_em_autoloop/)
"""

from __future__ import annotations

import math
import sys
import tempfile
from pathlib import Path

import numpy as np
import pytest

sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from cryo_em_autoloop import (
    CryoEMAutoLoop,
    CryoEMParams,
    CryoEMQCEvaluator,
    MetricsExtractor,
)
from cryo_em_autoloop.simulation import (
    ScenarioConfig,
    ScenarioRunner,
    make_motion_ctf_jobs,
    make_picking_jobs,
    make_2d_class_jobs,
    make_abinitio_jobs,
    make_fsc_jobs,
)


# ── Fixtures ─────────────────────────────────────────────────────────────────

@pytest.fixture
def tmpdir():
    with tempfile.TemporaryDirectory() as d:
        yield Path(d)


@pytest.fixture
def extractor():
    return MetricsExtractor(pixel_size=1.05)


# ── MetricsExtractor unit tests ───────────────────────────────────────────────

class TestMetricsExtractorPhaseA:

    def test_good_run_produces_correct_metrics(self, extractor):
        jobs = make_motion_ctf_jobs(
            n_batches=3,
            n_micrographs_per_batch=100,
            pixel_size=1.05,
            drift_mean_A=20.0,
            ctf_fom_mean=0.85,
            astig_mean_A=400.0,
        )
        m = extractor.extract_phase_A(jobs)

        # mean_total_drift_A should be near 20 Å (within ±10 Å for randomness)
        assert 10.0 < m["mean_total_drift_A"] < 35.0, m
        # CTF FOM should be near 0.85
        assert 0.70 < m["mean_ctf_fit_quality"] < 0.99, m
        # Astigmatism near 400 Å
        assert 200.0 < m["mean_astigmatism_A"] < 700.0, m

    def test_bad_drift_produces_high_drift_metric(self, extractor):
        jobs = make_motion_ctf_jobs(drift_mean_A=80.0, ctf_fom_mean=0.85)
        m = extractor.extract_phase_A(jobs)
        assert m["mean_total_drift_A"] > 50.0, m

    def test_bad_ctf_produces_low_fom(self, extractor):
        jobs = make_motion_ctf_jobs(drift_mean_A=20.0, ctf_fom_mean=0.55)
        m = extractor.extract_phase_A(jobs)
        assert m["mean_ctf_fit_quality"] < 0.70, m

    def test_pixel_size_scales_drift(self):
        jobs = make_motion_ctf_jobs(drift_mean_A=20.0, pixel_size=1.0)
        m1 = MetricsExtractor(pixel_size=1.0).extract_phase_A(jobs)
        m2 = MetricsExtractor(pixel_size=2.0).extract_phase_A(jobs)
        # With pixel_size=2.0 the same raw pixel values give 2× the Å drift
        assert m2["mean_total_drift_A"] == pytest.approx(2.0 * m1["mean_total_drift_A"], rel=0.01)

    def test_empty_job_list_returns_nan(self, extractor):
        m = extractor.extract_phase_A([])
        assert math.isnan(m["mean_total_drift_A"])

    def test_multiple_batches_aggregated(self, extractor):
        jobs = make_motion_ctf_jobs(n_batches=5, n_micrographs_per_batch=200)
        m = extractor.extract_phase_A(jobs)
        # Should not raise; result should be finite
        assert math.isfinite(m["mean_total_drift_A"])
        assert math.isfinite(m["mean_ctf_fit_quality"])


class TestMetricsExtractorPhaseB:

    def test_good_picking_low_junk(self, extractor):
        jobs = make_picking_jobs(n_classes=200, n_classes_junk=20)
        m = extractor.extract_phase_B(jobs)
        assert m["junk_fraction"] == pytest.approx(20 / 200, abs=0.01)
        assert m["num_particles_selected"] > 50_000

    def test_high_junk_fraction_detected(self, extractor):
        jobs = make_picking_jobs(n_classes=200, n_classes_junk=160)
        m = extractor.extract_phase_B(jobs)
        assert m["junk_fraction"] > 0.70

    def test_junk_threshold_parameter(self, extractor):
        """Classes well above the junk threshold should give junk_fraction == 0."""
        # particles_per_good_class must be > 200 so rng.integers(200, 2x) is valid
        jobs = make_picking_jobs(n_classes=10, n_classes_junk=0,
                                  particles_per_good_class=300)
        m = extractor.extract_phase_B(jobs, junk_threshold=50)
        assert m["junk_fraction"] == 0.0

    def test_empty_job_list(self, extractor):
        m = extractor.extract_phase_B([])
        assert math.isnan(m["junk_fraction"])
        assert m["num_particles_selected"] == 0


class TestMetricsExtractorPhaseC:

    def test_isotropic_distribution_low_anisotropy(self, extractor):
        jobs = make_2d_class_jobs(n_particles=50_000, anisotropy=2.0)
        m = extractor.extract_phase_C(jobs)
        # Uniform distribution: anisotropy should be low
        assert m["orientation_anisotropy"] < 5.0, m

    def test_anisotropic_distribution_high_score(self, extractor):
        """High anisotropy input should produce clearly higher score than isotropic."""
        # anisotropy=12: squeezes cos_theta to N(0,0.3) → side-view bias.
        # After sin-normalisation the metric reads ~3-4× (well above isotropic ~1.1).
        jobs = make_2d_class_jobs(n_particles=50_000, anisotropy=12.0)
        m = extractor.extract_phase_C(jobs)
        assert m["orientation_anisotropy"] > 2.0, m

    def test_empty_returns_nan(self, extractor):
        m = extractor.extract_phase_C([])
        assert math.isnan(m["orientation_anisotropy"])


class TestMetricsExtractorPhaseD:

    def test_good_score_extracted(self, extractor):
        jobs = make_abinitio_jobs(best_class_score=0.35)
        m = extractor.extract_phase_D(jobs)
        assert m["best_abinitio_class_score"] == pytest.approx(0.35, abs=0.01)
        assert m["best_abinitio_resolution_A"] < 25.0

    def test_bad_score_gives_poor_resolution(self, extractor):
        jobs = make_abinitio_jobs(best_class_score=0.05)
        m = extractor.extract_phase_D(jobs)
        assert m["best_abinitio_class_score"] == pytest.approx(0.05, abs=0.01)
        assert m["best_abinitio_resolution_A"] >= 25.0

    def test_empty_returns_nan(self, extractor):
        m = extractor.extract_phase_D([])
        assert math.isnan(m["best_abinitio_class_score"])


class TestMetricsExtractorPhaseE:

    def test_good_resolution_extracted(self, extractor):
        jobs = make_fsc_jobs(fsc_resolution_A=4.5)
        m = extractor.extract_phase_E(jobs)
        # Should be within ±2 Å of the target
        assert abs(m["fsc_resolution_A"] - 4.5) < 2.0, m

    def test_bad_resolution_extracted(self, extractor):
        jobs = make_fsc_jobs(fsc_resolution_A=25.0)
        m = extractor.extract_phase_E(jobs)
        assert m["fsc_resolution_A"] > 15.0, m

    def test_empty_returns_nan(self, extractor):
        m = extractor.extract_phase_E([])
        assert math.isnan(m["fsc_resolution_A"])


# ── End-to-end: ScenarioRunner → MetricsExtractor → QCEvaluator ─────────────

class TestScenarioRunnerWithExtractor:
    """
    Validates that ScenarioRunner output can be piped through MetricsExtractor
    and that the resulting scalars correctly pass/fail QC gates.
    """

    def test_good_scenario_passes_phase_A(self):
        config = ScenarioConfig(
            drift_per_attempt=[20.0],
            ctf_fom_per_attempt=[0.88],
            astig_per_attempt=[350.0],
        )
        runner = ScenarioRunner(config)
        extractor = MetricsExtractor(pixel_size=config.pixel_size)
        evaluator = CryoEMQCEvaluator()

        jobs = runner("phase_A", None)
        metrics = extractor.extract_phase_A(jobs)
        result = evaluator.evaluate_phase_A(metrics)

        assert result.passed, f"Expected pass; metrics={metrics}"

    def test_bad_drift_scenario_fails_phase_A(self):
        config = ScenarioConfig(drift_per_attempt=[90.0], ctf_fom_per_attempt=[0.85])
        runner = ScenarioRunner(config)
        extractor = MetricsExtractor(pixel_size=config.pixel_size)
        evaluator = CryoEMQCEvaluator()

        jobs = runner("phase_A", None)
        metrics = extractor.extract_phase_A(jobs)
        result = evaluator.evaluate_phase_A(metrics)

        assert not result.passed
        assert any(g.gate == "motion_drift" for g in result.halts)

    def test_good_scenario_passes_phase_B(self):
        config = ScenarioConfig(junk_fraction=0.15)
        runner = ScenarioRunner(config)
        extractor = MetricsExtractor()
        evaluator = CryoEMQCEvaluator()

        jobs = runner("phase_B", None)
        metrics = extractor.extract_phase_B(jobs)
        result = evaluator.evaluate_phase_B(metrics)

        assert result.passed, f"metrics={metrics}"

    def test_bad_junk_scenario_fails_phase_B(self):
        config = ScenarioConfig(junk_fraction=0.85)
        runner = ScenarioRunner(config)
        extractor = MetricsExtractor()
        evaluator = CryoEMQCEvaluator()

        jobs = runner("phase_B", None)
        metrics = extractor.extract_phase_B(jobs)
        result = evaluator.evaluate_phase_B(metrics)

        assert not result.passed

    def test_good_scenario_passes_phase_E(self):
        config = ScenarioConfig(fsc_resolution_A=4.5)
        runner = ScenarioRunner(config)
        extractor = MetricsExtractor()
        evaluator = CryoEMQCEvaluator()

        jobs = runner("phase_E", None)
        metrics = extractor.extract_phase_E(jobs)
        result = evaluator.evaluate_phase_E(metrics)

        assert result.passed, f"metrics={metrics}"

    def test_bad_fsc_scenario_fails_phase_E(self):
        # The FSC sigmoid crossing shifts due to steepness; use 50 Å so the
        # extracted 0.143-criterion resolution reliably exceeds the 20 Å gate.
        config = ScenarioConfig(fsc_resolution_A=50.0)
        runner = ScenarioRunner(config)
        extractor = MetricsExtractor()
        evaluator = CryoEMQCEvaluator()

        jobs = runner("phase_E", None)
        metrics = extractor.extract_phase_E(jobs)
        assert metrics["fsc_resolution_A"] > 20.0, f"Expected extracted >20 Å, got {metrics}"
        result = evaluator.evaluate_phase_E(metrics)
        assert not result.passed


# ── Full orchestrator integration with SimulatedPhaseRunner ──────────────────

class SimulatedPhaseRunner:
    """
    Wraps ScenarioRunner + MetricsExtractor to produce the scalar metrics dict
    that CryoEMAutoLoop.run() expects.

    This is the adapter between the realistic simulation layer and the
    existing orchestrator interface.  In production, replace ScenarioRunner
    with a real cryosparc.tools job runner.
    """

    def __init__(self, config: ScenarioConfig, rng_seed: int = 42):
        self._scenario = ScenarioRunner(config, rng_seed=rng_seed)
        self._extractor = MetricsExtractor(pixel_size=config.pixel_size)

    def __call__(self, phase: str, params: CryoEMParams) -> dict:
        jobs = self._scenario(phase, params)
        return self._extractor.extract(phase, jobs)


class TestFullOrchestrationWithSimulation:

    def test_all_good_scenario_all_phases_pass(self, tmpdir):
        config = ScenarioConfig(
            drift_per_attempt=[20.0],
            ctf_fom_per_attempt=[0.88],
            astig_per_attempt=[350.0],
            junk_fraction=0.15,
            anisotropy=3.0,
            best_class_score=0.35,
            fsc_resolution_A=4.5,
        )
        runner = SimulatedPhaseRunner(config)
        loop = CryoEMAutoLoop("sim_all_pass", CryoEMParams(), output_dir=tmpdir)
        result = loop.run(runner)

        assert set(result.phases_passed) == {"phase_A", "phase_B", "phase_C", "phase_D", "phase_E"}
        assert result.phases_escalated == []
        assert result.total_attempts == 5
        assert result.audit_path.exists()
        assert result.summary_path.exists()

    def test_drift_improves_on_retry(self, tmpdir):
        """
        Attempt 0: bad drift (90 Å) → fails phase_A
        Attempt 1: good drift (20 Å) → passes phase_A
        All other phases: good
        """
        config = ScenarioConfig(
            drift_per_attempt=[90.0, 20.0],   # retry sequence
            ctf_fom_per_attempt=[0.85, 0.88],
            astig_per_attempt=[350.0, 350.0],
            junk_fraction=0.15,
            anisotropy=3.0,
            best_class_score=0.35,
            fsc_resolution_A=4.5,
        )
        runner = SimulatedPhaseRunner(config)
        loop = CryoEMAutoLoop("sim_retry", CryoEMParams(), max_retries_per_phase=2,
                               output_dir=tmpdir)
        result = loop.run(runner)

        assert "phase_A" in result.phases_passed, f"phase_A should pass after retry: {result}"
        assert result.phases_escalated == []
        assert result.total_attempts >= 6  # 2 for phase_A + 1 each for B/C/D/E

    def test_persistent_bad_drift_escalates(self, tmpdir):
        """phase_A always bad → escalates after max_retries."""
        config = ScenarioConfig(
            drift_per_attempt=[200.0],   # always terrible
            ctf_fom_per_attempt=[0.30],  # also terrible
            junk_fraction=0.15,
            anisotropy=3.0,
            best_class_score=0.35,
            fsc_resolution_A=4.5,
        )
        runner = SimulatedPhaseRunner(config)
        loop = CryoEMAutoLoop("sim_escalate", CryoEMParams(), max_retries_per_phase=2,
                               output_dir=tmpdir)
        result = loop.run(runner)

        assert "phase_A" in result.phases_escalated, result
        # Other phases should still run
        assert len(result.phases_passed) >= 3

    def test_membrane_profile_tolerates_higher_drift(self, tmpdir):
        """
        Drift of 65 Å fails purified profile (threshold 50) but passes
        membrane profile (threshold 80).
        """
        config = ScenarioConfig(
            drift_per_attempt=[65.0],
            ctf_fom_per_attempt=[0.75],
            astig_per_attempt=[800.0],
            junk_fraction=0.15,
            anisotropy=3.0,
            best_class_score=0.35,
            fsc_resolution_A=4.5,
        )
        # Purified profile should escalate phase_A
        runner_purified = SimulatedPhaseRunner(config)
        loop_purified = CryoEMAutoLoop(
            "sim_purified", CryoEMParams(),
            qc_profile="cryoem_spa_purified",
            max_retries_per_phase=1,
            output_dir=tmpdir,
        )
        result_purified = loop_purified.run(runner_purified)
        assert "phase_A" in result_purified.phases_escalated, result_purified

        # Membrane profile should pass phase_A
        runner_membrane = SimulatedPhaseRunner(config, rng_seed=99)
        loop_membrane = CryoEMAutoLoop(
            "sim_membrane", CryoEMParams(),
            qc_profile="cryoem_spa_membrane",
            max_retries_per_phase=1,
            output_dir=tmpdir,
        )
        result_membrane = loop_membrane.run(runner_membrane)
        assert "phase_A" in result_membrane.phases_passed, result_membrane

    def test_audit_files_contain_numpy_derived_metrics(self, tmpdir):
        """Verify that audit JSONL records contain realistic (non-nan) metric values."""
        import json

        config = ScenarioConfig(drift_per_attempt=[20.0], ctf_fom_per_attempt=[0.88])
        runner = SimulatedPhaseRunner(config)
        loop = CryoEMAutoLoop("sim_audit_check", CryoEMParams(), output_dir=tmpdir)
        result = loop.run(runner)

        lines = result.audit_path.read_text().strip().splitlines()
        # Find the phase_A attempt record
        phase_a_records = [
            json.loads(line) for line in lines
            if json.loads(line).get("phase") == "phase_A"
            and json.loads(line).get("event") == "attempt"
        ]
        assert len(phase_a_records) >= 1, "Expected at least one phase_A attempt record"
        rec = phase_a_records[0]
        # Gate results should reference the motion_drift gate
        gate_names = [g["gate"] for g in rec.get("gate_results", [])]
        assert "motion_drift" in gate_names, f"gate_results: {rec.get('gate_results')}"


if __name__ == "__main__":
    import subprocess
    sys.exit(subprocess.call(["python", "-m", "pytest", __file__, "-v"]))
