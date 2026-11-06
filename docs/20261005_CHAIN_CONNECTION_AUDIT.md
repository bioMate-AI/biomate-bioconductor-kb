# Chain Step-to-Step Connection Audit — Handoff-Name Mismatches

**Date:** 2026-10-05
**Scope:** Every connection in every workflow chain in `backend/database/galaxy_ai_tools.db` (`workflow_chains`, 69 rows), checked against the live handoff resolver and the actual `.nf` outputs/params each step produces/consumes.
**Mode:** Read-only correctness audit. No files edited.

---

## 1. Resolver summary (one line, so verdicts match real behavior)

When a chain has `connections`, each is wired by `_apply_connection_handoffs` → `pick_artifact_file(files, from_output)`, which matches `from_output` (lowercased) to a **real runtime output FILENAME** by, in order: **(1)** exact filename, **(2)** the `_PARAM_TO_EXT` extension map *only if `from_output` is one of its logical keys* (`reads/input/fastq/bam/bai/vcf/variants/genome/fasta/reference/samplesheet/tsv/csv/params_json/ligand_sdf/compounds/ligand_file/smiles/ligand_smiles`), **(3)** `from_output` is a **substring** of a filename, **(4)** a file's extension is a substring of `from_output`; the wired value is then set as `params[to_input]`.

**Critical behavioral fact (the root of every BROKEN below):** the extension-heuristic fallback `_EXT_TO_PARAM` / `_resolve_outputs_for_run` is **only** used in the `elif idx > 0` branch — i.e. when the chain has **no `connections` at all**. For any chain that declares connections (58 of 69), if `pick_artifact_file` returns `None`, the handoff is silently dropped (a `handoff_warning` is appended, the param is never set), and **no fallback rescues it**. So a `from_output` that is a semantic/logical label (`de_results`, `cluster_assignments`, `normalized_sce`, …) resolves **only** if that exact token happens to appear as a substring of a published filename. This is exactly the DE→enrichment bug the user found (`de_results` vs the published `*_DESeq2_results.csv`), and it recurs across the catalog.

---

## 2. Methodology & honesty caveats

- Upstream output names were extracted **statically** from each resolved `.nf` (`path "..."`, `emit:`, `touch`, `write.csv`/`saveRDS`/`ggsave`/`paste0`/`file=` targets, glob `*.ext`). Step workflow→`.nf` resolution reproduces `resolve_workflow_name_to_path` (the same cascade the engine uses).
- **Runtime filename prefixes** (e.g. `${contrast}_DESeq2_results.csv`, `${meta.id}_seqarray_results.csv`) cannot be known fully in advance; I matched on the static stem/suffix the code guarantees. Where a `.nf` could not be located under `backend/biomni_workflows/` or declares no parseable outputs (a script-only stub), the connection is marked **UNCERTAIN** rather than guessed.
- **`to_input` "⚠not-a-param"**: many downstream wrappers ingest inputs by downloading from S3 inside their R/Python body using generic params (`params.input`, `params.matrix`) rather than declaring the connection's `to_input` as a literal `params.<to_input>`. So a `⚠not-a-param` tag is a *secondary* signal (the wired value may be ignored even when `from_output` resolves); it is **not** by itself proof of breakage and should not be read as one. Only 5 of 137 `to_input` names are literal downstream params. The primary verdict column is driven by `from_output` resolvability.
- A **BROKEN** `from_output` does not always hard-*halt* the chain: the step still launches with its `params_template` defaults. It stalls/produces wrong science only when `to_input` is a required input with no default. Either way the **declared data handoff does not happen** — that is the defect audited here.

### Verdict totals

| Verdict | Count | Meaning |
|---|---:|---|
| **OK** | 23 | `from_output` resolves cleanly (exact / ext-map / clear substring) |
| **FALLBACK** | 12 | resolves only via rule 4 (a file extension is a substring of `from_output`, e.g. `normalised_bam`→`.bam`, `somatic_vcf`→`.vcf`, `filtered_smiles`→`.smi`) — works today but brittle |
| **BROKEN** | 56 | `from_output` matches no published filename and is not a `_PARAM_TO_EXT` key → handoff silently dropped |
| **UNCERTAIN** | 46 | upstream `.nf` not found in tree, is a script-only stub with no declared outputs, or `from_output` is a scalar JSON field the file-resolver cannot address |
| **TOTAL** | **137** | across 69 chains (58 with connections) |

- Chains with ≥1 BROKEN connection: **33**.
- Chains entirely **OK**: 5 — `alternative_polyadenylation_analysis`, `bioc_proteomics_de_v2`, `bioc_scrna_cluster_v2`, `cellcell_communication_with_viz`, `time_series_de_with_edge`.
- Chains fully clean (**OK or FALLBACK** only, no BROKEN/UNCERTAIN): 9 — the 5 above **plus** `cutandtag_chromatin_analysis`, `mutation_signature_pipeline`, `phylogenetic_uncertainty_via_phykit`, `visium_voyager_to_isee`.
- Single-step chains (no connections, nothing to wire): `bispecific_format_triage_chain`, `fda_ligand_screen_chain`, `glp1_modality_bakeoff_chain`, `in_vivo_base_edit_design_chain`, `in_vivo_cart_codesign_chain`, `scgwas_immunology_chain`, `torchgwas_udip_chain`, `target_discovery_full`, `modality_triage_oncology_chain`, `tumor_reactive_t_cell_chain`, `z01_gwas_methods_chain` (the last three list steps but define `connections: []`, so steps run independently with no data handoff).

---

## 3. Prioritized SHORTLIST of BROKEN connections (with exact fixes)

Two kinds of breakage. **(A) Renameable** — upstream *does* produce the right artifact; the `from_output` label just doesn't match the filename. Fix = change `from_output` (and sometimes `to_input`) to a resolvable token. **(B) Design gap** — upstream does **not** emit the artifact the connection wants at all; no rename fixes it (the wrapper must be changed to emit the file, or an intermediate step added). These are called out explicitly.

### Tier 1 — High-traffic RNA-seq / DE / enrichment chains (fix first)

| Chain | Connection | Current `from_output` | Suggested `from_output` | Why |
|---|---|---|---|---|
| `bulk_rnaseq_de_analysis` | s2→s3 | `de_results` | **`results`** (or `csv`) | nf-core/differentialabundance writes `*_DESeq2_results.csv`; `results`⊂ filename. *(the user's confirmed bug)* |
| `rnaseq_to_lincs_moa` | s2→s3 (×2) | `top_up_genes`, `top_down_genes` | **`significant_genes`** (matches `significant_genes.txt`) or `results` | differentialabundance emits no separate up/down files — **(B) partial design gap**: one file holds all DEGs; downstream `transcriptomic_moa_lincs` must split, or add a splitter step |
| `ensemble_gene_set_enrichment_egsea` | s1→s3 | `de_table` | **`results`** / `significant_genes` | same differentialabundance outputs |
| `bulk_rnaseq_consensus_de_bioc` | s2→s3 | `de_table` | **`results`** | deseq2 writes `condition_treated_results.csv` |
| `bp4_rnaseq_best_practices_pipeline` | s1→s2 | `salmon_quants` | **`quant`** (matches `quant.sf`) or `counts_matrix` | rnaseq emits `*/quant.sf` + `counts_matrix.tsv`, never `salmon_quants` |
| `bp4_rnaseq_best_practices_pipeline` | s3→s4 | `de_table` | **`results`** | deseq2 multi_factor writes `results_multi_factor_*.csv` |
| `multiomic_differential_expression_exphunter` | s1→s2 | `count_matrix` | **`counts_matrix`** | **plain typo** (missing `s`); rnaseq emits `counts_matrix.tsv` |
| `meta_analysis_with_bacon` | s2→s3 | `effect_sizes_and_se` | **`results`** | multi_factor emits `results_multi_factor_*.csv` |
| `rnaseq_differential_transcript_usage` | s1→s2 | `salmon_quants` | **`quant`** / `counts_matrix` | rnaseq, as above |
| `rnaseq_differential_transcript_usage` | s2→s4 | `drim_results` | **`dtu_gene_results`** (matches `dtu_gene_results.csv`) or `drimseq` | drimseq filenames use `dtu_*` / `drimseq_*`, never `drim_results` |

### Tier 2 — Bioconductor reactive / curated chains (renameable)

| Chain | Connection | Current | Suggested | Published artifact it should match |
|---|---|---|---|---|
| `bioc_bulk_rnaseq_de_v2` | s2→s3 | `enrichment` | `enrichgo_results` / `ego_object` / `rds` | `enrichGO_results_full.csv`, `ego_object.rds` |
| `bioc_methylation_dm_v2` | s2→s3 | `results` | `result_wrapper` / `csv` | DSS uses **singular** `result_wrapper.csv` / `result_step_by_step.csv` (so `results` with an `s` fails) |
| `bioc_variant_annotation_v2` | s1→s2 | `results` | `located_variants` / `csv` | `located_variants.csv` |
| `bioc_chipseq_annotation_v2` | s1→s2 | `results` | `csv` (→ `*_peak_profiling_and_visualization.csv`) | chipseeker emits no `*results*` file |
| `methylation_450k_array_analysis` | s1→s2, s1→s3 | `GenomicMethylSet` | `gmsetex` / `rds` | minfi persists the GenomicMethylSet as `gmsetex.rds` |
| `methylation_450k_array_analysis` | s2→s4 | `dmps` | `top_table` / `csv` | limma emits `top_table_summary.csv`, `all_genes_results.csv` |
| `cytof_mass_cytometry_analysis` | s2→s3, s2→s4 | `cluster_assignments` | `flowsom_assignments` / `assignments` / `csv` | `flowsom_assignments.csv` |
| `geomx_spatial_transcriptomics` | s2→s3 | `norm_set` | `normalized_target` / `geomxset` / `rds` | `normalized_target_demodata_geomxset.rds` |
| `cnv_consensus_pipeline` | s2→s3 | `cnv_segments` | `copy_number_estimates` / `csv` | `copy_number_estimates.csv` |
| `lcms_metabolomics_consensus` | s1→s2 | `xcms_set` | `xcms_preprocessed` / `rds` | `xcms_preprocessed_object.rds` |
| `lcms_metabolomics_consensus` | s2→s3 | `annotated_features` | `xsannotated` / `csv` | `xsannotated.csv` |
| `cyp450_ddi_chain` | s1→s2 | `ddi_predictions` | `ddi_risk_assessment` / `ddi_risk` / `json` | `ddi_risk_assessment.json`, `ddi_risk_report.html` |
| `mageck_to_gears_moa` | s1→s2 | `top_hit_genes` | `pathway_enrichment` / `tsv` | mageck emits `pathway_enrichment.tsv` (no explicit hit-gene file — partial **(B)**) |

### Tier 3 — Drug-design / docking / MD chains (renameable where a file exists)

| Chain | Connection | Current | Suggested | Note |
|---|---|---|---|---|
| `andv_inhibitor_track_v1`, `target_to_lead_full` | docking s4→s5 | `vina_poses` | `pdbqt` / `sdf` (→ `out_{idx}.pdbqt`, `lig_{idx}.sdf`) | docking emits indexed pose files |
| `andv_inhibitor_track_v1`, `target_to_lead_full` | MD s5→s6 | `mmgbsa_scores` | `mmgbsa_results` / `csv` | gromacs emits `mmgbsa_results.csv` |
| `andv_inhibitor_track_v1`, `drug_discovery_admet_gated_screening`, `target_to_lead_full` | admet s3→s4 | `passed_compounds` | — | **(B) design gap**: predict_admet emits only `predict_admet_properties_results.json` / `toxicity_report.json` — no filtered compound SDF/SMILES. ADMET wrapper must emit a passed-compounds file (sdf/smi) for docking to consume. |
| `drug_discovery_screening` | s1→s2 | `filtered_compounds` | — | same ADMET design gap |

### Tier 4 — Genuine design gaps (no rename fixes them — upstream does not emit the artifact)

| Chain | Connection | Problem |
|---|---|---|
| `variant_burden_after_sarek` | s2→s3 `gds`→`gds` | **SeqArray wrapper emits only `*_seqarray_results.csv` / `.rds` / `.pdf` — no `.gds`.** GWASTools needs a GDS. Wrapper must `seqVCF2GDS` → publish `*.gds`, or downstream must read the `.rds`. |
| `recount_public_rnaseq_reanalysis` | s1→s2 `rse`, s2→s3 `scaled_rse` | recount3 wrapper persists `scaled_counts.csv` / `scale_factors.csv`, **not** the RangedSummarizedExperiment `.rds`. Rename to `scaled_counts`/`csv` *and* confirm downstream accepts a CSV, or make the wrapper `saveRDS` the RSE. |
| `scrna_pseudobulk_de_bioc` | s2→s3 `qc_sce`→`sce` | **scater QC wrapper emits only plots (`*.pdf`) + `*_structure.txt` — no `.rds` SCE object.** The QC'd SingleCellExperiment is never persisted, so the entire 7-step pseudobulk chain cannot hand off after step 2. Wrapper must `saveRDS` the filtered SCE. |
| `scrna_consensus_de_bioc` | s2→s3, s2→s4 `normalized_sce` | same scater-emits-no-rds gap. |
| `scrna_pseudobulk_de_bioc` | s3→s4, s4→s5, s4→s6, s5→s7, s6→s7 (`normalised_sce`,`clustered_sce`,`markers`,`annotated_sce`) | scran emits one `sce_normed.rds` + `quick_clusters.csv`; singler emits `predicted_labels.rds`. Labels like `clustered_sce`/`markers` don't match and multiple `.rds` are ambiguous — needs distinct, matchable filenames per stage. |
| `single_cell_multimodal_analysis` | s3→s4, s3→s5 `h5ad_annotated` | `annotate_celltype_scRNA` emits only `*_output.txt` / `*_results.json` (an AI step) — no `.h5ad`. Downstream trajectory/DA steps need an AnnData. |
| `rnaseq_epigenomic_integration_fluent` | s1→s3 `de_genes_bed` | nf-core/rnaseq produces no DE/BED file (only counts/bam) — a DE-calling + BED-export step is missing between rnaseq and plyranges. |
| `bioc_variant_annotation_workflow` | s2→s3 `annotated_vcf` | Bioconductor VariantAnnotation emits `located_variants.csv`/`.rds`, **not** a VCF; downstream `variantfiltering` expects a VCF. Format mismatch — either keep nf-core VEP output as the VCF source or convert. |

> **Also note — scalar-field handoffs (UNCERTAIN, structurally unsupported):** the mechanistic PK/ADMET chains (`admet_to_cipa_cardiac`, `admet_to_virtual_patient_dose_opt`, `pbpk_to_tumor_tgi`, `cyp450_ddi_chain` s2→s3, `pbpk_renal_impairment_chain`, `phase2_dose_justification_chain`) wire **scalar JSON fields** (`herg_ic50_nM`, `bioavailability`, `cl_L_h`, `cmax_mg_L`, `er_model`, …) step-to-step. The file resolver cannot address a field *inside* a JSON. These need the `context_params` mechanism (`resolve_context_params`, already in `workflow_chain.py`) which reads from `prev_run_params` — but **none of these connections set `context_params`**. Several of their `.nf` paths also don't exist under `backend/biomni_workflows/`, so they're UNCERTAIN here; regardless, as plain `from_output`/`to_input` file handoffs they will not resolve.

---

## 4. Full per-chain connection table

Legend: **OK** = resolves cleanly · **FALLBACK** = resolves only by rule-4 extension-in-name (brittle) · **BROKEN** = no match, handoff dropped · **UNCERTAIN** = `.nf` unresolved / stub / scalar field. `⚠not-a-param` = `to_input` is not a literal `params.<name>` in the downstream `.nf` (secondary signal only — see §2).

<!-- TABLE START -->
#### `admet_to_cipa_cardiac`
| verdict | conn (from→to) | from_output | to_input | note |
|---|---|---|---|---|
| **BROKEN** | s1→s2 | `herg_ic50_nM` | `herg_ic50_nM` | 'herg_ic50_nm' not substring of any output name/stem; exts=['json', 'txt', 'yml'] |
| **BROKEN** | s1→s2 | `admet_results` | `admet_context` | 'admet_results' not substring of any output name/stem; exts=['json', 'txt', 'yml'] |

#### `admet_to_virtual_patient_dose_opt`
| verdict | conn (from→to) | from_output | to_input | note |
|---|---|---|---|---|
| **BROKEN** | s1→s3 | `bioavailability` | `bioavailability` | 'bioavailability' not substring of any output name/stem; exts=['json', 'txt', 'yml'] |
| **UNCERTAIN** | s2→s3 | `cl_L_h` | `cl_L_h` | upstream .nf not resolved/found |
| **UNCERTAIN** | s2→s3 | `vd_L` | `vd_L` | upstream .nf not resolved/found |

#### `alternative_polyadenylation_analysis`
| verdict | conn (from→to) | from_output | to_input | note |
|---|---|---|---|---|
| **OK** | s1→s2 | `bam` | `bam` ⚠not-a-param | resolves |

#### `andv_inhibitor_track_v1`
| verdict | conn (from→to) | from_output | to_input | note |
|---|---|---|---|---|
| **FALLBACK** | s2→s3 | `filtered_smiles` | `smiles` ⚠not-a-param | ext-in-name heuristic |
| **BROKEN** | s3→s4 | `passed_compounds` | `ligand_sdf` ⚠not-a-param | 'passed_compounds' not substring of any output name/stem; exts=['json', 'txt', 'yml'] |
| **UNCERTAIN** | s1→s4 | `pocket_json` | `pocket_coords` ⚠not-a-param | upstream .nf not resolved/found |
| **BROKEN** | s4→s5 | `vina_poses` | `docked_poses` ⚠not-a-param | 'vina_poses' not substring of any output name/stem; exts=['json', 'pdb', 'pdbqt', 'sdf', 'txt', 'yml'] |
| **BROKEN** | s5→s6 | `mmgbsa_scores` | `seed_smiles` | 'mmgbsa_scores' not substring of any output name/stem; exts=['csv', 'edr', 'gro', 'json', 'mol2', 'pdb', 'png', 'sdf', 'xtc'] |

#### `bioc_bulk_rnaseq_de_v2`
| verdict | conn (from→to) | from_output | to_input | note |
|---|---|---|---|---|
| **OK** | s1→s2 | `results` | `de_results` ⚠not-a-param | resolves |
| **BROKEN** | s2→s3 | `enrichment` | `enrichment_obj` ⚠not-a-param | 'enrichment' not substring of any output name/stem; exts=['csv', 'json', 'pdf', 'rds', 'txt', 'yml'] |

#### `bioc_chipseq_annotation_v2`
| verdict | conn (from→to) | from_output | to_input | note |
|---|---|---|---|---|
| **BROKEN** | s1→s2 | `results` | `gene_list` | 'results' not substring of any output name/stem; exts=['csv', 'pdf', 'rds', 'yml'] |

#### `bioc_methylation_dm_v2`
| verdict | conn (from→to) | from_output | to_input | note |
|---|---|---|---|---|
| **OK** | s1→s2 | `rds` | `methylset_rds` ⚠not-a-param | resolves |
| **BROKEN** | s2→s3 | `results` | `dmp_results` ⚠not-a-param | 'results' not substring of any output name/stem; exts=['csv', 'json', 'pdf', 'rds', 'yml'] |

#### `bioc_proteomics_de_v2`
| verdict | conn (from→to) | from_output | to_input | note |
|---|---|---|---|---|
| **OK** | s1→s2 | `rds` | `msnset_rds` ⚠not-a-param | resolves |

#### `bioc_scrna_cluster_v2`
| verdict | conn (from→to) | from_output | to_input | note |
|---|---|---|---|---|
| **OK** | s1→s2 | `rds` | `sce_rds` ⚠not-a-param | resolves |

#### `bioc_variant_annotation_v2`
| verdict | conn (from→to) | from_output | to_input | note |
|---|---|---|---|---|
| **BROKEN** | s1→s2 | `results` | `gene_list` | 'results' not substring of any output name/stem; exts=['csv', 'gz', 'json', 'pdf', 'rds', 'yml'] |

#### `bioc_variant_annotation_workflow`
| verdict | conn (from→to) | from_output | to_input | note |
|---|---|---|---|---|
| **OK** | s1→s2 | `vcf` | `vcf` ⚠not-a-param | resolves |
| **BROKEN** | s2→s3 | `annotated_vcf` | `annotated_vcf` ⚠not-a-param | 'annotated_vcf' not substring of any output name/stem; exts=['csv', 'gz', 'json', 'pdf', 'rds', 'yml'] |
| **BROKEN** | s3→s4 | `filtered_vcf` | `vcf_or_maf` | 'filtered_vcf' not substring of any output name/stem; exts=['bam', 'csv', 'pdf', 'rds', 'yml'] |

#### `bp4_rnaseq_best_practices_pipeline`
| verdict | conn (from→to) | from_output | to_input | note |
|---|---|---|---|---|
| **BROKEN** | s1→s2 | `salmon_quants` | `quants` ⚠not-a-param | 'salmon_quants' not substring of any output name/stem; exts=['bai', 'bam', 'bigwig', 'csv', 'fq', 'gz', 'html', 'json', 'png', 'sf', 'tsv', 'txt'] |
| **OK** | s2→s3 | `dds` | `dds` ⚠not-a-param | resolves |
| **BROKEN** | s3→s4 | `de_table` | `ranked_genes` ⚠not-a-param | 'de_table' not substring of any output name/stem; exts=['csv', 'json', 'pdf', 'rds', 'yml'] |

#### `bulk_rnaseq_consensus_de_bioc`
| verdict | conn (from→to) | from_output | to_input | note |
|---|---|---|---|---|
| **OK** | s1→s2 | `counts_matrix` | `counts` ⚠not-a-param | resolves |
| **BROKEN** | s2→s3 | `de_table` | `gene_list` | 'de_table' not substring of any output name/stem; exts=['csv', 'json', 'pdf', 'rds', 'yml'] |

#### `bulk_rnaseq_de_analysis`
| verdict | conn (from→to) | from_output | to_input | note |
|---|---|---|---|---|
| **OK** | s1→s2 | `counts_matrix` | `counts` ⚠not-a-param | resolves |
| **BROKEN** | s2→s3 | `de_results` | `gene_list` ⚠not-a-param | 'de_results' not substring of any output name/stem; exts=['csv', 'html', 'json', 'pdf', 'rds', 'txt', 'yml'] |

#### `cage_seq_promoter_analysis`
| verdict | conn (from→to) | from_output | to_input | note |
|---|---|---|---|---|
| **UNCERTAIN** | s1→s2 | `ctss_bed` | `ctss_input` | upstream .nf not resolved/found |
| **UNCERTAIN** | s2→s3 | `tag_clusters` | `clusters` | upstream .nf not resolved/found |

#### `cellcell_communication_with_viz`
| verdict | conn (from→to) | from_output | to_input | note |
|---|---|---|---|---|
| **OK** | s1→s2 | `liana_for_ccplotr.tsv` | `interactions_tsv` ⚠not-a-param | resolves |
| **OK** | s1→s3 | `liana_for_ccplotr.tsv` | `interactions_tsv` ⚠not-a-param | resolves |

#### `chipseq_window_based_differential_binding`
| verdict | conn (from→to) | from_output | to_input | note |
|---|---|---|---|---|
| **UNCERTAIN** | s1→s2 | `bam_files` | `bam_inputs` | upstream .nf not resolved/found |
| **UNCERTAIN** | s2→s3 | `window_counts` | `counts` ⚠not-a-param | upstream .nf not resolved/found |
| **OK** | s3→s4 | `qlf_results` | `window_pvals` | resolves |

#### `cnv_consensus_pipeline`
| verdict | conn (from→to) | from_output | to_input | note |
|---|---|---|---|---|
| **OK** | s1→s2 | `bam` | `bam` ⚠not-a-param | resolves |
| **BROKEN** | s2→s3 | `cnv_segments` | `cnv_regions` ⚠not-a-param | 'cnv_segments' not substring of any output name/stem; exts=['csv', 'pdf', 'rds', 'yml'] |

#### `consensus_de_with_piano`
| verdict | conn (from→to) | from_output | to_input | note |
|---|---|---|---|---|
| **OK** | s1→s2 | `counts_matrix` | `counts` | resolves |
| **UNCERTAIN** | s2→s3 | `gene_level_stats` | `myTval` ⚠not-a-param | upstream .nf not resolved/found |

#### `cutandtag_chromatin_analysis`
| verdict | conn (from→to) | from_output | to_input | note |
|---|---|---|---|---|
| **FALLBACK** | s1→s2 | `normalised_bam` | `bam` ⚠not-a-param | ext-in-name heuristic |
| **FALLBACK** | s2→s3 | `peaks_bed` | `peaks` ⚠not-a-param | ext-in-name heuristic |
| **FALLBACK** | s1→s3 | `normalised_bam` | `bam` ⚠not-a-param | ext-in-name heuristic |

#### `cyp450_ddi_chain`
| verdict | conn (from→to) | from_output | to_input | note |
|---|---|---|---|---|
| **BROKEN** | s1→s2 | `ddi_predictions` | `in_vitro_ddi` | 'ddi_predictions' not substring of any output name/stem; exts=['html', 'json', 'png', 'sdf'] |
| **UNCERTAIN** | s2→s3 | `scaled_pk` | `human_pk` | upstream .nf not resolved/found |

#### `cytof_mass_cytometry_analysis`
| verdict | conn (from→to) | from_output | to_input | note |
|---|---|---|---|---|
| **OK** | s1→s2 | `sce` | `expr_matrix` ⚠not-a-param | resolves |
| **BROKEN** | s2→s3 | `cluster_assignments` | `cluster_labels` ⚠not-a-param | 'cluster_assignments' not substring of any output name/stem; exts=['csv', 'pdf', 'rds', 'yml'] |
| **BROKEN** | s2→s4 | `cluster_assignments` | `cluster_labels` ⚠not-a-param | 'cluster_assignments' not substring of any output name/stem; exts=['csv', 'pdf', 'rds', 'yml'] |

#### `drug_discovery_admet_gated_screening`
| verdict | conn (from→to) | from_output | to_input | note |
|---|---|---|---|---|
| **FALLBACK** | s1→s2 | `filtered_smiles` | `smiles` ⚠not-a-param | ext-in-name heuristic |
| **BROKEN** | s2→s3 | `passed_compounds` | `ligand_sdf` | 'passed_compounds' not substring of any output name/stem; exts=['json', 'txt', 'yml'] |

#### `drug_discovery_screening`
| verdict | conn (from→to) | from_output | to_input | note |
|---|---|---|---|---|
| **BROKEN** | s1→s2 | `filtered_compounds` | `compounds` | 'filtered_compounds' not substring of any output name/stem; exts=['json', 'txt', 'yml'] |
| **UNCERTAIN** | s2→s3 | `docked_poses` | `complexes` ⚠not-a-param | upstream .nf not resolved/found |

#### `ensemble_gene_set_enrichment_egsea`
| verdict | conn (from→to) | from_output | to_input | note |
|---|---|---|---|---|
| **BROKEN** | s1→s3 | `de_table` | `input_de_table` | 'de_table' not substring of any output name/stem; exts=['csv', 'html', 'json', 'pdf', 'rds', 'txt', 'yml'] |
| **UNCERTAIN** | s2→s3 | `gs_collections` | `gs_collections` | upstream .nf not resolved/found |

#### `genome_coordinate_liftover`
| verdict | conn (from→to) | from_output | to_input | note |
|---|---|---|---|---|
| **UNCERTAIN** | s1→s2 | `chain` | `chain` | upstream .nf not resolved/found |
| **UNCERTAIN** | s2→s3 | `lifted_ranges` | `lifted` | upstream .nf not resolved/found |

#### `geomx_spatial_transcriptomics`
| verdict | conn (from→to) | from_output | to_input | note |
|---|---|---|---|---|
| **OK** | s1→s2 | `geomxset` | `raw_set` ⚠not-a-param | resolves |
| **BROKEN** | s2→s3 | `norm_set` | `input_set` ⚠not-a-param | 'norm_set' not substring of any output name/stem; exts=['csv', 'pdf', 'rds', 'yml'] |

#### `gpcr_spa_cryo_em_pipeline`
| verdict | conn (from→to) | from_output | to_input | note |
|---|---|---|---|---|
| **UNCERTAIN** | s1→s2 | `particles` | `particles` | upstream .nf not resolved/found |
| **UNCERTAIN** | s2→s3 | `refined_volume` | `refined_volume` ⚠not-a-param | upstream .nf not resolved/found |

#### `lcms_metabolomics_consensus`
| verdict | conn (from→to) | from_output | to_input | note |
|---|---|---|---|---|
| **BROKEN** | s1→s2 | `xcms_set` | `xcms_set` ⚠not-a-param | 'xcms_set' not substring of any output name/stem; exts=['csv', 'pdf', 'rds', 'yml'] |
| **BROKEN** | s2→s3 | `annotated_features` | `feature_table` ⚠not-a-param | 'annotated_features' not substring of any output name/stem; exts=['csv', 'pdf', 'rds', 'yml'] |

#### `mageck_to_gears_moa`
| verdict | conn (from→to) | from_output | to_input | note |
|---|---|---|---|---|
| **BROKEN** | s1→s2 | `top_hit_genes` | `perturb_genes` | 'top_hit_genes' not substring of any output name/stem; exts=['html', 'json', 'tsv', 'txt'] |
| **UNCERTAIN** | s2→s3 | `up_regulated` | `up_genes` | upstream .nf not resolved/found |
| **UNCERTAIN** | s2→s3 | `down_regulated` | `down_genes` | upstream .nf not resolved/found |

#### `meta_analysis_with_bacon`
| verdict | conn (from→to) | from_output | to_input | note |
|---|---|---|---|---|
| **OK** | s1→s2 | `counts_matrix` | `counts` ⚠not-a-param | resolves |
| **BROKEN** | s2→s3 | `effect_sizes_and_se` | `es_and_se_matrices` ⚠not-a-param | 'effect_sizes_and_se' not substring of any output name/stem; exts=['csv', 'json', 'pdf', 'rds', 'yml'] |

#### `methylation_450k_array_analysis`
| verdict | conn (from→to) | from_output | to_input | note |
|---|---|---|---|---|
| **BROKEN** | s1→s2 | `GenomicMethylSet` | `beta` ⚠not-a-param | 'genomicmethylset' not substring of any output name/stem; exts=['csv', 'pdf', 'rds', 'yml'] |
| **BROKEN** | s1→s3 | `GenomicMethylSet` | `beta` ⚠not-a-param | 'genomicmethylset' not substring of any output name/stem; exts=['csv', 'pdf', 'rds', 'yml'] |
| **BROKEN** | s2→s4 | `dmps` | `dmp_ids` ⚠not-a-param | 'dmps' not substring of any output name/stem; exts=['csv', 'pdf', 'rds', 'txt', 'yml'] |

#### `microarray_normalization_comparison`
| verdict | conn (from→to) | from_output | to_input | note |
|---|---|---|---|---|
| **BROKEN** | s1→s5 | `rma_eset` | `rma_input` ⚠not-a-param | 'rma_eset' not substring of any output name/stem; exts=['csv', 'pdf', 'rds', 'yml'] |
| **BROKEN** | s2→s5 | `vsn_eset` | `vsn_input` ⚠not-a-param | 'vsn_eset' not substring of any output name/stem; exts=['csv', 'json', 'pdf', 'rds', 'yml'] |
| **UNCERTAIN** | s3→s5 | `lumi_eset` | `lumi_input` ⚠not-a-param | upstream .nf not resolved/found |
| **BROKEN** | s4→s5 | `combat_eset` | `combat_input` ⚠not-a-param | 'combat_eset' not substring of any output name/stem; exts=['csv', 'json', 'pdf', 'rds', 'yml'] |

#### `mrna_codon_optimization_chain`
| verdict | conn (from→to) | from_output | to_input | note |
|---|---|---|---|---|
| **UNCERTAIN** | s1→s2 | `optimized_mrna_constructs` | `candidate_constructs` | upstream .nf not resolved/found |

#### `multi_omics_mofa_chain`
| verdict | conn (from→to) | from_output | to_input | note |
|---|---|---|---|---|
| **UNCERTAIN** | s1→s4 | `normalised_counts` | `rna_matrix` | upstream .nf not resolved/found |
| **UNCERTAIN** | s2→s4 | `protein_abundances` | `proteomics_matrix` | upstream .nf not resolved/found |
| **UNCERTAIN** | s3→s4 | `metabolite_intensities` | `metabolomics_matrix` | upstream .nf not resolved/found |

#### `multiomic_differential_expression_exphunter`
| verdict | conn (from→to) | from_output | to_input | note |
|---|---|---|---|---|
| **BROKEN** | s1→s2 | `count_matrix` | `counts` | 'count_matrix' not substring of any output name/stem; exts=['bai', 'bam', 'bigwig', 'csv', 'fq', 'gz', 'html', 'json', 'png', 'sf', 'tsv', 'txt'] |
| **UNCERTAIN** | s2→s3 | `consensus_de_table` | `de_table` | upstream .nf not resolved/found |

#### `mutation_signature_pipeline`
| verdict | conn (from→to) | from_output | to_input | note |
|---|---|---|---|---|
| **FALLBACK** | s1→s2 | `somatic_vcf` | `vcf` ⚠not-a-param | ext-in-name heuristic |
| **FALLBACK** | s1→s3 | `somatic_vcf` | `vcf` ⚠not-a-param | ext-in-name heuristic |

#### `pbpk_renal_impairment_chain`
| verdict | conn (from→to) | from_output | to_input | note |
|---|---|---|---|---|
| **UNCERTAIN** | s1→s2 | `human_pk_parameters` | `pk_parameters` | upstream .nf not resolved/found |
| **UNCERTAIN** | s2→s3 | `impaired_pk_model` | `pk_model` | upstream .nf not resolved/found |

#### `pbpk_to_tumor_tgi`
| verdict | conn (from→to) | from_output | to_input | note |
|---|---|---|---|---|
| **UNCERTAIN** | s1→s2 | `cmax_mg_L` | `cmax_mg_L` | upstream .nf not resolved/found |
| **UNCERTAIN** | s1→s2 | `auc_mg_h_L` | `auc_mg_h_L` | upstream .nf not resolved/found |
| **UNCERTAIN** | s1→s2 | `pk_summary` | `pk_summary_json` | upstream .nf not resolved/found |

#### `phase2_dose_justification_chain`
| verdict | conn (from→to) | from_output | to_input | note |
|---|---|---|---|---|
| **UNCERTAIN** | s1→s2 | `er_model` | `er_model` | upstream .nf not resolved/found |
| **UNCERTAIN** | s2→s3 | `simulated_outcomes` | `phase3_predictions` | upstream .nf not resolved/found |

#### `phylogenetic_uncertainty_via_phykit`
| verdict | conn (from→to) | from_output | to_input | note |
|---|---|---|---|---|
| **FALLBACK** | s1→s2 | `mafft_alignment_and_iqtree_treefile` | `mafft_alignment_iqtree_treefile` | ext-in-name heuristic |

#### `protein_structure_prediction_chain`
| verdict | conn (from→to) | from_output | to_input | note |
|---|---|---|---|---|
| **UNCERTAIN** | s1→s2 | `msa_output` | `msa` | upstream .nf not resolved/found |
| **UNCERTAIN** | s2→s3 | `predicted_structure` | `structure_pdb` | upstream .nf not resolved/found |

#### `rare_disease_multimodal_workup`
| verdict | conn (from→to) | from_output | to_input | note |
|---|---|---|---|---|
| **OK** | s1→s2 | `vcf` | `vcf` ⚠not-a-param | resolves |
| **OK** | s3→s4 | `bam` | `bam` ⚠not-a-param | resolves |
| **FALLBACK** | s2→s5 | `annotated_vcf` | `variant_evidence` ⚠not-a-param | ext-in-name heuristic |
| **UNCERTAIN** | s4→s5 | `outrider_results` | `expression_evidence` ⚠not-a-param | upstream .nf declares no parseable output files (stub) |
| **UNCERTAIN** | s4→s5 | `fraser_results` | `splicing_evidence` ⚠not-a-param | upstream .nf declares no parseable output files (stub) |

#### `recount_public_rnaseq_reanalysis`
| verdict | conn (from→to) | from_output | to_input | note |
|---|---|---|---|---|
| **BROKEN** | s1→s2 | `rse` | `rse` ⚠not-a-param | 'rse' not substring of any output name/stem; exts=['csv', 'pdf', 'rds', 'yml'] |
| **BROKEN** | s2→s3 | `scaled_rse` | `counts` ⚠not-a-param | 'scaled_rse' not substring of any output name/stem; exts=['csv', 'pdf', 'rds', 'yml'] |

#### `rnaseq_differential_transcript_usage`
| verdict | conn (from→to) | from_output | to_input | note |
|---|---|---|---|---|
| **BROKEN** | s1→s2 | `salmon_quants` | `counts` ⚠not-a-param | 'salmon_quants' not substring of any output name/stem; exts=['bai', 'bam', 'bigwig', 'csv', 'fq', 'gz', 'html', 'json', 'png', 'sf', 'tsv', 'txt'] |
| **BROKEN** | s2→s4 | `drim_results` | `drimseq_results` ⚠not-a-param | 'drim_results' not substring of any output name/stem; exts=['csv', 'json', 'pdf', 'rds', 'txt', 'yml'] |
| **OK** | s3→s4 | `dexseq_results` | `dexseq_results` ⚠not-a-param | resolves |

#### `rnaseq_epigenomic_integration_fluent`
| verdict | conn (from→to) | from_output | to_input | note |
|---|---|---|---|---|
| **BROKEN** | s1→s3 | `de_genes_bed` | `gene_regions` ⚠not-a-param | 'de_genes_bed' not substring of any output name/stem; exts=['bai', 'bam', 'bigwig', 'csv', 'fq', 'gz', 'html', 'json', 'png', 'sf', 'tsv', 'txt'] |
| **UNCERTAIN** | s2→s3 | `atac_peaks_bed` | `peak_regions` ⚠not-a-param | upstream .nf not resolved/found |
| **BROKEN** | s3→s4 | `peak_gene_pairs` | `observed` ⚠not-a-param | 'peak_gene_pairs' not substring of any output name/stem; exts=['csv', 'pdf', 'rds', 'yml'] |

#### `rnaseq_to_lincs_moa`
| verdict | conn (from→to) | from_output | to_input | note |
|---|---|---|---|---|
| **OK** | s1→s2 | `counts_matrix` | `counts` ⚠not-a-param | resolves |
| **BROKEN** | s2→s3 | `top_up_genes` | `up_genes` | 'top_up_genes' not substring of any output name/stem; exts=['csv', 'html', 'json', 'pdf', 'rds', 'txt', 'yml'] |
| **BROKEN** | s2→s3 | `top_down_genes` | `down_genes` | 'top_down_genes' not substring of any output name/stem; exts=['csv', 'html', 'json', 'pdf', 'rds', 'txt', 'yml'] |

#### `scrna_adt_multimodal_via_scrapper`
| verdict | conn (from→to) | from_output | to_input | note |
|---|---|---|---|---|
| **UNCERTAIN** | s1→s2 | `sce_or_h5ad` | `sce.s` ⚠not-a-param | upstream .nf declares no parseable output files (stub) |

#### `scrna_consensus_de_bioc`
| verdict | conn (from→to) | from_output | to_input | note |
|---|---|---|---|---|
| **UNCERTAIN** | s1→s2 | `sce_or_h5ad` | `sce` ⚠not-a-param | upstream .nf declares no parseable output files (stub) |
| **BROKEN** | s2→s3 | `normalized_sce` | `sce` ⚠not-a-param | 'normalized_sce' not substring of any output name/stem; exts=['csv', 'json', 'pdf', 'rds', 'txt', 'yml'] |
| **BROKEN** | s2→s4 | `normalized_sce` | `sce` ⚠not-a-param | 'normalized_sce' not substring of any output name/stem; exts=['csv', 'json', 'pdf', 'rds', 'txt', 'yml'] |

#### `scrna_pseudobulk_de_bioc`
| verdict | conn (from→to) | from_output | to_input | note |
|---|---|---|---|---|
| **UNCERTAIN** | s1→s2 | `sce_or_h5ad` | `sce` ⚠not-a-param | upstream .nf declares no parseable output files (stub) |
| **BROKEN** | s2→s3 | `qc_sce` | `sce` ⚠not-a-param | 'qc_sce' not substring of any output name/stem; exts=['csv', 'json', 'pdf', 'rds', 'txt', 'yml'] |
| **BROKEN** | s3→s4 | `normalised_sce` | `sce` ⚠not-a-param | 'normalised_sce' not substring of any output name/stem; exts=['csv', 'json', 'pdf', 'rds', 'txt', 'yml'] |
| **BROKEN** | s4→s5 | `clustered_sce` | `sce` ⚠not-a-param | 'clustered_sce' not substring of any output name/stem; exts=['csv', 'json', 'pdf', 'rds', 'txt', 'yml'] |
| **BROKEN** | s4→s6 | `clustered_sce` | `sce` ⚠not-a-param | 'clustered_sce' not substring of any output name/stem; exts=['csv', 'json', 'pdf', 'rds', 'txt', 'yml'] |
| **BROKEN** | s5→s7 | `markers` | `markers` ⚠not-a-param | 'markers' not substring of any output name/stem; exts=['csv', 'json', 'pdf', 'rds', 'txt', 'yml'] |
| **BROKEN** | s6→s7 | `annotated_sce` | `sce` ⚠not-a-param | 'annotated_sce' not substring of any output name/stem; exts=['csv', 'pdf', 'rds', 'yml'] |

#### `shotgun_metagenomics_to_mag`
| verdict | conn (from→to) | from_output | to_input | note |
|---|---|---|---|---|
| **UNCERTAIN** | s1→s2 | `bins` | `contigs` | upstream .nf not resolved/found |
| **UNCERTAIN** | s2→s3 | `taxonomy_table` | `taxa_abundance` ⚠not-a-param | upstream .nf not resolved/found |

#### `single_cell_multimodal_analysis`
| verdict | conn (from→to) | from_output | to_input | note |
|---|---|---|---|---|
| **UNCERTAIN** | s1→s2 | `h5ad_filtered` | `h5ad` ⚠not-a-param | upstream .nf not resolved/found |
| **FALLBACK** | s2→s3 | `h5ad_integrated` | `h5ad` ⚠not-a-param | ext-in-name heuristic |
| **BROKEN** | s3→s4 | `h5ad_annotated` | `h5ad` ⚠not-a-param | 'h5ad_annotated' not substring of any output name/stem; exts=['json', 'txt', 'yml'] |
| **BROKEN** | s3→s5 | `h5ad_annotated` | `h5ad` | 'h5ad_annotated' not substring of any output name/stem; exts=['json', 'txt', 'yml'] |

#### `small_rna_piRNA_seqpac_analysis`
| verdict | conn (from→to) | from_output | to_input | note |
|---|---|---|---|---|
| **UNCERTAIN** | s1→s2 | `seq_table` | `seq_table` | upstream .nf not resolved/found |
| **UNCERTAIN** | s2→s3 | `annotated_seqs` | `annotated` | upstream .nf not resolved/found |

#### `target_to_lead_full`
| verdict | conn (from→to) | from_output | to_input | note |
|---|---|---|---|---|
| **UNCERTAIN** | s1→s4 | `pocket_json` | `pocket_coords` | upstream .nf not resolved/found |
| **FALLBACK** | s2→s3 | `filtered_smiles` | `smiles` ⚠not-a-param | ext-in-name heuristic |
| **BROKEN** | s3→s4 | `passed_compounds` | `ligand_sdf` | 'passed_compounds' not substring of any output name/stem; exts=['json', 'txt', 'yml'] |
| **UNCERTAIN** | s4→s5 | `vina_poses` | `docked_poses` ⚠not-a-param | upstream .nf not resolved/found |
| **BROKEN** | s5→s6 | `mmgbsa_scores` | `seed_smiles` | 'mmgbsa_scores' not substring of any output name/stem; exts=['csv', 'edr', 'gro', 'json', 'mol2', 'pdb', 'png', 'sdf', 'xtc'] |

#### `target_tractability_assessment`
| verdict | conn (from→to) | from_output | to_input | note |
|---|---|---|---|---|
| **UNCERTAIN** | s1→s2 | `scored_targets` | `candidate_targets` ⚠not-a-param | upstream .nf not resolved/found |

#### `time_series_de_with_edge`
| verdict | conn (from→to) | from_output | to_input | note |
|---|---|---|---|---|
| **OK** | s1→s2 | `counts_matrix` | `kidexpr_or_endoexpr` ⚠not-a-param | resolves |

#### `variant_burden_after_sarek`
| verdict | conn (from→to) | from_output | to_input | note |
|---|---|---|---|---|
| **OK** | s1→s2 | `vcf` | `vcf` ⚠not-a-param | resolves |
| **BROKEN** | s2→s3 | `gds` | `gds` ⚠not-a-param | 'gds' not substring of any output name/stem; exts=['csv', 'pdf', 'rds', 'yml'] |

#### `visium_voyager_to_isee`
| verdict | conn (from→to) | from_output | to_input | note |
|---|---|---|---|---|
| **FALLBACK** | s1→s2 | `sfe_with_multispati.rds` | `sce_rds` ⚠not-a-param | ext-in-name heuristic |
<!-- TABLE END -->

---

## 5. Root-cause synthesis

The breakage is **systemic, not incidental**: chain `connections` were authored with *semantic* logical output names (a data-contract style — `de_results`, `normalized_sce`, `cluster_assignments`, `effect_sizes_and_se`), but the runtime resolver only does **filename substring / extension matching** against whatever the `.nf` actually writes, with **no fallback when connections are present**. Wherever the semantic label and the real filename diverge, the handoff is silently dropped.

Two durable fixes (either closes the whole class — see `CLAUDE.md` "Resolve Root Causes"):

1. **Make the labels match the files** (data-only, lowest risk): normalize every `connections[].from_output` in `workflow_chains` to a token guaranteed to be a substring of the upstream's published filename (or a `_PARAM_TO_EXT` logical key). The Tier-1/2/3 tables above give the exact renames.
2. **Give the resolver a declared contract** (code): have each `.nf` publish a small `outputs.json` (logical-name → filename) and have `pick_artifact_file` consult it before falling back to substring matching — so chains can keep semantic names. Pair with un-gating the `_EXT_TO_PARAM` fallback so it also runs for connection-based chains.

Design-gap chains (Tier 4) need the upstream wrapper changed to actually emit the artifact (persist the SCE/RSE `.rds`, export the `.gds`, emit a filtered-compounds file), independent of either fix above.
