"""
Integration tests for autoloop_bridge.py (BR-1 to BR-20).

Covers: domain classification, schema adapters, SSE event emission,
suggestion store, fail-open behaviour, and all four domains end-to-end.
"""
import sys
import os
import pytest

# Allow running from backend root
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from autoloop_bridge import (
    classify_domain,
    evaluate_and_emit,
    get_suggestions,
    pop_suggestions,
    _adapt_admet,
    _adapt_docking,
    _adapt_cyp_ddi,
    _adapt_nca_pk,
)


# ── Fixtures ──────────────────────────────────────────────────────────────────

def _collector():
    events = []
    def cb(evt_type, data):
        events.append({"event": evt_type, **data})
    return events, cb


# ── BR-1: domain classification ───────────────────────────────────────────────
def test_br1_classify_domain_all():
    assert classify_domain("ADMET_TOXICITY")       == "admet"
    assert classify_domain("HERG_SCREEN")           == "admet"
    assert classify_domain("MOLECULAR_DOCKING")     == "docking"
    assert classify_domain("VINA")                  == "docking"
    assert classify_domain("DDI_RISK_ASSESSMENT")   == "cyp_ddi"
    assert classify_domain("CYP_PANEL")             == "cyp_ddi"
    assert classify_domain("NCA_PKNCA")             == "nca_pk"
    assert classify_domain("PKNCA")                 == "nca_pk"
    assert classify_domain("RNASEQ_ALIGN")          is None
    assert classify_domain("")                      is None


# ── BR-2: ADMET adapter renames dili_risk → dili_risk_level ──────────────────
def test_br2_admet_adapter_dili_risk_rename():
    raw = {"herg_ic50_uM": 5.0, "dili_probability": 0.3, "dili_risk": "medium",
           "ames_probability": 0.1, "ames_positive": False}
    out = _adapt_admet(raw)
    assert out["dili_risk_level"] == "medium"
    assert "dili_risk" in out          # original key preserved


# ── BR-3: ADMET adapter adds logp/mw defaults ─────────────────────────────────
def test_br3_admet_adapter_defaults():
    raw = {"herg_ic50_uM": 5.0, "dili_probability": 0.1, "ames_positive": False,
           "ames_probability": 0.05}
    out = _adapt_admet(raw)
    assert "logp" in out
    assert "molecular_weight_da" in out


# ── BR-4: docking adapter adds success flag ───────────────────────────────────
def test_br4_docking_adapter_success():
    raw = {"best_score_kcal_mol": -7.5, "n_poses_generated": 3}
    out = _adapt_docking(raw)
    assert out["success"] is True

    raw_none = {"best_score_kcal_mol": -5.0, "n_poses_generated": 0}
    out_none = _adapt_docking(raw_none)
    assert out_none["success"] is False


# ── BR-5: docking adapter aliases n_poses_generated → n_ligands_docked ────────
def test_br5_docking_adapter_alias():
    raw = {"best_score_kcal_mol": -8.0, "n_poses_generated": 5}
    out = _adapt_docking(raw)
    assert out["n_ligands_docked"] == 5


# ── BR-6: CYP DDI adapter passes through {"summary": {...}} unchanged ─────────
def test_br6_cyp_ddi_adapter_passthrough():
    raw = {"summary": {"n_clinical": 1, "n_investigate": 2, "n_tdi": 0,
                       "overall_recommendation": "CLINICAL_STUDY_RECOMMENDED"}}
    out = _adapt_cyp_ddi(raw)
    assert out == raw


# ── BR-7: CYP DDI adapter wraps flat dict ────────────────────────────────────
def test_br7_cyp_ddi_adapter_flat():
    raw = {"n_clinical_study_recommended": 1, "n_investigate": 0,
           "n_tdi_flagged": 2, "overall_recommendation": "CLINICAL_STUDY_RECOMMENDED"}
    out = _adapt_cyp_ddi(raw)
    assert "summary" in out
    assert out["summary"]["n_clinical"] == 1
    assert out["summary"]["n_tdi"] == 2


# ── BR-8: NCA-PK adapter wraps flat dict into population_summary ──────────────
def test_br8_nca_pk_adapter():
    raw = {"auc_extrap_pct_max": 25.0, "thalf_mean_h": 6.0,
           "auclast_mean": 800.0, "subjects_with_no_terminal_slope": 1,
           "cmax_mean": 120.0}
    out = _adapt_nca_pk(raw)
    ps = out["population_summary"]
    assert ps["auc_extrap_pct"] == 25.0
    assert ps["t_half_mean"] == 6.0
    assert ps["auc_last_mean"] == 800.0
    assert ps["subjects_with_no_terminal_slope"] == 1
    # auc_inf synthesised: 800 / (1 - 0.25) = 1066.67
    assert ps["auc_inf_mean"] == pytest.approx(800.0 / 0.75, rel=1e-3)


# ── BR-9: ADMET pass emits gate_results + phase_complete ─────────────────────
def test_br9_admet_pass_events():
    events, cb = _collector()
    raw = {"herg_ic50_uM": 25.0, "dili_probability": 0.2, "dili_risk": "low",
           "ames_positive": False, "ames_probability": 0.1,
           "logp": 2.5, "molecular_weight_da": 380.0}
    passed = evaluate_and_emit("ADMET_TOXICITY", raw, "br9", cb)
    assert passed
    types = [e["event"] for e in events]
    assert "autoloop_gate_results" in types
    assert "autoloop_phase_complete" in types
    assert "autoloop_update" not in types


# ── BR-10: ADMET fail emits gate_results + update (with remediations) ─────────
def test_br10_admet_fail_events():
    events, cb = _collector()
    raw = {"herg_ic50_uM": 3.5, "dili_probability": 0.2, "dili_risk": "low",
           "ames_positive": False, "ames_probability": 0.1}
    passed = evaluate_and_emit("ADMET_TOXICITY", raw, "br10", cb)
    assert not passed
    types = [e["event"] for e in events]
    assert "autoloop_gate_results" in types
    assert "autoloop_update" in types
    update = next(e for e in events if e["event"] == "autoloop_update")
    assert len(update["remediations"]) >= 1


# ── BR-11: docking pass ───────────────────────────────────────────────────────
def test_br11_docking_pass():
    events, cb = _collector()
    raw = {"best_score_kcal_mol": -9.2, "n_poses_generated": 10}
    passed = evaluate_and_emit("MOLECULAR_DOCKING", raw, "br11", cb)
    assert passed
    assert any(e["event"] == "autoloop_phase_complete" for e in events)


# ── BR-12: docking fail stores suggestions ────────────────────────────────────
def test_br12_docking_fail_suggestions():
    events, cb = _collector()
    raw = {"best_score_kcal_mol": -5.0, "n_poses_generated": 3}
    passed = evaluate_and_emit("MOLECULAR_DOCKING", raw, "br12", cb)
    assert not passed
    sug = get_suggestions("br12")
    assert sug is not None
    assert sug["domain"] == "docking"
    assert len(sug["remediations"]) >= 1


# ── BR-13: CYP DDI pass ───────────────────────────────────────────────────────
def test_br13_cyp_ddi_pass():
    events, cb = _collector()
    raw = {"summary": {"n_clinical": 0, "n_investigate": 0, "n_tdi": 0,
                       "overall_recommendation": "NOT_EXPECTED"}}
    passed = evaluate_and_emit("DDI_RISK_ASSESSMENT", raw, "br13", cb)
    assert passed


# ── BR-14: CYP DDI fail with citations ───────────────────────────────────────
def test_br14_cyp_ddi_citations():
    events, cb = _collector()
    raw = {"summary": {"n_clinical": 1, "n_investigate": 2, "n_tdi": 0,
                       "overall_recommendation": "CLINICAL_STUDY_RECOMMENDED"}}
    evaluate_and_emit("CYP_PANEL", raw, "br14", cb)
    sug = get_suggestions("br14")
    rem = sug["remediations"][0]
    assert len(rem["citations"]) > 0
    # FDA DDI Guidance should appear
    assert any("FDA" in c["paper_ref"] for c in rem["citations"])


# ── BR-15: NCA-PK pass ────────────────────────────────────────────────────────
def test_br15_nca_pk_pass():
    events, cb = _collector()
    raw = {"auc_extrap_pct_max": 8.0, "thalf_mean_h": 5.0,
           "auclast_mean": 900.0, "subjects_with_no_terminal_slope": 0,
           "cmax_mean": 150.0}
    passed = evaluate_and_emit("PKNCA", raw, "br15", cb)
    assert passed


# ── BR-16: NCA-PK fail (high extrap) ─────────────────────────────────────────
def test_br16_nca_pk_fail():
    events, cb = _collector()
    raw = {"auc_extrap_pct_max": 35.0, "thalf_mean_h": 8.0,
           "auclast_mean": 900.0, "subjects_with_no_terminal_slope": 0,
           "cmax_mean": 150.0}
    passed = evaluate_and_emit("NCA_ANALYSIS", raw, "br16", cb)
    assert not passed
    sug = get_suggestions("br16")
    assert "auc_extrapolation" in sug["failed_gates"]


# ── BR-17: unknown process → pass-through (returns True, no events) ───────────
def test_br17_unknown_process_pass_through():
    events, cb = _collector()
    passed = evaluate_and_emit("RNASEQ_ALIGN", {"reads": 1000000}, "br17", cb)
    assert passed
    assert len(events) == 0


# ── BR-18: pop_suggestions removes entry ─────────────────────────────────────
def test_br18_pop_suggestions():
    _, cb = _collector()
    raw = {"best_score_kcal_mol": -5.0, "n_poses_generated": 2}
    evaluate_and_emit("VINA", raw, "br18", cb)
    assert get_suggestions("br18") is not None
    popped = pop_suggestions("br18")
    assert popped is not None
    assert get_suggestions("br18") is None


# ── BR-19: gate_results event contains numeric value+threshold ────────────────
def test_br19_gate_results_numeric():
    events, cb = _collector()
    raw = {"best_score_kcal_mol": -7.5, "n_poses_generated": 3}
    evaluate_and_emit("DOCKING", raw, "br19", cb)
    gr = next(e for e in events if e["event"] == "autoloop_gate_results")
    for g in gr["gates"]:
        assert isinstance(g["value"], (int, float))
        assert isinstance(g["threshold"], (int, float))


# ── BR-20: bridge is fail-open (exceptions return True, not propagated) ────────
def test_br20_fail_open_on_bad_metrics():
    events, cb = _collector()
    # Empty dict — evaluators handle gracefully (default values) so this may
    # evaluate normally.  What matters: no exception propagates to caller.
    passed = evaluate_and_emit("ADMET_TOXICITY", {}, "br20", cb)
    # Must not raise; bridge always returns a bool (True = fail-open or genuine pass)
    assert isinstance(passed, bool)
    # Verify specifically that a completely corrupt dict (non-dict) fails open to True
    passed_corrupt = evaluate_and_emit("ADMET_TOXICITY", None, "br20b", cb)  # type: ignore
    assert passed_corrupt is True, "Non-dict metrics must fail-open to True"


# ── BR-21: CYP DDI adapter key collision: n_clinical_study_recommended wins ───
def test_br21_cyp_ddi_adapter_key_priority():
    from autoloop_bridge import _adapt_cyp_ddi
    # When both keys present, n_clinical_study_recommended takes priority
    raw = {"n_clinical_study_recommended": 3, "n_clinical": 1,
           "n_investigate": 0, "n_tdi_flagged": 0,
           "overall_recommendation": "CLINICAL_STUDY_RECOMMENDED"}
    out = _adapt_cyp_ddi(raw)
    assert out["summary"]["n_clinical"] == 3, \
        "n_clinical_study_recommended should take priority over n_clinical"


# ── BR-22: NCA-PK adapter thalf key fallback ─────────────────────────────────
def test_br22_nca_pk_thalf_fallback():
    from autoloop_bridge import _adapt_nca_pk
    # Uses t_half_mean when thalf_mean_h absent
    raw = {"auc_extrap_pct_max": 10.0, "t_half_mean": 5.5,
           "auclast_mean": 800.0, "subjects_with_no_terminal_slope": 0,
           "cmax_mean": 120.0}
    out = _adapt_nca_pk(raw)
    assert out["population_summary"]["t_half_mean"] == 5.5


# ── BR-24: autoloop_update event includes failed_gates directly ───────────────
def test_br24_update_event_has_failed_gates():
    """failed_gates must be emitted in the event, not reconstructed from remediations."""
    events, cb = _collector()
    raw = {"best_score_kcal_mol": -5.0, "n_poses_generated": 2}
    evaluate_and_emit("DOCKING", raw, "br24", cb)
    update = next(e for e in events if e["event"] == "autoloop_update")
    assert "failed_gates" in update, "autoloop_update must carry failed_gates"
    assert isinstance(update["failed_gates"], list)
    assert len(update["failed_gates"]) >= 1


# ── BR-25: NCA-PK auc_inf edge cases ─────────────────────────────────────────
def test_br25_nca_pk_auc_inf_edge_cases():
    from autoloop_bridge import _adapt_nca_pk
    # extrap = 0 → guard: 0 < 0 is False → auc_inf = auc_last
    out0 = _adapt_nca_pk({"auc_extrap_pct_max": 0.0, "auclast_mean": 800.0,
                           "thalf_mean_h": 5.0, "subjects_with_no_terminal_slope": 0})
    assert out0["population_summary"]["auc_inf_mean"] == 800.0

    # extrap = 100 → guard: 100 < 100 is False → auc_inf = auc_last (no div/0)
    out100 = _adapt_nca_pk({"auc_extrap_pct_max": 100.0, "auclast_mean": 500.0,
                             "thalf_mean_h": 5.0, "subjects_with_no_terminal_slope": 0})
    assert out100["population_summary"]["auc_inf_mean"] == 500.0

    # extrap = 99.9 → large but finite
    out99 = _adapt_nca_pk({"auc_extrap_pct_max": 99.9, "auclast_mean": 100.0,
                            "thalf_mean_h": 5.0, "subjects_with_no_terminal_slope": 0})
    assert out99["population_summary"]["auc_inf_mean"] == pytest.approx(
        100.0 / 0.001, rel=1e-3
    )


# ── BR-26: CYP DDI flat fallback chains n_clinical when recommended absent ────
def test_br26_cyp_ddi_flat_fallback_chain():
    from autoloop_bridge import _adapt_cyp_ddi
    # Only n_clinical present (no n_clinical_study_recommended)
    raw = {"n_clinical": 2, "n_investigate": 1, "n_tdi_flagged": 0,
           "overall_recommendation": "CLINICAL_STUDY_RECOMMENDED"}
    out = _adapt_cyp_ddi(raw)
    assert out["summary"]["n_clinical"] == 2, \
        "Must fall back to n_clinical when n_clinical_study_recommended absent"


# ── BR-27: HERG_SCREEN routes to phase_3_herg_screen ────────────────────────
def test_br27_herg_screen_phase_routing():
    from autoloop_bridge import _resolve_phase
    assert _resolve_phase("admet", "HERG_SCREEN") == "phase_3_herg_screen"
    assert _resolve_phase("admet", "herg_screen") == "phase_3_herg_screen"  # case-insensitive


# ── BR-28: DILI_SCREEN routes to phase_4_dili_ames ───────────────────────────
def test_br28_dili_screen_phase_routing():
    from autoloop_bridge import _resolve_phase
    assert _resolve_phase("admet", "DILI_SCREEN")  == "phase_4_dili_ames"
    assert _resolve_phase("admet", "AMES_SCREEN")  == "phase_4_dili_ames"
    assert _resolve_phase("admet", "ADMET_TOXICITY") == "phase_2_admet_prediction"
    assert _resolve_phase("docking", "MOLECULAR_DOCKING") == "phase_1_docking"
    assert _resolve_phase("cyp_ddi", "DDI_RISK_ASSESSMENT") == "phase_2_ddi_risk"
    assert _resolve_phase("nca_pk",  "NCA_PKNCA") == "phase_1_nca_analysis"


# ── BR-23: suggestions store is keyed per invocation — no cross-contamination ─
def test_br23_suggestions_isolation():
    _, cb1 = _collector()
    _, cb2 = _collector()
    raw_fail = {"best_score_kcal_mol": -5.0, "n_poses_generated": 1}
    raw_pass = {"best_score_kcal_mol": -9.2, "n_poses_generated": 10}
    evaluate_and_emit("DOCKING", raw_fail, "iso-a", cb1)
    evaluate_and_emit("DOCKING", raw_pass, "iso-b", cb2)
    assert get_suggestions("iso-a") is not None
    assert get_suggestions("iso-b") is None  # passed → no suggestions stored
