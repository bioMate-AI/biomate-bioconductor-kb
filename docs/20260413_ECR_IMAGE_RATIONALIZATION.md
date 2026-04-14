# BioMate ECR Image Rationalization — Comprehensive Analysis

**Date:** 2026-04-13  
**Scope:** All 31 ECR repositories, 60+ Dockerfiles, 2,756 workflow container directives  
**Supersedes:** `docs/20260412_DOCKER_SHRINK_ANALYSIS.md` (that doc was too simplified)

---

## Executive Summary

The existing shrink analysis proposed splitting `biomate-interactive` and `biomni-tools` as if those were the only relevant images. The actual situation is more complex:

1. **Separate Dockerfiles already exist** for `jupyter-biomate`, `rstudio-biomate`, `cellxgene`, `pavian`, `biomate-notebook` — but **none are in ECR** and **no workflows reference them**. The monolithic `biomate-interactive` is still what's actually deployed.

2. **Separate ECR repos already exist** for `biomni-pharma`, `biomni-structural`, `biomni-microbiology`, `biomni-cloning`, `biomni-crispr`, `biomni-systems`, `biomni-synbio` (all created 2026-02-05) — but their **Dockerfiles are missing** from `backend/docker/`, and **no workflow uses them**. They appear to be orphaned or alias pushes.

3. **`biomni-tools` is still the actual workhorse** for 400+ workflows. Any rationalization must change `.nf` container directives in addition to building new images — this is the non-trivial part that was not addressed.

4. **Tool overlap is significant**: `vina`+`meeko`+`RDKit` appear in `biomni-tools`, `biomni-structure-to-drug`, AND `biomni-drug-discovery-nf`. The base image (`biomate-nextflow-base`) already provides `numpy`, `scipy`, `biopython`, `rdkit` — so child images re-declare some of these redundantly.

5. **24 pharmacology workflows have a container bug** — they reference `biomate/biomni-tools:latest` (DockerHub, doesn't exist publicly) instead of the conditional ECR path. This is a separate issue from rationalization but must be fixed in the same pass.

---

## 1. Current ECR Inventory (31 Repositories)

### 1A. Active Batch / Workflow Images (actually used in .nf files)

| ECR Repository | Tag(s) Used | Workflows Using It | Dockerfile Location |
|---|---|---|---|
| `biomate/biomni-tools` | `:x86` | 400+ (drug discovery, pharmacology, synbio, codon, docking) | `docker/biomni-tools/Dockerfile` ✓ |
| `biomate/biomni-drug-discovery-nf` | `:x86` | scaffold_hopping, aizynthfinder_retrosynthesis, drug_moa_rnaseq | `docker/drug-discovery-nf/Dockerfile` ✓ |
| `biomate/biomni-structure-to-drug` | `:x86` | pocket_detection, pharmacophore_filtering | `docker/biomni-structure-to-drug/Dockerfile` ✓ |
| `biomate/genomics-germline` | `:x86` | wgs_germline_gatk (entire pipeline) | `docker/genomics-germline/Dockerfile` ✓ |
| `biomate/sra-tools` | `:3.1.1` | FASTERQ_DUMP in germline pipeline | `docker/sra-tools/Dockerfile` ✓ |
| `biomate/ambertools-gromacs-nf` | `:latest` | gromacs_protein_md, amber_pmemd_md | `docker/ambertools-gromacs-nf/Dockerfile` ✓ |
| `biomate-nextflow-base` | `:latest` | Default (cryo-EM, cryo-ET, any process without explicit directive) | `aws_infrastructure/configs/Dockerfile.nextflow-base` ✓ |
| `biomate/biomni-microbiology` | `:latest` | Some generated/Galaxy microbiology workflows | Unknown — **Dockerfile MISSING** |

### 1B. ECR Repos With No Active Workflow Usage

| ECR Repository | Tags | Status | Notes |
|---|---|---|---|
| `biomate/biomni-pharma` | `:latest`, `:x86`, `:arm64` | **Orphaned** | Created 2026-02-05; no .nf uses it; Dockerfile missing |
| `biomate/biomni-structural` | `:latest`, `:x86`, `:arm64` | **Orphaned** | Created 2026-02-05; no .nf uses it; Dockerfile missing |
| `biomate/biomni-cloning` | `:latest`, `:x86`, `:arm64` | **Orphaned** | No .nf uses it; Dockerfile missing |
| `biomate/biomni-crispr` | `:latest`, `:x86`, `:arm64` | **Orphaned** | No .nf uses it; Dockerfile missing |
| `biomate/biomni-systems` | `:latest`, `:x86`, `:arm64` | **Orphaned** | No .nf uses it; Dockerfile missing |
| `biomate/biomni-synbio` | `:latest`, `:x86`, `:arm64` | **Orphaned** | No .nf uses it; Dockerfile missing |
| `biomate/cutandrun` | `:x86` | Unused | No .nf references; specific pipeline image |
| `biomate/rnaseq` | `:x86` | Unused | No .nf references; specific pipeline image |
| `biomate/singlecell` | `:x86` | Unused | No .nf references; specific pipeline image |
| `biomate/ai-tools/protrek` | `:latest`, `:nextflow` | Unclear | Galaxy Interactive Tool, not Nextflow Batch |
| `biomate/ai-tools/state` | `:latest`, `:nextflow` | Unclear | AI model container |
| `biomate/ai-tools/syncraft` | `:latest`, `:nextflow` | Unclear | AI model container |
| `biomate/ai-tools/scfv-pmpnn` | `:latest`, `:nextflow` | Unclear | AI model container |
| `biomate/ai-tools/drugclip` | `:latest`, `:nextflow` | Unclear | AI model container |
| `biomate/ai-tools/boltz` | `:latest`, `:nextflow` | Unclear | AI model container |
| `biomate/ai-tools/profam` | `:latest`, `:nextflow` | Unclear | AI model container |
| `biomate/ai-tools/chai1` | `:latest`, `:nextflow` | Unclear | AI model container |
| `biomni-lite` | `:latest` | Unclear | Lightweight variant, not used in production .nf |
| `galaxy-tool-runner-v2` | `:latest` etc. | Galaxy runner | Galaxy tool execution, not Nextflow |
| `galaxy-fetch-and-run` | `:v2.5` etc. | AWS Batch helper | Fetch-and-run pattern for AWS Batch |
| `biomate/dev`, `dev-frontend`, `dev-backend` | various | Dev only | CI/CD dev containers |

### 1C. Interactive Tool Images (Galaxy IT, not Nextflow Batch)

**Already have separate Dockerfiles** but none are in ECR under these names:

| Dockerfile | Proposed ECR Name | Status |
|---|---|---|
| `docker/jupyter-biomate/Dockerfile` | `biomate/jupyter` | Built locally, not pushed to ECR |
| `docker/rstudio-biomate/Dockerfile` | `biomate/rstudio` | Built locally, not pushed to ECR |
| `docker/cellxgene/Dockerfile` | `biomate/cellxgene` | Built locally, not pushed to ECR |
| `docker/pavian/Dockerfile` | `biomate/pavian` | Built locally, not pushed to ECR |
| `docker/biomate-notebook/Dockerfile` | `biomate/notebook` | Built locally, not pushed to ECR |
| `docker/biomate-interactive/Dockerfile` | `biomate/biomate-interactive` | **Not in ECR either** — this is used as Galaxy IT locally only |

**Key finding**: `biomate-interactive` is not in ECR at all. It's built and run locally for Galaxy Interactive Tools. The separate images (jupyter, rstudio, cellxgene) are refinements of it but also not in ECR. None of this affects Nextflow Batch workflows.

---

## 2. Tool Overlap Matrix

The real rationalization problem: multiple images contain the same tools.

### 2A. Overlap in Nextflow Batch Images

| Tool / Package | `biomate-nextflow-base` | `biomni-tools` | `biomni-structure-to-drug` | `biomni-drug-discovery-nf` | `genomics-germline` | `ambertools-gromacs-nf` |
|---|:---:|:---:|:---:|:---:|:---:|:---:|
| AWS CLI v2 | ✓ | (inherited) | (inherited) | (inherited) | (inherited) | ✓ (manual) |
| numpy/scipy/pandas | ✓ | (inherited) | (inherited) | (inherited) | ✗ | ✓ (conda) |
| RDKit | ✓ | (inherited) | (inherited) | (via base) | ✗ | ✓ (conda) |
| biopython | ✓ | (inherited) | (inherited) | (inherited) | ✗ | ✗ |
| gget | ✓ | (inherited) | (inherited) | (inherited) | ✗ | ✗ |
| scikit-learn | ✗ | ✓ | ✓ | ✗ | ✗ | ✗ |
| matplotlib/seaborn/plotly | ✗ | ✓ | ✓ | ✗ | ✗ | ✗ |
| AutoDock Vina + Meeko | ✗ | ✓ | ✓ | ✓ | ✗ | ✗ |
| gemmi | ✗ | ✓ | ✓ | ✓ | ✗ | ✗ |
| openbabel-wheel | ✗ | ✓ | ✓ | ✓ | ✗ | ✗ |
| ViennaRNA | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ |
| codon-tools | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ |
| statsmodels | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ |
| scikit-image | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ |
| DeepPurpose | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ |
| fpocket | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ |
| aizynthfinder | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ |
| pydeseq2 / gseapy | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ |
| REINVENT4 | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ |
| bwa-mem2, samtools, GATK | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ |
| AmberTools 23 | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ |
| GROMACS 2024.2 | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ |
| acpype | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ |

**Significant overlaps:**
- `vina + meeko + gemmi + openbabel` repeated in `biomni-tools`, `biomni-structure-to-drug`, `biomni-drug-discovery-nf` — these are the docking-stack tools
- `ViennaRNA` in both `biomni-tools` and `biomni-drug-discovery-nf`
- `scikit-learn + matplotlib` in both `biomni-tools` and `biomni-structure-to-drug`

### 2B. Overlap in Interactive Tool Images

| Package | `biomate-interactive` | `jupyter-biomate` | `rstudio-biomate` | `biomate-notebook` | `cellxgene` |
|---|:---:|:---:|:---:|:---:|:---:|
| jupyter/datascience-notebook base | ✓ | ✓ | ✗ | ✓ | ✗ |
| RStudio Server | ✓ | ✗ | ✓ | ✗ | ✗ |
| scanpy, anndata | ✓ | ✓ | ✗ | ✓ | ✓ |
| DESeq2, edgeR, limma | ✓ | ✓ | ✓ | ✓ | ✗ |
| ggplot2, tidyverse | ✓ | ✓ | ✓ | ✓ | ✗ |
| clusterProfiler, enrichplot | ✓ | ✓ | ✓ | ✓ | ✗ |
| bioblend (Galaxy) | ✓ | ✓ | ✗ | ✓ | ✗ |
| cellxgene | ✓ | ✗ | ✗ | ✗ | ✓ |
| Pavian (shiny/Sankey) | ✓ | ✗ | ✗ | ✗ | ✗ |
| samtools, bcftools, bedtools | ✓ | ✓ | ✓ | ✗ | ✗ |
| papermill, nbconvert | ✗ | ✗ | ✗ | ✓ | ✗ |

The separate `jupyter-biomate`, `rstudio-biomate` Dockerfiles are clean subsets. They were clearly written as the "post-split" version of `biomate-interactive` — but the split was never completed (they're not in ECR, not referenced anywhere).

---

## 3. Current Issues — Ranked by Severity

### P0 — Breaks AWS Batch Production Today

**Issue:** 24 pharmacology workflows hardcode `container 'biomate/biomni-tools:latest'`  
**Impact:** On AWS Batch, Docker tries to pull from public DockerHub. This image does not exist on DockerHub → pull fails → entire workflow fails before any process runs.  
**Affected workflows:** ADMET_pred, analyze_fda_safety_signals, analyze_interaction_mechanisms, analyze_western_blot, analyze_xenograft, bi_exp_model, calculate_physicochemical_properties, check_drug_combination_safety, check_fda_drug_recalls, find_alternative_drugs, get_fda_drug_label_info, grade_adverse_events, perform_mwas_cyp2c19, predict_binding_affinity, qsar_rf_model, retrieve_topk_repurposing_drugs, run_3d_chondrogenic_assay, run_autosite, run_diffdock_with_smiles, sigmoid, + 100+ generated microbiology workflows in `nextflow_generated/`.  
**Fix:** Change container directive to the conditional pattern already used elsewhere:
```groovy
container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] \
    ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' \
    : 'biomate/biomni-tools:latest'
```

### P1 — Orphaned ECR Images Waste Storage

**Issue:** `biomni-pharma`, `biomni-structural`, `biomni-cloning`, `biomni-crispr`, `biomni-systems`, `biomni-synbio` have ECR repos (all created 2026-02-05, each with `latest`, `x86`, `arm64` tags) but:
- No Dockerfile exists for any of them in `backend/docker/`
- No `.nf` workflow references any of them
- Their contents are unknown — they may be re-tags of an old `biomni-tools` build or early prototypes

**Questions before action:**
- What's actually inside them? (`docker run --rm <uri> pip list`)
- Are they intended to eventually replace `biomni-tools`?
- If they're domain-specific subsets, what was the plan?

**Immediate action:** Do not delete without auditing contents first. Run `aws ecr describe-images` to check image sizes.

### P2 — Missing Dockerfiles for Orphaned ECR Images

If the orphaned ECR images ARE meaningful (have content distinct from `biomni-tools`), their build Dockerfiles must be recovered or reconstructed. Otherwise any future rebuild of those images requires reverse-engineering from `docker inspect` output.

### P3 — Interactive Tool Split Incomplete

The Dockerfiles for separate `jupyter-biomate`, `rstudio-biomate`, `cellxgene`, `pavian`, `biomate-notebook` exist and are well-written. But:
- None are built and pushed to ECR
- `biomate-interactive` (the monolith) is still used where any IT is needed
- ECR repos for these don't exist

This is already conceptually solved — it just needs to be executed.

### P4 — Docking Stack Triplicated

`vina + meeko + gemmi + openbabel-wheel` appears in three images:
- `biomni-tools` (general workflows + pharmacology)
- `biomni-structure-to-drug` (pocket detection, pharmacophore)
- `biomni-drug-discovery-nf` (retrosynthesis, MoA)

These should share a common `biomni-docking-base` that the specialized images build on. Currently, each image builds this stack independently → divergence risk when versions change.

### P5 — biomate-nextflow-base Dependency Chain

All BioMate Nextflow images inherit `FROM 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate-nextflow-base:latest`. The ambertools-gromacs-nf image does NOT inherit from it (uses `continuumio/miniconda3` instead) — it installs AWS CLI manually, creating a diverged base.

If `biomate-nextflow-base` is ever updated (e.g., AWS CLI version bump), `ambertools-gromacs-nf` won't benefit. The decision was made for conda compatibility reasons (AWS CLI v2 built into the base needs pip, but conda-only image can't use pip wheels cleanly on ARM).

---

## 4. Rationalization Plan

### Phase 1 — Fix Production Bugs (Do First, Independent of Rationalization)

1. Fix P0: Run the script that patches the 24 pharmacology container directives to use the conditional ECR path. This is a mechanical find-and-replace across all `.nf` files in `subworkflows/pharmacology/`.

2. Audit orphaned ECR images (P1): Pull each `biomni-pharma:x86`, `biomni-structural:x86` etc. and run `pip list` to see what's actually inside. If they're copies of an old `biomni-tools`, they can be safely deleted or left as-is.

### Phase 2 — Document the Intended Split (Required Before Touching Images)

The intended domain split (based on ECR repo names) was:

| Domain | ECR Repo | Tools It Should Contain | Workflows It Should Serve |
|---|---|---|---|
| Pharmacology | `biomni-pharma` | statsmodels, scikit-image, DeepPurpose, pubchempy + docking stack | ADMET, xenograft, MWAS, western blot |
| Structural | `biomni-structural` | fpocket, vina+meeko, gemmi, openbabel + docking stack | pocket detection, pharmacophore |
| Microbiology | `biomni-microbiology` | Kraken2, MetaPhlAn, HUMAnN, custom tools | metagenomics workflows |
| Cloning | `biomni-cloning` | codon-tools, restriction enzyme libs, BioPython | golden gate, restriction, codon opt |
| CRISPR | `biomni-crispr` | CRISPResso2, mageck, sgRNA design tools | CRISPR, base editing workflows |
| Systems/SynBio | `biomni-systems`, `biomni-synbio` | ViennaRNA, codon-tools, synthetic biology libs | RNA design, circuit simulation |

**Problem**: If `biomni-tools` is split into these domain images, **every `.nf` workflow that currently says `biomni-tools` must be updated** to say the correct domain image. This is the non-trivial part — there are 400+ affected process blocks across many `.nf` files.

### Phase 3 — Interactive Tool ECR Publish

The separate Dockerfiles are ready. The work is:
1. Create ECR repos for `biomate/jupyter`, `biomate/rstudio`, `biomate/cellxgene`, `biomate/pavian`
2. Build and push each image
3. Update Galaxy Interactive Tools configuration to reference ECR URIs (not local Docker builds)
4. Deprecate `biomate-interactive` once all IT references are migrated

This does NOT require any `.nf` file changes (IT images are not used in Nextflow Batch).

### Phase 4 — Extract Shared Docking Base (Future)

Create `biomate/biomni-docking-base`:
```dockerfile
FROM 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate-nextflow-base:latest
RUN pip install --no-cache-dir gemmi vina meeko openbabel-wheel scikit-learn matplotlib
```

Then `biomni-tools`, `biomni-structure-to-drug`, `biomni-drug-discovery-nf` all `FROM biomni-docking-base`. This removes version divergence risk. The cost: one more image in the pull chain (3 layers instead of 2). Acceptable tradeoff.

---

## 5. Image Size Estimates & Priority

| Image | Est. Size | Current Usage | Rationalization Impact | Priority |
|---|---|---|---|---|
| `biomate-interactive` | 9–14 GB | Galaxy IT locally | Split into 3-5 ECR images (P3) | Medium |
| `biomni-tools` | 3.5–5 GB | 400+ workflows | Domain split requires .nf changes (P2/future) | High |
| `genomics-germline` | 2–3 GB | WGS pipeline only | Correct scope, no change needed | None |
| `biomate-nextflow-base` | 1.0–1.5 GB | Foundation for all | Keep, don't split | None |
| `biomni-structure-to-drug` | 1.5–2.5 GB | 2 workflows | Overlap with biomni-tools; extract docking base (P4) | Low |
| `biomni-drug-discovery-nf` | 2–3 GB | 3 workflows | Overlap with biomni-tools; extract docking base (P4) | Low |
| `ambertools-gromacs-nf` | 4–6 GB | 2 MD workflows | Correct scope (conda env), no change needed | None |
| `sra-tools` | 0.5 GB | 1 process | Correct scope, no change needed | None |

---

## 6. Workflow Container Directive Change Scope

Before any domain split can happen, the team needs to know exactly how many `.nf` files must change and what. A mechanical pass cannot be used because process names in different files might need different domain images.

**Estimated change scope for a `biomni-tools` split:**

| Domain Target Image | Processes to Reroute | Estimated File Count |
|---|---|---|
| `biomni-pharma` | ADMET, MWAS, xenograft, western blot, FDA safety, drug recall, adverse events | ~24 .nf files |
| `biomni-structural` | Pharmacophore, pocket detection, autosite | ~10 .nf files |
| `biomni-cloning` | Codon optimization, restriction enzyme, ORF finding, golden gate | ~15 .nf files |
| `biomni-systems` / `biomni-synbio` | ViennaRNA, RNA design, synthetic circuits | ~20 .nf files |
| `biomni-crispr` | CRISPR screen, sgRNA design, base editing | ~10 .nf files |
| Keep in `biomni-tools` (general) | All remaining workflows using generic tools | ~300+ .nf files |

This is a significant change with high regression risk. Each domain split must be tested with a real Batch execution before `biomni-tools` is narrowed.

---

## 7. Immediate Action Items (Ordered)

1. **[P0, 1 hour]** Fix pharmacology container bug: patch 24 `.nf` files + microbiology generated workflows to use conditional ECR path for `biomni-tools:x86`. This is independent of the rationalization question and unblocks Batch execution.

2. **[P1, 2 hours]** Audit orphaned ECR images: pull each domain image and `pip list` to determine if they have content distinct from `biomni-tools`. Determine if they were a WIP domain split that stalled.

3. **[P3, 1 day]** Push IT images to ECR: build and push `jupyter-biomate`, `rstudio-biomate`, `cellxgene`, `pavian` to ECR. Update Galaxy IT config. This is self-contained and does not affect Nextflow.

4. **[P2, 2–3 days]** Write/recover missing Dockerfiles for `biomni-pharma`, `biomni-structural`, etc. if they are to be used as intended domain images.

5. **[P4, 1 week]** Domain split of `biomni-tools`: plan workflow-by-workflow rerouting, build domain images, test each in Batch, then patch `.nf` files. Do NOT start until P2 is complete.

6. **[P4, future]** Extract shared `biomni-docking-base` to eliminate `vina+meeko+gemmi+openbabel` triplication.
