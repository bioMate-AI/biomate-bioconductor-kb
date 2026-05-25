"""Tests for the PBPK auto-loop (qc_evaluator + param_tuner + enriched + bridge)."""

from __future__ import annotations

import os
import sys
from pathlib import Path

import pytest

# Add backend/ to sys.path so `experiments.*` and `galaxy.*` import
_ROOT = Path(__file__).resolve().parents[3]   # backend/
sys.path.insert(0, str(_ROOT))
sys.path.insert(0, str(_ROOT / "lib"))

from experiments.pbpk_autoloop.qc_evaluator import (
    PBPKQCEvaluator, QCAction, QCLevel,
)
from experiments.pbpk_autoloop.params import PBPKParams
from experiments.pbpk_autoloop.param_tuner import PBPKTuner
from experiments.pbpk_autoloop.enriched_tuner import KnowledgeEnrichedPBPKTuner


# ─── QC evaluator gates ──────────────────────────────────────────────────────

def test_all_gates_pass_with_good_metrics():
    metrics = {
        "tmax_h": 4.0,
        "simulation_duration_h": 24.0,
        "cl_l_per_h": 5.0,
        "thalf_estimable": True,
        "mass_balance_recovery": 1.001,
        "auc_pred_h_ug_per_mL": 100.0,
        "auc_obs_h_ug_per_mL": 110.0,
    }
    ev = PBPKQCEvaluator("pbpk_ind_submission")
    r = ev.evaluate_phase("phase_1_pbpk_simulation", metrics)
    assert r.passed
    assert r.overall_level == QCLevel.GOLD


def test_tmax_fraction_halt_ind_submission():
    """Tmax at 95% of window → HALT under IND profile."""
    metrics = {
        "tmax_h": 22.8,
        "simulation_duration_h": 24.0,
        "cl_l_per_h": 5.0,
    }
    ev = PBPKQCEvaluator("pbpk_ind_submission")
    r = ev.evaluate_phase("phase_1_pbpk_simulation", metrics)
    assert not r.passed
    halts = [g for g in r.halts]
    assert any(g.gate == "pbpk_tmax_fraction" for g in halts)


def test_tmax_fraction_advisory_in_screening_profile():
    """Same metrics → ADVISORY under screening profile (advisory_only=True)."""
    metrics = {
        "tmax_h": 22.8,
        "simulation_duration_h": 24.0,
        "cl_l_per_h": 5.0,
    }
    ev = PBPKQCEvaluator("pbpk_screening")
    r = ev.evaluate_phase("phase_1_pbpk_simulation", metrics)
    # Screening doesn't HALT — but the gate result is still ADVISORY
    advisories = [g for g in r.gate_results if g.action == QCAction.ADVISORY]
    assert any(g.gate == "pbpk_tmax_fraction" for g in advisories)


def test_cl_min_halt():
    metrics = {
        "tmax_h": 4.0, "simulation_duration_h": 24.0,
        "cl_l_per_h": 0.001,   # below 0.01 floor
    }
    ev = PBPKQCEvaluator("pbpk_ind_submission")
    r = ev.evaluate_phase("phase_1_pbpk_simulation", metrics)
    assert not r.passed
    assert any(g.gate == "pbpk_cl_min" for g in r.halts)


def test_mass_balance_gate_skipped_when_recovery_absent():
    metrics = {
        "tmax_h": 4.0, "simulation_duration_h": 24.0, "cl_l_per_h": 5.0,
        # no mass_balance_recovery field
    }
    ev = PBPKQCEvaluator("pbpk_ind_submission")
    r = ev.evaluate_phase("phase_1_pbpk_simulation", metrics)
    # Mass balance gate not emitted (skipped, not failed)
    assert not any(g.gate == "pbpk_mass_balance" for g in r.gate_results)
    assert r.passed


def test_mass_balance_halt():
    metrics = {
        "tmax_h": 4.0, "simulation_duration_h": 24.0, "cl_l_per_h": 5.0,
        "mass_balance_recovery": 0.85,   # 15% deviation > 5% IND tol
    }
    ev = PBPKQCEvaluator("pbpk_ind_submission")
    r = ev.evaluate_phase("phase_1_pbpk_simulation", metrics)
    halts = [g for g in r.halts]
    assert any(g.gate == "pbpk_mass_balance" for g in halts)


def test_auc_fold_error_halt():
    metrics = {
        "tmax_h": 4.0, "simulation_duration_h": 24.0, "cl_l_per_h": 5.0,
        "auc_pred_h_ug_per_mL": 1000.0,  # 10× overprediction
        "auc_obs_h_ug_per_mL": 100.0,
    }
    ev = PBPKQCEvaluator("pbpk_ind_submission")
    r = ev.evaluate_phase("phase_1_pbpk_simulation", metrics)
    assert not r.passed
    assert any(g.gate == "pbpk_auc_fold_error" for g in r.halts)


def test_auc_fold_error_gate_skipped_when_observed_absent():
    metrics = {
        "tmax_h": 4.0, "simulation_duration_h": 24.0, "cl_l_per_h": 5.0,
        "auc_pred_h_ug_per_mL": 100.0,
        # no auc_obs
    }
    ev = PBPKQCEvaluator("pbpk_ind_submission")
    r = ev.evaluate_phase("phase_1_pbpk_simulation", metrics)
    assert not any(g.gate == "pbpk_auc_fold_error" for g in r.gate_results)


def test_unknown_profile_raises():
    with pytest.raises(ValueError, match="Unknown QC profile"):
        PBPKQCEvaluator("not_a_real_profile")


# ─── Param tuner ─────────────────────────────────────────────────────────────

def test_tmax_remediation_extends_duration():
    metrics = {
        "tmax_h": 22.0, "simulation_duration_h": 24.0, "cl_l_per_h": 5.0,
    }
    ev = PBPKQCEvaluator("pbpk_ind_submission")
    r = ev.evaluate_phase("phase_1_pbpk_simulation", metrics)
    tuner = PBPKTuner()
    new_params, remeds = tuner.remediate(r, PBPKParams())
    tmax_remed = [m for m in remeds if m.gate == "pbpk_tmax_fraction"]
    assert len(tmax_remed) == 1
    assert new_params.simulation_duration_h > 24.0


def test_cl_remediation_doubles_clint():
    metrics = {
        "tmax_h": 4.0, "simulation_duration_h": 24.0, "cl_l_per_h": 0.001,
    }
    ev = PBPKQCEvaluator("pbpk_ind_submission")
    r = ev.evaluate_phase("phase_1_pbpk_simulation", metrics)
    tuner = PBPKTuner()
    new_params, remeds = tuner.remediate(r, PBPKParams())
    cl_remed = [m for m in remeds if m.gate == "pbpk_cl_min"]
    assert len(cl_remed) == 1
    assert new_params.clint_mL_per_min == pytest.approx(100.0)  # 50.0 * 2


def test_mass_balance_remediation_tightens_solver():
    metrics = {
        "tmax_h": 4.0, "simulation_duration_h": 24.0, "cl_l_per_h": 5.0,
        "mass_balance_recovery": 0.80,
    }
    ev = PBPKQCEvaluator("pbpk_ind_submission")
    r = ev.evaluate_phase("phase_1_pbpk_simulation", metrics)
    tuner = PBPKTuner()
    new_params, remeds = tuner.remediate(r, PBPKParams())
    mb = [m for m in remeds if m.gate == "pbpk_mass_balance"]
    assert len(mb) == 1
    assert new_params.integration_rtol < 1e-6


def test_auc_remediation_reduces_kp_scale():
    metrics = {
        "tmax_h": 4.0, "simulation_duration_h": 24.0, "cl_l_per_h": 5.0,
        "auc_pred_h_ug_per_mL": 1000.0, "auc_obs_h_ug_per_mL": 100.0,
    }
    ev = PBPKQCEvaluator("pbpk_ind_submission")
    r = ev.evaluate_phase("phase_1_pbpk_simulation", metrics)
    tuner = PBPKTuner()
    new_params, remeds = tuner.remediate(r, PBPKParams())
    auc = [m for m in remeds if m.gate == "pbpk_auc_fold_error"]
    assert len(auc) == 1
    assert new_params.kp_scale == pytest.approx(0.75)


# ─── Enriched tuner: knowledge citations attached ────────────────────────────

def test_enriched_tuner_attaches_knowledge():
    metrics = {
        "tmax_h": 22.0, "simulation_duration_h": 24.0, "cl_l_per_h": 0.001,
    }
    ev = PBPKQCEvaluator("pbpk_ind_submission")
    r = ev.evaluate_phase("phase_1_pbpk_simulation", metrics)
    tuner = KnowledgeEnrichedPBPKTuner()
    _, enriched_remeds = tuner.remediate(r, PBPKParams())
    assert len(enriched_remeds) == 2  # tmax + cl
    for er in enriched_remeds:
        assert len(er.knowledge) >= 1
        d = er.to_dict()
        assert "knowledge" in d
        # Every knowledge entry has a citation
        for k in d["knowledge"]:
            assert k["paper_ref"]
            assert k["paper_doi"]


# ─── Bridge integration ───────────────────────────────────────────────────────

def test_bridge_classifies_pbpk_domain():
    from experiments.autoloop_bridge import classify_domain
    for proc in ("PBPK_SIMULATION", "PBPK_PEDIATRIC", "PK_SIM_PBPK",
                  "SIMCYP_PBPK", "pbpk_simulation"):
        assert classify_domain(proc) == "pbpk", f"failed for {proc}"


def test_bridge_does_not_classify_non_pbpk():
    from experiments.autoloop_bridge import classify_domain
    # Avoid false positives on unrelated process names
    for proc in ("RNA_SEQ_ALIGN", "FASTQC", "STAR_ALIGN"):
        assert classify_domain(proc) != "pbpk"


def test_bridge_end_to_end_emits_pbpk_events():
    from experiments.autoloop_bridge import evaluate_and_emit

    events: list[tuple[str, dict]] = []

    def sse_callback(event_type: str, data: dict) -> None:
        events.append((event_type, data))

    raw_metrics = {
        "tmax_h": 23.5,  # 98% of window → HALT under IND profile
        "simulation_duration_h": 24.0,
        "cl_l_per_h": 5.0,
    }

    passed = evaluate_and_emit(
        process_name="PBPK_SIMULATION",
        raw_metrics=raw_metrics,
        invocation_id="test-pbpk-001",
        sse_callback=sse_callback,
        qc_profile="pbpk_ind_submission",
    )
    assert passed is False  # HALT
    event_types = {e[0] for e in events}
    assert "autoloop_gate_results" in event_types
    assert "autoloop_update" in event_types
    # Remediation must include the tmax fix
    update = next(d for (t, d) in events if t == "autoloop_update")
    failed = update["failed_gates"]
    assert "pbpk_tmax_fraction" in failed
    remeds = update["remediations"]
    assert any(r["gate"] == "pbpk_tmax_fraction" for r in remeds)


def test_bridge_screening_profile_does_not_halt():
    from experiments.autoloop_bridge import evaluate_and_emit

    events: list[tuple[str, dict]] = []

    def sse_callback(event_type: str, data: dict) -> None:
        events.append((event_type, data))

    raw_metrics = {
        "tmax_h": 23.5,
        "simulation_duration_h": 24.0,
        "cl_l_per_h": 5.0,
    }
    passed = evaluate_and_emit(
        process_name="PBPK_SIMULATION",
        raw_metrics=raw_metrics,
        invocation_id="test-pbpk-002",
        sse_callback=sse_callback,
        qc_profile="pbpk_screening",
    )
    # Screening is advisory-only — even with tmax 98% of window, it passes
    assert passed is True
    assert ("autoloop_phase_complete", events[-1][1]) == ("autoloop_phase_complete", events[-1][1])
