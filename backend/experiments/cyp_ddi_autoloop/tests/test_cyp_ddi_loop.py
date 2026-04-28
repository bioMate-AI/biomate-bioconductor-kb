"""
CYP DDI auto-loop unit tests (CD-1 to CD-24).

FDA DDI guidance (2020):
  R1 ≥ 1.02 → INVESTIGATE; R1 ≥ 1.1 → CLINICAL_STUDY_RECOMMENDED
  R2 ≤ 0.79 → INVESTIGATE; R2 ≤ 0.71 → CLINICAL_STUDY_RECOMMENDED

Tests:
  CD-1  to CD-6:  QC evaluator gate logic
  CD-7  to CD-10: ParamTuner remediation
  CD-11 to CD-14: Orchestrator retry/escalation
  CD-15 to CD-17: AuditLogger output
  CD-18 to CD-21: Scenario runners
  CD-22 to CD-24: Profile variants + edge cases
"""
import json
import pytest
from ..params import CYPDDIParams
from ..qc_evaluator import CYPDDIQCEvaluator, QCAction, QCLevel
from ..param_tuner import CYPDDIParamTuner
from ..orchestrator import CYPDDIAutoLoop, MockPhaseRunner
from ..simulation import (
    ScenarioRunner,
    SCENARIO_CLINICAL_THEN_PASS,
    SCENARIO_INVESTIGATE_THEN_PASS,
    SCENARIO_CLEAN_PASS,
    SCENARIO_PERSISTENT_FAIL,
)

CLEAN = {"summary": {"n_clinical": 0, "n_investigate": 0, "n_tdi": 0,
                     "overall_recommendation": "NOT_EXPECTED"}}
CLINICAL_1 = {"summary": {"n_clinical": 1, "n_investigate": 2, "n_tdi": 0,
                           "overall_recommendation": "CLINICAL_STUDY_RECOMMENDED"}}
INVESTIGATE_3 = {"summary": {"n_clinical": 0, "n_investigate": 3, "n_tdi": 1,
                              "overall_recommendation": "INVESTIGATE"}}


# ── CD-1: CLINICAL_STUDY gate — HALT when n_clinical > 0 ─────────────────────
def test_cd1_clinical_halt(tmp_path):
    ev = CYPDDIQCEvaluator("cyp_ddi_standard")
    result = ev.evaluate_phase_2(CLINICAL_1)
    assert not result.passed
    halt_gates = [g.gate for g in result.halts]
    assert "clinical_study_isoforms" in halt_gates


# ── CD-2: clean pass — no INVESTIGATE or CLINICAL flags ──────────────────────
def test_cd2_clean_pass():
    ev = CYPDDIQCEvaluator("cyp_ddi_standard")
    result = ev.evaluate_phase_2(CLEAN)
    assert result.passed
    assert result.overall_level == QCLevel.GOLD


# ── CD-3: INVESTIGATE gate — HALT when n_investigate > max ───────────────────
def test_cd3_investigate_halt():
    ev = CYPDDIQCEvaluator("cyp_ddi_standard")  # max_investigate = 2
    result = ev.evaluate_phase_2(INVESTIGATE_3)  # n_investigate=3 > 2
    halt_gates = [g.gate for g in result.halts]
    assert "investigate_isoforms" in halt_gates


# ── CD-4: strict profile — 0 INVESTIGATE allowed ─────────────────────────────
def test_cd4_strict_investigate_halts():
    ev = CYPDDIQCEvaluator("cyp_ddi_strict")
    metrics = {"summary": {"n_clinical": 0, "n_investigate": 1, "n_tdi": 0,
                           "overall_recommendation": "INVESTIGATE"}}
    result = ev.evaluate_phase_2(metrics)
    assert not result.passed, "Strict: 1 INVESTIGATE should HALT"


# ── CD-5: TDI advisory — passes phase but gate is advisory ───────────────────
def test_cd5_tdi_advisory():
    ev = CYPDDIQCEvaluator("cyp_ddi_standard")
    metrics = {"summary": {"n_clinical": 0, "n_investigate": 0, "n_tdi": 2,
                           "overall_recommendation": "NOT_EXPECTED"}}
    result = ev.evaluate_phase_2(metrics)
    assert result.passed, "TDI advisory should not HALT"
    tdi_gate = next(g for g in result.gate_results if g.gate == "tdi_concern")
    assert tdi_gate.action == QCAction.ADVISORY


# ── CD-6: unknown profile raises ValueError ───────────────────────────────────
def test_cd6_unknown_profile():
    with pytest.raises(ValueError, match="Unknown QC profile"):
        CYPDDIQCEvaluator("nonexistent")


# ── CD-7: tuner CLINICAL HALT — halves cmax_ss_uM ────────────────────────────
def test_cd7_tuner_clinical_halves_cmax():
    ev = CYPDDIQCEvaluator("cyp_ddi_standard")
    tuner = CYPDDIParamTuner()
    params = CYPDDIParams(cmax_ss_uM=2.0)
    qc = ev.evaluate_phase_2(CLINICAL_1)
    new_params, rems = tuner.remediate(qc, params)
    assert new_params.cmax_ss_uM < params.cmax_ss_uM
    assert abs(new_params.cmax_ss_uM - 1.0) < 1e-9  # 2.0 × 0.5
    assert any(r.gate == "clinical_study_isoforms" for r in rems)
    assert "R1" in rems[0].rationale or "Cmax" in rems[0].rationale


# ── CD-8: tuner INVESTIGATE HALT — reduces cmax by 30% ───────────────────────
def test_cd8_tuner_investigate_reduces_cmax():
    ev = CYPDDIQCEvaluator("cyp_ddi_standard")
    tuner = CYPDDIParamTuner()
    params = CYPDDIParams(cmax_ss_uM=2.0)
    qc = ev.evaluate_phase_2(INVESTIGATE_3)
    new_params, rems = tuner.remediate(qc, params)
    assert abs(new_params.cmax_ss_uM - 1.4) < 0.01   # 2.0 × 0.7
    assert any(r.gate == "investigate_isoforms" for r in rems)


# ── CD-9: tuner unknown gate → advisory remediation ──────────────────────────
def test_cd9_tuner_unknown_gate():
    from ..qc_evaluator import PhaseQCResult, GateResult
    tuner = CYPDDIParamTuner()
    fake = GateResult(gate="unknown_gate", action=QCAction.HALT, level=QCLevel.FAIL,
                      value=1.0, threshold=0.0, message="fake")
    from ..qc_evaluator import PhaseQCResult
    fake_qc = PhaseQCResult(phase="phase_2_ddi_risk", gate_results=[fake])
    params = CYPDDIParams()
    new_params, rems = tuner.remediate(fake_qc, params)
    assert rems[0].param_changes == {}
    assert "manual review" in rems[0].rationale


# ── CD-10: params copy is independent ────────────────────────────────────────
def test_cd10_params_copy_independent():
    p1 = CYPDDIParams(cmax_ss_uM=1.5)
    p2 = p1.copy()
    p2.cmax_ss_uM = 3.0
    assert p1.cmax_ss_uM == 1.5


# ── CD-11: orchestrator clean pass ───────────────────────────────────────────
def test_cd11_orchestrator_clean_pass(tmp_path):
    loop = CYPDDIAutoLoop(run_id="cd11", output_dir=tmp_path)
    runner = MockPhaseRunner({"phase_2_ddi_risk": CLEAN})
    result = loop.run(runner)
    assert result.phases_passed == ["phase_2_ddi_risk"]
    assert result.phases_escalated == []


# ── CD-12: orchestrator CLINICAL HALT then pass ───────────────────────────────
def test_cd12_orchestrator_clinical_retry(tmp_path):
    loop = CYPDDIAutoLoop(run_id="cd12", output_dir=tmp_path, max_retries_per_phase=2)
    runner = MockPhaseRunner({"phase_2_ddi_risk": [CLINICAL_1, CLEAN]})
    result = loop.run(runner)
    assert "phase_2_ddi_risk" in result.phases_passed
    assert result.total_attempts == 2


# ── CD-13: orchestrator escalates on persistent fail ─────────────────────────
def test_cd13_orchestrator_escalates(tmp_path):
    loop = CYPDDIAutoLoop(run_id="cd13", output_dir=tmp_path, max_retries_per_phase=2)
    always_fail = {"summary": {"n_clinical": 3, "n_investigate": 4, "n_tdi": 2,
                               "overall_recommendation": "CLINICAL_STUDY_RECOMMENDED"}}
    runner = MockPhaseRunner({"phase_2_ddi_risk": always_fail})
    result = loop.run(runner)
    assert len(result.phases_escalated) > 0
    assert result.total_attempts == 3


# ── CD-14: cmax_ss_uM mutated across retries ─────────────────────────────────
def test_cd14_cmax_mutated(tmp_path):
    initial_cmax = 4.0
    loop = CYPDDIAutoLoop(run_id="cd14", params=CYPDDIParams(cmax_ss_uM=initial_cmax),
                           output_dir=tmp_path, max_retries_per_phase=2)
    runner = MockPhaseRunner({"phase_2_ddi_risk": [CLINICAL_1, CLINICAL_1, CLEAN]})
    loop.run(runner)
    assert loop.params.cmax_ss_uM < initial_cmax


# ── CD-15: audit JSONL written ────────────────────────────────────────────────
def test_cd15_audit_jsonl(tmp_path):
    loop = CYPDDIAutoLoop(run_id="cd15", output_dir=tmp_path)
    runner = MockPhaseRunner({"phase_2_ddi_risk": CLEAN})
    loop.run(runner)
    audit = tmp_path / "cd15_audit.jsonl"
    assert audit.exists()
    records = [json.loads(l) for l in audit.read_text().strip().split("\n") if l]
    assert any(r["event"] == "attempt" for r in records)
    assert any(r["event"] == "phase_final" for r in records)


# ── CD-16: summary report written ────────────────────────────────────────────
def test_cd16_summary_report(tmp_path):
    loop = CYPDDIAutoLoop(run_id="cd16", output_dir=tmp_path)
    runner = MockPhaseRunner({"phase_2_ddi_risk": CLEAN})
    loop.run(runner)
    summary = tmp_path / "cd16_summary.txt"
    assert summary.exists()
    assert "cd16" in summary.read_text()


# ── CD-17: audit records param changes ───────────────────────────────────────
def test_cd17_audit_param_changes(tmp_path):
    loop = CYPDDIAutoLoop(run_id="cd17", output_dir=tmp_path, max_retries_per_phase=2)
    runner = MockPhaseRunner({"phase_2_ddi_risk": [CLINICAL_1, CLEAN]})
    loop.run(runner)
    records = [json.loads(l) for l in (tmp_path / "cd17_audit.jsonl").read_text().strip().split("\n") if l]
    attempt1 = next(r for r in records if r["event"] == "attempt" and r["attempt"] == 1)
    assert attempt1["outcome"] == "halt"
    assert any("cmax_ss_uM" in r["param_changes"] for r in attempt1["remediations"])


# ── CD-18: scenario clinical then pass ───────────────────────────────────────
def test_cd18_scenario_clinical_then_pass(tmp_path):
    loop = CYPDDIAutoLoop(run_id="cd18", output_dir=tmp_path, max_retries_per_phase=2)
    result = loop.run(ScenarioRunner(SCENARIO_CLINICAL_THEN_PASS).phase_runner)
    assert "phase_2_ddi_risk" in result.phases_passed


# ── CD-19: scenario investigate then pass ────────────────────────────────────
def test_cd19_scenario_investigate_then_pass(tmp_path):
    loop = CYPDDIAutoLoop(run_id="cd19", output_dir=tmp_path, max_retries_per_phase=2)
    result = loop.run(ScenarioRunner(SCENARIO_INVESTIGATE_THEN_PASS).phase_runner)
    assert "phase_2_ddi_risk" in result.phases_passed


# ── CD-20: scenario clean pass on first attempt ──────────────────────────────
def test_cd20_scenario_clean_pass(tmp_path):
    loop = CYPDDIAutoLoop(run_id="cd20", output_dir=tmp_path)
    result = loop.run(ScenarioRunner(SCENARIO_CLEAN_PASS).phase_runner)
    assert result.total_attempts == 1


# ── CD-21: scenario persistent fail escalates ────────────────────────────────
def test_cd21_scenario_persistent_fail(tmp_path):
    loop = CYPDDIAutoLoop(run_id="cd21", output_dir=tmp_path, max_retries_per_phase=2)
    result = loop.run(ScenarioRunner(SCENARIO_PERSISTENT_FAIL).phase_runner)
    assert len(result.phases_escalated) == 1


# ── CD-22: oncology profile tolerates 1 CLINICAL isoform ─────────────────────
def test_cd22_oncology_allows_one_clinical():
    ev = CYPDDIQCEvaluator("cyp_ddi_oncology")
    result = ev.evaluate_phase_2(CLINICAL_1)  # n_clinical=1, max=1 in oncology
    assert result.passed, "Oncology allows 1 CLINICAL isoform"


# ── CD-23: strict profile fails even 1 INVESTIGATE ───────────────────────────
def test_cd23_strict_no_investigate():
    ev = CYPDDIQCEvaluator("cyp_ddi_strict")
    result = ev.evaluate_phase_2({"summary": {"n_clinical": 0, "n_investigate": 1,
                                              "n_tdi": 0, "overall_recommendation": "INVESTIGATE"}})
    assert not result.passed


# ── CD-24: evaluate_phase dispatches correctly ────────────────────────────────
def test_cd24_evaluate_phase_dispatch():
    ev = CYPDDIQCEvaluator()
    result = ev.evaluate_phase("phase_2_ddi_risk", CLEAN)
    assert result.phase == "phase_2_ddi_risk"
    with pytest.raises(ValueError):
        ev.evaluate_phase("phase_99_unknown", {})
