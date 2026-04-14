# BioMate Container Architecture — Definitive Reference

**Date**: 2026-04-08
**Status**: Active — single source of truth for all Nextflow container assignments
**Covers**: Drug Discovery Pilot, CryoEM Pilot, Extended Study, Germline/Genomics

---

## Design Principles

1. **Every BioMate task container inherits from `biomate-nextflow-base`** — provides AWS CLI v2, ensuring `nxf_s3_upload`/`nxf_s3_download` work on AWS Batch.
2. **One tool, one container** — no container duplicates another's core purpose.
3. **Third-party public images** are used as-is from DockerHub/GHCR; we do not re-bake them.
4. **License-gated tools** (AMBER, Schrödinger, MOE, CryoSPARC) are referenced in `.nf` files but only activated when the user supplies a valid credential at runtime.

---

## Container Hierarchy

```
biomate-nextflow-base:latest  (AWS CLI v2 + numpy/scipy/pandas/biopython/rdkit/gget)
        │
        ├── biomate/biomni-tools:x86          ← general Python analysis + ALL pharmacology
        │       also tagged: biomni-pharma:x86, biomni-pharma:latest, biomni-microbiology:latest
        │
        ├── biomate/biomni-drug-discovery-nf:x86   ← generative AI + retrosynthesis + MoA
        │
        ├── biomate/biomni-structure-to-drug:x86   ← structure-based drug design
        │
        ├── biomate/genomics-germline:x86      ← WGS germline variant calling (conda-based)
        │
        ├── biomate/sra-tools:3.1.1            ← NCBI SRA download
        │
        └── [PLANNED] biomate/biomni-md:x86    ← GROMACS-based MD (see Gap section)
            [PLANNED] biomate/biomni-cryoem:x86 ← RELION + cryo-EM tools
```

---

## Custom BioMate Images (ECR)

### 1. `biomate-nextflow-base:latest`
**Source**: `aws_infrastructure/configs/Dockerfile.nextflow-base`
**Contents**: AWS CLI v2, Python 3.11, numpy, scipy, pandas, biopython, rdkit, gget, cryosparc-tools, procps
**Used by**: Default container for any Nextflow process without an explicit `container` directive

---

### 2. `biomate/biomni-tools:x86` (= `biomni-pharma:x86` = `biomni-microbiology:latest`)
**Source**: `backend/docker/biomni-tools/Dockerfile`
**All tags share the same image layer** — single build, multiple ECR tags.

**Contents** (on top of base):
- `libgomp1`, `libgfortran5`, `libxrender1`, `libxext6`, `swig`
- `scikit-learn`, `matplotlib`, `requests`, `pubchempy`
- `ViennaRNA` — RNA secondary structure (RNAfold, MFE)
- `vina`, `meeko`, `gemmi`, `openbabel-wheel` — molecular docking
- `codon-tools`, `python-codon-tables` — CAI, codon optimization
- `adjustText`, `seaborn`, `plotly` — visualization
- `statsmodels` — ANOVA, regression, Tukey HSD (**pharmacology-specific**)
- `scikit-image` — western blot image analysis (**pharmacology-specific**)
- `DeepPurpose` — MPNN/CNN ADMET models (**pharmacology-specific**, non-fatal if install fails)

**Used by** (pharmacology + drug discovery pilot):

| Workflow | Session |
|---|---|
| `predict_admet_properties` | Drug Discovery S1 |
| `ADMET_pred` | Drug Discovery S1 |
| `ivive_hepatic_clearance` | Drug Discovery S2 |
| `assay_ingestion_and_ranking` | Drug Discovery S5 |
| `cro_submission_export` | Drug Discovery S6 |
| `analyze_xenograft_tumor_growth_inhibition` | — |
| `perform_mwas_cyp2c19_metabolizer_status` | — |
| `analyze_western_blot` | — |
| `apply_vcog_grade` | — |
| 400+ other pharmacology subworkflows | — |

---

### 3. `biomate/biomni-drug-discovery-nf:x86`
**Source**: `backend/docker/drug-discovery-nf/Dockerfile`

**Contents** (on top of base):
- `aizynthfinder>=4.4.1` — retrosynthesis planning
- `pydeseq2` — RNA-seq differential expression (drug MoA)
- `gseapy` — GSEA pathway enrichment
- `vina`, `meeko`, `gemmi`, `ViennaRNA`, `openbabel-wheel` — inherited tools
- BioMate drug discovery Python modules (`/opt/biomate/drug_discovery/`)

**Used by**:

| Workflow | Purpose |
|---|---|
| `aizynthfinder_retrosynthesis` | Retrosynthesis routes |
| `reinvent4_lead_design` | Generative lead design (RDKIT_CONTAINER path) |
| `drug_moa_rnaseq` | Drug mechanism of action via RNA-seq |
| `scaffold_hopping` | RDKit scaffold operations |

---

### 4. `biomate/biomni-structure-to-drug:x86`
**Source**: `backend/docker/biomni-structure-to-drug/Dockerfile`

**Contents** (on top of base):
- `vina`, `meeko`, `gemmi`, `openbabel-wheel` — docking tools
- `scikit-learn`, `matplotlib`, `plotly`, `pubchempy`

**Used by**:

| Workflow | Purpose |
|---|---|
| `pocket_detection_druggability` | FPocket-based binding site detection |
| `pharmacophore_filtering` | Pharmacophore feature matching |
| `structure_prediction_docking` (AlphaFold3 path) | Structural docking pipeline |

> **Note**: FPocket itself is called as a CLI within the Python script, not as a separate container process. The `fpocket` binary must be present in this image. **This is a current gap** — fpocket is not yet installed in `biomni-structure-to-drug`. See Gap section.

---

### 5. `biomate/genomics-germline:x86`
**Source**: `backend/docker/genomics-germline/Dockerfile`

**Contents**: Miniforge + bwa-mem2, samtools, htslib, bcftools, picard, mosdepth, tabix, gatk4, fastqc, fastp, multiqc, pigz, snpEff (Java 21)

**Used by**: `wgs_germline_gatk` — WGS germline variant calling (entire pipeline)

---

### 6. `biomate/sra-tools:3.1.1`
**Source**: `backend/docker/sra-tools/Dockerfile`

**Contents**: NCBI SRA Toolkit 3.1.1 (fastq-dump, prefetch, fasterq-dump)

**Used by**: `wgs_germline_gatk` — SRA download step

---

## Third-Party Public Images (not built by BioMate)

These are pulled from DockerHub/GHCR at runtime. We do **not** re-push them to ECR.

| Image | Used by workflow | Notes |
|---|---|---|
| `gromacs/gromacs:2025.1` | `gromacs_protein_md` | GROMACS MD engine |
| `ambermd/ambertools:23` | `gromacs_protein_md`, `amber_pmemd_md` | AMBER force field tools |
| `simonbray/gmx_mmpbsa:1.6.3` | `gromacs_protein_md` | MM-GBSA analysis |
| `rocker/r-ver:4.3.1` | `nca_pknca` | R base for PK |
| `rocker/tidyverse:4.3.1` | `nca_pknca` | R + tidyverse for PKNCA |
| `catgumag/alphafold3:latest` | `structure_prediction_docking` | AlphaFold3 |
| `simonelenz/diffdock:latest` | `structure_prediction_docking` | DiffDock ML docking |
| `cford38/autodockvina:latest` | `docking_autodock_vina` | AutoDock Vina |
| `steineggerlab/foldseek:latest` | `alphafold_db_search` | Structure search |
| `soedinglab/mmseqs2:latest` | `alphafold_db_search` | Sequence search |
| `informaticsmatters/rdkit-python3-debian:latest` | `scaffold_hopping` | RDKit scaffold ops |
| `python:3.11-slim` | Lightweight processing steps | No AWS CLI — avoid for Batch |

> **Warning**: `python:3.11-slim` has no AWS CLI. Any workflow using it on AWS Batch will fail S3 staging. Switch to `biomate-nextflow-base:latest` instead.

---

## License-Gated Images (not built unless license present)

These images are referenced in `.nf` files but only activated when the user provides credentials via the BioMate credential vault.

| Image | Tool | License required | Workflow |
|---|---|---|---|
| `amber24-cuda` | AMBER pmemd.cuda GPU MD | AMBER license agreement | `amber_pmemd_md` |
| `schrodinger2024` | Schrödinger Glide docking | SCHRODINGER_LICENSE_FILE | `schrodinger_glide_docking` |
| `moe2024` | MOE covalent docking | LM_LICENSE_FILE | `moe_covalent_docking` |
| CryoSPARC (via SDK) | Cryo-EM processing | Partner license key | `cryosparc_*` workflows |

---

## Gaps — Containers Needed for Pilot Studies

### GAP 1: `fpocket` missing from `biomni-structure-to-drug`
**Impact**: `pocket_detection_druggability` fails — critical for CryoEM + Drug Discovery pilots
**Fix**: Add `fpocket` binary to `biomni-structure-to-drug/Dockerfile`
```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends \
    fpocket && rm -rf /var/lib/apt/lists/*
# (or build from source: https://github.com/Discngine/fpocket)
```

### GAP 2: `python:3.11-slim` used in some workflow steps
**Impact**: Those steps fail S3 staging on AWS Batch
**Fix**: Change `container 'python:3.11-slim'` → `container 'biomate-nextflow-base:latest'` in affected `.nf` files

### GAP 3: No `biomate/biomni-md` image
**Impact**: GROMACS workflows currently use `gromacs/gromacs:2025.1` (third-party) — works but BioMate has no control over it; MM-GBSA uses `simonbray/gmx_mmpbsa` (third-party)
**Priority**: Low — third-party images work fine for pilot
**Future**: Build `biomni-md:x86` with GROMACS + MDAnalysis + custom BioMate MD analysis scripts when scaling to extended study

### GAP 4: No `biomate/biomni-cryoem` image
**Impact**: CryoEM pilot requires RELION 4.0 (open-source fallback when CryoSPARC unavailable)
**Fix needed before CryoEM pilot**:
```dockerfile
# backend/docker/biomni-cryoem/Dockerfile
FROM 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate-nextflow-base:latest
# Install RELION 4.0, ctffind4, MotionCor2 (open-source), Topaz
```

### GAP 5: `reinvent4_lead_design` uses `biomni-drug-discovery-nf` but REINVENT4 binary not verified
**Impact**: REINVENT4 may not be installed correctly
**Fix**: Add explicit REINVENT4 smoke test to `drug-discovery-nf/Dockerfile`

---

## Workflow → Container Quick Reference

| Workflow path | Container (AWS Batch) | Container (local) |
|---|---|---|
| `pharmacology/predict_admet_properties` | `biomni-tools:x86` | `biomni-tools:latest` |
| `pharmacology/ADMET_pred` | `biomni-tools:x86` | `biomni-tools:latest` |
| `pharmacology/ivive_hepatic_clearance` | `biomni-tools:x86` | `biomni-tools:latest` |
| `pharmacology/assay_ingestion_and_ranking` | `biomni-tools:x86` | `biomni-tools:latest` |
| `pharmacology/cro_submission_export` | `biomni-tools:x86` | `biomni-tools:latest` |
| `pharmacology/analyze_xenograft_*` | `biomni-tools:x86` | `biomni-tools:latest` |
| `pharmacology/analyze_western_blot` | `biomni-tools:x86` | `biomni-tools:latest` |
| `pharmacology/nca_pknca` | `rocker/r-ver:4.3.1` | `rocker/r-ver:4.3.1` |
| `drug_discovery/pocket_detection_druggability` | `biomni-structure-to-drug:x86` ⚠️ missing fpocket | `biomni-drug-discovery-nf:latest` |
| `drug_discovery/pharmacophore_filtering` | `biomni-structure-to-drug:x86` | `biomni-drug-discovery-nf:latest` |
| `drug_discovery/aizynthfinder_retrosynthesis` | `biomni-drug-discovery-nf:x86` | `biomni-drug-discovery-nf:latest` |
| `drug_discovery/reinvent4_lead_design` | `biomni-drug-discovery-nf:x86` | `biomni-drug-discovery-nf:latest` |
| `drug_discovery/drug_moa_rnaseq` | `biomni-drug-discovery-nf:x86` | `biomni-drug-discovery-nf:latest` |
| `drug_discovery/gromacs_protein_md` | `gromacs/gromacs:2025.1` + `ambermd/ambertools:23` | same |
| `drug_discovery/structure_prediction_docking` | `catgumag/alphafold3`, `cford38/autodockvina`, `simonelenz/diffdock`, `biomni-structure-to-drug:x86` | various |
| `drug_discovery/alphafold_db_search` | `steineggerlab/foldseek`, `soedinglab/mmseqs2` | same |
| `genomics/wgs_germline_gatk` | `genomics-germline:x86`, `sra-tools:3.1.1` | same |

---

## Action Items (Priority Order)

| # | Action | Priority | Owner |
|---|---|---|---|
| 1 | Add `fpocket` to `biomni-structure-to-drug/Dockerfile`, rebuild + push | **Critical — blocks drug discovery pilot S3/S4** | Dev |
| 2 | Replace `python:3.11-slim` with `biomate-nextflow-base:latest` in all `.nf` steps | High | Dev |
| 3 | Add REINVENT4 smoke test to `drug-discovery-nf/Dockerfile` | High | Dev |
| 4 | Build `biomni-cryoem:x86` with RELION 4.0 before CryoEM pilot | High — blocks CryoEM pilot | Dev |
| 5 | Verify `biomni-drug-discovery-nf:x86` actually runs REINVENT4 on a test Batch job | High | Dev |
| 6 | Build `biomni-md:x86` (GROMACS + MDAnalysis) for extended study | Medium — third-party works for now | Dev |
