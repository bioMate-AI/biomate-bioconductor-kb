# BioMate Catalog Audit

Generated against `backend/database/galaxy_ai_tools.db` by `python -m galaxy.ai.chain_composer.catalog_audit`.

This snapshot is intentionally read-only and serves as ground truth for design decisions about pattern library content, retrieval tuning, and downstream wiring. Re-run periodically to track drift.

---

## 1. Composition

- **Total workflows**: 4,005
- **Executable**: 3,960 (99%)

### By source
| Source | Count | Share |
|---|---|---|
| `bioconductor` | 3,310 | 83% |
| `biomni_nextflow` | 259 | 6% |
| `nfcore` | 230 | 6% |
| `nfcore_subwf` | 93 | 2% |
| `nextflow` | 61 | 2% |
| `biomate` | 45 | 1% |
| `biomni` | 3 | 0% |
| `galaxy_biomni` | 2 | 0% |
| `biomate_test` | 1 | 0% |
| `biomate_curated` | 1 | 0% |

### Top 20 domains
| Domain | Count |
|---|---|
| transcriptomics | 1,688 |
| genomics | 741 |
| epigenomics | 261 |
| variant_calling | 179 |
| proteomics | 174 |
| general | 129 |
| drug_discovery | 110 |
| systems_biology | 106 |
| single_cell | 85 |
| imaging | 77 |
| metagenomics | 75 |
| metabolomics | 56 |
| pharmacology | 39 |
| genetics | 35 |
| molecular_biology | 33 |
| bioimaging | 24 |
| immunology | 23 |
| microbiology | 17 |
| physiology | 14 |
| bioengineering | 13 |

## 2. Workflow shape

### Step count distribution (executable only)
| Steps | Workflows | Share |
|---|---|---|
| null | 11 | 0% |
| 0 | 10 | 0% |
| 1 | 1,170 | 30% |
| 2-3 | 836 | 21% |
| 4-5 | 898 | 23% |
| 6-10 | 750 | 19% |
| 11+ | 285 | 7% |

### Description quality
| Length | Workflows | Share |
|---|---|---|
| empty/null | 0 | 0% |
| 1–30 chars (likely truncated) | 265 | 7% |
| 31–120 chars (one-sentence) | 1,497 | 38% |
| 120+ chars (paragraph) | 2,198 | 56% |

### `annotation` field coverage
- has annotation text: **2,432** (61%)

## 3. Typed I/O coverage + indexer quality

- `input_types` populated: **3,094** / 3,960 (78%)
- `output_types` populated: **3,139** / 3,960 (79%)

- **Bioconductor output stub**: 2,770 / 3,310 (84%) have identical `output_types=['table/csv','plot/pdf','object/rds']`

- **biomni_nextflow params-as-types**: 72 / 250 (29%) workflows have `input_types` composed of parameter names (indexer bug at index_all_workflows.py:309)

## 4. Curated chain reach

- Total curated chains: **34**
- Intent-eligible (excl. bioc_reactive): **34**

- Unique step names referenced by curated chains: **74**
- Of those, exist in catalog: **51** (69%)
- Catalog workflows reachable via curated chains: **51** / 3,959 (1%)

> The vast majority of the catalog is NOT yet reachable via curated chains. Curated chains cover a thin slice; the rest only reachable via L2 (pattern + LLM compose).

- Curated chains spanning ≥2 known sources: **17** / 34 (50%)

## 5. Per-pattern catalog coverage

For each pattern, how many catalog workflows score above quality thresholds when BM25-searched with the pattern's `When + Pitfall + Instantiations` text. High score = strong textual alignment (not necessarily a perfect fit).

| Pattern | top-1 | n ≥ 30 | n ≥ 15 | n ≥ 5 | top-3 candidates |
|---|---|---|---|---|---|
| `sequential_omics_pipeline` | 60.6 | 165 | 1018 | 2743 | `Lc Ms Proteomics Metabolomics`, `nf-core/rnavar`, `nf-core/longraredisease` |
| `multi_omics_integration` | 84.9 | 29 | 331 | 1834 | `scrapper_multimodal_rna_adt_analysis`, `nipalsmcia_single_cell_cite_seq_mcia`, `mosim_single_cell_multi_omics_simulation` |
| `multi_method_consensus` | 47.0 | 113 | 674 | 2043 | `piano_consensus_gsa_scoring`, `bionero_consensus_modules`, `nf-core/rnavar` |
| `ensemble_annotation` | 49.1 | 42 | 544 | 1904 | `reactomepa_reactome_gsea`, `Vcf Annotate Ensemblvep`, `nf-core/vcf_annotate_ensemblvep` |
| `iterative_refinement` | 38.1 | 2 | 126 | 880 | `ADMET Pred (Legacy)`, `fishalyser_manual_threshold_and_particle_cleaning`, `Predict ADMET Properties (AI)` |
| `cross_cohort_replication` | 51.8 | 9 | 209 | 1475 | `bacon_multiple_sets_and_meta_analysis`, `epimutacions_leave_one_out_epimutation_analysis`, `mmuphin` |
| `discovery_then_validation` | 43.4 | 11 | 281 | 1629 | `damirseq_cross_validation_and_independent_prediction`, `icare_absolute_risk_model_validation`, `Transcriptomic Biomarker` |
| `branching_on_qc` | 48.8 | 64 | 712 | 2398 | `nf-core/h5ad_removebackground_barcodes_cellbender_anndata`, `CryoSPARC Standard Single-Particle Analysis`, `nf-core/rnaseq` |
| `hierarchical_re_evaluation` | 57.8 | 48 | 416 | 1556 | `celaref_scrnaseq_to_microarray_comparison`, `scmap_cell`, `retrofit_one_step_deconvolution_and_annotation` |
| `filter_cascade` | 46.8 | 37 | 449 | 1632 | `aizynthfinder_retrosynthesis`, `Scaffold Hopping`, `cogena_drug_repositioning` |
| `resampling_uncertainty` | 54.6 | 5 | 147 | 1633 | `PhyKIT Phylogenetic Metrics`, `synergyfinder_two_drug_with_replicates`, `hopach` |
| `time_series_longitudinal` | 83.8 | 70 | 766 | 2346 | `edge_timecourse_de_analysis`, `randrotation_mixed_model_batch_correction`, `Analyze Xenograft Tumor Growth Inhibition` |

Read: a pattern with `n ≥ 15 = 50` has 50 strongly-aligned catalog workflows. A pattern with `n ≥ 30 = 0` may be under-served by the catalog OR may have a narrow pattern doc that doesn't generate many BM25 hits.
## 6. Auxiliary tables

- **`tools`** (Galaxy ToolShed atomic tools): 10,201 tools + 0 datasets

  Top 10 tool categories:
  - Sequence Analysis: 1,300
  - Metagenomics: 948
  - Proteomics: 397
  - RNA: 389
  - Variant Analysis: 332
  - Assembly: 298
  - Convert Formats: 287
  - Computational chemistry: 282
  - Metabolomics: 279
  - nf-core: 231

- **`tool_compatibility`**: 9,656 rows (input=9656)
  > Note: every row's `compatibility_type` is the same. This table currently records *what tools accept as input* — not output edges. Cannot be used as-is to infer tool-to-tool chain edges.

- **`tool_usage_patterns`**: 0 rows — **empty, no usage signal available**
- **`session_workflows`**: 0 rows — empty, no run history available

  > No popularity / success-rate signals exist. Confidence-calibration cannot be driven by real usage; only synthetic eval sets (e.g. eval_queries.jsonl).

- **BGE dense embeddings** (used by `unified_workflow_search`):
  - `galaxy_ai_tools_embeddings.npz`: tool_ids=(8095,), embeddings=(8095, 384)
  - `galaxy_ai_workflow_embeddings.npz`: workflow_ids=(2473,), embeddings=(2473, 384)

## 7. Headline takeaways

1. **Bioconductor dominates: 3,310 / 3,960 executable workflows (84%).** Of those, 2,770 (84%) have an identical `output_types` stub. Output typing of Bioc is essentially uninformative; only the prose description carries signal.

2. **Curated coverage is thin**: 34 chains reference 51 catalog workflows out of 3,959 (1%). The rest of the catalog is only reachable via L2 (pattern + LLM compose) or L3 (free tool-use loop).

3. **No usage data exists.** `tool_usage_patterns` and `session_workflows` are both empty. We can't calibrate confidence thresholds against real success/abandon signals; only synthetic eval.

4. **Tool_compatibility is one-directional.** All 9,656 rows are `input` edges. Cannot be used to derive tool→tool chain edges as-is; needs an `output` indexing pass.

5. **The catalog has rich coverage but uneven indexer quality.** Per-pattern retrieval works well for shapes whose canonical tools have distinctive descriptions (`edge_timecourse_de_analysis`, `piano_consensus_gsa_scoring`). It fails when the catalog stores names without descriptions or with stub outputs.

6. **BGE dense embeddings cover ~67% of executable workflows** (2,473 / 3,695). The remaining 1,222 workflows are reachable only via lexical (BM25) retrieval — the prototype's L2 path. A backfill pass would close the gap.
