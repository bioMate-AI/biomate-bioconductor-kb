"""Freeze evaluation roles for the extracted labels. Deterministic, no RNG.

Every entry is quarantined: role is assigned but training_eligible stays False
until (a) the matched expression matrix / arm tables are joined, (b) overlap vs
existing pretraining+KG+text is checked, and (c) a human signs off. This file
only FREEZES which units are reserved for blind external test so later steps
cannot leak them into training.
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
geo = json.loads((ROOT / "geo_label_summary.json").read_text())
trial_reg = json.loads((ROOT / "trial_label_register.json").read_text())
# reproducibility QC from matrix build (may be absent for GSEs whose matrix isn't local)
mat = {}
for mp in (ROOT / "geo_matrix_summary.json", ROOT / "gse113156_matrix_summary.json"):
    if mp.exists():
        mat.update(json.loads(mp.read_text()))

reg = {"frozen": True, "training_eligible": False, "geo": {}, "trials": {}}
MIN_REPRO_R = 0.3  # per-patient labels below this are not reliable enough to score on

# GEO: role gated by BOTH pairing AND per-patient reproducibility QC
for gse, s in geo.items():
    paired = s["n_paired_pre_post"]
    qc = mat.get(gse, {})
    rep_r = qc.get("median_dye_swap_replicate_r")
    entry = dict(
        n_samples=s["n_samples"], n_paired_pre_post=paired,
        n_response_labeled=s["n_response_labeled"],
        split_rule="all timepoints of a patient stay on the same side of the split",
    )
    if rep_r is not None and rep_r < MIN_REPRO_R:
        # dye-swap / replicate design that fails per-patient reproducibility
        entry.update(
            design=qc.get("design"),
            RETRACTED_prior_framing="counted as paired pre/post durability patients — WRONG; see qc",
            qc_median_replicate_r=rep_r,
            role="DEMOTED: cohort-average evidence-only; NOT a per-patient eval cohort",
            reason="per-patient contrasts not reproducible between replicates; no reliable per-patient labels",
            heldout_patients="N/A",
        )
    elif qc.get("complete_w0_w24_pairs") is not None:
        # real matrix joined (e.g. GSE113156 RNA-seq)
        entry.update(
            assay=qc.get("assay"), n_genes=qc.get("n_genes"),
            complete_w0_w24_pairs=qc.get("complete_w0_w24_pairs"),
            matrix=qc.get("matrix"),
            role=qc.get("role", "external-test only (matrix joined)"),
            heldout_patients="ALL",
        )
    elif "gap" in qc:
        entry.update(
            role="labels ready but expression matrix NOT local — blocked on series-matrix download",
            gap=qc.get("gap"), heldout_patients="ALL (whole study, once matrix obtained)",
        )
    elif paired >= 20:
        entry.update(role="train+dev with frozen patient-held-out test",
                     heldout_patients=s["proposed_heldout_patients"])
    elif paired > 0:
        entry.update(role="external-test only (too few paired patients to train)", heldout_patients="ALL")
    else:
        entry.update(role="evidence-only / external-test (cross-sectional, no pairing, small n)",
                     heldout_patients="ALL")
    reg["geo"][gse] = entry

# Trials: aggregate evidence; freeze ~20% of usable NCTs per disease as external test
usable = set(trial_reg.get("_usable_trial_ncts", []))
for disease in ["rheumatoid_arthritis", "asthma", "lupus"]:
    recs = json.loads((ROOT / f"trial_labels_{disease}.json").read_text())
    disease_usable = sorted(r["nct"] for r in recs if r["nct"] in usable)
    n_test = max(1, round(len(disease_usable) * 0.2)) if disease_usable else 0
    # deterministic: hash-free, take every 5th by sorted NCT for the test fold
    test = [nct for i, nct in enumerate(disease_usable) if i % 5 == 0][:n_test]
    reg["trials"][disease] = dict(
        usable_aggregate_trials=len(disease_usable),
        frozen_external_test=test,
        role="aggregate efficacy/safety/withdrawal evidence; trial-held-out external test",
        caveat="arm-level only; NOT patient time-to-event; do not expand to per-patient examples",
    )

# ImmPort measured immune-response (vaccine HAI/neutAb) — built from DR66 parquet in S3
ivp = ROOT / "immport_vaccine_response_summary.json"
if ivp.exists():
    s = json.loads(ivp.read_text())
    reg["immport_vaccine_response"] = dict(
        source=s["source"],
        objective="immune response prediction (measured pre/post vaccine titers)",
        total_subjects=s["total_subjects"], total_studies=s["total_studies"],
        total_response_rows=s["total_response_rows"],
        usable_seroconversion_rows=s["usable_seroconversion_rows"],
        raw_titer_studies=s["raw_titer_studies"], log_scale_studies_flagged=s["log_or_index_studies"],
        role="train/dev + STUDY-held-out external test (24 studies frozen)",
        frozen_study_heldout_test=s["frozen_study_heldout_test"],
        split_rule="all subjects/strains of a held-out STUDY stay together",
        leakage="ImmPort not wired into training (verified); quarantine until knowledge-source exclusion confirmed",
        caveats=s["caveats"],
    )

# ImmPort safety (arm-level AE rates)
sfp = ROOT / "immport_safety_summary.json"
if sfp.exists():
    s = json.loads(sfp.read_text())
    reg["immport_safety"] = dict(
        source=s["source"], objective=s["objective"],
        n_arms=s["n_arms"], n_studies=s["n_studies"],
        scope=s["scope"], arms_excluded_no_ae_collection=s["arms_excluded_no_ae_collection"],
        n_subjects=s["n_subjects_in_denominator"],
        role=s["role"], frozen_study_heldout_test=s["frozen_study_heldout_test"],
        caveats=s["caveats"],
    )

# ImmPort therapy-duration (iWITH survival)
iwp = ROOT / "immport_iwith_survival_summary.json"
if iwp.exists():
    s = json.loads(iwp.read_text())
    reg["immport_therapy_duration_iwith"] = dict(
        source=s["source"], objective=s["objective"],
        n_enrolled=s["n_enrolled_with_followup"], n_events=s["n_rejection_events"],
        event_rate=s["event_rate"], median_time_to_rejection_days=s["median_time_to_rejection_days"],
        median_followup_days=s["median_followup_days"],
        role=s["role"], caveats=s["caveats"],
    )

reg["_admission_gate"] = (
    "All roles pending: matrix/arm-table join, overlap-vs-training dedup, human sign-off. "
    "No optimization on these labels until gate cleared."
)
(ROOT / "EVAL_REGISTER.json").write_text(json.dumps(reg, indent=2) + "\n")
print(json.dumps(reg, indent=2))
