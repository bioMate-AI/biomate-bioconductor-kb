# ANDV inhibitor track — Nextflow step-by-step execution (current work)

**Purpose**: Separate **campaign execution** (running indexed BioMate Nextflow workflows in order via the API) from **BioMate product architecture** (chat chaining, artifact DAGs). This document describes how to *finish the planned computational stages* using the batch runner script.

**Last updated**: 2026-05-09

---

## 1. Two tracks

| Track | Scope | Doc |
|-------|--------|-----|
| **Execute the plan** | Submit workflows stepwise with `POST /api/nextflow/execute`, poll status, download S3 outputs, keep a manifest. | This file + `research/anti-virus/scripts/run_andv_inhibitor_pipeline_nextflow.py` |
| **Improve BioMate orchestration** | Registry sync, gap protocol, UI DAG runner, artifact contracts. | `docs/FUTURE_WORK_BIOMATE_ORCHESTRATION.md` |

---

## 2. Script: `run_andv_inhibitor_pipeline_nextflow.py`

Location: `research/anti-virus/scripts/run_andv_inhibitor_pipeline_nextflow.py`

It runs up to **six** sequential stages aligned with the inhibitor implementation plan and the **`target_to_lead_full`** chain semantics, with **AutoDock Vina** used for structure-based docking (PDB + SMILES + box) instead of the heavier AlphaFold3-based `structure_prediction_docking` workflow.

| Step | Key | Nextflow path (repo-relative) |
|------|-----|--------------------------------|
| 1 | `pocket` | `nextflow_nfcore/subworkflows/drug_discovery/pocket_detection_druggability/main.nf` |
| 2 | `pharmacophore` | `nextflow_nfcore/subworkflows/drug_discovery/pharmacophore_filtering/main.nf` |
| 3 | `admet` | `nextflow_nfcore/subworkflows/pharmacology/predict_admet_properties/main.nf` |
| 4 | `docking_vina` | `nextflow_nfcore/subworkflows/pharmacology/docking_autodock_vina/main.nf` |
| 5 | `gromacs_mmgbsa` | `nextflow_nfcore/subworkflows/drug_discovery/gromacs_protein_md/main.nf` |
| 6 | `reinvent4` | `nextflow_nfcore/subworkflows/drug_discovery/reinvent4_lead_design/main.nf` |

**Outputs**: Each run writes under `research/anti-virus/runs/andv_nf_pipeline_<timestamp>/`, including `pipeline_manifest.json` and per-step `submit.json`, `status.json`, and downloaded artifacts when AWS CLI is available.

---

## 3. Minimal run (structure / pocket only)

Requires API key (`GALAXY_API_KEY` or `backend/config/galaxy.yml`), BioMate backend reachable, and AWS credentials if outputs are pulled from S3.

```bash
python3 research/anti-virus/scripts/run_andv_inhibitor_pipeline_nextflow.py \
  --pdb-input s3://biomate-nextflow-work/inputs/andv_campaign/20260507/9P3I.pdb \
  --through-step 1
```

This completes **Phase 1 pocket/druggability** from `ANDV_INHIBITOR_TRACK_IMPLEMENTATION.md` in the same way as the existing pocket-only monitors.

---

## 4. Extending through screening, ADMET, and docking

Later steps need **project-specific inputs** (not generated automatically by step 1):

- **Step 2 (pharmacophore)**: `--reference-actives-s3` and `--compound-library-s3` (SMILES/SDF on S3).
- **Step 3 (ADMET)**: `--smiles-json` (JSON array string). If omitted when step 3 runs, the script falls back to a tiny demo list so the workflow still executes (replace with real candidates).
- **Step 4 (Vina)**: `--smiles-json` and either **`--use-top-pocket-box`** (reads top pocket center from step 1 `*_pockets.json` in the manifest) or **`--box-center-json`** / **`--box-size-json`**. Receptor is `--pdb-input`.

Example skeleton:

```bash
python3 research/anti-virus/scripts/run_andv_inhibitor_pipeline_nextflow.py \
  --pdb-input s3://.../9P3I.pdb \
  --through-step 4 \
  --reference-actives-s3 s3://.../actives.smi \
  --compound-library-s3 s3://.../library.smi \
  --smiles-json '["SMILES1","SMILES2"]' \
  --use-top-pocket-box
```

Do **not** use `--skip-downloads` before step 4 if you rely on `--use-top-pocket-box`: the script needs local `*_pockets.json` from step 1.

---

## 5. Heavy / optional steps (5–6)

- **GROMACS + MM-GBSA** is GPU- and time-intensive. Pass **`--ligand-s3`** (ligand structure on S3). Tune **`--gromacs-n-steps`** for shorter sanity checks.
- **REINVENT4** uses **`--seed-smiles`** (and optional **`--reinvent-scoring docking_gnina`** with the same receptor PDB on S3).

---

## 6. Relationship to BioMate UI and curated chains

The chat UI can surface the same workflows via **`target_to_lead_full`** in `workflow_chains`, but **automatic file wiring between steps is not guaranteed** in product today. This script is the **explicit execution path** for “finish the plan” until orchestration improvements in `docs/FUTURE_WORK_BIOMATE_ORCHESTRATION.md` land.

---

## 7. Parallel open-library vs REINVENT4 (screening + generation)

For **pocket → REINVENT4 → ADMET → docking** alongside **open-library screening**, see **`docs/20260510_ANDV_PARALLEL_SCREEN_AND_GENERATIVE_DESIGN.md`** and scripts:

- `research/anti-virus/scripts/download_open_screening_library.py`
- `research/anti-virus/scripts/run_parallel_library_vs_generative.py`

---

## 8. Related references

- `research/anti-virus/ANDV_INHIBITOR_TRACK_IMPLEMENTATION.md`
- `research/anti-virus/BIOMATE_CAPABILITY_GAP.md`
- `docs/20260417_DRUG_DEVELOPMENT_COVERAGE_ANALYSIS.md`
- `research/anti-virus/scripts/e2e_biomate_batch_monitor.py` (single-step pocket E2E)

**Version**: 1.0
