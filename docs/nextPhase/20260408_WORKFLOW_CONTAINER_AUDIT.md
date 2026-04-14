# BioMate Workflow Container Audit — Drug Discovery + CryoEM

**Date**: 2026-04-08
**Status**: Definitive reference for all workflow → container assignments
**Scope**: `drug_discovery/` (19 workflows), `pharmacology/` (25 workflows), `cryo_em/` (14), `cryo_et/` (5)

---

## Summary of Issues Found

| Severity | Issue | Affected | Fix |
|---|---|---|---|
| **CRITICAL** | Pharmacology workflows use `biomate/biomni-tools:latest` (DockerHub), not ECR path | All 24 pharmacology workflows | Add AWS conditional or remove per-process `container` directive |
| **CRITICAL** | `apply_vcog_grade` hardcodes ECR path without conditional (fails locally) | 1 pharmacology workflow | Make conditional |
| **HIGH** | cryo_em + cryo_et have no container directives | 19 workflows | Confirm default executor container covers `cryosparc-tools`; add explicit directive |
| **MEDIUM** | `alphafold_db_search` MERGE step fixed (was `python:3.11-slim`) | Fixed 2026-04-08 | Done |
| **LOW** | `nlmixr2_population_pk` uses DockerHub image (needs AMI fix for AWS Batch) | 1 pharmacology workflow | AMI rebuild (Phase 1) |

---

## Drug Discovery Workflows (19 total)

| Workflow | Container (AWS Batch) | Container (Local) | Key CLI Tools | Python Libs | Mock Mode | AWS-ready? |
|---|---|---|---|---|---|---|
| `predict_admet_properties` | `biomni-tools:x86` | `biomni-tools:latest` | python3 | RDKit, DeepPurpose, pandas | yes | ✓ |
| `ADMET_pred` | `biomni-tools:x86` | `biomni-tools:latest` | python3 | RDKit, DeepPurpose, pandas | yes | ✓ |
| `ivive_hepatic_clearance` | `biomni-tools:x86` | `biomni-tools:latest` | python3 | scipy, pandas | yes | ✓ |
| `assay_ingestion_and_ranking` | `biomni-tools:x86` | `biomni-tools:latest` | python3 | pandas, scikit-learn, plotly | yes | ✓ |
| `cro_submission_export` | `biomni-tools:x86` | `biomni-tools:latest` | python3 | RDKit, pandas | yes | ✓ |
| `pocket_detection_druggability` | `biomni-structure-to-drug:x86` | `biomni-drug-discovery-nf:latest` | python3, **fpocket** | BioPython, scipy, numpy | stub | ✓ |
| `pharmacophore_filtering` | `biomni-structure-to-drug:x86` | `biomni-drug-discovery-nf:latest` | python3 | RDKit pharmacophore, matplotlib | stub | ✓ |
| `p0_docking_validation` | `biomni-tools:x86` | `biomni-tools:latest` | python3, vina, obabel | RDKit, meeko, vina | no | ✓ |
| `p0_pharmacophore_validation` | `biomni-tools:x86` | `biomni-tools:latest` | python3 | RDKit ChemicalFeatures | no | ✓ |
| `p0_mrna_validation` | `biomni-tools:x86` | `biomni-tools:latest` | python3 | ViennaRNA, codon_tools | no | ✓ |
| `p0_pkpd_semaglutide` | `biomni-tools:x86` | `biomni-tools:latest` | python3 | scipy, matplotlib, pandas | no | ✓ |
| `aizynthfinder_retrosynthesis` | `biomni-drug-discovery-nf:x86` | `biomni-drug-discovery-nf:latest` | python3, aizynthfinder | AiZynthFinder, RDKit | no | ✓ |
| `scaffold_hopping` | `biomni-drug-discovery-nf:x86` | `biomni-drug-discovery-nf:latest` | python3 | RDKit BRICS, mmpdb (optional) | stub | ✓ |
| `drug_moa_rnaseq` | `biomni-drug-discovery-nf:x86` | `biomni-drug-discovery-nf:latest` | python3 | pydeseq2, gseapy, seaborn | stub | ✓ |
| `reinvent4_lead_design` | `biomni-drug-discovery-nf:x86` | `biomni-drug-discovery-nf:latest` | python3, reinvent4 | REINVENT4, RDKit BRICS fallback | no | ✓ |
| `alphafold_db_search` | `foldseek:latest` + `mmseqs2:latest` + `biomate-nextflow-base:x86` | same | foldseek, mmseqs2, python3 | csv, json | always live | ✓ (fixed) |
| `nca_pknca` | `rocker/r-ver:4.3.1` + `rocker/tidyverse:4.3.1` | same | Rscript | PKNCA, ggplot2, knitr | stub | ✓ (AMI needed) |
| `gromacs_protein_md` | `ambertools:23` + `gromacs:2025.1` + `gmx_mmpbsa:1.6.3` | same | antechamber, gmx, gmx_MMPBSA | RDKit, acpype, MDAnalysis | no | ✓ (AMI needed) |
| `structure_prediction_docking` | `alphafold3:latest` + `diffdock:latest` + `autodockvina:latest` | same | python3, obabel | RDKit, pydantic | always live | ✓ (AMI needed) |
| `amber_pmemd_md` | `ambertools:23` (prep) + `amber24-cuda:latest` (GPU) | same | antechamber, pmemd.cuda, cpptraj, MMPBSA.py | RDKit | no | license-gated |
| `schrodinger_glide_docking` | `schrodinger2024:latest` (ECR) | same | ligprep, prepwizard, glide | RDKit, schrodinger.structure | no | license-gated |
| `moe_covalent_docking` | `moe2024:latest` (ECR) | same | moebatch (SVL) | RDKit, MOE Python | no | license-gated |

**Notes**:
- All drug discovery workflows with BioMate images use correct `System.getenv('NEXTFLOW_USE_AWS')` conditional — **AWS-ready** ✓
- Third-party public images (rocker, gromacs, ambertools, alphafold3, diffdock, autodockvina, foldseek, mmseqs2) require AMI rebuild to have AWS CLI for S3 staging
- `nca_pknca` also exists in `pharmacology/nca_pknca/` — the `drug_discovery/nca_pknca/` path should be canonical

---

## Pharmacology Workflows (25 total)

> **CRITICAL BUG**: All 24 workflows below use `container 'biomate/biomni-tools:latest'` — a **local Docker tag** that resolves to DockerHub on AWS Batch (where it doesn't exist). They will fail S3 staging on Batch.
>
> **Fix**: Change to conditional `System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'`

| Workflow | Container | Key Tools | Python Libs | AWS Bug |
|---|---|---|---|---|
| `ADMET_pred` | `biomni-tools:latest` (local only) | python3 | RDKit, DeepPurpose | ⚠️ |
| `analyze_fda_safety_signals` | `biomni-tools:latest` | python3 | pandas, statsmodels | ⚠️ |
| `analyze_interaction_mechanisms` | `biomni-tools:latest` | python3 | RDKit, biopython | ⚠️ |
| `analyze_radiolabeled_antibody_biodistribution` | `biomni-tools:latest` | python3 | scipy, matplotlib | ⚠️ |
| `analyze_western_blot` | `biomni-tools:latest` | python3 | scikit-image, matplotlib | ⚠️ |
| `analyze_xenograft_tumor_growth_inhibition` | `biomni-tools:latest` | python3 | statsmodels, scipy, seaborn | ⚠️ |
| `bi_exp_model` | `biomni-tools:latest` | python3 | scipy curve_fit, matplotlib | ⚠️ |
| `calculate_physicochemical_properties` | `biomni-tools:latest` | python3 | RDKit Descriptors | ⚠️ |
| `check_drug_combination_safety` | `biomni-tools:latest` | python3 | pandas | ⚠️ |
| `check_fda_drug_recalls` | `biomni-tools:latest` | python3 | requests, pandas | ⚠️ |
| `estimate_alpha_particle_radiotherapy_dosimetry` | `biomni-tools:latest` | python3 | numpy, scipy | ⚠️ |
| `find_alternative_drugs_ddinter` | `biomni-tools:latest` | python3 | requests, pandas | ⚠️ |
| `get_fda_drug_label_info` | `biomni-tools:latest` | python3 | requests, json | ⚠️ |
| `grade_adverse_events_using_vcog_ctcae` | `biomni-tools:latest` | python3 | pandas | ⚠️ |
| `perform_mwas_cyp2c19_metabolizer_status` | `biomni-tools:latest` | python3 | statsmodels, pandas | ⚠️ |
| `predict_binding_affinity_protein_1d_sequence` | `biomni-tools:latest` | python3 | DeepPurpose | ⚠️ |
| `qsar_rf_model` | `biomni-tools:latest` | python3 | RDKit, scikit-learn | ⚠️ |
| `retrieve_topk_repurposing_drugs_from_disease_txgnn` | `biomni-tools:latest` | python3 | pandas | ⚠️ |
| `run_3d_chondrogenic_aggregate_assay` | `biomni-tools:latest` | python3 | matplotlib, pandas | ⚠️ |
| `run_autosite` | `biomni-tools:latest` | python3 | RDKit, vina | ⚠️ |
| `run_diffdock_with_smiles` | `biomni-tools:latest` | python3 | vina, meeko, openbabel | ⚠️ |
| `sigmoid` | `biomni-tools:latest` | python3 | scipy, matplotlib | ⚠️ |
| `nca_pknca` | `rocker/r-ver:4.3.1` + `rocker/tidyverse:4.3.1` | Rscript | PKNCA, ggplot2 | ✓ (AMI needed) |
| `nlmixr2_population_pk` | `nlmixr2/nlmixr2:latest` | Rscript | nlmixr2, rxode2, xpose | ✓ (AMI needed) |
| `apply_vcog_grade` | `399683337364...biomni-pharma:latest` (hardcoded ECR) | python3 | pandas | ⚠️ (no local fallback) |

**apply_vcog_grade specific issue**: Hardcodes full ECR path unconditionally — works on Batch but fails locally. Should be made conditional.

---

## Cryo-EM Workflows (14 total)

> **Note**: None of these workflows have explicit `container` directives. They rely on the global `process.container` set by `nextflow_executor.py` (default: `biomate-nextflow-base:latest`). This is **correct** — all cryo-EM workflows use only Python + `cryosparc-tools` (which is installed in `biomate-nextflow-base`) or pure Python file I/O. No external CLI tools required beyond what's in the base image.

| Workflow | Container (via config default) | Mode | Tools Used | CryoSPARC Required |
|---|---|---|---|---|
| `import_micrographs` | `biomate-nextflow-base:latest` | SDK or file-scan | cryosparc-tools Python SDK | optional (`use_cryosparc=false` → file scan) |
| `import_particles` | `biomate-nextflow-base:latest` | SDK or JSON | cryosparc-tools | optional |
| `topaz_train` | `biomate-nextflow-base:latest` | SDK or mock | topaz (if installed), cryosparc-tools | optional |
| `topaz_extract` | `biomate-nextflow-base:latest` | SDK or mock | topaz (if installed), cryosparc-tools | optional |
| `global_ctf_refinement` | `biomate-nextflow-base:latest` | SDK | cryosparc-tools | yes (job submission) |
| `local_refinement` | `biomate-nextflow-base:latest` | SDK | cryosparc-tools | yes |
| `focused_refinement_pipeline` | `biomate-nextflow-base:latest` | SDK | cryosparc-tools | yes |
| `helical_refinement` | `biomate-nextflow-base:latest` | SDK | cryosparc-tools | yes |
| `helical_spa_pipeline` | `biomate-nextflow-base:latest` | SDK | cryosparc-tools | yes |
| `3d_variability_analysis` | `biomate-nextflow-base:latest` | SDK | cryosparc-tools | yes |
| `3d_variability_pipeline` | `biomate-nextflow-base:latest` | SDK | cryosparc-tools | yes |
| `particle_subtraction` | `biomate-nextflow-base:latest` | SDK | cryosparc-tools | yes |
| `symmetry_expansion` | `biomate-nextflow-base:latest` | SDK | cryosparc-tools | yes |
| `filament_tracer` | `biomate-nextflow-base:latest` | SDK | cryosparc-tools | yes |

**Key observation**: All 14 cryo-EM workflows operate via the CryoSPARC Python SDK (submitting jobs to a running CryoSPARC server). When `use_cryosparc=false`, they fall back to Python-only file processing. No separate `biomni-cryoem` container is needed for these workflows.

**`cryosparc-tools` is already in `biomate-nextflow-base`** — confirmed in `Dockerfile.nextflow-base`.

**Container to add explicitly** (recommended): Although the default works, adding explicit directives improves clarity and prevents breakage if the default ever changes:
```groovy
container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] \
    ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate-nextflow-base:latest' \
    : 'biomate-nextflow-base:latest'
```

---

## Cryo-ET Workflows (5 total)

> Same pattern as cryo-EM: no explicit container directives → uses config default (`biomate-nextflow-base:latest`).

| Workflow | Container (via config default) | IMOD Tools | Notes |
|---|---|---|---|
| `import_tiltseries` | `biomate-nextflow-base:latest` | None (file scan) | Reads MRC/TIFF tilt series, outputs JSON |
| `tilt_alignment` | `biomate-nextflow-base:latest` | `tilt`, `xftoxg` (IMOD) | Falls back to python-only WBP estimate if IMOD absent |
| `tomogram_reconstruction` | `biomate-nextflow-base:latest` | `tilt`, `imod_sirtfilter` | Falls back to python-only reconstruction |
| `subtomogram_averaging` | `biomate-nextflow-base:latest` | `newstack`, `aligned_stack` | Relion optional |
| `et_full_pipeline` | `biomate-nextflow-base:latest` | (delegates) | Orchestrates all 4 above |

> **Note**: `tilt`, `newstack`, `imod_sirtfilter` etc. are IMOD tools — NOT in `biomate-nextflow-base`. However, all cryo-ET workflows have Python fallback paths. For full IMOD support, either install IMOD in the base image or build `biomni-cryoem:x86` with IMOD included.

---

## Container Summary — What Exists vs What's Needed

### BioMate ECR Images (all inherit from `biomate-nextflow-base`)
| Image | Tag | Status | Drug Discovery | Pharmacology | CryoEM/ET |
|---|---|---|---|---|---|
| `biomate-nextflow-base` | `latest` | ✓ built | default | default (via config) | default |
| `biomate/biomni-tools` | `x86`, `latest`, `biomni-pharma:x86,latest`, `biomni-microbiology:latest` | ✓ rebuilt 2026-04-08 | S1,S2,S5,S6 + p0 sessions | all 24 workflows | — |
| `biomate/biomni-drug-discovery-nf` | `x86`, `latest` | ✓ rebuilt 2026-04-08 | AiZynthFinder, REINVENT4, scaffold, MoA | — | — |
| `biomate/biomni-structure-to-drug` | `x86` | ✓ rebuilt 2026-04-08 (+fpocket) | S3,S4 (pocket, pharmacophore) | — | — |
| `biomate/genomics-germline` | `x86` | ✓ existing | — | — | — |
| `biomate/sra-tools` | `3.1.1` | ✓ new 2026-04-08 | — | — | — |

### Third-Party Images (need AMI rebuild for AWS CLI)
| Image | Used by | AMI fix needed |
|---|---|---|
| `rocker/r-ver:4.3.1` | nca_pknca | yes |
| `rocker/tidyverse:4.3.1` | nca_pknca | yes |
| `nlmixr2/nlmixr2:latest` | nlmixr2_population_pk | yes |
| `gromacs/gromacs:2025.1` | gromacs_protein_md | yes |
| `ambermd/ambertools:23` | gromacs_protein_md, amber_pmemd_md | yes |
| `simonbray/gmx_mmpbsa:1.6.3` | gromacs_protein_md | yes |
| `catgumag/alphafold3:latest` | structure_prediction_docking | yes |
| `simonelenz/diffdock:latest` | structure_prediction_docking | yes |
| `cford38/autodockvina:latest` | structure_prediction_docking | yes |
| `steineggerlab/foldseek:latest` | alphafold_db_search | yes |
| `soedinglab/mmseqs2:latest` | alphafold_db_search | yes |

### License-Gated (no action until partner provides key)
| Image | Tool | Workflow |
|---|---|---|
| `amber24-cuda:latest` | AMBER GPU | amber_pmemd_md |
| `schrodinger2024:latest` | Glide docking | schrodinger_glide_docking |
| `moe2024:latest` | MOE covalent | moe_covalent_docking |

---

## Action Items

### P0 — Fix Pharmacology Container Bug (blocks all pharmacology on AWS Batch)

All 24 pharmacology workflows use `container 'biomate/biomni-tools:latest'` which resolves to DockerHub on Batch. Fix: script-update all to conditional:

```bash
# Files to update (24 workflows):
find backend/biomni_workflows/nextflow_nfcore/subworkflows/pharmacology -name "main.nf" \
  | xargs grep -l "container 'biomate/biomni-tools:latest'"

# Replace pattern in each:
# OLD: container 'biomate/biomni-tools:latest'
# NEW: container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'
```

Also fix `apply_vcog_grade`:
```groovy
# OLD: container '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-pharma:latest'
# NEW: container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'
```
Note: `biomni-pharma:latest` and `biomni-tools:x86` are now the same image (merged 2026-04-08).

### P1 — AMI Rebuild (see `20260408_PILOT_READINESS_PLAN.md` Phase 1)
Unblocks: all 11 third-party public images listed above.

### P2 — cryo-ET IMOD Support (optional — Python fallback available)
`tilt_alignment`, `tomogram_reconstruction`, `subtomogram_averaging` call IMOD binaries.
- Python fallback works for file generation/metadata
- For real cryo-ET processing: build `biomni-cryoem:x86` with IMOD installed

### P3 — Explicit Container in cryo-EM/cryo-ET (low priority)
Add explicit container directives to all 19 cryo-EM/ET workflows to prevent silent breakage.

---

## Pilot Study Readiness

### Drug Discovery Pilot (S1–S6) — READY (after BioMate image push complete)

| Session | Workflow | Container | Status |
|---|---|---|---|
| S1 | `ADMET_pred` / `predict_admet_properties` | `biomni-tools:x86` | ✓ ready |
| S2 | `ivive_hepatic_clearance` | `biomni-tools:x86` | ✓ ready |
| S3 | `pocket_detection_druggability` | `biomni-structure-to-drug:x86` (fpocket ✓) | ✓ ready |
| S4 | `pharmacophore_filtering` | `biomni-structure-to-drug:x86` | ✓ ready |
| S5 | `assay_ingestion_and_ranking` | `biomni-tools:x86` | ✓ ready |
| S6 | `cro_submission_export` | `biomni-tools:x86` | ✓ ready |

### CryoEM Pilot (P0 sessions)

| Session | Workflow | Container | Status |
|---|---|---|---|
| P0-A | CryoSPARC cryo-EM processing | `biomate-nextflow-base:latest` (SDK) | ⚠️ needs CryoSPARC server + GPU CE + EMPIAR data |
| P0-B | `p0_mrna_validation` | `biomni-tools:x86` | ✓ ready |
| P0-C | `p0_docking_validation` | `biomni-tools:x86` | ✓ ready |
| P0-D | `p0_pharmacophore_validation` | `biomni-tools:x86` | ✓ ready |
| P0-E | `p0_pkpd_semaglutide` | `biomni-tools:x86` | ✓ ready |
