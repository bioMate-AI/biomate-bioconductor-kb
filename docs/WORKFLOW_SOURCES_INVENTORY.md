# BioMate Workflow Sources — Inventory, Locations & Overlap Analysis

*Last updated: 2026-03-10*

---

## 1. Directory Map

```
backend/
├── biomni_workflows/
│   ├── nextflow_nfcore/
│   │   └── subworkflows/          ← PRIMARY source for execution
│   │       ├── biochemistry/      (9 workflows)
│   │       ├── bioconductor/      (1818 R-package modules)
│   │       ├── bioengineering/    (13 workflows)
│   │       ├── bioimaging/        (22 workflows)
│   │       ├── biophysics/        (2 workflows)
│   │       ├── cancer_biology/    (7 workflows)
│   │       ├── cell_biology/      (5 workflows)
│   │       ├── cryo_em/           (15 workflows)  ← NF-only, no Galaxy source
│   │       ├── cryo_et/           (5 workflows)   ← NF-only, no Galaxy source
│   │       ├── database/          (5 workflows)
│   │       ├── drug_discovery/    (3 workflows)   ← NF-only, no Galaxy source
│   │       ├── genetics/          (11 workflows)
│   │       ├── genomics/          (30 workflows)
│   │       ├── glycoengineering/  (3 workflows)
│   │       ├── immunology/        (13 workflows)
│   │       ├── lab_automation/    (6 workflows)
│   │       ├── literature/        (4 workflows)
│   │       ├── microbiology/      (16 workflows)
│   │       ├── molecular_biology/ (26 workflows)
│   │       ├── pathology/         (7 workflows)
│   │       ├── pharmacology/      (29 workflows)
│   │       ├── physiology/        (14 workflows)
│   │       ├── proteomics/        (1 workflow)    ← NF-only, no Galaxy source
│   │       ├── synthetic_biology/ (10 workflows)
│   │       └── systems_biology/   (12 workflows)
│   │
│   └── galaxy/
│       ├── workflows/             ← ORIGINAL Galaxy .ga source (122 files)
│       │   └── <domain>/<name>.ga
│       └── subworkflows/          ← EXPANDED Galaxy .ga source (227 files)
│           └── <domain>/<name>.ga
│
├── nf-core-workflows/             ← Full nf-core pipelines (community)
│   ├── rnaseq/
│   ├── chipseq/
│   ├── sarek/
│   └── ...
│
└── galaxy_workflows/              ← nf-core Galaxy wrappers (93 .ga files)
```

---

## 2. Workflow Source Inventory

| Source | Format | Count | Search Priority | Description |
|--------|--------|------:|:---------------:|-------------|
| `nfcore` | nextflow | 100 | **100** (highest) | Full community nf-core pipelines (rnaseq, sarek, chipseq, …) |
| `biomni_nextflow` | nextflow | 268 | **85** | BioMate's domain-specific Python analysis workflows, Docker-native |
| `bioconductor` | nextflow | 1817 | **75** | Individual Bioconductor R-package nf-core module wrappers |
| `galaxy_local` | galaxy_ga | 93 | **60** | nf-core community workflows in Galaxy format |
| `biomni` (legacy) | galaxy_ga | 0 | **10** | Old Galaxy-format BioMate workflows — **removed**, superseded by `biomni_nextflow` |
| **Total** | | **2278** | | |

---

## 3. BioMate Nextflow Workflows — Galaxy Origin

The 268 `biomni_nextflow` workflows descend from Galaxy `.ga` files through two
conversion stages:

```
Galaxy .ga  →  galaxy/subworkflows/  →  nextflow_nfcore/subworkflows/
```

### Conversion coverage

| Galaxy source | Total .ga files | With NF equivalent | Missing NF equivalent |
|---|---:|---:|---:|
| `galaxy/subworkflows/` | 227 | 217 (96%) | 10 (4%) |
| `galaxy/workflows/` | 122 | 121 (99%) | 1 (1%) |

> Note: `galaxy/workflows/` is a subset of `galaxy/subworkflows/`. The two directories
> are not identical — `subworkflows/` has additional domains (`glycoengineering`,
> `lab_automation`, `literature`, `support_tools`) that `workflows/` does not.

---

## 4. Galaxy Workflows WITHOUT a Nextflow Equivalent

These Galaxy files have no corresponding `main.nf` in `nextflow_nfcore/subworkflows/`
and are therefore **not executable** through the Nextflow engine.

### From `galaxy/subworkflows/` (10 files)

| Domain | Workflow | Reason |
|--------|----------|--------|
| `biophysics` | `predict_protein_disorder_regions` | Conversion pending |
| `support_tools` | `clear_captured_plots` | Internal utility — not user-facing |
| `support_tools` | `download_synapse_data` | Internal utility |
| `support_tools` | `execute_in_repl` | Internal utility |
| `support_tools` | `get_captured_plots` | Internal utility |
| `support_tools` | `read_function_source_code` | Internal utility |
| `support_tools` | `run_python_repl` | Internal utility |
| `support_tools` | `savefig_with_capture` | Internal utility |
| `support_tools` | `show_with_capture` | Internal utility |
| `synthetic_biology` | `identify_fas_functional_domains` | Conversion pending |

### From `galaxy/workflows/` (1 file)

| Domain | Workflow | Reason |
|--------|----------|--------|
| `synthetic_biology` | `identify_fas_functional_domains` | Same as above (also in subworkflows) |

**Action items:**
- `predict_protein_disorder_regions` and `identify_fas_functional_domains` need Nextflow wrappers.
- The 8 `support_tools/` entries are Python REPL / figure-capture utilities used internally by
  the Galaxy executor; they have no Nextflow equivalent by design.

---

## 5. Nextflow-Only Workflows (No Galaxy Source)

These 50 workflows exist **only** in `nextflow_nfcore/subworkflows/` and were written
directly in Nextflow without a Galaxy predecessor. They cover domains BioMate added
after the initial Galaxy-to-Nextflow conversion sprint.

| Domain | Count | Workflows |
|--------|------:|-----------|
| `bioimaging` | 17 | `check_model_files_exist`, `command_iteration`, `create_affine_transform`, `create_deformable_transform`, `create_rigid_transform`, `create_segmentation_visualization`, `load_image`, `patched_torch_load`, `prepare_input_for_nnunet`, `preprocess_image`, `register_images`, `save_image`, `segment_with_nn_unet`, `setup_nnunet_environment`, `setup_registration_method`, `split_modalities`, `verify_nifti_input` |
| `cryo_em` | 15 | `3d_variability_analysis`, `3d_variability_pipeline`, `cryosparc_standard_spa`, `filament_tracer`, `focused_refinement_pipeline`, `global_ctf_refinement`, `helical_refinement`, `helical_spa_pipeline`, `import_micrographs`, `import_particles`, `local_refinement`, `particle_subtraction`, `symmetry_expansion`, `topaz_extract`, `topaz_train` |
| `cryo_et` | 5 | `et_full_pipeline`, `import_tiltseries`, `subtomogram_averaging`, `tilt_alignment`, `tomogram_reconstruction` |
| `drug_discovery` | 3 | `nca_pknca`, `scaffold_hopping`, `structure_prediction_docking` |
| `genomics` | 5 | `geo_data_connector`, `perturb_seq_analysis`, `trajectory_inference`, `transcriptomic_biomarker`, `wgs_germline_gatk` |
| `pharmacology` | 4 | `ivive_hepatic_clearance`, `nca_pknca`, `nlmixr2_population_pk`, `qsar_rf_model` |
| `proteomics` | 1 | `chemoproteomics_pulldown` |
| **Total** | **50** | |

> These are all production-ready Nextflow workflows. The absence of a Galaxy source
> is by design — they were developed directly for the Nextflow engine.

---

## 6. Bioconductor Modules

### What they are

The 1818 workflows in `nextflow_nfcore/subworkflows/bioconductor/` are **nf-core module
wrappers** for individual Bioconductor R packages. Each provides:
- A `process BIOC_<PKG>` Nextflow process
- Official Bioconductor/Singularity container
- Documented upstream/downstream package dependencies
- Stub Rscript illustrating key function calls

They are **building blocks** for larger workflows, not standalone analyses.

### Coverage

| Metric | Count |
|--------|------:|
| Total Bioconductor packages wrapped | 1818 |
| Unique (indexed in DB) | **1817** |
| Skipped — overlap with `biomni_nextflow` | 1 (`target`) |

### Overlaps with other sources

#### Bioconductor ↔ nf-core tools (3 tools used in both)

These three packages appear as **tools inside nf-core pipelines** AND have standalone
Bioconductor module wrappers. In the search index the full nf-core pipeline is returned
(priority 100 > 75) when the user asks about an end-to-end pipeline; the Bioconductor
module wrapper is returned when the user asks for the specific package.

| Bioconductor package | Appears in nf-core pipelines |
|----------------------|------------------------------|
| `deseq2` | `nf-core/rnaseq`, `nf-core/differentialabundance` |
| `edger` | `nf-core/differentialabundance` |
| `limma` | `nf-core/differentialabundance` |

#### Bioconductor ↔ biomni_nextflow (1 overlap)

| Bioconductor package | biomni_nextflow workflow | Resolution |
|---|---|---|
| `target` | `lab_automation/target` | `biomni_nextflow` version kept (priority 85 > 75); Bioconductor version skipped during indexing |

---

## 7. Source Priority and Dispatch Logic

When a user asks BioMate to run an analysis, `UnifiedWorkflowSearch` scores all
candidate workflows and returns the highest-priority match:

```
nfcore (100)  →  biomni_nextflow (85)  →  bioconductor (75)  →  galaxy_local (60)
```

**Example scenarios:**

| User request | Source selected | Reason |
|---|---|---|
| "Run RNA-seq on my FASTQs" | `nfcore/rnaseq` | Full pipeline, highest priority |
| "Run DESeq2 on my count matrix" | `biomni_nextflow/genomics` | BioMate analysis workflow; DESeq2 is also in nf-core but only as a tool |
| "Use the edgeR Bioconductor module" | `bioconductor/edger` | Explicit package request |
| "Analyse microbial population dynamics" | `biomni_nextflow/microbiology` | No nf-core equivalent |
| "Run CryoSPARC SPA pipeline" | `biomni_nextflow/cryo_em` | NF-only; no nf-core equivalent |

---

## 8. Re-indexing

The workflow index is stored in `backend/database/galaxy_ai_tools.db` (git-ignored).
Run the following to rebuild it:

```bash
# Standard rebuild (no bioconductor — fast, ~2s)
python3 backend/scripts/index_all_workflows.py --rebuild

# Full rebuild including bioconductor (~5s)
python3 backend/scripts/index_all_workflows.py --rebuild --include-bioconductor

# Add/refresh bioconductor only (without removing other sources)
python3 backend/scripts/index_all_workflows.py --rebuild-bioconductor
```

---

## 9. Outstanding Gaps

| Gap | Priority | Notes |
|-----|:--------:|-------|
| NF wrapper for `synthetic_biology/identify_fas_functional_domains` | High | Galaxy .ga exists in both `workflows/` and `subworkflows/` |
| NF wrapper for `biophysics/predict_protein_disorder_regions` | Medium | Galaxy .ga in `subworkflows/` only |
| `support_tools` Galaxy utilities | Low | REPL/plot capture — not needed in Nextflow |
| Bioconductor modules not yet in `nf-core/rnaseq` or similar | — | 1817 individual package wrappers available as building blocks |
