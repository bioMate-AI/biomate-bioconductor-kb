# Deep Workflow Survey — Aims, I/O, Natural Patterns and Chains

**Date**: 2026-06-10
**User directive**: "look into our workflows in depth, regarding their aim, input and output, and survey for confirmation for any potential pattern and chains" — with the explicit correction that Bioconductor must NOT be excluded; "find other fields to interpret them."

## Headline

Bioconductor IS heavily connected — but the connections live in `annotation_v2`, not in `output_types`. The output stub (`["table/csv","plot/pdf","object/rds"]` repeats for 2,775 of 3,310 Bioc workflows) is an indexer artifact, NOT evidence of unchaineability. The real structure is in three richer fields and confirms massive natural chain coverage that's currently invisible to typed-port retrieval.

## The fields that actually carry signal for Bioc

The audit catalogued only `input_types`, `output_types`, `domain`, `description`. Three more fields turn out to be the real chain-discovery substrate:

| Field | Coverage (of 3,310 Bioc) | What it provides |
|---|---|---|
| `annotation_v2.when_to_use` | 2,682 (81%) | Semantic input description: *"appropriate when analyzing un-normalized integer count data from RNA-seq…"* — maps directly to canonical type kinds |
| `annotation_v2.alternatives` | 2,269 (69%) | **Substitution graph**: which other Bioc tools fit the same slot. e.g. DESeq2 names edgeR, limma, DSS, EBSeq, baySeq, IHW as alternatives |
| `annotation_v2.key_parameters` | 2,608 (79%) | What parameters mean — useful for inferring intent |
| `annotation_v2.pitfalls` | 2,608 (79%) | What to avoid — useful for verifier and prompt context |

The `input_types` field for Bioc DOES carry signal too, but as freeform prose: `"counts.tsv (matrix of raw integer counts)"`. Token extraction (`counts`, `vcf`, `bam`, `expression matrix`, `gene list`, etc.) recovers usable type cues.

## Finding 1: 4 type-canonical cross-source bridges with massive scale

Cross-source = non-Bioc workflow producing a type that 100+ Bioc workflows consume. Computed by parsing Bioc `when_to_use` for canonical input phrases, then matching against non-Bioc `output_types`.

| Bridge type | Non-Bioc producers | Bioc consumers | Example producers |
|---|---|---|---|
| **`counts_matrix`** | 14 | **170** | `nf-core/rnaseq`, `nf-core/quantify_pseudo_alignment`, `nf-core/circrna` |
| **`expression_matrix`** | 11 | **283** | `nf-core/circrna`, `nf-core/denovotranscript`, `nf-core/drop` |
| **`scrna` (h5ad / SingleCellExperiment)** | 4 | **388** | `nf-core/scrnaseq`, `nf-core/h5ad_removebackground_*` |
| **`variants_vcf`** | 26 | **132** | `nf-core/sarek`, `nf-core/bam_tumor_normal_somatic`, `nf-core/bam_create_som_pon_gatk` |

**Total: 55 cross-source producer workflows can naturally feed 973 Bioc consumer workflows.** None of these chains are currently in `workflow_chains` (now 34) as explicit edges; they exist only as latent potential because Bioc's `output_types` was stubbed.

This is the user's "connect specialties" vision quantified: nfcore + biomate + biomni_nextflow have ~55 typed-output producers; Bioc has ~970 typed-input consumers. The 29 → 34 curated chains barely scratch this surface.

## Finding 2: 241 natural alternative-substitution clusters in Bioc

Computed from `annotation_v2.alternatives` by building a graph where A→B means A names B as alternative, then taking symmetric closure and connected components.

| Cluster size | Count | Interpretation |
|---|---|---|
| ≥ 50 | 1 (size 520) | mega-cluster of "differential-something" tools (DE + DA combined; too broad to be one consensus chain) |
| 10–49 | 11 | actionable consensus clusters per topic |
| 3–9 | 229 | finer-grained substitution groups |

Notable mid-size clusters and their canonical role:

| Cluster topic | Size | Representative members | Natural chain type |
|---|---|---|---|
| LC-MS metabolomics differential | 43 | `biosigner`, `camera`, `camera_isotope_*`, `clumsid` | `multi_method_consensus` for metabolomics |
| GWAS hierarchical | 25 | `genegeneinter`, `hiergwas`, `hierinf`, `pharmacogx`, `GWASTools` | `multi_method_consensus` for GWAS |
| aCGH / copy number | 19 | `adacgh2`, `biohmm`, `cghseg`, `cn_farms`, `crlmm` | `multi_method_consensus` for CNV |
| GWAS bayesian | 16 | `bg2`, `gbscleanr`, `gwastools`, `relatedness`, `saigegds` | `multi_method_consensus` for GWAS (Bayesian) |
| Heatmap / circular viz | 16 | `circlize`, `complexheatmap`, `gcrisprtools`, `gmoviz` | `ensemble_annotation` (visualization variants) |
| Motif analysis | 15 | `daglogo`, `icelogo`, `motifcounter`, `motifdb`, `motifstack` | `multi_method_consensus` for motif calling |
| CNV from sequencing | 14 | `cnvkit`, `cnvranger`, `cnvranger_cnv_expression_eqtl` | `multi_method_consensus` for CNV from BAM/VCF |
| Flow cytometry | 13 | `depecher`, `flowcore`, `flowspecs`, `flowstats` | `sequential_omics_pipeline` (flow-cyto specific) |
| Mutation signatures | 13 | `clusteredmutations`, `kataegis`, `katdetectr`, `maftools`, `musicatk` | `multi_method_consensus` for signature extraction |
| Motif enrichment | 12 | `ame`, `monalisa`, `ismara` | `multi_method_consensus` for motif enrichment |
| Microarray QC | 11 | `affyplm`, `arraymvout`, `arrayqualitymetrics` | `branching_on_qc` (QC then conditional analysis) |

Each cluster ≥ 10 is a candidate for ONE new curated chain that consumes upstream nfcore-typed output and produces a consensus result via the cluster members. That's 11 new chains directly justified by the data.

## Finding 3: Internal Bioc ladders (output role → input role)

Beyond pairwise substitution, Bioc workflows form natural sequential ladders inferred from `when_to_use` text:

| Common ladder | Example producers | Example consumers |
|---|---|---|
| normalization_factors → de_table | `affyplm` (microarray normalization) | `absseq`, `adverscarial` (DE callers) |
| de_table → enrichment_results | `aldex2`, `ancombc` (DE callers) | clusterProfiler family, enrichGO, ReactomePA |
| de_table → visualizations | (any DE caller) | `EnhancedVolcano`, `complexheatmap` |
| clusters_or_modules → de_table | scRNA clustering (`SingleR`, `Seurat`) | differential abundance within clusters |
| variants → gene_burden | sarek-emitted VCFs | `SKAT`, `seqArray` |

The naive A→B count over Bioc is noisy (the cross-product produces 600k+ candidate pairs) but the **inferred ladders match the canonical workflow grammar** Bioc users actually follow. The signal is there; it just needs a typed manifest contract (not stub outputs) to be useful at retrieval time.

## Finding 4: Per-cluster, what does the live curated catalog already cover?

Of the 11 mid-size alternative clusters (10–49 members), zero are referenced by name in any curated chain. Even `BIOC_DESeq2` and `BIOC_limma` (which we DO have in curated chains via the placeholder grounding) are members of the broader DE mega-cluster but no curated chain expresses them as one of N consensus alternatives — they're treated as single-method picks.

In other words: **the curated catalog uses Bioc tools as building blocks but never as substitutable alternatives within a consensus shape.** Every `multi_method_consensus` opportunity for these clusters is currently latent.

## Finding 5: Hub workflows from the type-flow graph (non-Bioc subset)

For workflows with real typed I/O (the 310 non-Bioc + 3 Bioc that have non-stub outputs):

**Top producers by out-degree** (= how many downstream workflows can consume them):

| Out-deg | Workflow | Source / Domain |
|---|---|---|
| 121 | nf-core/viralmetagenome | nfcore / genomics |
| 120 | nf-core/genomeqc, nf-core/pairgenomealign | nfcore / genomics |
| 103 | scfv_antibody_design | nextflow / drug_discovery |
| 101 | cart_construct_design | biomate / drug_discovery |
| 94 | Fasta Binning Concoct | nfcore_subwf / metagenomics |
| 82 | Fasta Index Bismark Bwameth, Fasta Index Methylseq | nfcore_subwf / genomics |
| 81 | Fasta Hmmsearch Rank Fastas | nfcore_subwf / genomics |
| 81 | P0 Mrna Validation | biomni_nextflow / drug_discovery |

**Top consumers by in-degree** (= how many upstream workflows can feed them):

| In-deg | Workflow | Source / Domain |
|---|---|---|
| 103 | nf-core/bam_variant_calling_sort_freebayes_bcftools | nfcore / variant_calling |
| 88 | Tiff Segmentation Vpt, nf-core/quantify_pseudo_alignment | nfcore_subwf / imaging, transcriptomics |
| 85 | nf-core/tiff_segmentation_vpt | nfcore / imaging |
| 84 | (group) `pbpk_simulation`, `clinical_trial_simulation`, `allometric_scaling`, `nlmixr2_population_pk`, `metabolite_prediction_biotransformer`, `pharmacogenomics_pgx_report`, `target_tractability_scorer`, `antibody_developability`, `hts_plate_qc_hit_calling`, `exposure_response_modelling` | nextflow / pharmacology + drug_discovery |

The pharmacology cluster all hits exactly 84 in-degree because they accept the same generic types (csv, json). This is a strong "common consumer slot" — a single upstream workflow could feed any of them; chains differ only in which is selected.

## Finding 6: Cross-source flow is concentrated

For the non-stub subset (310 workflows × 6,077 edges):

| Source pair | Edges |
|---|---|
| nfcore → nfcore_subwf | 849 |
| nfcore_subwf → nfcore | 657 |
| nextflow → nfcore | 515 |
| biomate → nextflow | 435 |
| biomate → nfcore | 269 |
| biomni_nextflow → nextflow | 247 |
| biomni_nextflow → nfcore | 163 |

**`biomate` produces typed outputs that feed `nfcore` in 269 edges, and `nextflow` in 435 edges. `biomni_nextflow` produces typed outputs that feed `nextflow` in 247 edges and `nfcore` in 163.** These are real upstream → downstream chain patterns living in the catalog right now, but none are explicitly curated as chains.

## Finding 7: Domain-transition motifs from the type-flow graph

Across all 6,077 cross-source typed edges, the top 5 domain transitions are:

| Source domain → Target domain | Edges | Representative pair |
|---|---|---|
| genomics → transcriptomics | 572 | `nf-core/fastq_align_chromap` (bam) → `nf-core/bam_stringtie_merge` |
| drug_discovery → pharmacology | 528 | `Nca Pknca` (csv) → `exposure_response_modeling` |
| genomics → variant_calling | 315 | `nf-core/fastq_align_chromap` (bam) → `nf-core/sarek` |
| drug_discovery → transcriptomics | 228 | `Nca Pknca` (csv) → `nf-core/quantify_pseudo_alignment` |
| transcriptomics → genomics | 224 | `nf-core/rnaseq` (bam) → `nf-core/bam_sort_stats_samtools` |

The `drug_discovery → pharmacology` edge (528) is striking because that bridge has very few curated chains — most go directly drug_discovery → drug_discovery.

## Implications

### What this confirms about the user's "connect specialties" vision

1. **Cross-source typed bridges exist for 55 producers + 970 Bioc consumers** = ~973 potential chain end-points already aligned by data type. Today curated chains cover 16 of these workflows. The other 950+ are latent.
2. **241 multi-method-consensus clusters in Bioc** are documented by the `alternatives` field. None of them yet appear as consensus chains in the curated catalog.
3. **Domain-transition motifs are observable** in 100s of edges per domain pair. Curated chains span only 3 verified cross-domain pairs (per the co-occurrence analysis) — 99% of the latent cross-domain coverage is unexplored.

### What's blocking automated chain extraction

- **Bioc `output_types` stub.** This single indexer fingerprint defeats type-flow graph extraction on 82% of the catalog. Re-extracting outputs from the per-package `process output` block (or even just enriching with a single canonical output kind from the package's documented role) would unblock the same analysis that worked on the 310 non-Bioc workflows.
- **The 241 alternative clusters are not currently surfaced anywhere.** The composer's pattern_evidence module uses `description + annotation + tools_used` for BM25 retrieval but not `annotation_v2.alternatives` — so it never sees "these 12 workflows do the same job by their own admission." Adding alternatives to the retrieval doc would unlock per-pattern coverage.

### What can be done immediately (no code changes)

1. **Author curated chains for the 11 mid-size alternative clusters.** Pattern: `multi_method_consensus_<topic>` (LC-MS DE, GWAS hierarchical, CNV, mutation signatures, motif enrichment, etc.). Each chain references the cluster members as substitutable alternatives within `multi_method_consensus` shape.
2. **Author 4 cross-source bridge chains** that codify the dominant patterns:
   - `nf-core/rnaseq → consensus_bioc_de → bioc_enrichment` (anchored on `counts_matrix`)
   - `nf-core/scrnaseq → consensus_bioc_sc_de → bioc_sc_annotation` (anchored on `scrna`)
   - `nf-core/sarek → bioc_variant_burden → bioc_pathway` (anchored on `variants_vcf`)
   - `nf-core/rnaseq → drug_response_with_pharmacogx` (cross-domain transcriptomics → drug_discovery)

### What requires modest code changes

3. **Surface `annotation_v2.alternatives` in `pattern_evidence.py`'s retrieval text.** One field append; massively improves per-pattern catalog coverage.
4. **Bioc output canonical-kind backfill** via LLM-judge over `when_to_use`. The same Haiku-tier approach we used for domain reclassification can extract one canonical output type per package. ~$3, ~1 hour. Output: real `output_types` for 2,775 workflows. Unblocks type-flow graph analysis on the entire Bioc subspace.

### What the user said and what the data confirms

> *"the bioconductor is important to connect with other workflows, find other fields to interpret them."*

The data confirms exactly this: Bioc is the most-connected subset, but its connections are invisible to type-flow analysis because the `output_types` field was stubbed. The `annotation_v2.*` fields contain the connection signal directly. Three findings of practical scale (170 / 283 / 388 Bioc consumers of nfcore producer types) make this concrete.

## Open questions for next session

1. **Should `annotation_v2.alternatives` drive multi-method-consensus chain authoring automatically?** A script could enumerate the 11 mid-size clusters, propose a `consensus_<topic>` chain per cluster, and apply with the same simulator+verifier workflow. Output: ~11 new curated chains in addition to the 5 already proposed.
2. **Bioc `output_types` re-extraction**: how to do it cleanly? Options:
   - (a) LLM-judge over `when_to_use` text to assign one canonical output kind (~$3-5)
   - (b) Per-package handwritten lookup (slow, accurate)
   - (c) Re-parse from `workflow_json_v2` if it has the actual process output block
3. **Type vocabulary canonicalization**. The catalog has 5,576 unique `input_types` but only ~50 are canonical short types. The other 5,500+ are freeform descriptions like *"counts.tsv (matrix of raw integer counts)"*. A vocabulary mapping pass would let typed retrieval work uniformly.

## Status

Survey complete. No code changes in this analysis. Findings recorded for review and to inform next-session chain-authoring decisions.
