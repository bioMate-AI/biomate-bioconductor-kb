"""
ADMET auto-loop unit tests.

Mirrors the structure of cryo_em_autoloop tests but for drug discovery
ADMET safety screening.  All tests run without any live backend — they use
the SimulatedADMETJob / MockPhaseRunner for deterministic scenarios.

Test plan:
  AL-1  to AL-6:  QC evaluator gate logic (per gate)
  AL-7  to AL-10: ParamTuner remediation rules (per gate)
  AL-11 to AL-14: Orchestrator retry/escalation behaviour
  AL-15 to AL-17: AuditLogger JSONL output + summary report
  AL-18 to AL-20: Scenario runner integration (hERG, DILI, Ames)
  AL-21 to AL-23: Profile variants (cns, oncology)
  AL-24:          Persistent-failure escalation path
"""

import json
import pytest
from pathlib import Path

from ..params import ADMETParams
from ..qc_evaluator import ADMETQCEvaluator, QCAction, QCLevel
from ..param_tuner import ADMETParamTuner
from ..orchestrator import ADMETAutoLoop, MockPhaseRunner
from ..simulation import (
    ScenarioRunner,
    SCENARIO_HERG_THEN_PASS,
    SCENARIO_DILI_THEN_PASS,
    SCENARIO_AMES_THEN_PASS,
    SCENARIO_MULTI_GATE,
    SCENARIO_PERSISTENT_FAIL,
    SCENARIO_CLEAN_PASS,
)


# ── Fixtures ──────────────────────────────────────────────────────────────────

@pytest.fixture
def evaluator():
    return ADMETQCEvaluator(profile="admet_standard")

@pytest.fixture
def tuner():
    return ADMETParamTuner()

@pytest.fixture
def default_params():
    return ADMETParams()

@pytest.fixture
def tmp_loop(tmp_path):
    """Fresh ADMETAutoLoop with tmp_path for audit output."""
    return ADMETAutoLoop(
        run_id="test-run",
        params=ADMETParams(),
        qc_profile="admet_standard",
        max_retries_per_phase=2,
        output_dir=tmp_path,
    )


# ── AL-1: hERG gate — HALT when IC50 below threshold ─────────────────────────

def test_al1_herg_halt_below_threshold(evaluator):
    metrics = {"herg_ic50_uM": 3.5}  # < 10 µM → HALT
    result = evaluator.evaluate_phase_3(metrics)
    halt_gates = [g for g in result.gate_results if g.action == QCAction.HALT]
    assert any(g.gate == "herg_ic50" for g in halt_gates), "hERG gate should HALT"
    assert not result.passed


# ── AL-2: hERG gate — PASS when IC50 above threshold ─────────────────────────

def test_al2_herg_pass_above_threshold(evaluator):
    metrics = {"herg_ic50_uM": 18.0}  # > 10 µM → PASS
    result = evaluator.evaluate_phase_3(metrics)
    assert result.passed, "hERG gate should PASS"


# ── AL-3: DILI probability gate — HALT when probability exceeds max ───────────

def test_al3_dili_probability_halt(evaluator):
    metrics = {
        "herg_ic50_uM": 25.0,
        "dili_probability": 0.78,   # > 0.5 → HALT
        "dili_risk": "high",
        "ames_positive": False,
        "ames_probability": 0.1,
        "logP": 3.0,
        "mw": 320.0,
    }
    result = evaluator.evaluate_phase_2(metrics)
    halt_gates = [g.gate for g in result.halts]
    assert "dili_probability" in halt_gates or "dili_risk_level" in halt_gates


# ── AL-4: DILI risk-level gate — "high" exceeds "medium" max ─────────────────

def test_al4_dili_risk_level_halt(evaluator):
    metrics = {
        "herg_ic50_uM": 25.0,
        "dili_probability": 0.3,    # probability within limit
        "dili_risk": "high",        # risk level "high" > "medium" max → HALT
        "ames_positive": False,
        "ames_probability": 0.1,
        "logP": 3.0,
        "mw": 320.0,
    }
    result = evaluator.evaluate_phase_4(metrics)
    halt_gates = [g.gate for g in result.halts]
    assert "dili_risk_level" in halt_gates


# ── AL-5: Ames gate — HALT when ames_positive is True ────────────────────────

def test_al5_ames_positive_halt(evaluator):
    metrics = {
        "herg_ic50_uM": 30.0,
        "dili_probability": 0.2,
        "dili_risk": "low",
        "ames_positive": True,      # structural alert → HALT
        "ames_probability": 0.72,
        "logP": 2.8,
        "mw": 310.0,
    }
    result = evaluator.evaluate_phase_4(metrics)
    halt_gates = [g.gate for g in result.halts]
    assert "ames_mutagenicity" in halt_gates


# ── AL-6: Clean pass — all gates within limits ────────────────────────────────

def test_al6_all_gates_pass(evaluator):
    metrics = {
        "herg_ic50_uM": 45.0,
        "dili_probability": 0.12,
        "dili_risk": "low",
        "ames_positive": False,
        "ames_probability": 0.08,
        "logP": 2.4,
        "mw": 320.0,
    }
    result = evaluator.evaluate_phase_2(metrics)
    assert result.passed
    assert result.overall_level in (QCLevel.GOLD, QCLevel.SILVER)


# ── AL-7: Tuner — hERG HALT reduces logP_max ─────────────────────────────────

def test_al7_tuner_herg_reduces_logp(tuner, evaluator, default_params):
    metrics = {"herg_ic50_uM": 3.5}
    qc = evaluator.evaluate_phase_3(metrics)
    new_params, remediations = tuner.remediate(qc, default_params)
    assert new_params.logp_max < default_params.logp_max, "logp_max should decrease"
    assert any(r.gate == "herg_ic50" for r in remediations)
    assert "Aronov" in remediations[0].rationale


# ── AL-8: Tuner — DILI probability HALT caps logP/MW at Lammert boundary ─────

def test_al8_tuner_dili_caps_logp_mw(tuner, evaluator):
    params = ADMETParams(logp_max=6.0, mw_max_da=600.0)
    metrics = {
        "herg_ic50_uM": 25.0,
        "dili_probability": 0.78,
        "dili_risk": "medium",      # only prob gate fires
        "ames_positive": False,
        "ames_probability": 0.1,
        "logP": 5.0,
        "mw": 550.0,
    }
    qc = evaluator.evaluate_phase_2(metrics)
    new_params, remediations = tuner.remediate(qc, params)
    assert new_params.logp_max <= 4.0, "logP should be capped at Lammert boundary"
    assert new_params.mw_max_da <= 400.0, "MW should be capped at Lammert boundary"


# ── AL-9: Tuner — Ames HALT enables strict mode + reduces candidates ──────────

def test_al9_tuner_ames_enables_strict(tuner, evaluator):
    params = ADMETParams(ames_strict=False, num_candidates=50)
    metrics = {
        "herg_ic50_uM": 30.0,
        "dili_probability": 0.2,
        "dili_risk": "low",
        "ames_positive": True,
        "ames_probability": 0.72,
        "logP": 2.8,
        "mw": 310.0,
    }
    qc = evaluator.evaluate_phase_4(metrics)
    new_params, remediations = tuner.remediate(qc, params)
    assert new_params.ames_strict is True
    assert new_params.num_candidates < params.num_candidates
    assert any("Kazius" in r.rationale for r in remediations)


# ── AL-10: Tuner — unknown gate returns advisory-only remediation ─────────────

def test_al10_tuner_unknown_gate_advisory(tuner, evaluator):
    # Synthesise a PhaseQCResult with a gate name the tuner has no handler for
    from ..qc_evaluator import PhaseQCResult, GateResult, QCAction, QCLevel
    fake_gate = GateResult(
        gate="unknown_safety_gate",
        action=QCAction.HALT,
        level=QCLevel.FAIL,
        value=999.0,
        threshold=100.0,
        message="synthetic unknown gate",
    )
    fake_qc = PhaseQCResult(phase="phase_2_admet_prediction", gate_results=[fake_gate])
    params = ADMETParams()
    new_params, remediations = tuner.remediate(fake_qc, params)
    assert len(remediations) == 1
    assert remediations[0].param_changes == {}
    assert "manual inspection" in remediations[0].rationale


# ── AL-11: Orchestrator — single-phase pass on first attempt ──────────────────

def test_al11_orchestrator_single_phase_clean_pass(tmp_path):
    loop = ADMETAutoLoop(
        run_id="al11",
        params=ADMETParams(),
        output_dir=tmp_path,
        max_retries_per_phase=2,
    )
    clean_metrics = {
        "herg_ic50_uM": 45.0,
        "dili_probability": 0.12,
        "dili_risk": "low",
        "ames_positive": False,
        "ames_probability": 0.08,
        "logP": 2.4,
        "mw": 320.0,
    }
    runner = MockPhaseRunner({
        "phase_2_admet_prediction": clean_metrics,
        "phase_3_herg_screen":      clean_metrics,
        "phase_4_dili_ames":        clean_metrics,
    })
    result = loop.run(runner)
    assert len(result.phases_passed) == 3
    assert len(result.phases_failed) == 0
    assert len(result.phases_escalated) == 0


# ── AL-12: Orchestrator — hERG HALT on attempt 1, pass on attempt 2 ──────────

def test_al12_orchestrator_herg_retry_then_pass(tmp_path):
    loop = ADMETAutoLoop(
        run_id="al12",
        params=ADMETParams(),
        output_dir=tmp_path,
        max_retries_per_phase=2,
    )
    runner = MockPhaseRunner({
        "phase_2_admet_prediction": [
            {"herg_ic50_uM": 3.5,  "dili_probability": 0.1,  "dili_risk": "low",  "ames_positive": False, "ames_probability": 0.05, "logP": 3.0, "mw": 350.0},
            {"herg_ic50_uM": 18.0, "dili_probability": 0.1,  "dili_risk": "low",  "ames_positive": False, "ames_probability": 0.05, "logP": 2.5, "mw": 340.0},
        ],
        "phase_3_herg_screen": {"herg_ic50_uM": 18.0},
        "phase_4_dili_ames":   {"herg_ic50_uM": 18.0, "dili_probability": 0.1, "dili_risk": "low", "ames_positive": False, "ames_probability": 0.05},
    })
    result = loop.run(runner)
    assert "phase_2_admet_prediction" in result.phases_passed
    assert result.total_attempts >= 2


# ── AL-13: Orchestrator — persistent failure escalates after max retries ──────

def test_al13_orchestrator_escalates_on_persistent_fail(tmp_path):
    loop = ADMETAutoLoop(
        run_id="al13",
        params=ADMETParams(),
        output_dir=tmp_path,
        max_retries_per_phase=2,  # 3 total attempts
    )
    always_fail = {
        "herg_ic50_uM": 0.8,
        "dili_probability": 0.91,
        "dili_risk": "high",
        "ames_positive": True,
        "ames_probability": 0.88,
        "logP": 6.2,
        "mw": 620.0,
    }
    runner = MockPhaseRunner({
        "phase_2_admet_prediction": always_fail,
        "phase_3_herg_screen":      always_fail,
        "phase_4_dili_ames":        always_fail,
    })
    result = loop.run(runner)
    assert len(result.phases_escalated) > 0
    assert result.total_attempts >= 3  # at least 1 phase used all 3 attempts


# ── AL-14: Orchestrator — params are mutated across retries ──────────────────

def test_al14_params_mutated_across_retries(tmp_path):
    initial_logp = 5.0
    params = ADMETParams(logp_max=initial_logp)
    loop = ADMETAutoLoop(
        run_id="al14",
        params=params,
        output_dir=tmp_path,
        max_retries_per_phase=2,
    )
    runner = MockPhaseRunner({
        "phase_2_admet_prediction": [
            # Force hERG HALT twice so logP is reduced twice
            {"herg_ic50_uM": 3.5, "dili_probability": 0.1, "dili_risk": "low", "ames_positive": False, "ames_probability": 0.1, "logP": 3.0, "mw": 350.0},
            {"herg_ic50_uM": 3.5, "dili_probability": 0.1, "dili_risk": "low", "ames_positive": False, "ames_probability": 0.1, "logP": 3.0, "mw": 350.0},
            {"herg_ic50_uM": 18.0, "dili_probability": 0.1, "dili_risk": "low", "ames_positive": False, "ames_probability": 0.1, "logP": 2.5, "mw": 340.0},
        ],
        "phase_3_herg_screen": {"herg_ic50_uM": 18.0},
        "phase_4_dili_ames":   {"herg_ic50_uM": 18.0, "dili_probability": 0.1, "dili_risk": "low", "ames_positive": False, "ames_probability": 0.05},
    })
    loop.run(runner)
    # After 2 hERG HALTs, logp_max should be below initial
    assert loop.params.logp_max < initial_logp


# ── AL-15: AuditLogger — attempt lines written to JSONL ──────────────────────

def test_al15_audit_jsonl_written(tmp_path):
    loop = ADMETAutoLoop(run_id="al15", output_dir=tmp_path)
    clean = {"herg_ic50_uM": 45.0, "dili_probability": 0.1, "dili_risk": "low", "ames_positive": False, "ames_probability": 0.05, "logP": 2.4, "mw": 320.0}
    runner = MockPhaseRunner({
        "phase_2_admet_prediction": clean,
        "phase_3_herg_screen":      clean,
        "phase_4_dili_ames":        clean,
    })
    loop.run(runner)
    audit_file = tmp_path / "al15_audit.jsonl"
    assert audit_file.exists(), "JSONL audit file must exist"
    lines = audit_file.read_text().strip().split("\n")
    records = [json.loads(l) for l in lines if l]
    attempt_records = [r for r in records if r["event"] == "attempt"]
    phase_final_records = [r for r in records if r["event"] == "phase_final"]
    assert len(attempt_records) == 3   # 3 phases × 1 attempt each
    assert len(phase_final_records) == 3


# ── AL-16: AuditLogger — summary report contains pass/escalate counts ─────────

def test_al16_summary_report_contains_counts(tmp_path):
    loop = ADMETAutoLoop(run_id="al16", output_dir=tmp_path)
    always_fail = {"herg_ic50_uM": 0.8, "dili_probability": 0.9, "dili_risk": "high", "ames_positive": True, "ames_probability": 0.9, "logP": 6.0, "mw": 600.0}
    runner = MockPhaseRunner({
        "phase_2_admet_prediction": always_fail,
        "phase_3_herg_screen":      always_fail,
        "phase_4_dili_ames":        always_fail,
    })
    loop.run(runner)
    summary_file = tmp_path / "al16_summary.txt"
    assert summary_file.exists()
    text = summary_file.read_text()
    assert "Phases escalated:" in text
    assert "ADMET Auto-Loop Run:" in text


# ── AL-17: AuditLogger — param changes recorded in JSONL remediations ─────────

def test_al17_audit_records_param_changes(tmp_path):
    loop = ADMETAutoLoop(run_id="al17", output_dir=tmp_path, max_retries_per_phase=2)
    runner = MockPhaseRunner({
        "phase_2_admet_prediction": [
            {"herg_ic50_uM": 3.5, "dili_probability": 0.1, "dili_risk": "low", "ames_positive": False, "ames_probability": 0.1, "logP": 3.0, "mw": 350.0},
            {"herg_ic50_uM": 18.0, "dili_probability": 0.1, "dili_risk": "low", "ames_positive": False, "ames_probability": 0.1, "logP": 2.5, "mw": 340.0},
        ],
        "phase_3_herg_screen": {"herg_ic50_uM": 18.0},
        "phase_4_dili_ames":   {"herg_ic50_uM": 18.0, "dili_probability": 0.1, "dili_risk": "low", "ames_positive": False, "ames_probability": 0.05},
    })
    loop.run(runner)
    audit_lines = (tmp_path / "al17_audit.jsonl").read_text().strip().split("\n")
    attempt_records = [json.loads(l) for l in audit_lines if l and '"event": "attempt"' in l]
    # The first attempt should have hERG HALT + logp_max remediation
    first_attempt = next(r for r in attempt_records if r["attempt"] == 1 and r["phase"] == "phase_2_admet_prediction")
    assert first_attempt["outcome"] == "halt"
    assert any("logp_max" in r["param_changes"] for r in first_attempt["remediations"])


# ── AL-18: Scenario runner — hERG HALT then PASS ─────────────────────────────

def test_al18_scenario_herg_then_pass(tmp_path):
    loop = ADMETAutoLoop(run_id="al18", output_dir=tmp_path, max_retries_per_phase=2)
    runner = ScenarioRunner(SCENARIO_HERG_THEN_PASS)
    result = loop.run(runner.phase_runner)
    # hERG scenario: attempt 1 fails (IC50=3.5), attempt 2 passes (IC50=18.0)
    # So phase_2 should pass (after 2 attempts), rest should also pass
    assert "phase_2_admet_prediction" in result.phases_passed


# ── AL-19: Scenario runner — DILI HALT then PASS ─────────────────────────────

def test_al19_scenario_dili_then_pass(tmp_path):
    loop = ADMETAutoLoop(run_id="al19", output_dir=tmp_path, max_retries_per_phase=2)
    runner = ScenarioRunner(SCENARIO_DILI_THEN_PASS)
    result = loop.run(runner.phase_runner)
    assert "phase_2_admet_prediction" in result.phases_passed


# ── AL-20: Scenario runner — Ames HALT then PASS ─────────────────────────────

def test_al20_scenario_ames_then_pass(tmp_path):
    loop = ADMETAutoLoop(run_id="al20", output_dir=tmp_path, max_retries_per_phase=2)
    runner = ScenarioRunner(SCENARIO_AMES_THEN_PASS)
    result = loop.run(runner.phase_runner)
    assert "phase_4_dili_ames" in result.phases_passed


# ── AL-21: CNS profile — stricter TPSA + DILI thresholds ─────────────────────

def test_al21_cns_profile_stricter_dili(tmp_path):
    loop_std = ADMETAutoLoop(run_id="al21s", output_dir=tmp_path, qc_profile="admet_standard")
    loop_cns = ADMETAutoLoop(run_id="al21c", output_dir=tmp_path, qc_profile="admet_cns")
    # Metrics that pass standard but fail CNS (dili_prob=0.45 > cns max 0.4)
    borderline = {
        "herg_ic50_uM": 20.0,
        "dili_probability": 0.45,
        "dili_risk": "medium",
        "ames_positive": False,
        "ames_probability": 0.1,
        "logP": 2.5,
        "mw": 320.0,
    }
    evaluator_std = ADMETQCEvaluator("admet_standard")
    evaluator_cns = ADMETQCEvaluator("admet_cns")
    result_std = evaluator_std.evaluate_phase_2(borderline)
    result_cns = evaluator_cns.evaluate_phase_2(borderline)
    # CNS should fail (dili_prob 0.45 > 0.4); standard should pass
    assert result_std.passed, "Standard profile should pass at dili_prob=0.45"
    assert not result_cns.passed, "CNS profile should fail at dili_prob=0.45 (max=0.4)"


# ── AL-22: Oncology profile — higher DILI tolerance ──────────────────────────

def test_al22_oncology_profile_higher_dili_tolerance():
    evaluator = ADMETQCEvaluator("admet_oncology")
    metrics = {
        "herg_ic50_uM": 20.0,
        "dili_probability": 0.55,  # > standard (0.5) but ≤ oncology (0.6)
        "dili_risk": "high",       # oncology allows "high"
        "ames_positive": False,
        "ames_probability": 0.1,
        "logP": 3.0,
        "mw": 420.0,
    }
    result = evaluator.evaluate_phase_2(metrics)
    # Oncology max DILI prob = 0.6 and allows "high" risk → should pass
    halts = [g.gate for g in result.halts]
    assert "dili_probability" not in halts, "Oncology profile should not halt at dili_prob=0.55"
    assert "dili_risk_level" not in halts,  "Oncology profile should allow 'high' DILI risk"


# ── AL-23: Unknown profile raises ValueError ─────────────────────────────────

def test_al23_unknown_profile_raises():
    with pytest.raises(ValueError, match="Unknown QC profile"):
        ADMETQCEvaluator(profile="nonexistent_profile")


# ── AL-24: Full scenario — multi-gate failure resolves in 3 attempts ──────────

def test_al24_multi_gate_resolves_in_3_attempts(tmp_path):
    loop = ADMETAutoLoop(
        run_id="al24",
        params=ADMETParams(),
        output_dir=tmp_path,
        max_retries_per_phase=2,   # max 3 attempts
    )
    runner = ScenarioRunner(SCENARIO_MULTI_GATE)
    result = loop.run(runner.phase_runner)
    # SCENARIO_MULTI_GATE: attempt 1 = hERG+DILI fail, attempt 2 = hERG only fail,
    # attempt 3 = all pass → phase_2 should pass, total attempts ≥ 3
    assert result.total_attempts >= 3
    assert len(result.phases_passed) >= 1, "At least one phase should pass"
    # Verify param was mutated (logP reduced from default 5.0)
    assert loop.params.logp_max < 5.0, "logP should have been reduced by remediations"
