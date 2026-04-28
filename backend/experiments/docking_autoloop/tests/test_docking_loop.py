"""
Docking auto-loop unit tests (DK-1 to DK-24).

Hit thresholds:
  Vina: binding_affinity < -7 kcal/mol = hit
  Glide: GlideScore < -6 (SP), < -8 (XP/lead opt)

Tests:
  DK-1  to DK-6:  QC evaluator gate logic
  DK-7  to DK-10: ParamTuner remediation
  DK-11 to DK-14: Orchestrator retry/escalation
  DK-15 to DK-17: AuditLogger output
  DK-18 to DK-21: Scenario runners
  DK-22 to DK-24: Profile variants + Glide support
"""
import json
import pytest
from ..params import DockingParams
from ..qc_evaluator import DockingQCEvaluator, QCAction, QCLevel
from ..param_tuner import DockingParamTuner
from ..orchestrator import DockingAutoLoop, MockPhaseRunner
from ..simulation import (
    ScenarioRunner,
    SCENARIO_WEAK_THEN_HIT,
    SCENARIO_NO_POSES_THEN_HIT,
    SCENARIO_STRONG_HIT,
    SCENARIO_PERSISTENT_FAIL,
    SCENARIO_CLEAN_PASS,
)

STRONG_HIT = {"success": True, "best_score_kcal_mol": -9.2, "n_ligands_docked": 10, "mean_score": -7.5}
WEAK_SCORE = {"success": True, "best_score_kcal_mol": -5.0, "n_ligands_docked": 10, "mean_score": -4.0}
NO_POSES   = {"success": False, "best_score_kcal_mol": 0.0,  "n_ligands_docked":  0, "mean_score": 0.0}


# ── DK-1: binding score HALT — score above threshold ─────────────────────────
def test_dk1_binding_score_halt():
    ev = DockingQCEvaluator("docking_hit_finding")
    result = ev.evaluate_phase_1(WEAK_SCORE)
    halt_gates = [g.gate for g in result.halts]
    assert "best_binding_score" in halt_gates


# ── DK-2: strong hit passes ───────────────────────────────────────────────────
def test_dk2_strong_hit_passes():
    ev = DockingQCEvaluator("docking_hit_finding")
    result = ev.evaluate_phase_1(STRONG_HIT)
    assert result.passed
    assert result.overall_level in (QCLevel.GOLD, QCLevel.SILVER)


# ── DK-3: no poses HALT ───────────────────────────────────────────────────────
def test_dk3_no_poses_halt():
    ev = DockingQCEvaluator("docking_hit_finding")
    result = ev.evaluate_phase_1(NO_POSES)
    assert not result.passed
    halt_gates = [g.gate for g in result.halts]
    assert "valid_poses" in halt_gates


# ── DK-4: fragment profile — weaker threshold ─────────────────────────────────
def test_dk4_fragment_profile_weak_threshold():
    ev_hit  = DockingQCEvaluator("docking_hit_finding")
    ev_frag = DockingQCEvaluator("docking_fragment")
    score_5_2 = {"success": True, "best_score_kcal_mol": -5.2, "n_ligands_docked": 5, "mean_score": -4.5}
    assert not ev_hit.evaluate_phase_1(score_5_2).passed    # -5.2 > -7 → HALT
    assert ev_frag.evaluate_phase_1(score_5_2).passed       # -5.2 < -5 → PASS


# ── DK-5: lead-opt profile — stricter threshold ───────────────────────────────
def test_dk5_lead_opt_stricter():
    ev = DockingQCEvaluator("docking_lead_opt")
    score_7_5 = {"success": True, "best_score_kcal_mol": -7.5, "n_ligands_docked": 8, "mean_score": -6.0}
    result = ev.evaluate_phase_1(score_7_5)
    # -7.5 > -8 threshold → HALT
    assert not result.passed


# ── DK-6: unknown profile raises ValueError ───────────────────────────────────
def test_dk6_unknown_profile():
    with pytest.raises(ValueError, match="Unknown QC profile"):
        DockingQCEvaluator("nonexistent")


# ── DK-7: tuner no-poses HALT → expands box + doubles exhaustiveness ──────────
def test_dk7_tuner_no_poses_expands_box():
    ev = DockingQCEvaluator()
    tuner = DockingParamTuner()
    params = DockingParams(exhaustiveness=8, center_box_expand_A=0.0)
    qc = ev.evaluate_phase_1(NO_POSES)
    new_params, rems = tuner.remediate(qc, params)
    # Both valid_poses and best_binding_score HALT on NO_POSES; exhaustiveness
    # increases via both handlers stacking, box expands via valid_poses handler.
    assert new_params.exhaustiveness > params.exhaustiveness
    assert new_params.center_box_expand_A == 1.0   # from valid_poses handler
    assert any(r.gate == "valid_poses" for r in rems)


# ── DK-8: tuner weak score → increases exhaustiveness ────────────────────────
def test_dk8_tuner_weak_score_increases_exhaustiveness():
    ev = DockingQCEvaluator()
    tuner = DockingParamTuner()
    params = DockingParams(exhaustiveness=8)
    qc = ev.evaluate_phase_1(WEAK_SCORE)
    new_params, rems = tuner.remediate(qc, params)
    assert new_params.exhaustiveness > params.exhaustiveness
    assert any(r.gate == "best_binding_score" for r in rems)


# ── DK-9: tuner SP→XP upgrade for Glide ──────────────────────────────────────
def test_dk9_tuner_glide_sp_upgrades_to_xp():
    ev = DockingQCEvaluator()
    tuner = DockingParamTuner()
    params = DockingParams(docking_precision="SP", exhaustiveness=8)
    qc = ev.evaluate_phase_1(WEAK_SCORE)
    new_params, rems = tuner.remediate(qc, params)
    assert new_params.docking_precision == "XP"
    assert "XP" in rems[-1].rationale


# ── DK-10: tuner cap at MAX_EXHAUSTIVENESS ───────────────────────────────────
def test_dk10_exhaustiveness_cap():
    ev = DockingQCEvaluator()
    tuner = DockingParamTuner()
    params = DockingParams(exhaustiveness=28)
    qc = ev.evaluate_phase_1(WEAK_SCORE)
    new_params, _ = tuner.remediate(qc, params)
    assert new_params.exhaustiveness <= 32


# ── DK-11: orchestrator clean pass ───────────────────────────────────────────
def test_dk11_clean_pass(tmp_path):
    loop = DockingAutoLoop(run_id="dk11", output_dir=tmp_path)
    runner = MockPhaseRunner({"phase_1_docking": STRONG_HIT})
    result = loop.run(runner)
    assert result.phases_passed == ["phase_1_docking"]


# ── DK-12: orchestrator weak score → hit on retry ────────────────────────────
def test_dk12_retry_then_hit(tmp_path):
    loop = DockingAutoLoop(run_id="dk12", output_dir=tmp_path, max_retries_per_phase=2)
    runner = MockPhaseRunner({"phase_1_docking": [WEAK_SCORE, STRONG_HIT]})
    result = loop.run(runner)
    assert "phase_1_docking" in result.phases_passed
    assert result.total_attempts == 2


# ── DK-13: orchestrator escalates on persistent fail ─────────────────────────
def test_dk13_escalates(tmp_path):
    loop = DockingAutoLoop(run_id="dk13", output_dir=tmp_path, max_retries_per_phase=2)
    runner = MockPhaseRunner({"phase_1_docking": NO_POSES})
    result = loop.run(runner)
    assert len(result.phases_escalated) == 1
    assert result.total_attempts == 3


# ── DK-14: exhaustiveness increases across retries ───────────────────────────
def test_dk14_exhaustiveness_grows(tmp_path):
    initial = 8
    loop = DockingAutoLoop(run_id="dk14", params=DockingParams(exhaustiveness=initial),
                            output_dir=tmp_path, max_retries_per_phase=2)
    runner = MockPhaseRunner({"phase_1_docking": [WEAK_SCORE, WEAK_SCORE, STRONG_HIT]})
    loop.run(runner)
    assert loop.params.exhaustiveness > initial


# ── DK-15: audit JSONL written ────────────────────────────────────────────────
def test_dk15_audit_written(tmp_path):
    loop = DockingAutoLoop(run_id="dk15", output_dir=tmp_path)
    runner = MockPhaseRunner({"phase_1_docking": STRONG_HIT})
    loop.run(runner)
    audit = tmp_path / "dk15_audit.jsonl"
    assert audit.exists()
    lines = [json.loads(l) for l in audit.read_text().strip().split("\n") if l]
    assert any(r["event"] == "attempt" for r in lines)


# ── DK-16: summary report written ────────────────────────────────────────────
def test_dk16_summary_written(tmp_path):
    loop = DockingAutoLoop(run_id="dk16", output_dir=tmp_path)
    runner = MockPhaseRunner({"phase_1_docking": STRONG_HIT})
    loop.run(runner)
    assert (tmp_path / "dk16_summary.txt").exists()


# ── DK-17: audit records exhaustiveness change ───────────────────────────────
def test_dk17_audit_exhaustiveness(tmp_path):
    loop = DockingAutoLoop(run_id="dk17", output_dir=tmp_path, max_retries_per_phase=2)
    runner = MockPhaseRunner({"phase_1_docking": [WEAK_SCORE, STRONG_HIT]})
    loop.run(runner)
    lines = [json.loads(l) for l in (tmp_path / "dk17_audit.jsonl").read_text().strip().split("\n") if l]
    attempt1 = next(r for r in lines if r["event"] == "attempt" and r["attempt"] == 1)
    assert attempt1["outcome"] == "halt"
    assert any("exhaustiveness" in r["param_changes"] for r in attempt1["remediations"])


# ── DK-18: scenario weak→hit ──────────────────────────────────────────────────
def test_dk18_scenario_weak_then_hit(tmp_path):
    loop = DockingAutoLoop(run_id="dk18", output_dir=tmp_path, max_retries_per_phase=2)
    result = loop.run(ScenarioRunner(SCENARIO_WEAK_THEN_HIT).phase_runner)
    assert "phase_1_docking" in result.phases_passed


# ── DK-19: scenario no-poses→hit ─────────────────────────────────────────────
def test_dk19_scenario_no_poses_then_hit(tmp_path):
    loop = DockingAutoLoop(run_id="dk19", output_dir=tmp_path, max_retries_per_phase=2)
    result = loop.run(ScenarioRunner(SCENARIO_NO_POSES_THEN_HIT).phase_runner)
    assert "phase_1_docking" in result.phases_passed


# ── DK-20: scenario strong hit first attempt ─────────────────────────────────
def test_dk20_scenario_strong_hit(tmp_path):
    loop = DockingAutoLoop(run_id="dk20", output_dir=tmp_path)
    result = loop.run(ScenarioRunner(SCENARIO_STRONG_HIT).phase_runner)
    assert result.total_attempts == 1


# ── DK-21: scenario persistent fail escalates ────────────────────────────────
def test_dk21_persistent_fail(tmp_path):
    loop = DockingAutoLoop(run_id="dk21", output_dir=tmp_path, max_retries_per_phase=2)
    result = loop.run(ScenarioRunner(SCENARIO_PERSISTENT_FAIL).phase_runner)
    assert len(result.phases_escalated) == 1


# ── DK-22: Glide score support (top_glidescore key) ──────────────────────────
def test_dk22_glide_score_key():
    ev = DockingQCEvaluator("docking_hit_finding")
    glide_hit = {"top_glidescore": -7.5, "n_poses_generated": 5}
    result = ev.evaluate_phase_1(glide_hit)
    assert result.passed, "Glide score -7.5 < -6 threshold → PASS"


# ── DK-23: Glide weak score fails ────────────────────────────────────────────
def test_dk23_glide_weak_fails():
    ev = DockingQCEvaluator("docking_hit_finding")
    glide_weak = {"top_glidescore": -3.0, "n_poses_generated": 5}
    result = ev.evaluate_phase_1(glide_weak)
    assert not result.passed


# ── DK-24: params copy independent ───────────────────────────────────────────
def test_dk24_params_copy():
    p = DockingParams(exhaustiveness=12)
    p2 = p.copy()
    p2.exhaustiveness = 24
    assert p.exhaustiveness == 12
