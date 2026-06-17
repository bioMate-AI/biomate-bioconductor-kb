# Single-Cell Workflows — Reference Packet for Claude Design Requirements

**Date:** 2026-06-16
**Purpose:** Reference material for writing Claude-design requirement specs for single-cell workflows. Pulls together prior planning docs, DB schema, and tested-workflow inventory so design specs don't hallucinate IDs, names, or capabilities.

---

## 1. What we already have (don't re-invent)

### 1.1 Prior planning docs (read these before writing new specs)

| File | What's inside |
|---|---|
| `docs/20260504_SINGLE_CELL_COVERAGE_AND_VIRTUAL_CELL_ANALYSIS.md` | Coverage audit; virtual-cell direction |
| `docs/20260509_blog_notes_singlecell_virtual_cell.md` | Blog-draft framing |
| `docs/20260510_single_cell_modality_build_plan.md` | The Tier-0 build plan (IDs 12905–12910 + 12932, 12933) |
| `docs/20260510_single_cell_modality_validation_survey.md` | Pre-build validation survey |
| `docs/20260511_single_cell_modality_week1_results.md` | Week-1 results: atlas modality triage **9/10 retrospective panel** (Morgan 2010 HER2 fatality, Parkhurst 2011 CEA colitis, ROR1, EGFR all correctly flagged) |
| `docs/20260511_tier0_cases_build_plan.md` | Tier-0 case-build plan including the 5 modalities |

### 1.2 Live infrastructure to point design specs at

- Workflow DB: `backend/database/galaxy_ai_tools.db` table `workflows` (full schema in §3)
- nf-core subworkflow root: `backend/lib/galaxy/.../nextflow_nfcore/subworkflows/`
- API endpoints relevant to design (do not invent new ones unless required):
  - `POST /api/nextflow/execute` — submit run
  - `GET /api/nextflow/steps?nextflow_path=...` — lazy-fetch steps + viz/QC metadata (note: API field is `parameters:` not `params:` — known footgun)
  - `POST /api/ai_assistant/generate_workflow`
  - `POST /api/ai_assistant/search_ranked` — IR over 2,455 workflows
- Tested E2E pattern: see `frontend/e2e/allometric-qc-coverage.e2e.ts` for the canonical session-restore pattern (single-cell E2E will follow the same shape)

---

## 2. Single-cell workflow inventory (current DB state)

### 2.1 Counts in `workflows` table

| Filter | Count |
|---|---|
| `domain='single_cell'` | **89** |
| `name LIKE '%scrna%' OR name LIKE '%single%cell%' OR name LIKE '%scanpy%' OR name LIKE '%seurat%'` (broader) | 42 |
| **Union of above with `executable=1`** | 120 |
| **`real_exec_status='ok'`** among union | 12 |
| `real_exec_status='ok_warnings'` among union | 16 |
| `real_exec_status='exec_error'` (broken) | 33 |
| `real_exec_status NULL` (untested) | 30 |
| `real_exec_status='fixture_failed'` | 8 |
| `real_exec_status='skip_input_type'` | 2 |

**Headline:** 28/120 workflows pass live execution. Design specs should reference the **28 green workflows** (§2.3) before referencing anything broken or untested.

### 2.2 The 6 Tier-0 modality workflows we built explicitly

These IDs are real; they were generated as part of `20260510_single_cell_modality_build_plan.md`. **None have `real_exec_status` set yet (status NULL = untested).** Treat them as *implemented but unverified* — design specs that depend on them should include a verification step.

| id | name | domain | tested? |
|---|---|---|---|
| 12860 | state_perturbation_prediction | single_cell | not yet |
| 12905 | cite_seq_preprocessing | single_cell | not yet |
| 12906 | multiome_rna_atac | single_cell | not yet |
| 12907 | scrna_doublet_qc | single_cell | not yet |
| 12908 | bd_rhapsody_scrna | single_cell | not yet |
| 12909 | parse_split_seq_scrna | single_cell | not yet |
| 12910 | merfish_spatial_analysis | single_cell | not yet |
| 12932 | atlas_expression_query | drug_discovery | atlas modality triage 9/10 retrospective panel (Week-1) |
| 12933 | modality_triage | drug_discovery | same — coupled to 12932 |

### 2.3 Tested + executable single-cell workflows (the safe-to-reference set)

These passed live execution as of 2026-06-09 / 06-10. Reference these IDs in design specs without checking.

| id | name | domain | exec_status |
|---|---|---|---|
| 10872 | alevinqc | single_cell | ok_warnings |
| 14180 | alevinqc_custom_plotting_and_data_extraction | single_cell | ok_warnings |
| 14181 | alevinqc_interactive_shiny_app | single_cell | ok_warnings |
| 13380 | celaref_scrna_seq_query_vs_microarray_ref | transcriptomics | ok |
| 14207 | celaref_scrnaseq_to_microarray_comparison | transcriptomics | ok |
| 14208 | cellbarcode_scrnaseq_sam_lineage_barcoding | transcriptomics | ok |
| 11206 | cytomem | single_cell | ok |
| 12964 | decoupler_tf_activity_scrnaseq | transcriptomics | ok_warnings |
| 13112 | destiny_projection_prediction | single_cell | ok_warnings |
| 11392 | flowclust | single_cell | ok |
| 13134 | flowclust_flowcore_integration | single_cell | ok |
| 11406 | flowSpecs | single_cell | ok |
| 11407 | flowstats | single_cell | ok_warnings |
| 13599 | geometrid_single_cell_3d_plot | single_cell | ok |
| 13000 | gsva_single_cell_gsva | transcriptomics | ok_warnings |
| 11653 | iSEE | single_cell | ok_warnings |
| 13006 | mast_scrnaseq_hurdle_analysis | transcriptomics | ok_warnings |
| 13200 | nebulosa_seurat_density | transcriptomics | ok |
| 13030 | rsubread_single_cell_10x_quantification | transcriptomics | ok |
| 14393 | rsubread_single_cell_rna_seq_quantification | transcriptomics | ok |
| 12337 | scRNAseqApp | transcriptomics | ok_warnings |
| 12312 | scfeatures | single_cell | ok_warnings |
| 14033 | scgps_subpopulation_relationship_prediction | single_cell | ok_warnings |
| 12314 | schex | single_cell | ok |
| 12336 | screpertoire | single_cell | ok_warnings |
| 13240 | screpertoire_bcr_repertoire_clustering | single_cell | ok_warnings |
| 12400 | singleCellTK | transcriptomics | ok_warnings |
| 12398 | singlecellalleleexperiment | transcriptomics | ok_warnings |
| 13059 | ucell_seurat_workflow | transcriptomics | ok |
| 13060 | ucell_single_cell_experiment_workflow | transcriptomics | ok |

### 2.4 nf-core single-cell pipelines (reference but verify before pinning)

| id | name | input_types | output_types |
|---|---|---|---|
| 12777 | nf-core/scrnaseq | `["fastq","samplesheet"]` | `["counts_matrix","h5ad","multiqc_report"]` |
| 12775 | nf-core/scdownstream | `[]` | `["results_dir"]` |
| 12776 | nf-core/scnanoseq | (varies) | (varies) |
| 12728 | nf-core/marsseq | (varies) | (varies) |
| 12715 | nf-core/hadge | (varies) | (varies) |
| 1804 | nf-core/h5ad_removebackground_barcodes_cellbender_anndata | (varies) | (varies) |
| 10539 | H5Ad Removebackground Barcodes Cellbender Anndata | (varies) | (varies) |

---

## 3. `workflows` table schema (fields you may need to reference)

```sql
CREATE TABLE workflows (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    filename TEXT UNIQUE NOT NULL,
    description TEXT,
    annotation TEXT,
    tags TEXT,                       -- JSON array
    domain TEXT,                     -- single_cell, transcriptomics, genomics, drug_discovery, ...
    workflow_json TEXT NOT NULL,     -- full .ga or .nf workflow body
    step_count INTEGER,
    tools_used TEXT,                 -- JSON array of tool IDs
    created_at TIMESTAMP,
    source TEXT,                     -- bioconductor / nf-core / custom / generated
    format TEXT,                     -- galaxy_ga | nextflow_nf
    executable INTEGER,              -- 1 = runnable on AWS Batch / Galaxy
    docker_image TEXT,
    category TEXT,                   -- bioconductor / nfcore / ...
    workflow_hash TEXT,
    indexed_at TEXT,
    input_types TEXT DEFAULT '[]',   -- JSON array of strings, freeform with parens
    output_types TEXT DEFAULT '[]',
    annotation_v2 TEXT,              -- v2 annotation (curated)
    annotation_v2_at TEXT,
    workflow_correctness_score REAL,
    workflow_correctness_verdict TEXT,
    workflow_json_v2 TEXT,
    workflow_json_v2_at TEXT,
    visualization_tools TEXT,        -- JSON
    qc_steps TEXT,                   -- JSON
    step_metadata TEXT,              -- JSON: per-step phase, outputs, viz, qc (see §4)
    real_exec_status TEXT,           -- ok | ok_warnings | exec_error | fixture_failed | skip_input_type | NULL
    real_exec_at TEXT,
    real_exec_produced INTEGER,
    real_exec_err TEXT,
    params_schema TEXT,              -- JSON: data_inputs[], param_inputs[]
    real_exec_provisional INTEGER
);
```

Indexes you can rely on: `idx_tools_category`, FTS table `workflows_fts` (name, description, annotation, tags, domain, tools_used).

---

## 4. Example `step_metadata` + `params_schema` (what design specs should produce)

### 4.1 `step_metadata` example (workflow id 13030, `rsubread_single_cell_10x_quantification`)

```json
[
  {
    "step": "Build reference index using buildindex",
    "phase": "Input & Preparation",
    "outputs": [],
    "visualizations": [],
    "qc": []
  },
  {
    "step": "Define sample sheet with Barcode/UMI and Read files",
    "phase": "Input & Preparation",
    "outputs": [],
    "visualizations": [],
    "qc": []
  },
  {
    "step": "Run single-cell quantification using cellCounts",
    "phase": "Core Analysis",
    "outputs": [
      {"file": "cellCounts_sample_info.csv", "kind": "table"},
      {"file": "cellCounts_output.rds", "kind": "object"},
      {"file": "cellCounts_matrix_Example.rds", "kind": "object"}
    ],
    "visualizations": [],
    "qc": []
  }
]
```

**Phase taxonomy in use** (per the pharmacology + bioc-viz refactors): `Input & Preparation`, `Core Analysis`, `QC & Filtering`, `Annotation & Interpretation`, `Output & Reporting`. Reuse these — don't invent new phase names.

**`outputs[]` shape:** each is `{file, kind}` where `kind ∈ {table, plot, object, archive, report}`.

**`visualizations[]` shape:** each is `{title, src, kind}` where `kind ∈ {image, html, pdf, interactive}`.

**`qc[]` shape:** each is `{metric, threshold, direction, gate_action}` where `direction ∈ {gte, lte, eq}` and `gate_action ∈ {halt, advisory, pass}`.

### 4.2 `params_schema` shape

```json
{
  "data_inputs": [
    {
      "name": "hg38_chr1.fa.gz",
      "type": "fasta",
      "optional": true,
      "read_by_workflow": false,
      "description": "FASTA reference genome"
    },
    {
      "name": "reads_R1.fastq.gz",
      "type": "data",
      "optional": true,
      "read_by_workflow": false,
      "description": "Barcode/UMI file"
    }
  ],
  "param_inputs": [
    /* same shape as data_inputs but for scalar params */
  ]
}
```

Reference `docs/20260417_DRUG_DEVELOPMENT_COVERAGE_ANALYSIS.md` for the canonical `params_schema` validation rules. **Don't add params to production `.nf` files for benchmark expectations** — CLAUDE.md rule §"Do not modify production workflow files for benchmark purposes".

---

## 5. Single-cell domain primitives — what should appear in a design spec

When writing a Claude design requirement for a single-cell workflow, the spec needs to address:

### 5.1 Input modality (pick one or combine)

- **10X Genomics** Chromium GEX (3'/5'), Multiome (RNA+ATAC), Visium, Xenium
- **BD Rhapsody** (we have a Tier-0 wrapper at id 12908)
- **Parse Biosciences SPLiT-seq** (id 12909)
- **Smart-seq2 / Smart-seq3** (plate-based)
- **MERFISH / seqFISH / Vizgen / Stereo-seq** spatial (id 12910 for MERFISH)
- **CITE-seq** RNA+protein (id 12905)
- **inDrops / Drop-seq** legacy
- **Long-read scRNA** (ONT / PacBio — handled by nf-core/scnanoseq id 12776)

### 5.2 Processing stage (where in the pipeline the workflow sits)

1. **Raw → counts:** alignment / quantification (`nf-core/scrnaseq` id 12777, `rsubread_single_cell_10x_quantification` id 13030)
2. **QC / filtering:** doublet detection (`scrna_doublet_qc` id 12907), background removal (`cellbender_anndata`)
3. **Normalization + integration:** Harmony, scVI, scanorama (gen workflows: `Create Harmony Embeddings Scrna` id 10663, `Create Scvi Embeddings Scrna` id 10665)
4. **Cell-type annotation:** `Annotate Celltype Scrna` id 10659, `panhumanpy` id 10660, `singler_annotation_with_single_cell_reference_and_diagnostics` id 13037
5. **Downstream:** DE (`mast_scrnaseq_hurdle_analysis` id 13006), TF activity (`decoupler_tf_activity_scrnaseq` id 12964), pathway scoring (`ucell` id 13059/13060)
6. **Visualization:** `iSEE` id 11653, `scRNAseqApp` id 12337, `schex` id 12314

### 5.3 QC gates that must appear in every single-cell spec

Per the auto-loop QC framework (`auto-loop QC: 96/96`), every single-cell workflow should declare gates for:

| Gate | Direction | Typical threshold | Action |
|---|---|---|---|
| min reads per cell | `gte` | 500 | halt-on-fail |
| % mitochondrial reads | `lte` | 20% | advisory |
| % ribosomal reads | `lte` | 50% | advisory |
| doublet score | `lte` | 0.3 (scDblFinder default) | advisory |
| cells per sample (post-QC) | `gte` | 500 | halt-on-fail |
| median UMI per cell | `gte` | 1000 | advisory |
| ambient RNA contamination (CellBender) | `lte` | 5% | advisory |

If the design spec doesn't specify a gate, auto-loop will use the default thresholds above.

### 5.4 Output contract every single-cell workflow must satisfy

- `counts_matrix` (`h5ad` or `mtx` or `rds`) — required
- `qc_report` (`html` or `pdf`) — required
- `cell_metadata` (`csv` or `tsv`) — required
- `umap_coords` (`csv`) — recommended
- `marker_genes` (`csv`) — recommended for annotation-stage workflows
- `methods_report` (`md` or `docx`) — auto-generated, do not specify

---

## 6. Known pitfalls (carry into the design spec)

1. **API field name `parameters:` not `params:`** (Pydantic silently drops the wrong key → `Channel.fromPath` returns no files). See `docs/20260511_BIXBENCH_HANDLER_REGISTRY_AND_GENERIC_GAP.md:41`.
2. **Biocontainer Debian images omit `procps`** → Nextflow's `ps` call fails with exit 127. Add `procps` to docker layer.
3. **Quay tag `quay.io/biocontainers/...:X`** intermittently fails with `CannotPullImageManifestError` even when listed in quay UI.
4. **Empty `input_types[]` / `output_types[]`** on the 6 Tier-0 modality workflows (12905–12910) — fill these in as part of the design spec.
5. **`real_exec_status NULL`** on Tier-0 = untested. Spec must include a smoke test before claiming the workflow runs.
6. **Galaxy reload after Python changes:** `kill -HUP $(pgrep -f "gunicorn.*8081" | head -1)` — new routes are invisible until then.
7. **Auto-loop benchmark "96/96"** is Playwright + mock SSE, **not** 96 real Batch GPU runs. Don't oversell in spec.
8. **Workflow file edits**: never add params to `nextflow_nfcore/subworkflows/**/*.nf` to match a benchmark — those files are executed by Nextflow. Only edit the nfcore stub under `biomni_workflows/nfcore/` for param-extraction work.

---

## 7. Recommended spec template (skeleton)

For each single-cell workflow design requirement, the doc should include:

```markdown
## Workflow: <name>
- ID (assign new or reference existing): <id>
- Domain: single_cell
- Format: nextflow_nf  (or galaxy_ga if curated)
- Source: custom | bioconductor | nf-core
- Docker image: <ecr URI>

## Inputs (`params_schema.data_inputs[]`)
- name | type | optional | description
- ...

## Params (`params_schema.param_inputs[]`)
- name | type | default | range | description
- ...

## Steps (`step_metadata[]`)
- step | phase | outputs[] | visualizations[] | qc[]
- ...

## Output contract
- counts_matrix: <format>
- qc_report: <format>
- ...

## Auto-loop QC gates
| Gate | Direction | Threshold | Action |
|---|---|---|---|
| ... | ... | ... | ... |

## E2E test plan
- Smoke (1 sample, 100 cells): expected wall time, expected outputs
- Real run (10 samples, ~5K cells/sample): expected wall time, expected cost (T0/T1/T2/T3 tier)
- Auto-loop verification: which gate to trigger, expected remediation

## Reference implementations
- Closest existing workflow ID(s) we can copy from
- Known pitfalls (from §6 above) that apply
```

---

## 8. Quick-reference: how to query the DB for design info

```bash
# All single-cell workflows that are TESTED & green:
sqlite3 backend/database/galaxy_ai_tools.db "SELECT id, name FROM workflows WHERE real_exec_status IN ('ok','ok_warnings') AND domain='single_cell' ORDER BY name"

# Find a workflow by partial name:
sqlite3 backend/database/galaxy_ai_tools.db "SELECT id, name, real_exec_status, input_types, output_types FROM workflows WHERE name LIKE '%doublet%'"

# See the step_metadata for an existing workflow:
sqlite3 backend/database/galaxy_ai_tools.db "SELECT step_metadata FROM workflows WHERE id=13030"

# Count of tested vs untested per domain:
sqlite3 backend/database/galaxy_ai_tools.db "SELECT domain, real_exec_status, COUNT(*) FROM workflows GROUP BY domain, real_exec_status ORDER BY domain"
```
