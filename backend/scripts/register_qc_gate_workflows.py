#!/usr/bin/env python3
"""
register_qc_gate_workflows.py

Idempotent registration of the 5 gate-only drug-dev workflows that were missing
from the chat-routing DB (galaxy_ai_tools.db). Matches schema and workflow_hash
idempotency used by register_ai_tool_workflows.py.

Already-registered (confirmed pre-run): hts_plate_qc_hit_calling,
ich_s5_reproductive_tox, ich_s7a_safety_pharmacology, clinical_trial_simulation,
adaptive_trial_design, allometric_scaling, lnp_formulation_optimization,
scfv_antibody_design, bispecific_antibody_design, sirna_offtarget_analysis,
polymorph_stability_screening, biomarker_patient_enrichment.

This script adds the 5 still-missing ones:
  - ivive_hepatic_clearance
  - openfe_rbfe
  - p0_pkpd_semaglutide
  - pocket_detection_druggability
  - aizynthfinder_retrosynthesis

Usage:
    python scripts/register_qc_gate_workflows.py [--db PATH] [--dry-run]
"""

import argparse
import hashlib
import json
import sqlite3
import sys
from datetime import datetime
from pathlib import Path

REPO_ROOT = Path(__file__).parent.parent
NF_BASE   = REPO_ROOT / "biomni_workflows" / "nextflow_nfcore" / "subworkflows"

WORKFLOWS = [
    {
        "name":        "ivive_hepatic_clearance",
        "filename":    "drug_discovery/ivive_hepatic_clearance/main.nf",
        "description": (
            "In vitro to in vivo extrapolation (IVIVE) of hepatic clearance. "
            "Scales microsomal or hepatocyte CLint to predicted in vivo hepatic clearance (CLh) "
            "using the well-stirred liver model (Wilkinson & Shand 1975; Obach 1999). "
            "Supports microsomal CLint (uL/min/mg) scaled via MPPGL, hepatocyte CLint "
            "(uL/min/1e6 cells) scaled via hepatocellularity; human/rat/mouse/dog. "
            "Input: clint_in_vitro, assay_type, fu_plasma, fu_inc, species, scaling_model. "
            "Output: ivive_results.json with CLh, CLh/QH fraction, uncertainty bounds."
        ),
        "annotation":  "IVIVE hepatic clearance (well-stirred / parallel-tube / dispersion). Input: CLint+fu. Output: ivive_results.json.",
        "tags":        "IVIVE,hepatic clearance,CLint,microsomal,hepatocyte,well-stirred model,MPPGL,Obach 1999,DMPK,intrinsic clearance",
        "domain":      "pharmacology",
        "category":    "Pharmacokinetics",
        "docker_image":"399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86",
        "input_types": ["json"],
        "output_types":["json", "csv"],
        "step_count":  1,
        "tools_used":  "SciPy, Wilkinson & Shand 1975, Obach 1999, MPPGL/hepatocellularity scaling",
    },
    {
        "name":        "openfe_rbfe",
        "filename":    "drug_discovery/openfe_rbfe/main.nf",
        "description": (
            "Relative Binding Free Energy (RBFE) alchemical perturbation pipeline using OpenFE. "
            "Computes DDG (kcal/mol) between two ligands competing for the same binding site via "
            "lambda-window replica exchange on GPU (OpenMM 8). "
            "Steps: RDKit + OpenFF Sage 2.2 ligand prep; PDBFixer + AmberFF14SB protein prep; "
            "Lomap2 MCS atom-mapping; OpenFE SepTop/RBFE protocol; MBAR analysis with Cinnabar. "
            "Input: receptor.pdb + ligand_a.sdf + ligand_b.sdf. "
            "Output: ddg_summary.json, overlap_matrix.png, ddg_convergence.png, rbfe_network.json."
        ),
        "annotation":  "OpenFE RBFE alchemical free energy (MBAR + Lomap2). Input: receptor+ligand_a+ligand_b. Output: ddg_summary.json.",
        "tags":        "RBFE,free energy perturbation,FEP,alchemical,OpenFE,OpenMM,MBAR,Lomap2,binding affinity,DDG,lead optimization,SepTop",
        "domain":      "drug_discovery",
        "category":    "Free Energy",
        "docker_image":"399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86",
        "input_types": ["pdb", "sdf"],
        "output_types":["json", "png", "html"],
        "step_count":  5,
        "tools_used":  "OpenFE, OpenMM 8, OpenFF Sage 2.2, Lomap2, Cinnabar, MBAR",
    },
    {
        "name":        "p0_pkpd_semaglutide",
        "filename":    "drug_discovery/p0_pkpd_semaglutide/main.nf",
        "description": (
            "P0 PKPD pipeline validation against published human semaglutide data. "
            "Runs a 2-compartment SC pharmacokinetic model with a GLP-1R Emax body-weight PD model, "
            "then validates predictions against Overgaard 2019 (Diabetes Therapy) PK reference and "
            "SUSTAIN-1 (Sorli 2017 Lancet Diabetes Endocrinol) PD reference. "
            "Pass criteria: predicted Cmax/AUCtau within 30% of Overgaard; 30-week body weight "
            "change between -3.0 and -6.0 kg (SUSTAIN-1 mean -4.53 kg). "
            "Input: dose_mg, n_weeks, PK params (CL/V1/Q/V2/ka/F). "
            "Output: pkpd_validation.json (pass/fail per metric), pk_profile.csv, pd_curve.csv."
        ),
        "annotation":  "P0 PKPD validation: 2-cmt SC PK + GLP-1R Emax PD vs semaglutide SUSTAIN-1. Output: pkpd_validation.json.",
        "tags":        "P0,PKPD validation,semaglutide,GLP-1,SUSTAIN-1,2-compartment,Emax,body weight,Overgaard 2019,Sorli 2017,subcutaneous,obesity,diabetes",
        "domain":      "drug_discovery",
        "category":    "Pharmacokinetics",
        "docker_image":"399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86",
        "input_types": ["json"],
        "output_types":["json", "csv"],
        "step_count":  1,
        "tools_used":  "SciPy ODE, NumPy, matplotlib, Overgaard 2019 PK, SUSTAIN-1 PD reference",
    },
    {
        "name":        "pocket_detection_druggability",
        "filename":    "drug_discovery/pocket_detection_druggability/main.nf",
        "description": (
            "fpocket-based binding-site detection and druggability assessment for a protein target. "
            "Detects binding cavities in a PDB structure and scores each pocket by volume (A^3), "
            "druggability score (0-1, Schmidtke & Barril 2010), hydrophobicity index, and polarity "
            "fraction. Applies an evidence-graded QC gate: PASS if best pocket druggability >= "
            "min_druggability AND volume >= min_volume; WARN if druggability >= warn_druggability; "
            "FAIL otherwise. "
            "Input: pdb_input (path or 4-letter PDB ID), min_druggability, min_volume. "
            "Output: pockets.csv (ranked), druggability_qc.json (PASS/WARN/FAIL with reasoning)."
        ),
        "annotation":  "fpocket pocket detection + druggability QC gate. Input: PDB. Output: pockets.csv, druggability_qc.json.",
        "tags":        "pocket detection,fpocket,druggability,binding site,cavity detection,Schmidtke Barril,target assessment,structure-based drug design,SBDD",
        "domain":      "drug_discovery",
        "category":    "Target Assessment",
        "docker_image":"399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86",
        "input_types": ["pdb"],
        "output_types":["json", "csv"],
        "step_count":  2,
        "tools_used":  "fpocket (Le Guilloux 2009), Schmidtke & Barril 2010 druggability score",
    },
    {
        "name":        "aizynthfinder_retrosynthesis",
        "filename":    "drug_discovery/aizynthfinder_retrosynthesis/main.nf",
        "description": (
            "Retrosynthesis route prediction for drug-like small molecules using AiZynthFinder "
            "(AstraZeneca open-source CASP tool). For each input SMILES, generates up to "
            "max_routes synthesis routes (max_depth tree depth), each scored by step count and "
            "feasibility. Applies QC gate: PASS if >=1 route has <=4 steps AND score >=0.6; "
            "WARN if best route is 5-6 steps; FAIL if no routes found or all >6 steps. "
            "Aggregates per-compound results into HTML report + CSV + QC JSON for CRO integration. "
            "Input: smiles_list (one per compound), max_routes, max_depth. "
            "Output: routes.json, filtered.tsv, report.html, qc_summary.json."
        ),
        "annotation":  "AiZynthFinder retrosynthesis + QC gate. Input: SMILES list. Output: routes.json, qc_summary.json, report.html.",
        "tags":        "retrosynthesis,AiZynthFinder,CASP,synthesis route,synthesizability,AstraZeneca,SA score,medicinal chemistry,synthetic accessibility",
        "domain":      "drug_discovery",
        "category":    "Drug Discovery",
        "docker_image":"399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86",
        "input_types": ["smiles"],
        "output_types":["json", "tsv", "html"],
        "step_count":  3,
        "tools_used":  "AiZynthFinder (Genheden 2020), RDKit, SA Score (Ertl & Schuffenhauer 2009)",
    },
]


def _hash(name: str, filename: str) -> str:
    return hashlib.sha256(f"{name}:{filename}".encode()).hexdigest()[:16]


def register(db_path: Path, dry_run: bool = False) -> None:
    conn = sqlite3.connect(db_path)
    cur  = conn.cursor()

    added = 0
    skipped = 0

    for wf in WORKFLOWS:
        wf_hash = _hash(wf["name"], wf["filename"])

        cur.execute("SELECT id FROM workflows WHERE workflow_hash=? OR name=?",
                    (wf_hash, wf["name"]))
        if cur.fetchone():
            print(f"  [skip] {wf['name']} already registered")
            skipped += 1
            continue

        nf_path = NF_BASE / wf["filename"]
        if not nf_path.exists():
            print(f"  [ERR ] missing main.nf: {nf_path}")
            continue
        nf_content = nf_path.read_text()

        if dry_run:
            print(f"  [dry-run] would register: {wf['name']}")
            added += 1
            continue

        cur.execute("""
            INSERT INTO workflows
                (name, filename, description, annotation, tags, domain,
                 workflow_json, step_count, tools_used, source, format,
                 executable, docker_image, category, workflow_hash, indexed_at,
                 input_types, output_types)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (
            wf["name"], wf["filename"], wf["description"], wf["annotation"],
            wf["tags"], wf["domain"], nf_content, wf["step_count"],
            wf["tools_used"], "nextflow", "nextflow", 1,
            wf["docker_image"], wf["category"], wf_hash,
            datetime.utcnow().isoformat(),
            json.dumps(wf["input_types"]), json.dumps(wf["output_types"]),
        ))
        print(f"  [added]  {wf['name']} (id={cur.lastrowid})")
        added += 1

    if not dry_run and added > 0:
        cur.execute("INSERT INTO workflows_fts(workflows_fts) VALUES('rebuild')")
        conn.commit()
        print("\nFTS index rebuilt.")

    conn.close()
    print(f"\nDone: {added} added, {skipped} skipped.")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", default=str(REPO_ROOT / "database" / "galaxy_ai_tools.db"))
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    db_path = Path(args.db)
    if not db_path.exists():
        sys.exit(f"DB not found: {db_path}")

    print(f"Registering QC-gate workflows into {db_path}")
    register(db_path, dry_run=args.dry_run)


if __name__ == "__main__":
    main()
