"""
NCA PK auto-loop unit tests (NCA-1 to NCA-24).

FDA guidance: AUCinf extrapolation > 20% → unreliable; extend sampling.

Tests:
  NCA-1  to NCA-6:  QC evaluator gate logic
  NCA-7  to NCA-10: ParamTuner remediation
  NCA-11 to NCA-14: Orchestrator retry/escalation
  NCA-15 to NCA-17: AuditLogger output
  NCA-18 to NCA-21: Scenario runners
  NCA-22 to NCA-24: Profile variants + edge cases
"""
import json
import pytest
from ..params import NCAPKParams
from ..qc_evaluator import NCAPKQCEvaluator, QCAction, QCLevel
from ..param_tuner import NCAPKParamTuner
from ..orchestrator import NCAPKAutoLoop, MockPhaseRunner
from ..simulation import (
    ScenarioRunner,
    SCENARIO_HIGH_EXTRAP_THEN_PASS,
    SCENARIO_NO_SLOPE_THEN_PASS,
    SCENARIO_CLEAN_PASS,
    SCENARIO_PERSISTENT_FAIL,
)

CLEAN = {"population_summary": {"auc_extrap_pct": 8.0, "subjects_with_no_terminal_slope": 0,
                                  "t_half_mean": 5.0, "auc_last_mean": 910.0,
                                  "auc_inf_mean": 994.0, "cmax_mean": 150.0}}
HIGH_EXTRAP = {"population_summary": {"auc_extrap_pct": 35.0, "subjects_with_no_terminal_slope": 0,
                                       "t_half_mean": 8.0, "auc_last_mean": 650.0,
                                       "auc_inf_mean": 1000.0, "cmax_mean": 120.0}}
NO_SLOPE = {"population_summary": {"auc_extrap_pct": 12.0, "subjects_with_no_terminal_slope": 4,
                                    "t_half_mean": 5.0, "auc_last_mean": 820.0,
                                    "auc_inf_mean": 1000.0, "cmax_mean": 200.0}}


# ── NCA-1: AUC extrap HALT > 20% ─────────────────────────────────────────────
def test_nca1_extrap_halt():
    ev = NCAPKQCEvaluator("nca_standard")
    result = ev.evaluate_phase_1(HIGH_EXTRAP)
    assert not result.passed
    assert "auc_extrapolation" in [g.gate for g in result.halts]


# ── NCA-2: Clean pass ─────────────────────────────────────────────────────────
def test_nca2_clean_pass():
    ev = NCAPKQCEvaluator("nca_standard")
    result = ev.evaluate_phase_1(CLEAN)
    assert result.passed
    assert result.overall_level in (QCLevel.GOLD, QCLevel.SILVER)


# ── NCA-3: terminal slope HALT > max ─────────────────────────────────────────
def test_nca3_no_slope_halt():
    ev = NCAPKQCEvaluator("nca_standard")  # max = 2
    result = ev.evaluate_phase_1(NO_SLOPE)  # n=4
    assert not result.passed
    assert "terminal_slope_coverage" in [g.gate for g in result.halts]


# ── NCA-4: advisory band — extrap at 18% (< 20%) → advisory not HALT ─────────
def test_nca4_advisory_near_threshold():
    ev = NCAPKQCEvaluator("nca_standard")
    metrics = {"population_summary": {"auc_extrap_pct": 18.0, "subjects_with_no_terminal_slope": 0,
                                       "t_half_mean": 5.0, "auc_last_mean": 820.0,
                                       "auc_inf_mean": 1000.0, "cmax_mean": 200.0}}
    result = ev.evaluate_phase_1(metrics)
    assert result.passed, "18% < 20% → should pass (advisory only)"
    extrap_gate = next(g for g in result.gate_results if g.gate == "auc_extrapolation")
    assert extrap_gate.action in (QCAction.PASS, QCAction.ADVISORY)


# ── NCA-5: regulatory profile stricter (max 15%) ─────────────────────────────
def test_nca5_regulatory_stricter():
    ev_std = NCAPKQCEvaluator("nca_standard")
    ev_reg = NCAPKQCEvaluator("nca_regulatory")
    metrics = {"population_summary": {"auc_extrap_pct": 18.0,
                                       "subjects_with_no_terminal_slope": 0,
                                       "t_half_mean": 5.0, "auc_last_mean": 820.0,
                                       "auc_inf_mean": 1000.0, "cmax_mean": 200.0}}
    assert ev_std.evaluate_phase_1(metrics).passed    # 18% < 20% → pass standard
    assert not ev_reg.evaluate_phase_1(metrics).passed  # 18% > 15% → fail regulatory


# ── NCA-6: unknown profile raises ValueError ─────────────────────────────────
def test_nca6_unknown_profile():
    with pytest.raises(ValueError, match="Unknown QC profile"):
        NCAPKQCEvaluator("nonexistent")


# ── NCA-7: tuner extrap HALT → extends last_sampling_time_h 1.5× ─────────────
def test_nca7_tuner_extends_sampling():
    ev = NCAPKQCEvaluator("nca_standard")
    tuner = NCAPKParamTuner()
    params = NCAPKParams(last_sampling_time_h=24.0)
    qc = ev.evaluate_phase_1(HIGH_EXTRAP)
    new_params, rems = tuner.remediate(qc, params)
    assert abs(new_params.last_sampling_time_h - 36.0) < 0.1  # 24 × 1.5
    assert any(r.gate == "auc_extrapolation" for r in rems)
    assert "×1.5" in rems[0].rationale or "1.5" in rems[0].rationale


# ── NCA-8: tuner terminal slope HALT → adds points + extends window ───────────
def test_nca8_tuner_slope_adds_points():
    ev = NCAPKQCEvaluator("nca_standard")
    tuner = NCAPKParamTuner()
    params = NCAPKParams(terminal_phase_points=3, last_sampling_time_h=24.0)
    qc = ev.evaluate_phase_1(NO_SLOPE)
    new_params, rems = tuner.remediate(qc, params)
    assert new_params.terminal_phase_points == 5   # 3 + 2
    assert new_params.last_sampling_time_h > params.last_sampling_time_h


# ── NCA-9: sampling window cap at MAX_LAST_SAMPLING_H ────────────────────────
def test_nca9_sampling_cap():
    ev = NCAPKQCEvaluator("nca_standard")
    tuner = NCAPKParamTuner()
    params = NCAPKParams(last_sampling_time_h=120.0)
    qc = ev.evaluate_phase_1(HIGH_EXTRAP)
    new_params, _ = tuner.remediate(qc, params)
    assert new_params.last_sampling_time_h <= 168.0


# ── NCA-10: params copy independent ──────────────────────────────────────────
def test_nca10_params_copy():
    p = NCAPKParams(last_sampling_time_h=24.0)
    p2 = p.copy()
    p2.last_sampling_time_h = 48.0
    assert p.last_sampling_time_h == 24.0


# ── NCA-11: orchestrator clean pass ──────────────────────────────────────────
def test_nca11_clean_pass(tmp_path):
    loop = NCAPKAutoLoop(run_id="nca11", output_dir=tmp_path)
    runner = MockPhaseRunner({"phase_1_nca_analysis": CLEAN})
    result = loop.run(runner)
    assert result.phases_passed == ["phase_1_nca_analysis"]


# ── NCA-12: orchestrator extrap HALT then pass ────────────────────────────────
def test_nca12_retry_then_pass(tmp_path):
    loop = NCAPKAutoLoop(run_id="nca12", output_dir=tmp_path, max_retries_per_phase=2)
    runner = MockPhaseRunner({"phase_1_nca_analysis": [HIGH_EXTRAP, CLEAN]})
    result = loop.run(runner)
    assert "phase_1_nca_analysis" in result.phases_passed
    assert result.total_attempts == 2


# ── NCA-13: orchestrator escalates on persistent fail ────────────────────────
def test_nca13_escalates(tmp_path):
    loop = NCAPKAutoLoop(run_id="nca13", output_dir=tmp_path, max_retries_per_phase=2)
    always_fail = {"population_summary": {"auc_extrap_pct": 55.0,
                                           "subjects_with_no_terminal_slope": 5,
                                           "t_half_mean": 2.0, "auc_last_mean": 450.0,
                                           "auc_inf_mean": 1000.0, "cmax_mean": 200.0}}
    runner = MockPhaseRunner({"phase_1_nca_analysis": always_fail})
    result = loop.run(runner)
    assert len(result.phases_escalated) == 1
    assert result.total_attempts == 3


# ── NCA-14: last_sampling_time_h mutated across retries ──────────────────────
def test_nca14_sampling_grows(tmp_path):
    initial = 24.0
    loop = NCAPKAutoLoop(run_id="nca14", params=NCAPKParams(last_sampling_time_h=initial),
                          output_dir=tmp_path, max_retries_per_phase=2)
    runner = MockPhaseRunner({"phase_1_nca_analysis": [HIGH_EXTRAP, HIGH_EXTRAP, CLEAN]})
    loop.run(runner)
    assert loop.params.last_sampling_time_h > initial


# ── NCA-15: audit JSONL written ───────────────────────────────────────────────
def test_nca15_audit_written(tmp_path):
    loop = NCAPKAutoLoop(run_id="nca15", output_dir=tmp_path)
    runner = MockPhaseRunner({"phase_1_nca_analysis": CLEAN})
    loop.run(runner)
    audit = tmp_path / "nca15_audit.jsonl"
    assert audit.exists()
    lines = [json.loads(l) for l in audit.read_text().strip().split("\n") if l]
    assert any(r["event"] == "attempt" for r in lines)
    assert any(r["event"] == "phase_final" for r in lines)


# ── NCA-16: summary report written ───────────────────────────────────────────
def test_nca16_summary_written(tmp_path):
    loop = NCAPKAutoLoop(run_id="nca16", output_dir=tmp_path)
    loop.run(MockPhaseRunner({"phase_1_nca_analysis": CLEAN}))
    assert (tmp_path / "nca16_summary.txt").exists()


# ── NCA-17: audit records param changes ──────────────────────────────────────
def test_nca17_audit_param_changes(tmp_path):
    loop = NCAPKAutoLoop(run_id="nca17", output_dir=tmp_path, max_retries_per_phase=2)
    runner = MockPhaseRunner({"phase_1_nca_analysis": [HIGH_EXTRAP, CLEAN]})
    loop.run(runner)
    lines = [json.loads(l) for l in (tmp_path / "nca17_audit.jsonl").read_text().strip().split("\n") if l]
    attempt1 = next(r for r in lines if r["event"] == "attempt" and r["attempt"] == 1)
    assert attempt1["outcome"] == "halt"
    assert any("last_sampling_time_h" in r["param_changes"] for r in attempt1["remediations"])


# ── NCA-18: scenario high extrap then pass ───────────────────────────────────
def test_nca18_high_extrap_then_pass(tmp_path):
    loop = NCAPKAutoLoop(run_id="nca18", output_dir=tmp_path, max_retries_per_phase=2)
    result = loop.run(ScenarioRunner(SCENARIO_HIGH_EXTRAP_THEN_PASS).phase_runner)
    assert "phase_1_nca_analysis" in result.phases_passed


# ── NCA-19: scenario no-slope then pass ──────────────────────────────────────
def test_nca19_no_slope_then_pass(tmp_path):
    loop = NCAPKAutoLoop(run_id="nca19", output_dir=tmp_path, max_retries_per_phase=2)
    result = loop.run(ScenarioRunner(SCENARIO_NO_SLOPE_THEN_PASS).phase_runner)
    assert "phase_1_nca_analysis" in result.phases_passed


# ── NCA-20: scenario clean pass on first attempt ─────────────────────────────
def test_nca20_clean_first_attempt(tmp_path):
    loop = NCAPKAutoLoop(run_id="nca20", output_dir=tmp_path)
    result = loop.run(ScenarioRunner(SCENARIO_CLEAN_PASS).phase_runner)
    assert result.total_attempts == 1


# ── NCA-21: scenario persistent fail escalates ───────────────────────────────
def test_nca21_persistent_fail(tmp_path):
    loop = NCAPKAutoLoop(run_id="nca21", output_dir=tmp_path, max_retries_per_phase=2)
    result = loop.run(ScenarioRunner(SCENARIO_PERSISTENT_FAIL).phase_runner)
    assert len(result.phases_escalated) == 1


# ── NCA-22: exploratory profile allows 30% extrap ────────────────────────────
def test_nca22_exploratory_allows_30pct():
    ev = NCAPKQCEvaluator("nca_exploratory")
    metrics = {"population_summary": {"auc_extrap_pct": 28.0,
                                       "subjects_with_no_terminal_slope": 0,
                                       "t_half_mean": 4.0, "auc_last_mean": 720.0,
                                       "auc_inf_mean": 1000.0, "cmax_mean": 100.0}}
    assert ev.evaluate_phase_1(metrics).passed, "Exploratory allows 28% < 30%"


# ── NCA-23: regulatory profile fails 18% extrap ──────────────────────────────
def test_nca23_regulatory_fails_18pct():
    ev = NCAPKQCEvaluator("nca_regulatory")
    metrics = {"population_summary": {"auc_extrap_pct": 18.0,
                                       "subjects_with_no_terminal_slope": 0,
                                       "t_half_mean": 5.0, "auc_last_mean": 820.0,
                                       "auc_inf_mean": 1000.0, "cmax_mean": 200.0}}
    assert not ev.evaluate_phase_1(metrics).passed, "Regulatory 18% > 15% → HALT"


# ── NCA-24: evaluate_phase dispatch + unknown phase raises ───────────────────
def test_nca24_evaluate_phase_dispatch():
    ev = NCAPKQCEvaluator()
    result = ev.evaluate_phase("phase_1_nca_analysis", CLEAN)
    assert result.phase == "phase_1_nca_analysis"
    with pytest.raises(ValueError):
        ev.evaluate_phase("phase_99_unknown", {})
