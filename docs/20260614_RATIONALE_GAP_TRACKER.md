# Rationale gap tracker — chains needing fresh DOI collection

Date: 2026-06-14
Branch: `bioc/v2-qc-audit-panel`
Drives: docs/20260614_EVIDENCE_RATIONALE_DATA_PLAN.md §"Concrete next deliverables" item (4).

## What this is

Sign-off checklist for the 14 chains whose domain has **zero** cited gates
in `backend/config/qc_evidence.yaml`. Scientific lead per domain collects
a DOI for each phase, adds the new gate to `qc_evidence.yaml`, then flips
the row in `backend/config/rationale_mapping.yaml` from
`needs_doi_collection: true` to `confirmed: true` with the gate name set.

Bioc chains (transcriptomics, single_cell, epigenomics, cryo_em) are NOT
in this tracker — those 24 rationales were populated in week-1.

Drug discovery and pharmacology chains are not here either — those are in
`rationale_mapping.yaml` as `category: mapping` and need a **gate pick**
(DOIs already exist in qc_evidence), not new DOI collection.

## Coverage summary

| domain | chains | phases needing DOIs | scientific lead | target sign-off |
|---|---|---|---|---|
| genomics | 5 | 14 | _(pending)_ | _(pending)_ |
| immunology | 1 | 4 | _(pending)_ | _(pending)_ |
| metabolomics | 1 | 3 | _(pending)_ | _(pending)_ |
| metagenomics | 1 | 3 | _(pending)_ | _(pending)_ |
| proteomics | 1 | 2 | _(pending)_ | _(pending)_ |
| rare_disease | 1 | 5 | _(pending)_ | _(pending)_ |
| variant_calling | 4 | 13 | _(pending)_ | _(pending)_ |

## Per-chain checklist

### genomics

#### `bioc_variant_annotation_v2` (chain_id 51)

| phase | step role | step workflow | DOI / source link | added to qc_evidence | confirmed |
|---|---|---|---|---|---|
| `A` | `import_annotate_vcf` | BIOC_VARIANTANNOTATION | _(pending)_ | ☐ | ☐ |
| `B` | `gene_set_enrichment` | BIOC_CLUSTERPROFILER | _(pending)_ | ☐ | ☐ |

#### `genome_coordinate_liftover` (chain_id 25)

| phase | step role | step workflow | DOI / source link | added to qc_evidence | confirmed |
|---|---|---|---|---|---|
| `A` | `load_chain_file` | BIOC_rtracklayer | _(pending)_ | ☐ | ☐ |
| `B` | `liftover_ranges` | BIOC_rtracklayer | _(pending)_ | ☐ | ☐ |
| `C` | `validate_and_report_failures` | BIOC_GenomicRanges | _(pending)_ | ☐ | ☐ |

#### `meta_analysis_with_bacon` (chain_id 31)

| phase | step role | step workflow | DOI / source link | added to qc_evidence | confirmed |
|---|---|---|---|---|---|
| `A` | `per_cohort_quantification` | nf-core/rnaseq | _(pending)_ | ☐ | ☐ |
| `B` | `per_cohort_de` | deseq2_multi_factor_analysis | _(pending)_ | ☐ | ☐ |
| `C` | `cross_cohort_meta_analysis` | bacon_multiple_sets_and_meta_analysis | _(pending)_ | ☐ | ☐ |

#### `phylogenetic_uncertainty_via_phykit` (chain_id 32)

| phase | step role | step workflow | DOI / source link | added to qc_evidence | confirmed |
|---|---|---|---|---|---|
| `A` | `alignment_and_phylogeny` | Analyze Protein Phylogeny | _(pending)_ | ☐ | ☐ |
| `B` | `per_gene_uncertainty_metrics` | PhyKIT Phylogenetic Metrics | _(pending)_ | ☐ | ☐ |

#### `rnaseq_epigenomic_integration_fluent` (chain_id 23)

| phase | step role | step workflow | DOI / source link | added to qc_evidence | confirmed |
|---|---|---|---|---|---|
| `A` | `rnaseq_quantification` | nf-core/rnaseq | _(pending)_ | ☐ | ☐ |
| `B` | `atac_peak_calling` | nf-core/atacseq | _(pending)_ | ☐ | ☐ |
| `C` | `associate_peaks_to_genes` | plyranges | _(pending)_ | ☐ | ☐ |
| `D` | `null_distribution_overlap` | nullranges | _(pending)_ | ☐ | ☐ |

### immunology

#### `cytof_mass_cytometry_analysis` (chain_id 19)

| phase | step role | step workflow | DOI / source link | added to qc_evidence | confirmed |
|---|---|---|---|---|---|
| `A` | `ingest_fcs_arcsinh` | catalyst | _(pending)_ | ☐ | ☐ |
| `B` | `som_metaclustering` | FlowSOM | _(pending)_ | ☐ | ☐ |
| `C` | `differential_abundance_DA` | diffcyt | _(pending)_ | ☐ | ☐ |
| `D` | `differential_state_DS` | diffcyt | _(pending)_ | ☐ | ☐ |

### metabolomics

#### `lcms_metabolomics_consensus` (chain_id 37)

| phase | step role | step workflow | DOI / source link | added to qc_evidence | confirmed |
|---|---|---|---|---|---|
| `A` | `peak_picking_and_alignment` | xcms | _(pending)_ | ☐ | ☐ |
| `B` | `isotope_adduct_annotation` | camera | _(pending)_ | ☐ | ☐ |
| `C` | `feature_selection_consensus` | biosigner | _(pending)_ | ☐ | ☐ |

### metagenomics

#### `shotgun_metagenomics_to_mag` (chain_id 43)

| phase | step role | step workflow | DOI / source link | added to qc_evidence | confirmed |
|---|---|---|---|---|---|
| `A` | `contig_binning` | Fasta Binning Concoct | _(pending)_ | ☐ | ☐ |
| `B` | `taxonomy_assignment` | Mmseqs Contig Taxonomy | _(pending)_ | ☐ | ☐ |
| `C` | `statistical_microbiome_analysis` | PathoStat | _(pending)_ | ☐ | ☐ |

### proteomics

#### `bioc_proteomics_de_v2` (chain_id 53)

| phase | step role | step workflow | DOI / source link | added to qc_evidence | confirmed |
|---|---|---|---|---|---|
| `A` | `load_quantify` | BIOC_MSNBASE | _(pending)_ | ☐ | ☐ |
| `B` | `differential_expression` | BIOC_LIMMA | _(pending)_ | ☐ | ☐ |

### rare_disease

#### `rare_disease_multimodal_workup` (chain_id 1)

| phase | step role | step workflow | DOI / source link | added to qc_evidence | confirmed |
|---|---|---|---|---|---|
| `A` | `germline_variant_calling` | nf-core/sarek | _(pending)_ | ☐ | ☐ |
| `B` | `variant_annotation` | nf-core/vcf_annotate_ensemblvep | _(pending)_ | ☐ | ☐ |
| `C` | `rna_alignment_quantification` | nf-core/rnaseq | _(pending)_ | ☐ | ☐ |
| `D` | `aberrant_expression_splicing` | nf-core/drop | _(pending)_ | ☐ | ☐ |
| `E` | `result_aggregation` | case_report_aggregation | _(pending)_ | ☐ | ☐ |

### variant_calling

#### `bioc_variant_annotation_workflow` (chain_id 28)

| phase | step role | step workflow | DOI / source link | added to qc_evidence | confirmed |
|---|---|---|---|---|---|
| `A` | `variant_calling` | nf-core/sarek | _(pending)_ | ☐ | ☐ |
| `B` | `annotate_with_txdb` | BIOC_VariantAnnotation | _(pending)_ | ☐ | ☐ |
| `C` | `filter_by_consequence_and_pop_freq` | variantfiltering | _(pending)_ | ☐ | ☐ |
| `D` | `tumor_summary_oncoplots` | BIOC_maftools | _(pending)_ | ☐ | ☐ |

#### `cnv_consensus_pipeline` (chain_id 36)

| phase | step role | step workflow | DOI / source link | added to qc_evidence | confirmed |
|---|---|---|---|---|---|
| `A` | `alignment_and_initial_calls` | nf-core/sarek | _(pending)_ | ☐ | ☐ |
| `B` | `cnv_segmentation` | cn_farms | _(pending)_ | ☐ | ☐ |
| `C` | `cnv_phenotype_association` | cnvranger | _(pending)_ | ☐ | ☐ |

#### `mutation_signature_pipeline` (chain_id 38)

| phase | step role | step workflow | DOI / source link | added to qc_evidence | confirmed |
|---|---|---|---|---|---|
| `A` | `somatic_variant_calling` | nf-core/sarek | _(pending)_ | ☐ | ☐ |
| `B` | `signature_extraction` | musicatk | _(pending)_ | ☐ | ☐ |
| `C` | `kataegis_detection` | katdetectr | _(pending)_ | ☐ | ☐ |

#### `variant_burden_after_sarek` (chain_id 40)

| phase | step role | step workflow | DOI / source link | added to qc_evidence | confirmed |
|---|---|---|---|---|---|
| `A` | `germline_variant_calling` | nf-core/sarek | _(pending)_ | ☐ | ☐ |
| `B` | `snp_array_container` | SeqArray | _(pending)_ | ☐ | ☐ |
| `C` | `burden_and_qc` | GWASTools | _(pending)_ | ☐ | ☐ |

---

## How a row gets closed

1. Scientific lead identifies the paper that grounds the chain step.
2. Add a new gate to `backend/config/qc_evidence.yaml` under the relevant
   domain block, with `paper_doi`, `paper_ref`, `paper_supports`, `rule_text`,
   `finding`, `provenance` (`GOLD`/`SILVER`/`BRONZE`) — same shape as the
   bioc additions made in Wave 1-2.
3. Update the matching row in `backend/config/rationale_mapping.yaml`:
   set `qc_gate_name: <new_gate>`, `confirmed: true`, `curated_by: <id>`.
4. Tick the checkboxes in this doc + commit both files together.
5. Populate script (run on the next deploy) picks up the new rows.

