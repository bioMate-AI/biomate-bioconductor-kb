"""Unit tests for the survival (Cox) auto-loop: evaluator + tuner + bridge wiring.

Run:  cd backend && PYTHONPATH=. python3 -m pytest experiments/survival_autoloop/tests -q
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))))

from experiments.survival_autoloop.qc_evaluator import SurvivalQCEvaluator
from experiments.survival_autoloop.param_tuner import SurvivalParamTuner
from experiments.survival_autoloop.params import SurvivalParams
from experiments.admet_autoloop.qc_evaluator import QCAction


# IMvigor210-shaped metrics: naive model omits ECOG + liver mets (both significant),
# PH assumption holds (the reanalysis reports "PH looks okay").
IMVIGOR_METRICS = {
    "schoenfeld_global_p": 0.41,
    "ph_violating_covariates": [],
    "omitted_confounders": [
        {"name": "ecog_ge1", "hr": 2.15, "p": 1.6e-5},
        {"name": "liver_mets", "hr": 1.49, "p": 0.017},
    ],
    "naive_primary_hr": 0.818,
    "adjusted_primary_hr": 0.819,
}


def test_confounding_gate_halts_and_refits():
    res = SurvivalQCEvaluator().evaluate_phase("phase_1_cox", IMVIGOR_METRICS)
    gates = {g.gate: g for g in res.gate_results}
    assert "cox_confounding" in gates and "cox_ph_schoenfeld" in gates
    # PH holds -> pass; confounding present -> HALT
    assert gates["cox_ph_schoenfeld"].action == QCAction.PASS
    assert gates["cox_confounding"].action == QCAction.HALT
    assert not res.passed

    params = SurvivalParams(covariates=["cd8teffector"],
                            candidate_confounders=["ecog_ge1", "liver_mets", "log_tmb"])
    new, rems = SurvivalParamTuner().remediate(res, params)
    # The confounders are moved into the design (the re-fit).
    assert "ecog_ge1" in new.covariates and "liver_mets" in new.covariates
    assert any(r.gate == "cox_confounding" for r in rems)
    chg = [r for r in rems if r.gate == "cox_confounding"][0].param_changes
    assert set(["cd8teffector", "ecog_ge1", "liver_mets"]).issubset(set(chg["covariates"]))


def test_ph_violation_gate_halts_and_stratifies():
    metrics = {"schoenfeld_global_p": 0.004, "ph_violating_covariates": ["ecog_ge1"],
               "omitted_confounders": []}
    res = SurvivalQCEvaluator().evaluate_phase("phase_1_cox", metrics)
    gates = {g.gate: g for g in res.gate_results}
    assert gates["cox_ph_schoenfeld"].action == QCAction.HALT
    params = SurvivalParams(covariates=["cd8teffector", "ecog_ge1"])
    new, rems = SurvivalParamTuner().remediate(res, params)
    assert len(new.strata) >= 1
    assert any(r.gate == "cox_ph_schoenfeld" for r in rems)


def test_clean_model_passes():
    metrics = {"schoenfeld_global_p": 0.6, "omitted_confounders": [
        {"name": "age", "hr": 1.01, "p": 0.4}]}
    res = SurvivalQCEvaluator().evaluate_phase("phase_1_cox", metrics)
    assert res.passed
    new, rems = SurvivalParamTuner().remediate(res, SurvivalParams())
    assert rems == []


def test_emitter_json_contract_flows_through_bridge():
    """The exact survival_qc.json the Cox .nf emitter writes (IMvigor adjusted CSV)
    must flow through _adapt_survival -> evaluator -> tuner and fire the confounder gate."""
    import json
    from experiments.autoloop_bridge import _adapt_survival
    # Shape produced by the Cox nf emitter (jsonlite::toJSON of the qc list):
    survival_qc = json.loads('''{
      "process": "BIOC_SURVIVAL_COX_PROPORTIONAL_HAZARDS_REGRESSION",
      "domain": "survival",
      "primary_covariate": "cd8teffector",
      "naive_primary_hr": 0.817,
      "adjusted_primary_hr": 0.806,
      "schoenfeld_global_p": 0.124,
      "ph_violating_covariates": [],
      "omitted_confounders": [
        {"name": "log_tmb", "hr": 0.838, "p": 0.0039},
        {"name": "ecog_ge1", "hr": 1.972, "p": 3.95e-07},
        {"name": "liver_mets", "hr": 1.705, "p": 0.000113}
      ]
    }''')
    metrics = _adapt_survival(survival_qc)
    res = SurvivalQCEvaluator().evaluate_phase("phase_1_cox", metrics)
    gates = {g.gate: g for g in res.gate_results}
    assert gates["cox_ph_schoenfeld"].action == QCAction.PASS   # 0.124 >= 0.05
    assert gates["cox_confounding"].action == QCAction.HALT     # ecog/liver/tmb significant
    params = SurvivalParams(covariates=["cd8teffector"],
                            candidate_confounders=["log_tmb", "ecog_ge1", "liver_mets"])
    new, rems = SurvivalParamTuner().remediate(res, params)
    assert set(["cd8teffector", "ecog_ge1", "liver_mets", "log_tmb"]) == set(new.covariates)


def test_bridge_routes_cox_process():
    from experiments.autoloop_bridge import classify_domain, _ADAPTERS, _load_components
    assert classify_domain("BIOC_SURVIVAL_COX_PROPORTIONAL_HAZARDS_REGRESSION") == "survival"
    assert "survival" in _ADAPTERS
    ev, tu, pa = _load_components("survival")
    assert ev is SurvivalQCEvaluator and pa is SurvivalParams


if __name__ == "__main__":
    import pytest, sys as _s
    _s.exit(pytest.main([__file__, "-q"]))
