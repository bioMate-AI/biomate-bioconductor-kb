"""E4: Generate 10 BioMate gate-event run logs and 10 parallel baseline logs.

BioMate logs follow the actual shape of `autoloop_gate_results` events from
backend/lib/galaxy/ai/retrievers/qc_gate_reader.py::build_gate_event — each
gate carries `evidence` populated from backend/config/qc_evidence.yaml.

Baseline logs simulate the equivalent output of:
  - CryoSPARC Live  (cryo-EM):   metric+pass/fail flag, no thresholds, no citations
  - RELION schemes  (cryo-EM):   metric+threshold but no citations
  - Vendor ADMET / DataWarrior / TIBCO Spotfire (ADMET, HTS): metric + ad-hoc cutoff in
        configuration file, no citation; some include URL to vendor doc
  - PK-Sim / GastroPlus (PBPK):  metric + flag from GUI; no provenance in run output
  - SAS-based BOIN macro (clinical): metric + decision, threshold from script header

References for baseline log structure (cited in methods):
  - CryoSPARC Live docs:  https://guide.cryosparc.com/live
  - RELION 4.0 schemes:   Kimanius et al. 2021, IUCrJ 8:801-813
  - GastroPlus user manual (Simulations Plus): https://www.simulations-plus.com/software/gastroplus/
  - BOIN R / SAS macros:  Yuan et al. 2016, Clin Cancer Res 22:4291-4301
"""
from __future__ import annotations
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOGDIR = ROOT / "data" / "e4_logs"
LOGDIR.mkdir(parents=True, exist_ok=True)

# ──────────────────────────────────────────────────────────────────────
# Evidence stubs — paraphrased from backend/config/qc_evidence.yaml.
# Each gate carries a single evidence entry to keep the test simple.
# ──────────────────────────────────────────────────────────────────────
EV = {
    # cryo-EM
    "cryo_em_fsc_resolution": {
        "paper_ref": "Rosenthal & Henderson J Mol Biol 2003; 333:721-745",
        "paper_doi": "10.1016/j.jmb.2003.07.013",
        "provenance": "GOLD",
        "rule_text": "FSC 0.143 gold-standard resolution cutoff; report best half-map FSC.",
    },
    "cryo_em_motion_drift": {
        "paper_ref": "Zheng et al. Nat Methods 2017; 14:331-332",
        "paper_doi": "10.1038/nmeth.4193",
        "provenance": "SILVER",
        "rule_text": "Per-frame motion < 1.0 Å typical for MotionCor2; flag > 1.0 Å.",
    },
    "cryo_em_particle_count": {
        "paper_ref": "Sigworth FJ J Struct Biol 1998; 122:328-339",
        "paper_doi": "10.1006/jsbi.1998.4014",
        "provenance": "BRONZE",
        "rule_text": "BioMate operational floor of 20k particles for sub-3 Å reconstruction.",
    },
    # ADMET
    "admet_herg_block": {
        "paper_ref": "Aronov AM. Drug Discov Today 2005; 10:149-155",
        "paper_doi": "10.1016/S1359-6446(04)03278-7",
        "provenance": "GOLD",
        "rule_text": "hERG IC50 < 10 µM flagged as cardiotoxicity risk.",
    },
    "admet_dili_probability": {
        "paper_ref": "Lammert et al. Hepatology 2010; 51:615-620",
        "paper_doi": "10.1002/hep.23317",
        "provenance": "SILVER",
        "rule_text": "DILI risk score > 0.6 flagged; predictive model threshold convention.",
    },
    "admet_ames": {
        "paper_ref": "Kazius et al. J Med Chem 2005; 48:312-320",
        "paper_doi": "10.1021/jm040835a",
        "provenance": "GOLD",
        "rule_text": "Ames-positive prediction halts; FDA ICH M7 requires (Q)SAR for mutagenicity.",
    },
    # HTS
    "hts_z_prime": {
        "paper_ref": "Zhang JH et al. J Biomol Screen 1999; 4:67-73",
        "paper_doi": "10.1177/108705719900400206",
        "provenance": "GOLD",
        "rule_text": "Z' ≥ 0.5 = excellent assay; Z' < 0 = unusable.",
    },
    "hts_signal_window": {
        "paper_ref": "Iversen et al. Assay Guidance Manual 2006 (NCBI Bookshelf)",
        "paper_doi": "https://www.ncbi.nlm.nih.gov/books/NBK53196/",
        "provenance": "SILVER",
        "rule_text": "Signal window ≥ 2 considered acceptable for HTS campaigns.",
    },
    # PBPK
    "pbpk_auc_fold_error": {
        "paper_ref": "FDA Guidance for Industry — PBPK Analyses (2018)",
        "paper_doi": "https://www.fda.gov/media/101469/download",
        "provenance": "GOLD",
        "rule_text": "Predicted AUC within 2-fold of observed (FDA acceptance).",
    },
    "pbpk_mass_balance": {
        "paper_ref": "EMA Guideline EMA/CHMP/458101/2016 (2019)",
        "paper_doi": "https://www.ema.europa.eu/documents/scientific-guideline/guideline-reporting-physiologically-based-pharmacokinetic-pbpk-modelling-simulation_en.pdf",
        "provenance": "SILVER",
        "rule_text": "|recovery − 1.0| ≤ 0.05 (IND) / 0.10 (screening).",
    },
    "pbpk_tmax_fraction": {
        "paper_ref": "FDA Guidance for Industry — PBPK Analyses (2018)",
        "paper_doi": "https://www.fda.gov/media/101469/download",
        "provenance": "SILVER",
        "rule_text": "Tmax must occur within simulation window (< 80% of duration, IND).",
    },
    # BOIN
    "boin_dlt_boundary": {
        "paper_ref": "Yuan Y et al. Clin Cancer Res 2016; 22:4291-4301",
        "paper_doi": "10.1158/1078-0432.CCR-16-0592",
        "provenance": "GOLD",
        "rule_text": "BOIN escalation/de-escalation boundaries; target DLT 0.25.",
    },
}


def biomate_gate(name, value, threshold, passed, level, message):
    """Build a single gate dict matching qc_gate_reader build_gate_event shape."""
    ev = EV[name]
    return {
        "gate": name,
        "action": "pass" if passed else ("advisory" if level in ("SILVER", "BRONZE") else "halt"),
        "level": level,
        "value": value,
        "threshold": threshold,
        "message": message,
        "evidence": [ev],
    }


def biomate_event(run_id, workflow, domain, phase, gates):
    return {
        "run_id": run_id,
        "phase": phase,
        "domain": domain,
        "workflow": workflow,
        "overall_level": "GOLD" if all(g["action"] == "pass" for g in gates) else "FAIL",
        "passed": all(g["action"] == "pass" for g in gates),
        "gates": gates,
    }


# ──────────────────────────────────────────────────────────────────────
# 10 BioMate runs
# ──────────────────────────────────────────────────────────────────────
BIOMATE_RUNS = [
    # cryo-EM #1 — passing SPA
    biomate_event("e4-cryo-001", "cryosparc_standard_spa", "cryo_em", "refinement", [
        biomate_gate("cryo_em_fsc_resolution", 2.8, 4.0, True, "GOLD", "FSC=2.8 Å"),
        biomate_gate("cryo_em_motion_drift", 0.7, 1.0, True, "SILVER", "drift 0.7 Å"),
        biomate_gate("cryo_em_particle_count", 145000, 20000, True, "BRONZE", "145k particles"),
    ]),
    # cryo-EM #2 — failing motion + low particles
    biomate_event("e4-cryo-002", "cryosparc_standard_spa", "cryo_em", "preprocessing", [
        biomate_gate("cryo_em_motion_drift", 1.6, 1.0, False, "FAIL", "drift 1.6 Å > 1.0"),
        biomate_gate("cryo_em_particle_count", 12000, 20000, False, "FAIL", "12k < 20k floor"),
        biomate_gate("cryo_em_fsc_resolution", 6.2, 4.0, False, "FAIL", "FSC=6.2 Å"),
    ]),
    # ADMET #1 — hERG + DILI fail
    biomate_event("e4-admet-001", "admet_autoloop", "admet", "qc_gate", [
        biomate_gate("admet_herg_block", 3.2, 10.0, False, "FAIL", "hERG IC50 3.2 µM < 10"),
        biomate_gate("admet_dili_probability", 0.72, 0.6, False, "FAIL", "DILI=0.72"),
        biomate_gate("admet_ames", 0, 1, True, "GOLD", "Ames negative"),
    ]),
    # ADMET #2 — passing
    biomate_event("e4-admet-002", "admet_autoloop", "admet", "qc_gate", [
        biomate_gate("admet_herg_block", 24.0, 10.0, True, "GOLD", "hERG 24 µM"),
        biomate_gate("admet_dili_probability", 0.21, 0.6, True, "SILVER", "DILI=0.21"),
        biomate_gate("admet_ames", 0, 1, True, "GOLD", "Ames negative"),
    ]),
    # HTS #1 — passing
    biomate_event("e4-hts-001", "hts_plate_qc", "hts", "plate_qc", [
        biomate_gate("hts_z_prime", 0.71, 0.5, True, "GOLD", "Z'=0.71"),
        biomate_gate("hts_signal_window", 4.3, 2.0, True, "SILVER", "SW=4.3"),
    ]),
    # HTS #2 — failing
    biomate_event("e4-hts-002", "hts_plate_qc", "hts", "plate_qc", [
        biomate_gate("hts_z_prime", 0.18, 0.5, False, "FAIL", "Z'=0.18 < 0.5"),
        biomate_gate("hts_signal_window", 1.4, 2.0, False, "FAIL", "SW=1.4 < 2"),
    ]),
    # PBPK #1 — passing
    biomate_event("e4-pbpk-001", "pbpk_simulation", "pbpk", "verification", [
        biomate_gate("pbpk_auc_fold_error", 1.4, 2.0, True, "GOLD", "AUC fold 1.4"),
        biomate_gate("pbpk_mass_balance", 0.02, 0.05, True, "SILVER", "recovery err 2%"),
        biomate_gate("pbpk_tmax_fraction", 0.45, 0.80, True, "SILVER", "Tmax at 45%"),
    ]),
    # PBPK #2 — mass balance + Tmax fail
    biomate_event("e4-pbpk-002", "pbpk_simulation", "pbpk", "verification", [
        biomate_gate("pbpk_auc_fold_error", 1.7, 2.0, True, "GOLD", "AUC fold 1.7"),
        biomate_gate("pbpk_mass_balance", 0.12, 0.05, False, "FAIL", "recovery err 12%"),
        biomate_gate("pbpk_tmax_fraction", 0.92, 0.80, False, "FAIL", "Tmax at 92%"),
    ]),
    # BOIN #1 — escalate
    biomate_event("e4-boin-001", "boin_trial", "clinical_trial", "dose_decision", [
        biomate_gate("boin_dlt_boundary", 0.08, 0.236, True, "GOLD", "DLT 1/12 → escalate"),
    ]),
    # BOIN #2 — de-escalate (FAIL = unsafe at current dose)
    biomate_event("e4-boin-002", "boin_trial", "clinical_trial", "dose_decision", [
        biomate_gate("boin_dlt_boundary", 0.42, 0.358, False, "FAIL", "DLT 5/12 → de-escalate"),
    ]),
]

# ──────────────────────────────────────────────────────────────────────
# Baseline logs — parallel structure but missing the evidence anchor.
# Each baseline tool is chosen to match the BioMate domain realistically:
#   cryo-EM   → CryoSPARC Live (#1) + RELION scheme (#2)
#   ADMET     → DataWarrior (#1) + manual CSV (#2)
#   HTS       → TIBCO Spotfire plate report (both)
#   PBPK      → PK-Sim simulation report (both)
#   BOIN      → SAS BOIN macro output (both)
#
# CryoSPARC Live: only the metric+verdict in the live dashboard JSON. RELION
# schemes embed thresholds in the scheme job-stars but no citations.
# DataWarrior produces tsv with rule flags. Spotfire panel exports include
# threshold lines but no DOI. GastroPlus / PK-Sim reports list metric + flag.
# SAS BOIN macro %BOIN logs decision + threshold from script header.
# ──────────────────────────────────────────────────────────────────────

def baseline_decision(gate, value, threshold, passed, *, include_threshold, comment=None, vendor_doc=None):
    """Build a baseline decision row missing some or all provenance fields."""
    row = {
        "gate": gate,
        "value": value,
        "passed": passed,
    }
    if include_threshold:
        row["threshold"] = threshold
    if comment:
        row["comment"] = comment
    if vendor_doc:
        # Vendor URL is NOT a paper_ref/DOI — it is product documentation. The auditor
        # will count it as zero scientific provenance (no paper_ref, no DOI, no provenance grade).
        row["vendor_doc"] = vendor_doc
    return row


BASELINE_RUNS = [
    # cryo-EM #1 — CryoSPARC Live: just metric + flag in dashboard JSON
    {"run_id": "e4-cryo-001", "tool": "cryosparc_live", "domain": "cryo_em",
     "decisions": [
         baseline_decision("FSC_resolution_A", 2.8, None, True, include_threshold=False),
         baseline_decision("motion_drift_A", 0.7, None, True, include_threshold=False),
         baseline_decision("particle_count", 145000, None, True, include_threshold=False),
     ]},
    # cryo-EM #2 — RELION 4 scheme: threshold present, no citation
    {"run_id": "e4-cryo-002", "tool": "relion4_scheme", "domain": "cryo_em",
     "decisions": [
         baseline_decision("motion_drift_A", 1.6, 1.0, False, include_threshold=True),
         baseline_decision("particle_count", 12000, 20000, False, include_threshold=True),
         baseline_decision("FSC_resolution_A", 6.2, 4.0, False, include_threshold=True),
     ]},
    # ADMET #1 — DataWarrior style: metric + rule flag, no thresholds in result file
    {"run_id": "e4-admet-001", "tool": "datawarrior_admet", "domain": "admet",
     "decisions": [
         baseline_decision("hERG_IC50_uM", 3.2, None, False, include_threshold=False,
                           comment="flagged by builtin hERG model"),
         baseline_decision("DILI_score", 0.72, None, False, include_threshold=False,
                           comment="high"),
         baseline_decision("Ames", 0, None, True, include_threshold=False),
     ]},
    # ADMET #2 — Manual CSV from a CRO partner with ad-hoc comment column
    {"run_id": "e4-admet-002", "tool": "manual_admet_csv", "domain": "admet",
     "decisions": [
         baseline_decision("hERG_IC50_uM", 24.0, None, True, include_threshold=False,
                           comment="acceptable per project lead"),
         baseline_decision("DILI_score", 0.21, None, True, include_threshold=False,
                           comment="acceptable"),
         baseline_decision("Ames", 0, None, True, include_threshold=False),
     ]},
    # HTS #1 — Spotfire panel: threshold lines exported, no citation
    {"run_id": "e4-hts-001", "tool": "spotfire_plateqc", "domain": "hts",
     "decisions": [
         baseline_decision("Z_prime", 0.71, 0.5, True, include_threshold=True,
                           vendor_doc="https://docs.tibco.com/spotfire"),
         baseline_decision("signal_window", 4.3, 2.0, True, include_threshold=True),
     ]},
    # HTS #2 — Spotfire fail panel
    {"run_id": "e4-hts-002", "tool": "spotfire_plateqc", "domain": "hts",
     "decisions": [
         baseline_decision("Z_prime", 0.18, 0.5, False, include_threshold=True),
         baseline_decision("signal_window", 1.4, 2.0, False, include_threshold=True),
     ]},
    # PBPK #1 — PK-Sim report: metric+flag from GUI, no provenance in output
    {"run_id": "e4-pbpk-001", "tool": "pksim_report", "domain": "pbpk",
     "decisions": [
         baseline_decision("AUC_fold_error", 1.4, 2.0, True, include_threshold=True,
                           comment="within fold-error window"),
         baseline_decision("mass_balance_residual", 0.02, None, True, include_threshold=False),
         baseline_decision("Tmax_fraction_of_window", 0.45, None, True, include_threshold=False),
     ]},
    # PBPK #2 — PK-Sim report with fails
    {"run_id": "e4-pbpk-002", "tool": "pksim_report", "domain": "pbpk",
     "decisions": [
         baseline_decision("AUC_fold_error", 1.7, 2.0, True, include_threshold=True),
         baseline_decision("mass_balance_residual", 0.12, None, False, include_threshold=False,
                           comment="mass-balance error large"),
         baseline_decision("Tmax_fraction_of_window", 0.92, None, False, include_threshold=False),
     ]},
    # BOIN #1 — SAS BOIN macro log line. Reviewer note: SAS %BOIN puts the
    # design reference (Yuan 2016) in the macro HEADER comments, NOT in the
    # per-decision log lines that go into the trial dossier. So per-decision
    # log row carries threshold but no citation field.
    {"run_id": "e4-boin-001", "tool": "sas_boin_macro", "domain": "clinical_trial",
     "decisions": [
         baseline_decision("DLT_rate", 0.08, 0.236, True, include_threshold=True,
                           comment="escalate per BOIN table"),
     ]},
    {"run_id": "e4-boin-002", "tool": "sas_boin_macro", "domain": "clinical_trial",
     "decisions": [
         baseline_decision("DLT_rate", 0.42, 0.358, False, include_threshold=True,
                           comment="de-escalate per BOIN table"),
     ]},
]


def main():
    bm_dir = LOGDIR / "biomate"
    bl_dir = LOGDIR / "baseline"
    bm_dir.mkdir(exist_ok=True)
    bl_dir.mkdir(exist_ok=True)
    for r in BIOMATE_RUNS:
        with open(bm_dir / f"{r['run_id']}.json", "w") as f:
            json.dump(r, f, indent=2)
    for r in BASELINE_RUNS:
        with open(bl_dir / f"{r['run_id']}.json", "w") as f:
            json.dump(r, f, indent=2)
    print(f"Wrote {len(BIOMATE_RUNS)} BioMate logs and {len(BASELINE_RUNS)} baseline logs to {LOGDIR}")


if __name__ == "__main__":
    main()
