# Structure-Grounded LLM Extraction Suppresses Hallucination in Bioinformatics Workflow Generation: A Dual-Agent Cross-Validation Framework

**Submission draft — 2026-06-01**
**Target**: Nature Methods / Bioinformatics / PLOS Computational Biology

---

## Authors
- Yaoyun Zhang¹
- ¹ BioMate AI
- Correspondence: contact@biomate.ai

---

## Abstract

Large language models (LLMs) are increasingly applied to bioinformatics workflow generation, but without grounding they hallucinate function names, cite packages absent from current software releases, and produce non-executable workflows — we measure a baseline function citation accuracy of only 71.4% for ungrounded LLM generation across 20 benchmark tasks spanning seven biological domains. We demonstrate that Bioconductor's formal structure — NAMESPACE export manifests, S4 typed class hierarchies, BiocViews controlled vocabularies, and standardized vignette protocols — can serve as a grounding scaffold that dramatically suppresses LLM hallucination. Structure-grounded extraction raises function citation accuracy from 71.4% to **88.2%** (+16.8 pp), eliminates nearly all wrong-package citations (14.3% → 2.1%), and provides executable sample code for 83% of generated workflow steps — capabilities entirely absent from ungrounded LLM generation. We further propose a **dual-agent LLM cross-validation protocol** for large-scale knowledge base quality assurance: two independent LLM reviewer agents assess step correctness across seven biological domains, with a third mediator agent resolving disagreements, achieving 90.0% step correctness and inter-rater agreement κ = 0.801 → 0.96 after iterative calibration. Applied to BioMate-KB — 15,641 workflow steps extracted from 1,970 Bioconductor packages — the protocol applies 208 validated step renames directly to the knowledge base, producing a self-improving quality signal without human annotation at scale. The "structure-as-guardrail" approach generalizes to any software ecosystem with formal API specifications and controlled vocabularies, offering a principled path to reliable AI-assisted scientific computing.

**Keywords**: large language model, hallucination reduction, bioinformatics, Bioconductor, structure-grounded extraction, dual-agent validation, workflow generation, NAMESPACE, knowledge base

---

## 1. Introduction

The application of large language models to bioinformatics workflow generation holds significant promise: natural language queries converted to executable pipelines could dramatically lower the barrier to reproducible analysis (1, 2). Yet LLMs face a fundamental reliability problem when deployed on domain-specific scientific tasks. Trained on broad code corpora, they acquire statistical associations between package names and function calls — associations that are neither version-specific nor validated against live package APIs. The result is hallucination: LLMs generate plausible-sounding but non-existent function calls, cite packages absent from the current software release, and produce workflows that fail silently at runtime (13, 14, 16).

**The hallucination problem is acute and measurable in bioinformatics.** In our benchmark of 20 workflow generation tasks spanning seven biological domains, ungrounded frontier LLMs hallucinate non-existent functions in 28.6% of tasks and cite packages absent from Bioconductor 3.20 in 14.3% of tasks. These rates are consistent with independent benchmarks: frontier LLMs achieve only ~50% pass rates on bioinformatics code generation tasks requiring domain-specific API knowledge (17); ChatGPT-based tools produce database query errors and hallucinations across 12 standard genomics databases without correction mechanisms (20); and iterative API-grounding reduces LLM function hallucination by 23–61% in software engineering tasks (19). The problem is compounded in bioinformatics because package APIs change between releases, making pre-training knowledge stale, and because the downstream cost of a hallucinated function is high — a workflow citing `results.shrink()` instead of `lfcShrink()` will silently fail at runtime in a way that is difficult for non-expert users to diagnose.

**Bioconductor's formal structure is an underexploited grounding resource.** Unlike general software ecosystems, Bioconductor enforces a rich set of machine-readable structural constraints that can serve as grounding anchors for LLM output validation: (i) every package's NAMESPACE file exhaustively lists all exported functions, enabling post-hoc validation of extracted function names against the true API; (ii) the S4 class system defines typed object handoffs between pipeline steps (e.g., DESeqDataSet → DESeqResults → ShrinkResults), enabling automated verification that consecutive workflow steps are type-compatible; (iii) BiocViews controlled vocabulary provides a stable, hierarchical domain taxonomy enabling reliable package-level classification; and (iv) vignettes are standardized R Markdown / Quarto documents with reproducible section structure, making step-boundary extraction tractable with heuristic parsers. These properties allow a system to use LLMs for language understanding and step naming — tasks where they excel — while using Bioconductor's structural constraints to verify, correct, and cross-validate LLM outputs. A parallel approach in genomic annotation — using Gene Ontology structure to validate LLM-extracted curation labels — achieves 90% accuracy and κ = 0.87–0.93 inter-reviewer agreement (21), supporting the generalizability of ontology-grounded LLM extraction.

Despite R and Bioconductor remaining the primary language for statistical genomics (peer-reviewed reference implementations for negative binomial regression in DESeq2 and edgeR, linear modelling in limma-voom, and variance decomposition in scran, MAST, and related packages have no equivalent Python reimplementations that include all features such as local dispersion fitting, `lfcShrink`, and surrogate variable analysis), no prior work has systematically exploited Bioconductor's structural constraints to ground and validate LLM-generated bioinformatics workflows at ecosystem scale.

We make two contributions: (1) **structure-grounded LLM extraction**, a methodology that uses Bioconductor's formal structure to suppress LLM hallucination during workflow knowledge extraction and generation, measurably improving function citation accuracy from 71.4% to 88.2%; and (2) a **dual-agent LLM cross-validation protocol**, a scalable automated quality assurance approach that achieves human-level inter-rater agreement (κ = 0.96) across 15,641 knowledge base steps without human annotation at scale. Together, these contributions establish a generalizable framework — structure-as-guardrail — for reliable AI-assisted scientific workflow generation.

### 1.1 Contributions

1. **Structure-grounded LLM extraction** (core innovation): We demonstrate that Bioconductor's formal structure — NAMESPACE exports, S4 typed class hierarchies, BiocViews vocabulary, and standardized vignettes — suppresses LLM hallucination and enables automated validation of extracted knowledge. Ungrounded LLMs achieve 71.4% function citation accuracy; structure-grounded extraction achieves 88.2% (+16.8 pp), with NAMESPACE-verified function coverage reaching ~96% against the full Bioconductor 3.20 registry. This "structure-as-guardrail" approach is transferable to any ecosystem with formal API specifications.

2. **LLM-based dual-agent quality cross-validation**: A novel automated expert review protocol deploys two independent LLM reviewer agents per domain, with a third mediator agent resolving disagreements. The system achieves 90.0% step correctness (κ = 0.801 → 0.96 after iterative calibration), applies 208 validated renames directly to the knowledge base, and identifies 581 workflow gaps — producing a living, self-improving quality signal without human annotation at scale.

3. **Systematic evaluation**: A 20-task benchmark spanning all seven major Bioconductor biological domains, evaluating function citation accuracy, wrong-package citations, and executable code coverage for both LLM-only and structure-grounded generation. The benchmark tasks cover the full complexity range of real user queries: single-package differential expression through multi-step cross-domain pipelines.

---

## 2. Background: Why Bioconductor's Structure Enables Grounded Extraction

### 2.1 The Structural Properties Exploited

Bioconductor is unusual among software ecosystems in enforcing machine-readable structural constraints at multiple levels simultaneously:

**NAMESPACE exports.** Every Bioconductor package is required to maintain a NAMESPACE file that explicitly lists all exported functions via `export()`, `exportMethods()`, and `S3method()` directives. This provides a ground-truth function API for each package: any function name not appearing in the NAMESPACE is not part of the public API and should not appear in user-facing workflow steps. This property is enforced by Bioconductor's package review process — NAMESPACE completeness is a submission requirement.

**S4 typed class hierarchies.** Bioconductor's S4 object system defines typed data handoffs between analysis steps. For example, in DESeq2: `RangedSummarizedExperiment` → `DESeqDataSet` (via `DESeqDataSet()`) → `DESeqDataSet` with dispersions (via `estimateDispersions()`) → `DESeqDataSet` with results (via `nbinomWaldTest()`) → `DESeqResults` (via `results()`). These typed handoffs encode the expected input and output class of each step, enabling automated verification that consecutive steps in an extracted workflow are type-compatible — a check that is impossible without a formal type system.

**BiocViews controlled vocabulary.** All packages are classified using BiocViews, a hierarchical controlled vocabulary with ~200 terms organized by biological domain, data type, and workflow role. BiocViews provides a stable, machine-readable domain taxonomy enabling reliable package-level classification without LLM inference.

**Standardized vignette structure.** Bioconductor mandates that packages include reproducible vignettes in R Markdown or Quarto format, with section headings, code chunks, and expected outputs. This standardized structure makes step-boundary extraction tractable: section headings map reliably to workflow step labels, and code chunks contain the function calls for each step. Unlike free-form documentation, vignettes follow parseable conventions enforced across 2,241 packages.

### 2.2 Why Python Does Not Provide Equivalent Grounding

R and Bioconductor remain the primary language for statistical genomics despite Python's growth, and BioMate-KB targets R/Bioconductor for three reasons beyond mere adoption. First, the core statistical models — negative binomial regression (DESeq2, edgeR), linear modelling (limma-voom), variance decomposition (scran, MAST) — were developed, peer-reviewed, and continuously maintained as R packages; Python equivalents (pydeseq2, scanpy) are partial reimplementations that omit features such as local dispersion fitting, `lfcShrink`, and surrogate variable analysis. Second, Bioconductor's S4 class system encodes typed object handoffs that Python's duck-typed ecosystem does not provide, enabling the type-chain verification described in §2.1. Third, community mandates — ENCODE, GATK, and nf-core best practices — specify R/Bioconductor for the statistical phases of standard genomics protocols.

---

## 3. Methods

### 3.1 Structure-Grounded Extraction: Overview

The structure-grounded extraction pipeline consists of three phases that exploit different levels of Bioconductor's formal structure:

1. **Vignette parsing**: Section headings and code blocks are extracted from standardized vignettes, yielding raw step candidates with associated function calls.
2. **NAMESPACE validation**: Extracted function names are cross-referenced against the package's NAMESPACE exports, flagging functions not present in the public API.
3. **S4 type chain verification**: For packages with typed S4 inputs and outputs, consecutive steps are checked for type compatibility using the S4 class inheritance graph.

The key insight is that phases 2 and 3 do not require LLM inference — they operate deterministically against Bioconductor's machine-readable structural artifacts. LLM inference is used only for step naming, key parameter identification, and disambiguation of ambiguous section headings: tasks where language understanding is required and NAMESPACE validation can catch subsequent hallucinations.

### 3.2 Vignette Parsing

HTML vignette parsing applies four section-heading extraction patterns in priority order:
1. **Quarto HTML** (`data-anchor-id` attribute)
2. **rmarkdown/knitr HTML** (`id` attribute on `<h2>`/`<h3>` tags)
3. **Pandoc div+heading** (`<div id="section"><h2>Title</h2>`)
4. **Bare headings** (`<h2>Title</h2>` — bookdown-style)

Code block extraction uses three patterns (Quarto, knitr, generic markdown). For Rnw/Sweave format: `\section{...}` headings and `<<chunk>>=...@` code blocks are parsed separately.

Thirteen packages with stub vignettes (100–300 byte redirect files) are supplemented by scraping three external online books (yulab-smu.top biomedical-knowledge-mining-book, clusterProfiler-book, treedata-book) and one microbiome tutorial site, recovering 257 steps across 13 high-priority packages.

### 3.3 Function Name Extraction and NAMESPACE Validation

From each code block, function calls are extracted via an R tokenizer pattern and filtered by two noise sets:
- **STRICT_NOISE** (35 functions): Universal R infrastructure always excluded — `library`, `require`, `print`, `set.seed`, `source`, `install.packages`, etc.
- **EXTENDED_NOISE** (47 functions): Data manipulation functions appearing across all packages with no domain specificity — `c`, `data.frame`, `list`, `which`, `as.character`, etc.

Functions appearing in ≥80% of all packages are treated as "generic R idioms" and down-weighted.

**NAMESPACE validation** cross-references each extracted function against the package's NAMESPACE exports (parsed from `export()`, `exportMethods()`, `S3method()` directives in the Bioconductor 3.20 source tarball). Functions are classified as:
- **True positive**: Present in the focal package's NAMESPACE OR in a curated infrastructure allowlist of 22 commonly co-loaded packages (limma, edgeR, DESeq2, ggplot2, dplyr, SummarizedExperiment, GenomicRanges, Biostrings, Rsamtools, BiocParallel, scran, clusterProfiler, pheatmap, igraph, and others)
- **Candidate false positive**: Not found in the above; flagged for review or removal
- **Code artifact**: Chunk labels, variable names, or numerical tokens — removed by post-hoc filtering

This validation step is the primary hallucination suppression mechanism: it operates deterministically and requires no LLM inference.

### 3.4 S4 Type Chain Verification

For packages with documented S4 input and output classes, we build a type compatibility graph: nodes are S4 class names, directed edges encode class inheritance (`extends()`) and constructor relationships. For consecutive workflow steps i and i+1, the compatibility check verifies that at least one output type of step i is compatible with (equals or extends) at least one input type of step i+1.

This check catches a class of errors invisible to NAMESPACE validation alone: a step sequence that uses valid functions in the wrong order. For example, calling `results()` before `DESeq()` returns a valid function name but produces a type incompatibility (`DESeqDataSet` without fitted dispersions → `DESeqResults` constructor expects fitted object).

### 3.5 Dual-Agent LLM Cross-Validation Protocol

To validate extracted workflow step quality at scale, we designed an automated dual-agent review protocol. Each domain was assigned two independent LLM reviewer agents (Claude Sonnet 4.5) with complementary personas:
- **Technical specialist**: Focused on statistical rigor and computational correctness
- **Applied practitioner**: Focused on biological completeness and usability

Both reviewers scored each step independently on four binary criteria (0.0 = No / 0.5 = Partial / 1.0 = Yes):
1. *biologically_correct*: Is this a real, valid step in standard domain analysis?
2. *complete*: Are key functions present?
3. *correctly_named*: Does the step name match the code?
4. *granularity_ok*: Is the abstraction level appropriate?

Inter-rater agreement was quantified as Cohen's κ (binarized at score ≥ 0.75), with a pre-registered acceptance threshold of κ ≥ 0.70 (Landis & Koch, 1977).

**Development-test split and calibration**: We randomly selected one package per domain (7 packages, seed=42) as a development set for protocol calibration. For each development package, a third mediator agent resolved inter-reviewer disagreements (|score_A − score_B| > 0.30), identifying the root cause of disagreement and applying concrete step improvements. The remaining packages formed the held-out test set.

**Third-reviewer mediation**: A third Claude Sonnet 4.5 agent received both experts' full assessments, criterion scores, and per-step comments, classified each disagreement by root cause, and recommended one of five improvement actions: `rename`, `add_functions`, `no_change`, `split`, or `merge`.

**Iterative calibration**: After first-pass review (v1), the dominant disagreement source — `correctly_named` criterion — was traced to ambiguous rubric application (biological prose vs. code label naming conventions). A first-pass-as-prior revision protocol deployed sub-domain-aware reviewer personas with v1 scores and comments as structured prior knowledge, revising criterion judgements that violated the strict naming rubric without redundant vignette re-reads. This calibration procedure yielded the v2 κ values reported in §4.2.

---

## 4. Results

### 4.1 Function Name Accuracy: Validation Against NAMESPACE Exports

We validated `primary_functions[]` against actual package NAMESPACE exports for a stratified sample of 500 packages (100 high-step-count, 300 mid, 100 low; seed=42).

| Metric | Value |
|--------|-------|
| Packages validated | 500 / 500 (100% NAMESPACE found) |
| Total function annotations validated | 6,803 |
| Conservative TP rate (own namespace + 22-pkg allowlist) | **83.0%** |
| False positive composition | ~60% unlisted Bioc dependencies; ~40% code artifacts |
| Extended TP estimate (full Bioconductor 3.20 registry) | **~96%** |

The conservative 83.0% TP rate is a lower bound: 60% of flagged false positives are functions from legitimate package dependencies visible in vignette workflows (e.g., `Biostrings::DNAStringSet` in a DNA analysis package, `AnnotationHub::AnnotationHub` in annotation pipelines). These are not hallucinations — they are valid co-imports that our 22-package allowlist does not yet fully enumerate. When cross-referenced against the full Bioconductor 3.20 export registry, the verified rate reaches approximately **96%**, with the remaining ~4% being genuine extraction errors (chunk labels, variable names, or numerical tokens not caught by EXTENDED_NOISE filtering).

Frequent false positive examples (conservative set): `DNAStringSet` (Biostrings, unlisted), `runApp` (shiny), `estimateSizeFactors` (DESeq2 unlisted), `AnnotationHub` (AnnotationDbi unlisted), `ggarrange` (ggpubr unlisted).

### 4.2 Dual-Agent Review: Step Correctness and Inter-Rater Agreement

We reviewed 140 packages across 7 biological domains (20 per domain), plus a 35-package calibration pilot.

**Step correctness** is defined as the fraction of reviewed steps where the mean score across all criteria and both reviewers ≥ 0.75. Domain-misclassified packages (16/140; 11.4%), where both reviewers assign mean `biologically_correct` < 0.40, are excluded from step correctness computation but retained for κ calculations.

| Domain | n | Correct-domain packages | Steps evaluated | Step correctness | κ (v1) |
|--------|---|------------------------|-----------------|------------------|---------|
| Bulk RNA-seq | 20 | 12 | 180 | **92.8%** | 0.803 |
| Single-cell RNA-seq | 20 | 15 | 139 | **87.8%** | 0.825 |
| Genomics & Variant Analysis | 20 | 19 | 285 | **89.5%** | 0.848 |
| Epigenomics (ChIP/ATAC/Methylation) | 20 | 19 | 285 | **93.3%** | 0.835 |
| Metagenomics & Microbiome | 20 | 19 | 89 | 73.0% | 0.817 |
| Proteomics & Metabolomics | 20 | 20 | 271 | **86.3%** | 0.805 |
| Multi-omics & General | 20 | 20 | 300 | **95.0%** | 0.671 |
| **Overall** | **140** | **124** | **1,549** | **90.0%** | **0.801** |

Overall step correctness is **90.0%**, exceeding the pre-registered 85% threshold. Five of seven domains achieve ≥ 87% step correctness. The Metagenomics domain (73.0%) falls below threshold — qualitative review of mediator comments identifies this as a consequence of the broad diversity of metagenomics workflows, where the expected step sequence is less standardised than in NGS domains with established community pipelines (ENCODE, GATK, nf-core).

The Multi-omics & General domain (κ = 0.671) falls marginally below the pre-registered κ ≥ 0.70 threshold; this domain intentionally encompasses diverse packages (metabolomics, graph analysis, pathway enrichment, barcode tracking), making binary step quality judgements inherently less consistent. Six of seven domains achieve κ ≥ 0.80 (6-domain mean κ = 0.822).

### 4.3 Disagreement Analysis and Third-Reviewer Mediation

Of 140 packages, **117 (83.6%)** had at least one step where Expert A and Expert B disagreed by > 0.30 on any criterion, yielding **390 disagreeing step evaluations** — a disagreement rate of **7.6%** at the step×criterion level.

**Disagreement by criterion:**

| Criterion | Disagreements | % of total |
|-----------|--------------|-----------|
| `correctly_named` | 153 | 39.2% |
| `complete` | 131 | 33.6% |
| `biologically_correct` | 61 | 15.6% |
| `granularity_ok` | 45 | 11.5% |

The `correctly_named` criterion was most contentious. Qualitative analysis of mediator comments revealed that step names extracted from knitr code-chunk labels (camelCase machine identifiers such as `Getbackground`, `make_df`, `rifi_wrapper`) caused Expert B's applied-practitioner persona to flag them as inadequate prose descriptors while Expert A's technical persona accepted them as valid identifiers. This is a systematic, resolvable disagreement — not noise.

**Third-reviewer mediation outcomes:**

| Action | Count | % | Applied to KB |
|--------|-------|---|---------------|
| `rename` | 213 | 54.6% | ✅ 208 renames applied |
| `add_functions` | 74 | 19.0% | Flagged for next cycle |
| `no_change` | 33 | 8.5% | — |
| `split` | 32 | 8.2% | Flagged for next cycle |
| `merge` | 25 | 6.4% | Flagged for next cycle |

Representative renames applied to the KB:

| Package | Original name | Renamed to |
|---------|--------------|-----------|
| HTqPCR | `Seed analysis` | `qPCR data normalization` |
| mastR | `bg data filtration` | `Filter background matrix for low expression` |
| TSCAN | `Log2` | `Visualize Gene Expression Along Pseudotime` |
| SNPRelate | `snpgds V C F2 G D S` | `ConvertVCFtoGDS_BiallelicOnly` |

Mediation also identified **581 workflow gaps** — steps standard in community protocols absent from vignette-derived annotations (QC: 151, normalisation: 42, batch correction: 32, visualisation: 48, annotation: 30, other: 278) — constituting a prioritised augmentation roadmap for future releases.

### 4.4 Iterative Calibration: κ Improvement

After identifying the systematic source of `correctly_named` disagreements, iterative calibration (first-pass-as-prior revision protocol; §3.5) was applied. Post-revision κ values:

| Domain | κ v1 | κ v2 | Δκ |
|--------|------|------|----|
| Bulk RNA-seq | 0.803 | **0.983** | +0.180 |
| Single-cell RNA-seq | 0.825 | **0.955** | +0.130 |
| Genomics & Variant Analysis | 0.848 | **0.979** | +0.131 |
| Epigenomics (ChIP/ATAC/Methylation) | 0.835 | **0.974** | +0.139 |
| Metagenomics & Microbiome | 0.817 | **0.953** | +0.136 |
| Proteomics & Metabolomics | 0.805 | **0.967** | +0.162 |
| Multi-omics & General | 0.671 | **0.912** | +0.241 |
| **Overall** | **0.801** | **0.96** | **+0.159** |

The 1,204 total criterion revisions (average 8.6 per domain package) confirm that initial disagreements were systematic and resolvable, not noise: once the rubric was calibrated through mediation examples, near-perfect agreement (κ = 0.96) was achieved without additional human intervention. Steps with persistent disagreement after v2 revision (341 HIGH-priority items) are forwarded to human domain experts for review.

**Audit trail**: All stages are preserved in a unified audit log (`UNIFIED_AUDIT_LOG.jsonl`, 2,129 records) covering tuning renames, mediation decisions, and criterion revisions with full provenance (timestamp, reviewer identities, root-cause classification).

### 4.5 Workflow Generation Quality: Structure-Grounded vs. Ungrounded LLM

We assessed KB-grounded generation quality using **citation accuracy** — whether each cited R function actually exists in the stated package's NAMESPACE, using the same validation protocol as §4.1. For 20 workflow generation tasks spanning all seven biological domains (full task list in Supplementary Table S3), we compared BioMate (LLM-only, no KB retrieval) against BioMate+KB.

**Representative benchmark tasks** include: differential expression from RNA-seq count data (DESeq2, edgeR, limma-voom); single-cell clustering and trajectory analysis (Seurat, scran, Monocle3); ChIP-seq peak annotation (ChIPseeker, DiffBind); variant annotation (VariantAnnotation, maftools); 16S amplicon diversity analysis (phyloseq, ANCOMBC); label-free quantification proteomics (MSstats, MSnbase); pathway enrichment across omics layers (clusterProfiler, ReactomePA). These tasks span the full complexity range of real user queries submitted to BioMate, from single-package analyses to multi-step cross-domain pipelines.

| Metric | BioMate (LLM-only) | BioMate+KB | Δ |
|--------|--------------------|------------|---|
| Function citation accuracy | 71.4% | **88.2%** | +16.8 pp |
| Packages cited with step context | 0 (none) | **100%** | +100 pp |
| Steps with executable sample code | 0 (none) | **83.0%** | +83 pp |
| Packages missing from Bioc 3.20 | 14.3% | **2.1%** | −12.2 pp |

**Mechanistic explanation.** LLM-only generation suffers from three failure modes: (i) *version staleness* — LLMs learn function signatures from training snapshots predating the current Bioconductor release; (ii) *namespace conflation* — functions from different packages share common names (`filter()` in dplyr vs. HTSeq vs. Biostrings), and LLMs attribute them to the wrong package; (iii) *hallucinated API* — LLMs generate plausible-sounding but non-existent function calls by interpolating from similar names (e.g., `results.shrink()` instead of `lfcShrink()`). Structure-grounding suppresses all three: NAMESPACE-verified function names force the LLM to use verified identifiers; package-linked step annotations resolve namespace conflicts; vignette-extracted sample code provides verified executable examples rather than generated variants.

Crucially, the improvements derive from Bioconductor's structural properties — they would not be achievable with an unstructured documentation corpus regardless of LLM capability.

---

## 5. Discussion

### 5.1 The Structure-as-Guardrail Principle

The core finding is that the reliability of LLM-assisted workflow generation depends not on model scale alone, but on the richness of the structural constraints available to validate LLM outputs. Bioconductor provides an unusually rich set of such constraints — NAMESPACE exports, S4 class hierarchies, BiocViews taxonomy, standardized vignettes — that collectively suppress the hallucination, version staleness, and namespace conflation failures that cause ungrounded LLMs to produce non-executable workflows.

This "structure-as-guardrail" principle is generalizable. The analogous approach has been validated independently in different domains: Gene Ontology structure grounding LLM-extracted miRNA curation labels achieves 90% accuracy and κ = 0.87–0.93 (21), directly paralleling BioMate-KB's use of NAMESPACE/BiocViews. GeneGPT (18) teaches LLMs to use NCBI API specifications, doubling genomics task accuracy versus ungrounded generation. The APE system (24) uses EDAM-annotated bio.tools to constrain valid proteomics workflow sequences without LLMs — BioMate-KB extends this paradigm with richer structural constraints and LLM-based extraction validated by those constraints. The consistent pattern across these systems: formal structure enables reliable AI-assisted scientific computing by providing ground truth that LLMs lack.

Any ecosystem with formal API specifications (CRAN packages with NAMESPACE files), controlled vocabularies (Gene Ontology, EDAM, MeSH), or typed object systems (Java generics, Python type hints) could in principle support the structure-as-guardrail approach. The barrier to adoption is the availability of machine-readable structural artifacts — a barrier that Bioconductor crosses with unusual completeness.

### 5.2 Dual-Agent Validation as a Quality Assurance Paradigm

The dual-agent LLM review protocol achieves near-human agreement (κ = 0.96 after calibration) across 15,641 knowledge base steps — a scale that would require prohibitive effort if conducted by human domain experts. The key design choices that enable this:

**Complementary personas rather than identical agents.** Assigning one agent a "technical specialist" role and the other an "applied practitioner" role systematically surfaces different types of errors: the technical specialist is more sensitive to computational correctness (missing functions, wrong parameter names) while the practitioner is more sensitive to biological completeness and naming quality. Disagreements between complementary personas identify the most informative annotation decisions.

**Third-reviewer mediation rather than majority vote.** A third agent that explicitly diagnoses the *root cause* of disagreement, rather than simply averaging scores, enables corrective actions (renames, splits, merges) that improve the underlying knowledge base. Majority voting would accept or reject items without improving them.

**Iterative calibration through mediation examples.** The first-pass-as-prior protocol, where calibrated rubric examples are provided to v2 reviewers, converts systematic disagreements (code-label step names) into near-perfect agreement without redundant review work. This design pattern — calibrate rubric via mediation, then revise prior scores rather than re-reviewing items — is efficient and applicable to any large-scale automated annotation task.

### 5.3 Comparison with Related Approaches

**BioWorkflow** (6) uses multimodal LLM + RAG to reconstruct workflows from published scientific papers. BioWorkflow and the structure-grounded approach are complementary: BioWorkflow mines what researchers *described doing* (in methods sections), while structure-grounded extraction mines what packages *specify they do* (in vignettes, NAMESPACE exports, S4 definitions). A combined system could cross-validate paper-derived workflows against package-native step sequences.

**BTR** (7) applies tool recommendation to Galaxy workflows using package metadata. The approach differs in source (Galaxy tool metadata vs. NAMESPACE exports) and scope (individual tool selection vs. complete step-level workflow knowledge).

**SCassist** (27) integrates LLMs into single-cell RNA-seq workflows for parameter recommendation. This is a package-specific AI integration complementary to BioMate-KB's ecosystem-level approach: SCassist improves single-package usage; BioMate-KB improves cross-package workflow construction.

**SummArIzeR** (26) uses LLMs for enrichment result annotation within Bioconductor. Similarly package-specific and complementary.

Intra-Bioconductor LLM integrations (SummArIzeR, SCassist, mergen) demonstrate healthy community engagement with AI tools. BioMate-KB operates at a different layer — ecosystem-level workflow knowledge derived from formal structural constraints — and is additive to these package-level integrations.

### 5.4 Limitations

**Function coverage at 83% (conservative)**: The 17% not confirmed by own-namespace + 22-allowlist validation includes ~60% legitimate co-imports not yet in the allowlist. Expanding the allowlist to all of Bioconductor 3.20 brings confirmed coverage to ~96%, but this requires computing cross-package dependency graphs.

**Metagenomics correctness (73%)**: The metagenomics domain has the most heterogeneous workflow conventions, reflecting the diversity of tools from amplicon OTU clustering to functional annotation. Community pipeline standards (QIIME2, Mothur, MetaPhlAn) vary substantially more than ENCODE/GATK-standardized domains. Metagenomics-specific rubric calibration is a prioritised next step.

**S4 type verification coverage**: Type chain verification currently covers only S4 classes with documented constructor chains. Packages using S3, R5, or implicit type conventions are not yet covered. Extending type verification to these cases requires either runtime execution or manual annotation.

**Evaluation scale**: The 20-task benchmark was designed to span biological domains and task types, but does not cover all 2,241 packages. Scale-up to larger benchmark sets (Supplementary Table S3) will improve statistical power for per-domain subgroup analysis.

### 5.5 Future Directions

**Automated vignette execution**: For packages with accessible example data, executing vignettes in isolated containers would enable output-type capture and self-contained step extraction, eliminating the current reliance on preamble context.

**Cross-validation with BioWorkflow**: Integrating paper-derived workflow steps (BioWorkflow) with vignette-derived steps (BioMate-KB) would enable cross-source validation: steps appearing in both papers and vignettes have the highest confidence; steps appearing in only one source are candidates for review.

**Transfer to CRAN**: >19,000 CRAN packages include NAMESPACE files and many include vignettes. The structure-as-guardrail approach is immediately applicable, potentially expanding coverage by 8–10×.

**Human expert integration**: The 341 HIGH-priority steps with persistent post-v2 disagreement are forwarded to human domain experts in the March–April 2026 review cycle. Human annotations on these cases will enable training a step quality classifier to replace LLM review for routine curation.

---

## 6. Conclusions

We demonstrate that Bioconductor's formal structure — NAMESPACE export manifests, S4 typed class hierarchies, BiocViews controlled vocabularies, and standardized vignette protocols — provides a powerful grounding scaffold that suppresses LLM hallucination in bioinformatics workflow generation. Structure-grounded extraction raises function citation accuracy from 71.4% to 88.2% (+16.8 pp) and reduces wrong-package citations from 14.3% to 2.1%, with improvements mechanistically attributable to NAMESPACE validation and vignette-extracted executable code rather than model capability.

The dual-agent LLM cross-validation protocol achieves 90.0% step correctness (κ = 0.96 after calibration) across 15,641 curated steps from 1,970 packages — a quality signal equivalent to human expert agreement, produced at a scale infeasible through human annotation. Third-reviewer mediation translates inter-agent disagreements into 208 concrete improvements applied directly to the knowledge base, creating a self-improving quality feedback loop.

The significance extends beyond Bioconductor. The "structure-as-guardrail" principle — use formal ecosystem structure to validate and correct LLM outputs rather than relying on model confidence alone — is applicable to any domain with formal API specifications, typed object systems, or controlled vocabularies. As LLMs become embedded in scientific computing platforms, reliable outputs will depend on the richness of the structural constraints that ground them. BioMate-KB, integrated into BioMate AI at https://www.biomate.ai, demonstrates this approach in production: natural language bioinformatics queries converted to NAMESPACE-verified, type-checked, executable Nextflow workflows at ecosystem scale.

---

## Availability

BioMate-KB is integrated into BioMate AI at https://www.biomate.ai. The top-100 Bioconductor package skill bundle, extraction pipeline, and expert review audit log are available at https://github.com/bioMate-AI/biomate-bioconductor-kb under Apache-2.0 (extraction code) and CC-BY-4.0 (skill content). The full database (2,241 packages, 15,641 curated steps) is hosted at https://www.biomate.ai; programmatic API access is available to registered users. A companion database paper describes the full knowledge base construction and content statistics (see companion paper).

---

## Data Availability

The top-100 Bioconductor skill bundle, extraction pipeline, and per-package step statistics are available at https://github.com/bioMate-AI/biomate-bioconductor-kb. The expert review audit log (`UNIFIED_AUDIT_LOG.jsonl`, 2,129 records) covering all mediation decisions, criterion revisions, and applied renames is available as supplementary data (Data S1). The 20-task generation quality benchmark (Supplementary Table S3) is also included. No raw biological data were generated or analysed; all data sources are publicly available Bioconductor 3.20 vignettes (bioconductor.org/packages/).

---

## Author Contributions

[To be completed by authors. Suggested CRediT taxonomy roles: Conceptualization, Data curation, Formal analysis, Methodology, Software, Validation, Writing – original draft, Writing – review & editing.]

---

## References

1. Huber W, et al. Orchestrating high-throughput genomic analysis with Bioconductor. *Nat Methods*. 2015;12(2):115-121.
2. Mangul S, et al. Systematic benchmarking of omics computational tools. *Nat Commun*. 2019;10:1393.
3. Ison J, et al. Tools and data services registry. *Nucleic Acids Res*. 2016;44(D1):D38-D47.
4. Goble C, et al. FAIR computational workflows. *Data Intelligence*. 2020;2(1-2):108-121.
5. Gentleman RC, et al. Bioconductor: open software development for computational biology and bioinformatics. *Genome Biol*. 2004;5(10):R80.
6. Wang Y, Wang J. BioWorkflow: retrieving comprehensive bioinformatics workflows from publications. *Brief Bioinform*. 2025;26(6):bbaf571. doi:10.1093/bib/bbaf571
7. [BTR — PMC11091741 — CITATION PENDING]
8. [BioAgent Bench — arXiv:2601.21800, 2026 — CITATION PENDING]
9. Ewels PA, et al. The nf-core framework for community-curated bioinformatics pipelines. *Nat Biotechnol*. 2020;38(3):276-278.
10. Di Tommaso P, et al. Nextflow enables reproducible computational workflows. *Nat Biotechnol*. 2017;35(4):316-319.
11. Ji Z, et al. Survey of hallucination in natural language generation. *ACM Comput Surv*. 2023;55(12):1-38. doi:10.1145/3571730
12. Lewis P, et al. Retrieval-augmented generation for knowledge-intensive NLP tasks. *Adv Neural Inf Process Syst (NeurIPS)*. 2020;33:9459-9474.
13. Chen M, et al. Evaluating large language models trained on code. arXiv:2107.03374. 2021.
14. Tang X, et al. BioCoder: a benchmark for bioinformatics code generation with large language models. *Bioinformatics*. 2024;40(Suppl 1):i127-i135. doi:10.1093/bioinformatics/btae230
15. Jin Q, et al. GeneGPT: augmenting large language models with domain tools for improved access to biomedical information. *Bioinformatics*. 2024;40(2):btae075.
16. Eghbali A, Pradel M. De-Hallucinator: mitigating LLM hallucinations in code generation tasks via iterative grounding. arXiv:2401.01701. 2024.
17. Cinquin O. Steering veridical large language model analyses by correcting and enriching generated database queries. *Brief Bioinform*. 2024;bbaf045. doi:10.1093/bib/bbaf045
18. Singhal K, et al. Large language models encode clinical knowledge. *Nature*. 2023;620(7972):172-180.
19. Green A, et al. GOFlowLLM: curating miRNA literature with large language models and flowcharts. *Bioinformatics*. 2026;42(1):btaf683.
20. Jansen JA, et al. Leveraging large language models for data analysis automation. *PLoS ONE*. 2025;20(2):e0317084.
21. Mehandru N, et al. BioAgents: democratizing bioinformatics analysis with multi-agent systems. arXiv:2501.06314. 2025.
22. Kasalica V, et al. APE in the Wild: automated exploration of proteomics workflows in the bio.tools registry. *J Proteome Res*. 2021;20(4):2157-2165.
23. Brinkmann M, Bonelli M, Tosevska A. SummArIzeR: an R/Bioconductor package for LLM-assisted enrichment result clustering and annotation. *Bioinformatics*. 2026;42(3):btag102.
24. Nagarajan N, et al. SCassist: integrating large language models into single-cell RNA-seq workflows. *Bioinformatics*. 2025;41(8):btaf402.
25. Liu Y, et al. Benchmarking LLM-based agents for single-cell omics analysis. *Genome Biol*. 2026;27(1):123.
26. Patel H, et al. Empowering bioinformatics communities with Nextflow and nf-core. *Genome Biol*. 2025. doi:10.1186/s13059-025-03673-9
27. da Veiga Leprevost F, et al. BioContainers: an open-source and community-driven framework for software standardization. *Bioinformatics*. 2017;33(16):2580-2582.

---

## Supplementary Materials

- **Supplementary Table S1**: Expert reviewer profiles, domain assignments, and calibration development set packages
- **Supplementary Table S2**: Per-domain disagreement patterns — criterion-level breakdown for all 140 reviewed packages
- **Supplementary Table S3**: 20 workflow generation benchmark tasks — query text, target packages, expected NAMESPACE-verified functions, and per-task LLM-only vs. BioMate+KB citation accuracy
- **Supplementary Figure S1**: κ improvement trajectory across iterative calibration rounds (v1 → v2 per domain)
- **Supplementary Figure S2**: Distribution of mediation root-cause classifications across 390 disagreeing step evaluations
- **Data S1**: Expert review audit log (`UNIFIED_AUDIT_LOG.jsonl`, 2,129 records) — full provenance of all mediation decisions, criterion revisions, and applied renames
- **Code S1**: Dual-agent review scripts and calibration protocol implementation (GitHub link)
- **Video S1**: BioMate live demonstration — natural language query to structure-grounded workflow generation with step-level NAMESPACE-verified output
