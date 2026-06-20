"""Tests for qc_gate_reader — surfaces gate evidence for ~10 QC-but-no-autoloop
workflows."""

from __future__ import annotations

import json
import sys
import tempfile
from pathlib import Path

import pytest

_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(_ROOT / "backend" / "lib"))
sys.path.insert(0, str(_ROOT))

from galaxy.ai.retrievers.qc_gate_reader import (  # noqa: E402
    read_gate_json,
    build_gate_event,
    list_supported_domains,
)


# ─── read_gate_json — file-handling ────────────────────────────────────

def test_read_missing_file_returns_none():
    assert read_gate_json("/nonexistent/path/file.json") is None


def test_read_valid_json(tmp_path):
    p = tmp_path / "qc.json"
    p.write_text(json.dumps({"z_prime": 0.85, "signal_window": 3.2}))
    assert read_gate_json(p) == {"z_prime": 0.85, "signal_window": 3.2}


def test_read_malformed_json_returns_none(tmp_path):
    p = tmp_path / "qc.json"
    p.write_text("{not valid json")
    assert read_gate_json(p) is None


def test_read_non_dict_root_returns_none(tmp_path):
    p = tmp_path / "qc.json"
    p.write_text(json.dumps([1, 2, 3]))
    assert read_gate_json(p) is None


# ─── HTS plate gates ─────────────────────────────────────────────────

def test_hts_z_prime_passes():
    e = build_gate_event("hts_plate_qc_hit_calling", "hts",
                          {"z_prime": 0.85, "signal_window": 3.2})
    z_gate = next(g for g in e["gates"] if g["gate"] == "hts_z_prime")
    assert z_gate["action"] == "pass"
    assert z_gate["level"] == "GOLD"


def test_hts_z_prime_fails_below_threshold():
    e = build_gate_event("hts_plate_qc_hit_calling", "hts",
                          {"z_prime": 0.2})
    z_gate = next(g for g in e["gates"] if g["gate"] == "hts_z_prime")
    assert z_gate["action"] == "halt"
    assert z_gate["level"] == "FAIL"
    assert "0.2" in z_gate["message"] or "0.20" in z_gate["message"]


# ─── ICH gates ─────────────────────────────────────────────────────────

def test_ich_s5_safety_margin_pass():
    e = build_gate_event("ich_s5_reproductive_tox", "ich_s5",
                          {"safety_margin_x": 50.0})
    g = e["gates"][0]
    assert g["action"] == "pass"
    assert g["level"] == "GOLD"


def test_ich_s5_safety_margin_fail():
    e = build_gate_event("ich_s5_reproductive_tox", "ich_s5",
                          {"safety_margin_x": 5.0})
    g = e["gates"][0]
    assert g["action"] == "halt"


def test_ich_s7b_herg_margin():
    e = build_gate_event("ich_s7a_safety_pharmacology", "ich_s7",
                          {"herg_safety_margin_x": 100.0})
    g = e["gates"][0]
    assert g["gate"] == "ich_s7b_herg_margin"
    assert g["level"] == "GOLD"


# ─── BOIN dose escalation ────────────────────────────────────────────

def test_boin_within_target_passes():
    e = build_gate_event("clinical_trial_simulation", "clinical_trial",
                          {"mtd_observed_dlt_rate": 0.22, "target_dlt_rate": 0.25})
    g = e["gates"][0]
    assert g["action"] == "pass"


def test_boin_above_target_fails():
    e = build_gate_event("clinical_trial_simulation", "clinical_trial",
                          {"mtd_observed_dlt_rate": 0.35, "target_dlt_rate": 0.25})
    g = e["gates"][0]
    assert g["action"] == "halt"


# ─── Allometric, IVIVE, OpenFE, p0 PKPD ──────────────────────────────

def test_allometric_r_squared_pass():
    e = build_gate_event("allometric_scaling", "allometric", {"r_squared": 0.97})
    assert e["gates"][0]["level"] == "GOLD"


def test_allometric_r_squared_fail():
    e = build_gate_event("allometric_scaling", "allometric", {"r_squared": 0.7})
    assert e["gates"][0]["action"] == "halt"


def test_ivive_fold_error_pass():
    e = build_gate_event("ivive_hepatic_clearance", "ivive",
                          {"cl_predicted_l_per_h": 5.0, "cl_observed_l_per_h": 4.5})
    assert e["gates"][0]["level"] == "GOLD"


def test_ivive_fold_error_3x_fails():
    e = build_gate_event("ivive_hepatic_clearance", "ivive",
                          {"cl_predicted_l_per_h": 15.0, "cl_observed_l_per_h": 5.0})
    assert e["gates"][0]["action"] == "halt"


def test_openfe_cycle_closure_pass():
    e = build_gate_event("openfe_rbfe", "openfe",
                          {"cycle_closure_kcal_per_mol": 0.3})
    assert e["gates"][0]["level"] == "GOLD"


def test_openfe_cycle_closure_fail():
    e = build_gate_event("openfe_rbfe", "openfe",
                          {"cycle_closure_kcal_per_mol": 2.5})
    assert e["gates"][0]["action"] == "halt"


def test_p0_pkpd_weight_in_band():
    e = build_gate_event("p0_pkpd_semaglutide", "p0_pkpd",
                          {"week30_weight_change_kg": -4.5})
    assert e["gates"][0]["action"] == "pass"


def test_p0_pkpd_weight_out_of_band():
    e = build_gate_event("p0_pkpd_semaglutide", "p0_pkpd",
                          {"week30_weight_change_kg": -10.0})
    assert e["gates"][0]["action"] == "halt"


def test_pocket_druggability_pass():
    e = build_gate_event("pocket_detection_druggability", "pocket_detection",
                          {"druggability_score": 0.75})
    assert e["gates"][0]["level"] == "GOLD"


def test_aizynth_no_routes_fails():
    e = build_gate_event("aizynthfinder_retrosynthesis", "aizynthfinder",
                          {"num_solved_routes": 0})
    assert e["gates"][0]["action"] == "halt"


# ─── Event shape + evidence wiring ────────────────────────────────────

def test_event_shape_matches_autoloop_format():
    """Event has IDENTICAL shape to autoloop_gate_results so existing
    frontend renders without code change."""
    e = build_gate_event("hts_plate_qc_hit_calling", "hts",
                          {"z_prime": 0.6, "signal_window": 2.5})
    assert set(e.keys()) >= {"phase", "domain", "overall_level", "passed", "gates"}
    for g in e["gates"]:
        assert set(g.keys()) >= {"gate", "action", "level", "value",
                                  "threshold", "message", "evidence"}


def test_every_gate_carries_evidence_field():
    """Each gate result includes the evidence list — what powers
    the frontend hover-tooltip via the qc-evidence-tooltip wrapper."""
    e = build_gate_event("hts_plate_qc_hit_calling", "hts",
                          {"z_prime": 0.85, "signal_window": 3.2})
    for g in e["gates"]:
        # evidence must be a list (may be empty if YAML entry missing)
        assert isinstance(g["evidence"], list)
    # At least one gate has evidence (z_prime has GOLD entry in YAML)
    has_evidence = [g for g in e["gates"] if g["evidence"]]
    assert len(has_evidence) >= 1


def test_evidence_entries_have_required_fields():
    e = build_gate_event("hts_plate_qc_hit_calling", "hts", {"z_prime": 0.85})
    for g in e["gates"]:
        for ev in g["evidence"]:
            assert ev["paper_ref"]
            assert ev["provenance"] in ("GOLD", "SILVER", "BRONZE")


def test_metric_missing_skips_gate():
    """Gate that lacks its required metric is skipped (not failed)."""
    e = build_gate_event("hts_plate_qc_hit_calling", "hts", {})
    # No z_prime, no signal_window → no gates at all
    assert e["gates"] == []
    assert e["passed"] is True   # vacuously true


def test_unknown_domain_returns_empty_gates():
    e = build_gate_event("unknown_workflow", "not_a_real_domain", {"foo": "bar"})
    assert e["gates"] == []
    assert e["passed"] is True


def test_overall_level_gold_when_all_pass():
    e = build_gate_event("hts_plate_qc_hit_calling", "hts",
                          {"z_prime": 0.9, "signal_window": 5.0})
    assert e["overall_level"] == "GOLD"
    assert e["passed"] is True


def test_overall_level_fail_when_any_fails():
    e = build_gate_event("hts_plate_qc_hit_calling", "hts",
                          {"z_prime": 0.1, "signal_window": 5.0})
    assert e["overall_level"] == "FAIL"
    assert e["passed"] is False


# ─── Coverage ────────────────────────────────────────────────────────

def test_supported_domains_count():
    """Reader covers all 11 QC-but-no-autoloop domains (10 gate-only + structure_prediction).

    Note: `rare_disease` (chain id 1, Liu) has yaml citations + rationale
    wired as of 2026-06-19 (commit efbeb5785) but no `_GATE_REGISTRY`
    entry — gate evaluation is a separate follow-up. Don't include it here.
    """
    domains = set(list_supported_domains())
    expected = {"hts", "ich_s5", "ich_s7", "clinical_trial", "allometric",
                "ivive", "openfe", "p0_pkpd", "pocket_detection", "aizynthfinder",
                "structure_prediction", "cancer_biology", "cryo_em", "cryo_et", "lnp_formulation", "nlmixr2_poppk", "antibody_developability", "sirna_offtarget", "polymorph_stability", "biomarker_enrichment", "bioconductor_qc"}
    assert domains == expected, f"missing: {expected - domains}, extra: {domains - expected}"


# ─── Structure prediction (Boltz / Chai / AlphaFold) ─────────────────

def test_struct_pred_mean_plddt_pass():
    e = build_gate_event("boltz_structure_prediction", "structure_prediction",
                          {"mean_plddt": 85.0})
    g = next(x for x in e["gates"] if x["gate"] == "struct_pred_mean_plddt")
    assert g["action"] == "pass"
    assert g["level"] == "GOLD"


def test_struct_pred_mean_plddt_fail():
    e = build_gate_event("boltz_structure_prediction", "structure_prediction",
                          {"mean_plddt": 45.0})
    g = next(x for x in e["gates"] if x["gate"] == "struct_pred_mean_plddt")
    assert g["action"] == "halt"
    assert g["level"] == "FAIL"


def test_struct_pred_confident_fraction_pass():
    e = build_gate_event("chai1_structure_prediction", "structure_prediction",
                          {"mean_plddt": 80.0, "confident_fraction": 0.85})
    g = next(x for x in e["gates"] if x["gate"] == "struct_pred_confident_fraction")
    assert g["action"] == "pass"


def test_struct_pred_confident_fraction_fail():
    e = build_gate_event("chai1_structure_prediction", "structure_prediction",
                          {"confident_fraction": 0.4})
    g = next(x for x in e["gates"] if x["gate"] == "struct_pred_confident_fraction")
    assert g["action"] == "halt"
    assert g["level"] == "FAIL"


def test_struct_pred_max_pae_skipped_when_missing():
    """Single-domain proteins don't report max_pae → gate not emitted."""
    e = build_gate_event("boltz_structure_prediction", "structure_prediction",
                          {"mean_plddt": 85.0, "confident_fraction": 0.9})
    gate_names = {g["gate"] for g in e["gates"]}
    assert "struct_pred_max_pae" not in gate_names
    assert "struct_pred_mean_plddt" in gate_names


def test_struct_pred_max_pae_pass():
    e = build_gate_event("alphafold_predict", "structure_prediction",
                          {"max_pae": 5.0})
    g = next(x for x in e["gates"] if x["gate"] == "struct_pred_max_pae")
    assert g["action"] == "pass"


def test_struct_pred_max_pae_fail():
    e = build_gate_event("alphafold_predict", "structure_prediction",
                          {"max_pae": 20.0})
    g = next(x for x in e["gates"] if x["gate"] == "struct_pred_max_pae")
    assert g["action"] == "halt"


def test_boltz_process_classification():
    from galaxy.ai.retrievers.qc_gate_emit import classify_gate_only_domain
    assert classify_gate_only_domain("BOLTZ_PREDICT") == "structure_prediction"
    assert classify_gate_only_domain("BOLTZ_STRUCTURE_PREDICTION") == "structure_prediction"


def test_chai_process_classification():
    from galaxy.ai.retrievers.qc_gate_emit import classify_gate_only_domain
    assert classify_gate_only_domain("CHAI1_PREDICT") == "structure_prediction"
    assert classify_gate_only_domain("CHAI1_STRUCTURE_PREDICTION") == "structure_prediction"


def test_alphafold_process_classification():
    from galaxy.ai.retrievers.qc_gate_emit import classify_gate_only_domain
    assert classify_gate_only_domain("ALPHAFOLD_PREDICT") == "structure_prediction"
    assert classify_gate_only_domain("RUN_AF3_INFERENCE") == "structure_prediction"


def test_end_to_end_boltz_event():
    """Realistic Boltz output → event with 3 gates + evidence on each."""
    metrics = {
        "mean_plddt": 82.5,
        "confident_fraction": 0.78,
        "max_pae": 6.2,
    }
    event = build_gate_event(
        workflow_name="BOLTZ_PREDICT",
        domain="structure_prediction",
        metrics=metrics,
    )
    assert event["passed"] is True
    gate_names = {g["gate"] for g in event["gates"]}
    assert gate_names == {
        "struct_pred_mean_plddt",
        "struct_pred_confident_fraction",
        "struct_pred_max_pae",
    }
    for g in event["gates"]:
        assert isinstance(g["evidence"], list)
        assert len(g["evidence"]) >= 1
        assert g["evidence"][0]["paper_ref"]


def test_end_to_end_read_and_build(tmp_path):
    """Realistic end-to-end: workflow emits qc.json → reader parses →
    build_gate_event produces the SSE-shaped dict ready to forward."""
    qc_path = tmp_path / "hts_qc.json"
    qc_path.write_text(json.dumps({"z_prime": 0.92, "signal_window": 4.5}))
    metrics = read_gate_json(qc_path)
    event = build_gate_event(
        workflow_name="hts_plate_qc_hit_calling",
        domain="hts",
        metrics=metrics,
    )
    assert event["passed"] is True
    assert event["overall_level"] == "GOLD"
    z_gate = next(g for g in event["gates"] if g["gate"] == "hts_z_prime")
    assert z_gate["evidence"][0]["paper_ref"].startswith("Zhang")


# ─── Cryo-ET tests ───────────────────────────────────────────────────

def test_cryo_et_in_supported_domains():
    assert "cryo_et" in set(list_supported_domains())


def test_cryo_et_sta_fsc_gold():
    e = build_gate_event("subtomogram_averaging", "cryo_et",
                          {"fsc_0143_resolution_angstroms": 7.5})
    g = next(g for g in e["gates"] if g["gate"] == "cryo_et_sta_fsc_resolution")
    assert g["level"] == "GOLD"


def test_cryo_et_sta_fsc_fail():
    e = build_gate_event("subtomogram_averaging", "cryo_et",
                          {"fsc_0143_resolution_angstroms": 35.0})
    g = next(g for g in e["gates"] if g["gate"] == "cryo_et_sta_fsc_resolution")
    assert g["action"] == "halt"


def test_cryo_et_tilt_residual_pass():
    e = build_gate_event("tilt_alignment", "cryo_et",
                          {"tilt_residual_pixels": 0.4})
    g = next(g for g in e["gates"] if g["gate"] == "cryo_et_tilt_residual")
    assert g["level"] == "GOLD"


def test_cryo_et_tilt_residual_fail():
    e = build_gate_event("tilt_alignment", "cryo_et",
                          {"tilt_residual_pixels": 4.5})
    g = next(g for g in e["gates"] if g["gate"] == "cryo_et_tilt_residual")
    assert g["action"] == "halt"


def test_cryo_et_defocus_in_range():
    e = build_gate_event("import_tiltseries", "cryo_et",
                          {"defocus_um": -3.5})
    g = next(g for g in e["gates"] if g["gate"] == "cryo_et_defocus_range")
    assert g["action"] == "pass"


def test_cryo_et_defocus_out_of_range():
    e = build_gate_event("import_tiltseries", "cryo_et",
                          {"defocus_um": -12.0})
    g = next(g for g in e["gates"] if g["gate"] == "cryo_et_defocus_range")
    assert g["action"] == "halt"


def test_cryo_et_process_classification():
    from galaxy.ai.retrievers.qc_gate_emit import classify_gate_only_domain
    for proc in ("ET_FULL_PIPELINE", "IMPORT_TILTSERIES", "TILT_ALIGNMENT",
                  "TOMOGRAM_RECONSTRUCTION", "SUBTOMOGRAM_AVERAGING"):
        assert classify_gate_only_domain(proc) == "cryo_et", f"failed for {proc}"


def test_cryo_et_no_collision_with_cryo_em():
    from galaxy.ai.retrievers.qc_gate_emit import classify_gate_only_domain
    assert classify_gate_only_domain("CRYOSPARC_STANDARD_SPA") == "cryo_em"
    assert classify_gate_only_domain("TOPAZ_EXTRACT") == "cryo_em"
    assert classify_gate_only_domain("IMPORT_MICROGRAPHS") == "cryo_em"
    assert classify_gate_only_domain("IMPORT_TILTSERIES") == "cryo_et"
    assert classify_gate_only_domain("SUBTOMOGRAM_AVERAGING") == "cryo_et"


def test_cryo_et_end_to_end():
    e = build_gate_event("subtomogram_averaging", "cryo_et",
                          {"fsc_0143_resolution_angstroms": 7.2,
                           "tilt_residual_pixels": 0.4, "defocus_um": -4.0})
    assert e["passed"] is True
    assert len(e["gates"]) == 3
    for g in e["gates"]:
        assert len(g["evidence"]) >= 1


# ─── Tests for 6 domains added 2026-05-26 ─────────────────────────────

# LNP formulation
def test_lnp_z_avg_pass():
    e = build_gate_event("LNP_FORMULATION_OPTIMIZATION", "lnp_formulation", {"z_avg_nm": 85.0})
    g = next(g for g in e["gates"] if g["gate"] == "lnp_z_avg_particle_size")
    assert g["action"] == "pass"

def test_lnp_z_avg_fail():
    e = build_gate_event("LNP_FORMULATION_OPTIMIZATION", "lnp_formulation", {"z_avg_nm": 220.0})
    g = next(g for g in e["gates"] if g["gate"] == "lnp_z_avg_particle_size")
    assert g["level"] == "FAIL"

def test_lnp_pdi_fail():
    e = build_gate_event("LNP_FORMULATION_OPTIMIZATION", "lnp_formulation", {"pdi": 0.42})
    g = next(g for g in e["gates"] if g["gate"] == "lnp_pdi")
    assert g["level"] == "FAIL"

def test_lnp_encap_fail():
    e = build_gate_event("LNP_FORMULATION_OPTIMIZATION", "lnp_formulation",
                          {"encapsulation_efficiency_pct": 55.0})
    g = next(g for g in e["gates"] if g["gate"] == "lnp_encapsulation_efficiency")
    assert g["level"] == "FAIL"

# nlmixr2 popPK
def test_nlmixr2_eta_pass():
    e = build_gate_event("POPPK_NLMIXR2_FIT", "nlmixr2_poppk", {"eta_shrinkage_pct_max": 12.0})
    g = next(g for g in e["gates"] if g["gate"] == "nlmixr2_eta_shrinkage")
    assert g["level"] == "GOLD"

def test_nlmixr2_eta_fail():
    e = build_gate_event("POPPK_NLMIXR2_FIT", "nlmixr2_poppk", {"eta_shrinkage_pct_max": 42.0})
    g = next(g for g in e["gates"] if g["gate"] == "nlmixr2_eta_shrinkage")
    assert g["level"] == "FAIL"

def test_nlmixr2_condition_fail():
    e = build_gate_event("POPPK_NLMIXR2_FIT", "nlmixr2_poppk", {"condition_number": 5200.0})
    g = next(g for g in e["gates"] if g["gate"] == "nlmixr2_condition_number")
    assert g["level"] == "FAIL"

# Antibody developability
def test_ab_tap_cdr_length_pass():
    e = build_gate_event("BISPECIFIC_ANTIBODY_DESIGN", "antibody_developability",
                          {"tap_total_cdr_length": 55})
    g = next(g for g in e["gates"] if g["gate"] == "ab_tap_cdr_length")
    assert g["level"] == "GOLD"

def test_ab_tap_cdr_length_fail():
    e = build_gate_event("BISPECIFIC_ANTIBODY_DESIGN", "antibody_developability",
                          {"tap_total_cdr_length": 75})
    g = next(g for g in e["gates"] if g["gate"] == "ab_tap_cdr_length")
    assert g["level"] == "FAIL"

def test_ab_camsol_fail():
    e = build_gate_event("SCFV_ANTIBODY_DESIGN", "antibody_developability",
                          {"camsol_intrinsic_score": -0.5})
    g = next(g for g in e["gates"] if g["gate"] == "ab_camsol_intrinsic_solubility")
    assert g["level"] == "FAIL"

# siRNA
def test_sirna_seed_pass():
    e = build_gate_event("SIRNA_OFFTARGET_ANALYSIS", "sirna_offtarget",
                          {"min_seed_mismatches": 3})
    g = next(g for g in e["gates"] if g["gate"] == "sirna_seed_mismatch_count")
    assert g["action"] == "pass"

def test_sirna_seed_fail():
    e = build_gate_event("SIRNA_OFFTARGET_ANALYSIS", "sirna_offtarget",
                          {"min_seed_mismatches": 0})
    g = next(g for g in e["gates"] if g["gate"] == "sirna_seed_mismatch_count")
    assert g["level"] == "FAIL"

def test_sirna_asymmetry_pass():
    e = build_gate_event("SIRNA_DESIGN", "sirna_offtarget",
                          {"delta_dg_asymmetry_kcal_mol": 1.2})
    g = next(g for g in e["gates"] if g["gate"] == "sirna_thermodynamic_asymmetry")
    assert g["level"] == "GOLD"

# Polymorph stability
def test_polymorph_assay_fail():
    e = build_gate_event("POLYMORPH_STABILITY_SCREENING", "polymorph_stability",
                          {"assay_loss_pct_6mo_accelerated": 6.8})
    g = next(g for g in e["gates"] if g["gate"] == "assay_degradation_accelerated")
    assert g["level"] == "FAIL"

def test_polymorph_conversion_pass():
    e = build_gate_event("POLYMORPH_STABILITY_SCREENING", "polymorph_stability",
                          {"polymorph_conversion_pct": 2.1})
    g = next(g for g in e["gates"] if g["gate"] == "polymorph_form_conversion")
    assert g["action"] == "pass"

# Biomarker enrichment
def test_biomarker_hr_pass():
    e = build_gate_event("BIOMARKER_PATIENT_ENRICHMENT", "biomarker_enrichment",
                          {"biomarker_pos_hr": 0.55})
    g = next(g for g in e["gates"] if g["gate"] == "biomarker_positive_hazard_ratio")
    assert g["action"] == "pass"

def test_biomarker_hr_fail():
    e = build_gate_event("BIOMARKER_PATIENT_ENRICHMENT", "biomarker_enrichment",
                          {"biomarker_pos_hr": 0.85})
    g = next(g for g in e["gates"] if g["gate"] == "biomarker_positive_hazard_ratio")
    assert g["level"] == "FAIL"

def test_biomarker_prevalence_advisory():
    e = build_gate_event("BIOMARKER_PATIENT_ENRICHMENT", "biomarker_enrichment",
                          {"biomarker_prevalence": 0.05})
    g = next(g for g in e["gates"] if g["gate"] == "predictive_prevalence")
    assert g["action"] != "pass"

# Classification tests
def test_new_domain_classifications():
    from galaxy.ai.retrievers.qc_gate_emit import classify_gate_only_domain
    assert classify_gate_only_domain("LNP_FORMULATION_OPTIMIZATION") == "lnp_formulation"
    assert classify_gate_only_domain("POPPK_NLMIXR2_FIT") == "nlmixr2_poppk"
    assert classify_gate_only_domain("BISPECIFIC_ANTIBODY_DESIGN") == "antibody_developability"
    assert classify_gate_only_domain("SIRNA_OFFTARGET_ANALYSIS") == "sirna_offtarget"
    assert classify_gate_only_domain("POLYMORPH_STABILITY_SCREENING") == "polymorph_stability"
    assert classify_gate_only_domain("BIOMARKER_PATIENT_ENRICHMENT") == "biomarker_enrichment"
