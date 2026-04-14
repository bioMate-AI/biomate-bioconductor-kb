# Drug Discovery Workflow Audit — 2026-04-04

## Purpose
Comprehensive audit of all `drug_discovery` domain Nextflow workflows in BioMate.
Covers: container settings, mock_mode defaults, DB registration, E2E test coverage.

---

## 1. Summary of Changes This Session

### 1.1 New Workflows Created (S5/S6 Pilot)
| ID | Workflow | Path | DB ID |
|----|----------|------|-------|
| S5 | `assay_ingestion_and_ranking` | `drug_discovery/assay_ingestion_and_ranking/main.nf` | 12814 |
| S6 | `cro_submission_export` | `drug_discovery/cro_submission_export/main.nf` | 12815 |

Both registered in DB with FTS, routing clauses added to `galaxy-assistant.ts` system prompt,
and keyword weights added to `unified_workflow_search.py`.

### 1.2 Mock Mode — Fixed Across All Workflows
**Rule**: `params.mock_mode` default MUST be `false` in all production `.nf` and `nextflow.config` files.

Files changed (23 total across `main.nf` + `nextflow.config`):

| Workflow | Was | Now |
|----------|-----|-----|
| `aizynthfinder_retrosynthesis` | `true` | `false` |
| `alphafold_db_search` | configs only | `false` |
| `amber_pmemd_md` | `true` | `false` |
| `drug_moa_rnaseq` | `true` | `false` |
| `gromacs_protein_md` | `true` | `false` |
| `moe_covalent_docking` | `true` | `false` |
| `nca_pknca` | `true` | `false` |
| `pharmacophore_filtering` | configs only | `false` |
| `pocket_detection_druggability` | configs only | `false` |
| `reinvent4_lead_design` | `true` | `false` |
| `scaffold_hopping` | `true` | `false` |
| `schrodinger_glide_docking` | `true` | `false` |
| `structure_prediction_docking` | `true` | `false` |

> **Note**: `"mock_mode": True` strings inside Python dict literals within heredocs are NOT changed —
> these are internal code branch values, not the Nextflow parameter default.

### 1.3 Container Settings — Dual-Container Pattern Applied
**Rule**: All container directives use:
```groovy
container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? 'ECR_IMAGE' : 'LOCAL_IMAGE'
```
When `NEXTFLOW_USE_AWS=true` (backend `.env`), ECR image is used for AWS Batch (AMD64).
Otherwise the local ARM image is used.

---

## 2. Complete Workflow Inventory

### Drug Discovery — drug_discovery/ (15 workflows)

| Workflow | DB ID | Container Strategy | ECR Image | Notes |
|----------|-------|--------------------|-----------|-------|
| `predict_admet_properties` | 10782 | dual | `biomni-pharma:x86` | S1, pharmacology/ |
| `ivive_hepatic_clearance` | 10778 | dual | `biomni-pharma:x86` | S2, pharmacology/ |
| `pocket_detection_druggability` | 12805 | dual | `biomni-structure-to-drug:x86` | S3 |
| `pharmacophore_filtering` | 12804 | dual | `biomni-structure-to-drug:x86` | S4 |
| `assay_ingestion_and_ranking` | 12814 | dual | `biomni-pharma:x86` | S5 — NEW |
| `cro_submission_export` | 12815 | dual | `biomni-pharma:x86` | S6 — NEW |
| `nca_pknca` | 10642 | public | `rocker/r-ver:4.3.1` + `rocker/tidyverse:4.3.1` | R containers, public |
| `scaffold_hopping` | 10643 | dual | `biomni-drug-discovery-nf:x86` | RDKit |
| `structure_prediction_docking` | 10644 | public | alphafold3 + diffdock + autodockvina | Tool-specific |
| `alphafold_db_search` | 12647 | public | foldseek + mmseqs2 + python:3.11-slim | Tool-specific |
| `gromacs_protein_md` | 12799 | dual-var | `biomni-drug-discovery-nf:x86` | GPU required |
| `reinvent4_lead_design` | 12800 | dual-var | `biomni-drug-discovery-nf:x86` | RL engine |
| `schrodinger_glide_docking` | 12801 | ECR only | `schrodinger2024:latest` | License required |
| `amber_pmemd_md` | 12802 | ECR+public | `amber24-cuda:latest` (ECR) + `ambermd/ambertools:23` | License + GPU |
| `moe_covalent_docking` | 12803 | ECR only | `moe2024:latest` | License required |
| `aizynthfinder_retrosynthesis` | 12806 | dual | `biomni-drug-discovery-nf:x86` | Retrosynthesis |
| `drug_moa_rnaseq` | 12807 | dual | `biomni-drug-discovery-nf:x86` | DESeq2/GSEA |

### Container Image Registry

| ECR Repository | Purpose | Workflows |
|----------------|---------|-----------|
| `biomate/biomni-pharma:x86` | Pharmacology/ADMET (pandas, RDKit, sklearn) | S1, S2, S5, S6 |
| `biomate/biomni-structure-to-drug:x86` | Structure-based DD (fpocket, RDKit) | S3, S4 |
| `biomate/biomni-drug-discovery-nf:x86` | Full drug discovery stack (REINVENT4, AiZynthFinder, RDKit, DESeq2) | S7-S11, GROMACS, REINVENT4 |
| `amber24-cuda:latest` | AMBER pmemd GPU | amber_pmemd_md |
| `schrodinger2024:latest` | Schrödinger Glide | schrodinger_glide_docking |
| `moe2024:latest` | MOE CovDock | moe_covalent_docking |

> **IMPORTANT**: `biomni-drug-discovery-nf:x86` must be built and pushed to ECR.
> The ARM local version (`biomni-drug-discovery-nf:latest`) exists and is current.
> Build x86 version: `docker buildx build --platform linux/amd64 -t 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-drug-discovery-nf:x86 --push .`

---

## 3. Execution Tier Classification

### Tier A — Full execution (public/BioMate containers, no license required)
Expected to run end-to-end in AWS Batch and produce output files:

| Session | Workflow | Container | Real Tool |
|---------|----------|-----------|-----------|
| S1 | `predict_admet_properties` | `biomni-pharma:x86` | RDKit Chem.Descriptors |
| S2 | `ivive_hepatic_clearance` | `biomni-pharma:x86` | Python scipy/IVIVE model |
| S3 | `pocket_detection_druggability` | `biomni-structure-to-drug:x86` | fpocket 4.1 |
| S4 | `pharmacophore_filtering` | `biomni-structure-to-drug:x86` | RDKit MolChemicalFeatures |
| S5 | `assay_ingestion_and_ranking` | `biomni-pharma:x86` | Python pandas/numpy |
| S6 | `cro_submission_export` | `biomni-pharma:x86` | Python pandas/RDKit |
| DA-1 | `nca_pknca` | `rocker/r-ver:4.3.1` | PKNCA R package |
| DA-2 | `scaffold_hopping` | `biomni-drug-discovery-nf:x86` | RDKit scaffold analysis |
| DA-3 | `drug_moa_rnaseq` | `biomni-drug-discovery-nf:x86` | DESeq2 + GSEA (bioconductor) |
| DA-4 | `alphafold_db_search` | foldseek + mmseqs2 | Foldseek + MMseqs2 |

### Tier B — Generation + execution start required; graceful failure acceptable
License, GPU, or large model downloads required. Test validates workflow card generation and execution API:

| Session | Workflow | Blocker | ECR Image |
|---------|----------|---------|-----------|
| DB-1 | `aizynthfinder_retrosynthesis` | Model files required (~2GB) | `biomni-drug-discovery-nf:x86` |
| DB-2 | `reinvent4_lead_design` | Model download + GPU ideal | `biomni-drug-discovery-nf:x86` |
| DB-3 | `structure_prediction_docking` | AF3 weights (>100GB), Docker auth | Tool-specific public |
| DB-4 | `gromacs_protein_md` | GPU strongly recommended | `biomni-drug-discovery-nf:x86` |
| DB-5 | `amber_pmemd_md` | AMBER license | `amber24-cuda:latest` (ECR) |
| DB-6 | `schrodinger_glide_docking` | Schrödinger FlexNet license | `schrodinger2024:latest` (ECR) |
| DB-7 | `moe_covalent_docking` | MOE FlexNet license | `moe2024:latest` (ECR) |

---

## 4. E2E Test Files

| File | Coverage | Assertion Level |
|------|----------|-----------------|
| `frontend/e2e/drug-discovery-pilot-e2e.e2e.ts` | S1–S6 (BCR-ABL1 pilot) | Full execution + billing + output vis |
| `frontend/e2e/drug-discovery-full-e2e.e2e.ts` | DA-1 to DA-4, DB-1 to DB-7 | Generation + execution + output_files 200 |

---

## 5. Known Issues and Action Items

### Must-do before production
1. **Build and push `biomni-drug-discovery-nf:x86`** to ECR for DA-1 through DB-4 execution on AWS Batch
   - Contains: REINVENT4, AiZynthFinder, RDKit, DESeq2, GSEA, scaffold analysis tools
   - Local ARM image is current — needs x86 cross-build

2. **Verify `biomni-structure-to-drug:x86` has fpocket 4.1** — S3 pocket detection requires it

3. **AiZynthFinder model files** — workflow expects route expansion models (~2GB) in `params.models_path`
   - Store in S3: `s3://biomate-structure-db/aizynthfinder/models/`

4. **AlphaFold DB on S3** — `alphafold_db_search` DA-4 requires `s3://biomate-structure-db/alphafold/`
   - Build status as of 2026-03-20: build running on spot instance

### Lower priority
5. **AMBER license** — Apply at ambermd.org for academic; store as `AMBER_LICENSE_FILE` in backend/.env
6. **Schrödinger trial** — Contact sales@schrodinger.com; store as `SCHRODINGER_LICENSE_FILE`
7. **MOE academic** — Apply at chemcomp.com; store as `LM_LICENSE_FILE`

---

## 6. Search/Routing Coverage for New Workflows

### `galaxy-assistant.ts` routing clauses added:
- `assay_ingestion_and_ranking`: triggers on "ingest assay data", "composite ranking", "hERG + IC50 ranking", "BCR-ABL1 campaign ranking"
- `cro_submission_export`: triggers on "CRO submission", "WuXi AppTec export", "format compounds for CRO"

### `unified_workflow_search.py` keyword weights added:
- assay_ingestion (4.0), compound_ranking (3.5), composite_score (3.5), bcr_abl1 (3.5), herg_ranking (3.5)
- cro_submission (4.0), wuxi_apptec (4.5), cro_export (4.0), compound_export (3.5)
