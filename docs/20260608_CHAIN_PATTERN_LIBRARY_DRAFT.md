# Chain Pattern Library — Draft v1

**Purpose**: A small catalog (~10–12 entries) of canonical chain shapes the LLM is *taught about* via retrieval, not *picks from* via enum. Each entry is a knowledge document. The LLM reads relevant patterns at composition time as scaffolding and may still emit off-pattern shapes when the question warrants.

**Companion doc**: `docs/20260608_CHAIN_GENERATION_DESIGN.md` — three-layer composition + confidence-driven surfacing.

**Format per entry**:
- **Name** — canonical identifier (`snake_case`)
- **When** — triggering signals in user query
- **Shape** — ASCII DAG
- **Real instantiations** — two from our 3,094-workflow catalog
- **Pitfall** — one common failure mode to avoid
- **Reference** — published methodology

---

## 1. `sequential_omics_pipeline`

**When**: Single modality, raw data → final result, no fork-in-the-road decisions. Most common shape. Triggered by "do X analysis on Y data" with a clear endpoint, single-modality work. Covers bulk RNA-seq alone, WGBS / methylation, miRNA-seq, proteomics alone, metabolomics alone — anything that is one modality from raw input to interpreted result. Distinguished from `multi_omics_integration` by the **absence** of integration / joint / combined / cross-modality language in the query, and from `branching_on_qc` by the absence of conditional / if-then language.

**Shape**:
```
[ingest/QC] → [primary_processing] → [analysis] → [interpretation/report]
```

**Instantiations**:
- `nf-core/rnaseq` → `nf-core/differentialabundance` → `clusterProfiler` (enrichment) — bulk RNA-seq DE
- `nf-core/sarek` → `vep_annotation` → `variant_filter_report` — germline variant calling

**Pitfall**: Treating the user's question as a sequential pipeline when it's actually multi-modal or consensus. Listen for plurals: "results from RNA-seq *and* proteomics" is not sequential.

**Reference**: Conesa et al. 2016, *A survey of best practices for RNA-seq data analysis*, Genome Biology 17:13.

---

## 2. `multi_omics_integration`

**When**: User mentions ≥2 modalities (RNA + ATAC, RNA + proteomics, RNA + methylation, CITE-seq, multi-modal scRNA). Goal is a *joint* model, not parallel single-omics reports.

**Shape**:
```
[RNA pipeline] ─┐
[ATAC pipeline] ─┼─→ [integration step] → [joint factors / shared embedding] → [interpretation]
[Meth pipeline] ─┘
```

**Instantiations**:
- `nf-core/rnaseq` + `nf-core/atacseq` → `MOFA+` (joint factor model) — multi-omics from bulk
- `nf-core/scrnaseq` + ADT counts → `Signac`/`MultiVI` → `Seurat` multimodal — CITE-seq

**Pitfall**: Running each modality's full pipeline independently and gluing the *interpretations* together (post-hoc overlap analysis). That's not integration — that's parallel single-omics with a Venn diagram. True integration shares a latent space.

**Reference**: Argelaguet et al. 2020, *MOFA+: a statistical framework for comprehensive integration of multi-modal single-cell data*, [Genome Biology 21:111](https://link.springer.com/article/10.1186/s13059-020-02015-1). See also Argelaguet et al. 2020, *Computational principles and challenges in single-cell data integration*, [Nature Methods 18:8](https://www.nature.com/articles/s41592-019-0692-4).

---

## 3. `multi_method_consensus`

**When**: User asks for a *robust* / *defensible* / *publication-quality* result on a contested step (most often differential expression or variant calling). Multiple methods exist, each with known biases.

**Shape**:
```
                   ┌→ [method A] → results_A ─┐
[shared input] ────┼→ [method B] → results_B ─┼→ [consensus aggregator] → intersected/scored result
                   └→ [method C] → results_C ─┘
```

**Instantiations**:
- Counts matrix → `DESeq2` ∥ `edgeR` ∥ `limma-voom` → intersection / FDR-aggregated DE list
- Aligned BAM → `GATK HaplotypeCaller` ∥ `Strelka2` ∥ `DeepVariant` → vote-based variant set

**Pitfall**: Treating disagreement between methods as noise to be averaged away. The disagreements *are signal* — a gene called by 3/3 methods is a different claim than one called by 1/3. Preserve method provenance in the aggregator.

**Reference**: Soneson & Delorenzi 2013, *A comparison of methods for differential expression analysis of RNA-seq data*, BMC Bioinformatics 14:91. Schurch et al. 2016, *How many biological replicates are needed in an RNA-seq experiment?*, RNA 22:839.

---

## 4. `ensemble_annotation`

**When**: User has a result list (genes, variants, peaks) and wants it *characterized* against multiple knowledge bases. Each annotator runs independently; outputs are consolidated for the user.

**Shape**:
```
                       ┌→ [GO] ─────────────┐
[gene/variant list] ───┼→ [KEGG] ───────────┼→ [consolidator/dashboard]
                       ├→ [Reactome] ───────┤
                       └→ [DisGeNET] ───────┘
```

**Instantiations**:
- DE gene list → `clusterProfiler::enrichGO` + `enrichKEGG` + `ReactomePA` → unified enrichment plot
- VCF → `VEP` + `SnpEff` + `ClinVar lookup` + `ACMG classifier` → variant report

**Pitfall**: Multiple-testing correction *across* annotators is easy to forget. If you run 4 enrichers each at FDR 0.05, your effective FDR is higher. Either correct globally or document the per-source FDR clearly.

**Reference**: Yu et al. 2012, *clusterProfiler: an R package for comparing biological themes among gene clusters*, OMICS 16:284. McLaren et al. 2016, *The Ensembl Variant Effect Predictor*, Genome Biology 17:122.

---

## 5. `iterative_refinement`

**When**: A step has a QC gate that, on fail, suggests parameter adjustment and re-execution. Bounded retry count. Drug-design and CryoEM are the canonical homes.

**Shape**:
```
[step] → [QC gate] ─pass→ [next step]
            │
            └─fail→ [param adjuster] → [step] (retry, ≤N times)
```

**Instantiations**:
- ADMET screen → hERG threshold check → fail → tighten logP filter → re-screen (already shipped in `admet_autoloop`)
- CryoEM particle pick → CTF resolution check → fail → adjust particle diameter → re-pick

**Pitfall**: Allowing the loop to mask genuine experimental issues. If the same gate fails 3+ times, the problem is upstream (bad data, wrong assay setup), not the parameters. Always raise to the user after the retry cap, never silently terminate.

**Reference**: Already implemented across ADMET / CYP-DDI / Docking / NCA-PK auto-loops; design echoed by GROMACS minimization protocols and RELION 3D classification stages.

**Comparison surface**: the auto-loop UI already shows the before/after parameter diff (red strikethrough → green new value) on the remediation card. This IS the user-facing "compare runs" view — `iterative_refinement` owns it, no separate comparison pattern needed.

---

## 6. `cross_cohort_replication`

**When**: User explicitly mentions multiple datasets, validation cohorts, or meta-analysis. Same DAG run independently per cohort, then results meta-analyzed.

**Shape**:
```
cohort_A → [pipeline] → result_A ─┐
cohort_B → [pipeline] → result_B ─┼→ [meta-analysis: METAL / RE2 / Fisher] → combined result
cohort_C → [pipeline] → result_C ─┘
```

**Instantiations**:
- TCGA + GTEx + ICGC RNA-seq each → DE per cohort → fixed-effect meta-analysis
- UK Biobank + FinnGen + BBJ GWAS → METAL fixed-effect meta-analysis

**Pitfall**: Combining batch-confounded cohorts without harmonization. If cohort A was Illumina HiSeq and cohort B was NovaSeq, run a per-cohort batch-correction before meta-analysis, not after.

**Reference**: Willer et al. 2010, *METAL: fast and efficient meta-analysis of genomewide association scans*, [Bioinformatics 26:2190](https://academic.oup.com/bioinformatics/article/26/17/2190/198154). Han & Eskin 2011, *Random-effects model aimed at discovering associations in meta-analysis of genome-wide association studies*, AJHG 88:586.

---

## 7. `discovery_then_validation`

**When**: User splits the question into exploratory and confirmatory phases — train/test or biomarker discovery / hold-out validation. Different inputs per phase; second phase is downstream of and dependent on the first.

**Shape**:
```
discovery_data → [feature_selection / model_training] → candidate_set ─┐
                                                                       ↓
validation_data ───────────────────────────────→ [confirmatory_test on candidates] → validated_result
```

**Instantiations**:
- Discovery RNA-seq → top 100 DEGs → qPCR validation on independent cohort
- Compound library docking → top 200 hits → in vitro binding assay on a focused set

**Pitfall**: Re-tuning on the validation set ("just one peek at the test set") — this collapses the experimental design into a one-shot discovery and inflates the effective false discovery rate. Either keep the validation set sealed, or treat the analysis as nested cross-validation and report accordingly.

**Reference**: Ransohoff 2004, *Bias as a threat to the validity of cancer molecular-marker research*, Nat Rev Cancer 5:142. Pesch et al. 2024, on hold-out leakage in ML for biology.

---

## 8. `branching_on_qc`

**When**: A QC outcome cleanly partitions the data into branches that need different downstream pipelines. Not a retry loop; the branches are alternative paths, not the same path retried. Triggered by "if X exceeds Y, switch to / use Z" or "when QC fails / passes, branch to". Conditional language: "if/else", "switch", "threshold", "depending on", "split into", "route to", "when X then Y", "case X / case Y". Common cases: **rRNA / ribosomal RNA contamination → switch to rRNA-depletion pipeline (ribosomal RNA contamination over a threshold percentage)**; library quality QC → branch by protocol; WGS vs WES coverage profile → different variant callers; ploidy / aneuploidy QC → different normalization. The rRNA-depletion branch is the textbook example: when rRNA contamination exceeds the threshold, the standard mRNA pipeline becomes inappropriate and an alternative rRNA-depletion or total-RNA pipeline must be substituted.

**Shape**:
```
[input] → [QC] ─IF rRNA% > 30% → [rRNA depletion pipeline]
              ─IF rRNA% ≤ 30% → [standard pipeline]
              ─IF degraded   → [3' tag-only pipeline]
```

**Instantiations**:
- scRNA-seq input → ambient-RNA QC → conditional `CellBender` denoising path vs. straight clustering
- Cryo-EM micrographs → CTF estimation → if astigmatism > threshold → aberration correction pipeline; else standard

**Pitfall**: Hard-coding the branch thresholds. They depend on tissue, instrument, library prep — exposing them as editable parameters in the chain card is mandatory; otherwise users silently get a wrong branch.

**Reference**: Lun et al. 2016, *A step-by-step workflow for low-level analysis of single-cell RNA-seq data with Bioconductor*, F1000Research 5:2122. Common pattern in `nf-core/sarek`'s conditional WES/WGS branching.

---

## 9. `hierarchical_re_evaluation`

**When**: Initial pass clusters data at a coarse level; user then wants to drill into one cluster and re-analyze it as if it were a fresh dataset. Common in single-cell atlasing, microbiome analysis, and any "cells of interest" follow-up.

**Shape**:
```
[all_data] → [initial clustering] → [annotation] →
        (pick cluster k) → [extract subset] → [re-cluster sub-pop] → [sub-annotation]
```

**Instantiations**:
- Whole-tissue scRNA → broad cell-type clustering → annotate T cells → re-cluster T-cell sub-pop → identify CD8 exhausted subset
- Microbiome 16S → genus-level community → focus on Bacteroidetes → strain-level re-cluster

**Pitfall**: Re-using the full-data UMAP / dim-red for the sub-clustering. The neighborhood structure is dominated by the *between*-population variation; you must recompute the embedding on the subset to see *within*-population structure.

**Reference**: Luecken & Theis 2019, *Current best practices in single-cell RNA-seq analysis: a tutorial*, Mol Syst Biol 15:e8746. Hao et al. 2021, *Integrated analysis of multimodal single-cell data*, Cell 184:3573 (Seurat v4).

---

## 10. `comparative_benchmarking` ⚠️ DEPRECATED FROM MAIN LIBRARY (2026-06-08)

**User decision**: the user-facing comparison concept is already covered by `iterative_refinement`'s before/after param diff (auto-loop remediation card). Method-vs-method bake-offs are a developer concern, not a user pattern. This entry is kept here for reference only — should be relocated to a developer-tier catalog or dropped before the library is wired into retrieval.

---

**When**: User explicitly wants to compare tool/method variants on the same data (method-evaluation studies, choosing a default for a lab). Different from consensus: the *output* is per-method performance metrics, not an aggregated result.

**Shape**:
```
[reference_data] ┬→ [method_A] → metrics_A ─┐
                 ├→ [method_B] → metrics_B ─┼→ [side-by-side report / ranking]
                 └→ [method_C] → metrics_C ─┘
```

**Instantiations**:
- Mixture-control scRNA → `Seurat` ∥ `Scanpy` ∥ `Harmony` ∥ `scVI` integration → ARI/silhouette scores per method
- Synthetic VCF → `GATK` ∥ `DeepVariant` ∥ `Strelka2` → precision/recall vs truth set

**Pitfall**: Cherry-picking the "best" method based on one metric on one dataset. Real benchmarks score multiple metrics across multiple data types (Tian 2019 used 14 datasets × 3,913 method combinations). Single-metric / single-dataset benchmarks are essentially anecdotes.

**Reference**: Tian et al. 2019, *Benchmarking single cell RNA-sequencing analysis pipelines using mixture control experiments*, [Nature Methods 16:479](https://www.nature.com/articles/s41592-019-0425-8). Luecken et al. 2022, *Benchmarking atlas-level data integration in single-cell genomics*, Nature Methods 19:41.

---

## 11. `filter_cascade`

**When**: User has a large candidate pool that must be narrowed by *successive* criteria, each enriching for a different property. Each step *filters* (removes), never produces new entities. Common in clinical genomics (variant prioritization) and drug screening.

**Shape**:
```
[large_pool] → [filter_1 by criterion_A] → [filter_2 by criterion_B] → [filter_3 by criterion_C] → [shortlist]
```

**Instantiations**:
- Whole-genome variants → frequency < 1% → predicted-damaging → in disease gene panel → segregates with phenotype → prioritized list
- 10⁶ compound library → drug-like (Lipinski Ro5) → docking score < −7 → ADMET pass → MD-stable → ranked leads

**Pitfall**: Order matters and is *not* commutative. Filtering by rare-frequency before damaging-prediction yields a different shortlist than reverse, because the predictors have rate-dependent biases. Document the canonical order per use case and surface it explicitly.

**Reference**: Richards et al. 2015, *Standards and guidelines for the interpretation of sequence variants (ACMG/AMP)*, Genet Med 17:405. Lipinski et al. 2001, *Experimental and computational approaches to estimate solubility and permeability*, Adv Drug Deliv Rev 46:3.

---

## 12. `resampling_uncertainty`

**When**: User wants confidence intervals or stability assessments around a point estimate that the primary method doesn't provide natively — bootstrap, subsampling, permutation. Often a *wrapper* around any of the patterns above.

**Shape**:
```
              ┌→ [resample 1] → [pipeline] → result_1 ─┐
[data] → [resample machinery] → [resample 2] → [pipeline] → result_2 ─┼→ [aggregate: CI / stability]
              └→ [resample N] → [pipeline] → result_N ─┘
```

**Instantiations**:
- DE: bootstrap 100× over samples → DESeq2 → per-gene stability score (which genes are robust to subsampling?)
- Phylogenetic tree: 1000 bootstrap pseudo-replicates → IQ-TREE → bootstrap-support values on branches

**Pitfall**: Resampling *within* a step that has internal normalization tied to library composition (e.g. DESeq2 size factors). Bootstrap with replacement perturbs the normalization, so per-bootstrap normalization must be re-estimated, not reused.

**Reference**: Efron & Tibshirani 1994, *An Introduction to the Bootstrap*. Felsenstein 1985, *Confidence limits on phylogenies: an approach using the bootstrap*, Evolution 39:783.

---

## 13. `time_series_longitudinal`

**When**: Same subjects (or same biological units — cells, organoids, animals) sampled at multiple timepoints. Distinct from `cross_cohort_replication` because of within-subject correlation that must propagate through every analysis step. Triggered by explicit time language: "0, 6, 24, 72 h", "day 0/7/14/28", "timecourse", "longitudinal", "perturbation followed over time", "developmental atlas", "circadian", "drug PK/PD time-course", "before/during/after treatment when measured repeatedly". Sample paired-end-analysis methods (mixed-effects models, time-aware DE).

**Shape**:
```
[t0 samples] → [pipeline] → result_t0 ─┐
[t1 samples] → [pipeline] → result_t1 ─┼─→ [time-aware joint model: mixed effects / splineTimeR / maSigPro] → temporal pattern report
[tN samples] → [pipeline] → result_tN ─┘
```

**Instantiations**:
- 0/6/24/72 h drug treatment RNA-seq → `nf-core/rnaseq` per timepoint → `maSigPro` for time-dependent DE
- Developmental scRNA-seq across E10.5 / E12.5 / E14.5 → per-timepoint `nf-core/scrnaseq` → `tradeSeq` for pseudotime-aware DE

**Pitfall**: Treating timepoints as independent groups (running pairwise DE between t1 vs t0, t2 vs t0, etc.) loses the trajectory structure. Worse, it inflates multiple-testing burden by ignoring the within-subject correlation. Use time-aware methods (`limma::duplicateCorrelation` for repeated measures, `lme4`/`lmerTest` for mixed effects, `maSigPro` / `splineTimeR` for spline fits) — not pairwise DE.

**Reference**: Spies & Ciaudo 2015, *Dynamics in transcriptomics: advancements in RNA-seq time course and downstream analysis*, Comput Struct Biotechnol J 13:469. Sun et al. 2016, *splineTimeR: time course gene expression data*, Bioinformatics 32:1571.

---

## Cross-reference: which patterns combine

Patterns compose. A real query often instantiates two or three at once. Examples observed in our 29 curated chains:

| Curated chain | Patterns combined |
|---|---|
| `bulk_rnaseq_de_analysis` | `sequential_omics_pipeline` + `ensemble_annotation` (at the enrichment step) |
| `rare_disease_multimodal_workup` | `multi_omics_integration` + `filter_cascade` (variant prioritization) |
| `target_to_lead_full` | `sequential_omics_pipeline` + `filter_cascade` + `iterative_refinement` (ADMET gate) |
| `single_cell_multimodal_analysis` | `multi_omics_integration` + `hierarchical_re_evaluation` |

The pattern library is **compositional grammar**, not enum. The LLM picks patterns the same way a writer picks rhetorical structures — multiple, blended, in service of the question.

---

## How the LLM uses this

At composition time, given a user query, the system:

1. **Retrieves top-K relevant patterns** (BGE over the `When` paragraphs).
2. **Retrieves top-K curated chains** as similar-shape exemplars.
3. **Injects both into the LLM context** alongside the user query and conversation memory.
4. **LLM emits a chain** in the free-form `{steps, edges, rationale}` schema, citing which pattern(s) it drew from in the rationale field.
5. **Verifier** checks: every step exists, no cycles, every edge has plausible I/O semantics (LLM judge).
6. **Confidence scorer** decides surfacing mode (upfront / stepwise / reactive).

The patterns are *scaffolding*. The LLM can ignore them — and should, when the question is genuinely novel — but they're the first thing it reaches for.

---

## Open questions before this lands

1. **Storage format**: markdown source-of-truth (this file, split into 12 files) + a build-time indexer that loads into the `chain_patterns` retrieval table. Authors edit prose; system retrieves embeddings.
2. **Are there missing patterns?** This draft is 12. Likely gaps: **time-series / longitudinal** (different from cross-cohort because each timepoint comes from the same subject), **case-control matched**, **dose-response**. Add if the user agrees they're distinct.
3. **Is "comparative benchmarking" really for end-users or for method developers?** It might belong in a "developer mode" tier rather than the main user-facing library. Flag for review.
4. **Should iterative_refinement be a pattern or just a property of any step?** It's already implemented as a step-level feature (`auto_loop`). Including it here makes the LLM aware it's an available *macro*, not just a setting — favoring inclusion, but verify against actual usage.
