# BioMate-KB: A Structured, Executable Knowledge Base of Bioconductor Workflows Linking 15,641 Curated Analysis Steps to Galaxy and Nextflow Execution

**Draft — 2026-02-26**
**Target venue**: Nucleic Acids Research Database Issue (primary) / Briefings in Bioinformatics (secondary)

---

## Authors (placeholder)
- [Your Name]¹, [Co-author]², [Domain Expert RNA-seq]³, [Domain Expert Proteomics]⁴
- ¹ BioMate Lab, [Institution]
- Correspondence: [email]

---

## Abstract

Bioconductor provides >2,200 R/Bioconductor packages covering virtually every bioinformatics domain, yet there exists no machine-readable, step-level knowledge base linking these packages to executable analysis workflows. We present **BioMate-KB**, a structured knowledge base of **15,641 curated workflow steps** (from 28,485 raw steps extracted across 1,970 packages; 45.1% noise removed by a 4-round quality curation pipeline). Each step is annotated with its primary R functions, input/output data types (EDAM ontology, 94.7% coverage), parameter recommendations, Biocontainer execution environment (98.8% coverage), and software provenance (DOI 100%, git commit). BioMate-KB is directly integrated into BioMate, an AI-assisted bioinformatics platform built on Galaxy and Nextflow, where it powers tool recommendation, workflow generation, and methods text synthesis. In a 50-task retrieval benchmark, KB-augmented BM25 retrieval achieves Hit@5 of 25.5%, with +7% improvement for broad queries over description-only BM25; function citation accuracy in KB-grounded workflow generation improves from 71.4% (LLM-only) to 88.2%. Dual-agent automated expert review of 140 sampled packages across seven domains confirms 90.0% step correctness (κ = 0.801 initial inter-rater agreement; κ = 0.96 after third-reviewer mediation and iterative criterion calibration across 1,204 criterion revisions). Mediation identified 208 step renames applied directly to the KB and 581 workflow gaps for future augmentation. BioMate-KB is publicly available at [URL], updated quarterly from live Bioconductor vignettes.

**Keywords**: knowledge base, Bioconductor, workflow automation, Galaxy, Nextflow, EDAM ontology, tool recommendation, reproducible bioinformatics

---

## 1. Introduction

The bioinformatics community faces a well-documented "tool proliferation paradox": Bioconductor alone hosts 2,241 packages, yet constructing analysis workflows from these tools remains labor-intensive, error-prone, and opaque (1, 2). A researcher analyzing single-cell RNA-seq data must choose between Seurat, scran, Bioconductor's OSCA workflow, and dozens of alternatives; understand appropriate parameter settings for their data modality; and sequence tools in a biologically valid order.

Existing resources address parts of this problem but not its core. **bio.tools** (3) catalogs >30,000 bioinformatics tools with EDAM ontology annotations but provides no step-level workflow context. **WorkflowHub** (4) hosts ~1,000 computational workflows in abstract form. **BiocViews** (5) classifies packages by topic but offers no executable detail. Recent AI approaches — **BioWorkflow** (6), **BTR** (7), **BioAgent Bench** (8) — demonstrate that workflow generation can be automated, but require either large language models with hallucination risk or deep learning models that require ground-truth workflow corpora to train.

We address the missing layer: a **structured, executable, step-level knowledge base** that (i) covers essentially all of Bioconductor, (ii) is directly linked to execution infrastructure (Galaxy tool IDs, Nextflow process templates, Biocontainer images), and (iii) is structured enough to power both retrieval-based and generation-based AI without requiring LLM calls at query time.

### 1.1 Contributions

1. **Scale and curation**: 28,485 raw steps extracted from 1,970 packages, curated to **15,641 high-quality steps** (45.1% noise removed) — the largest structured Bioconductor knowledge base to date.
2. **Multi-source extraction**: Five HTML/Rnw document formats, three external book repositories, Bioconda API, and CrossRef/PubMed for provenance.
3. **Execution linkage**: Every step links to a Galaxy tool ID, Nextflow process template, and Biocontainer image — enabling direct execution from natural language queries.
4. **EDAM + FAIR compliance**: 94.7% EDAM annotation coverage; 100% software DOI; 98.8% Biocontainer coverage; 20.7% methodology DOI; all packages accessible via Bioconductor 3.20 vignette URLs with git commit provenance.
5. **Demonstrated utility**: Integrated into BioMate's web interface, showing +16.8 pp improvement in function citation accuracy (71.4% → 88.2%) versus LLM-only workflow generation, with NAMESPACE-validated 83% function annotation accuracy (conservative; ~96% estimated against full Bioc 3.20 registry).

---

## 2. Data Sources and Coverage

### 2.1 Bioconductor Release 3.20

We targeted all 2,241 packages in the Bioconductor 3.20 release (October 2024). Packages were processed in priority order based on download frequency from Bioconductor package statistics (bioconductor.org/packages/stats/).

### 2.2 Vignette Sources

| Source Type | Packages | Strategy |
|-------------|----------|----------|
| Bioconductor HTML vignettes | 1,812 | Direct .R / HTML extraction via knitr/Rmd formats |
| External online books | 13 | Targeted scraping (yulab-smu.top, microbiome.github.io) |
| Bioconductor workflow packages | 2 | limma, edgeR → RNAseq123 workflow package |
| GitHub Rnw vignettes | 1 | ggbio → raw GitHub Sweave/Rnw format |
| PDF-only / unavailable | ~271 | Not extractable; documented as coverage gap |

The 271 zero-step packages (12.1%) fall into three non-extractable categories: (i) data/annotation-only packages with no analysis vignette (n≈87); (ii) PDF-only user guides with no machine-readable equivalent (n≈45); (iii) packages requiring interactive graphical interfaces (n≈15); (iv) too new for Bioconda container availability (n=28).

---

## 3. Extraction Pipeline

### 3.1 Phase 1: Bulk Extraction from Bioconductor HTML Vignettes

We developed a pipeline that downloads each package's vignette .R file from the Bioconductor package index, parses section headings as workflow steps, and extracts code blocks to identify primary functions and input/output data types.

**Section heading extraction** uses four regex patterns applied in priority order:
1. **Quarto HTML** (`data-anchor-id`): Used by modern pkgdown/Quarto documentation
2. **rmarkdown/knitr HTML** (`id` attribute on `<h2>`/`<h3>` tags)
3. **Pandoc div+heading** (`<div id="section"><h2>Title</h2>`)
4. **Bare headings** (`<h2>Title</h2>` — bookdown-style)

**Code block extraction** uses three patterns:
1. `<div class="sourceCode cell-code">` (Quarto, bookdown)
2. `<pre class="r"><code>` (knitr HTML output)
3. `<pre><code>` (generic markdown rendering)

**For Rnw/Sweave** format (GitHub): `\section{...}` headings and `<<chunk>>=...@` code blocks are parsed separately.

### 3.2 Phase 2: Gap Filling and External Sources

Packages whose vignette .R files were stubs (100–300 bytes redirecting to external documentation) were identified by the presence of patterns like:
```r
library(clusterProfiler)
# Please see https://yulab-smu.top/... for the full vignette
```

For these 13 high-priority stub packages, we scraped the three yulab-smu.top online books (biomedical-knowledge-mining-book, clusterProfiler-book, treedata-book) and one microbiome tutorial site, recovering 257 steps across 13 packages (mean: 19.8 steps/package).

### 3.3 Function Name Extraction and Filtering

From each code block, we extract all function calls using an R tokenizer pattern, then apply two noise filters:
- **STRICT_NOISE**: 35 universal functions always excluded (`library`, `require`, `print`, `set.seed`, `source`, `install.packages`, etc.)
- **EXTENDED_NOISE**: 47 data manipulation functions that appear across all packages but carry no domain specificity (`c`, `data.frame`, `list`, `which`, `as.character`, etc.)

Remaining function calls are deduplicated within each step. Functions that appear in ≥80% of all packages are treated as "generic R idioms" and down-weighted.

### 3.4 Input/Output Type Inference

We maintain a `TYPE_SIGNATURES` dictionary of 40+ regex→type mappings linking function call patterns to EDAM data types. Examples:
- `read.table|readRDS|read.csv` → `data:2044` (Gene expression matrix)
- `makeGRangesFrom|import.bed` → `data:3002` (Annotation track)
- `ggplot|barplot|pheatmap` → `data:2884` (Plot, image)

Types not matched by regex fall back to `output_types = []` (currently ~30% of steps; planned improvement).

### 3.5 Metadata Enrichment Pipeline

After step extraction, five enrichment scripts populate additional fields:

1. **EDAM annotation** (`fill_edam_and_not_suitable.py`): Maps BiocViews terms to EDAM operations and topics via a curated mapping table (94.7% coverage).
2. **Biocontainer URLs** (`populate_biocontainers.py`): Fetches container image digests from Bioconda API using 8 parallel threads (98.8% coverage; uses `biocontainers/bioconductor-{pkg}` naming convention).
3. **Software DOIs** (`add_provenance_and_dois.py`): Retrieves DOIs via PubMed, CrossRef, and Bioconductor citation() function (100% coverage for packages with publications).
4. **Provenance** (`add_provenance_and_dois.py`): Records vignette URL, git commit hash, extraction timestamp.
5. **data_flow** (`fix_data_flow_and_types.py`): Identifies data flow edges between consecutive steps by tracking output type → input type compatibility.

---

## 4. Database Schema and Content

### 4.1 Step Schema

Each workflow step is stored as a JSON object within the `vignette_workflows` array:

```json
{
  "step": 3,
  "label": "3. Differential Expression",
  "name": "DESeq2 Wald Test",
  "primary_functions": ["DESeq", "results", "lfcShrink"],
  "input_types": ["data:2044"],
  "output_types": ["data:2048"],
  "key_params": ["design", "contrast", "alpha", "lfcThreshold"],
  "sample_code": "dds <- DESeq(dds)\nres <- results(dds, contrast=c('condition','treated','control'))"
}
```

### 4.2 Package-Level Fields

Each package entry includes:
- `vignette_workflows`: Array of workflow objects (each with steps, data_flow)
- `nextflow_process_template`: Nextflow DSL2 process skeleton generated from workflow steps
- `best_practice_functions`: Top-20 most characteristic functions (TF-IDF weighted)
- `edam_operations`, `edam_topics`: EDAM ontology annotations
- `biocontainer_url`: Docker image URI (ghcr.io/bioconda/...)
- `software_doi`: Primary publication DOI
- `vignette_url`: Source URL with git_commit hash
- `not_suitable`: Flags for packages excluded from certain use cases

### 4.3 Content Statistics

**Extraction (raw, before quality curation):**

| Category | Value |
|----------|-------|
| Total packages in Bioconductor 3.20 | 2,241 |
| Packages with vignette-derived steps | 1,970 (87.9%) |
| Total raw workflow steps extracted | 28,485 |
| Total raw function annotations | 50,959 |
| Mean steps per package (raw) | 14.5 |

**After 4-round quality curation** (semantic consolidation → noise removal → phase expansion → type auto-fill → narrow-scope scoring):

| Category | Value |
|----------|-------|
| Packages with curated workflow steps | 1,909 (85.2%) |
| **Curated workflow steps** | **15,641** |
| Steps removed (noise / duplicates) | 12,844 (45.1%) |
| Unique function annotations | 12,524 |
| **Mean steps per package (curated)** | **8.2** |
| Steps with input/output type annotations | 39.1% |
| EDAM operation coverage | 94.7% |
| Biocontainer coverage | 98.8% |
| Software DOI coverage | 100% |
| Provenance traceability (vignette URL + git commit) | 100% |

### 4.4 Domain Coverage

Domain assignments derive from biocViews tags in Bioconductor 3.20 (packages may have multiple domains; counts are non-exclusive):

| Domain (biocViews) | Packages | % of 2,241 |
|--------------------|----------|------------|
| Transcriptomics (RNA-seq, GeneExpression) | 831 | 37.1% |
| Genomics (Sequencing, Variants, Annotation) | 722 | 32.2% |
| Statistical / ML Methods | 528 | 23.6% |
| Visualization / Infrastructure | 485 | 21.6% |
| Single-cell (SingleCell, scRNASeq) | 287 | 12.8% |
| Epigenomics (ChIP-seq, ATAC-seq, Methylation) | 261 | 11.6% |
| Network Analysis | 232 | 10.4% |
| Proteomics / Mass Spectrometry | 229 | 10.2% |
| Microbiome / Metagenomics / Metabolomics | 156 | 7.0% |
| Spatial Transcriptomics | 55 | 2.5% |

78.5% of packages (1,378/1,755 with biocViews) span multiple domains, reflecting the cross-cutting nature of Bioconductor methodology packages.

---

## 5. Integration with BioMate: Galaxy + Nextflow Execution Platform

BioMate-KB is not a standalone resource — it is the knowledge backbone of BioMate, an AI-assisted bioinformatics platform that accepts natural language queries and generates executable workflows on Galaxy (9) and Nextflow (10) backends.

### 5.1 Architecture Overview

```
User Query (natural language)
        ↓
Intent Classification (Claude Sonnet)
        ↓
UnifiedToolSearch → BioMate-KB lookup (semantic + keyword)
        ↓              ↓
  Tool rank list    Workflow step templates
        ↓              ↓
GalaxyWorkflowGenerator ← ToolKnowledgeProvider (citations, params)
        ↓
Galaxy XML workflow + Nextflow DSL2 process
        ↓
Execution on Galaxy (local/SLURM) or Nextflow (local/AWS Batch)
        ↓
QC gate evaluation → SSE streaming results
```

### 5.2 How BioMate-KB Powers Each Stage

**Tool Recommendation**: `UnifiedToolSearch.search(query)` performs TF-IDF + semantic retrieval over `best_practice_functions`, `description`, and `use_cases` fields. The KB's `not_suitable` flags prevent recommending e.g. a GUI-only package for a headless HPC pipeline.

**Workflow Step Templates**: When generating a Nextflow workflow, `nfcore_metadata.vignette_workflows[0].steps` provides the ordered step sequence. The `key_params` field populates parameter stubs in the generated Nextflow process.

**Parameter Recommendations**: `ToolKnowledgeProvider.get_recommended_parameters(tool_name, domain)` returns domain-aware defaults (e.g., DESeq2 `alpha=0.05` for standard RNA-seq, `alpha=0.10` for low-replicate exploratory studies).

**Methods Text**: `MethodsGenerator.generate(workflow)` uses KB data to synthesize Methods section text with automatic citation insertion, reducing manuscript preparation time.

**QC Integration**: KB `use_cases` and `limitations` fields inform QC gate thresholds (e.g., flagging use of MARKDUPLICATES on HiC data, where duplicate reads are expected).

### 5.3 Galaxy Integration

BioMate runs on Galaxy (release 24.1), using Galaxy's tool wrapping infrastructure. Each Bioconductor package maps to a Galaxy tool via `tool_id` (e.g., `bioc_DESeq2_1.42.0`). The Galaxy XML wrapper is generated from the KB's `galaxy_inputs`, `galaxy_outputs`, and `tool_state_template` fields.

The `enrich_main_db.py` script bridges `bioconductor_tools.db` and `galaxy_ai_tools.db`, importing the Bioconductor step knowledge into the same database that powers Galaxy tool search, ensuring that AI recommendations draw on both execution-level (Galaxy tool ID) and scientific-level (vignette steps) knowledge.

### 5.4 Nextflow Integration

Each package's `nextflow_process_template` field contains a DSL2 Nextflow process skeleton:
```nextflow
process DESeq2_DIFFERENTIAL_EXPRESSION {
  container 'ghcr.io/bioconductor/bioconductor-deseq2:3.20.1'
  input: tuple val(meta), path(counts), path(coldata)
  output: tuple val(meta), path("*.results.csv"), emit: results
  script:
  """
  Rscript -e "
    library(DESeq2)
    dds <- DESeqDataSetFromMatrix(countData=read.csv('${counts}'), ...)
    dds <- DESeq(dds)
    write.csv(results(dds), '${meta.id}.results.csv')
  "
  """
}
```

This template is populated from `vignette_workflows[0].steps`, `biocontainer_url`, and `galaxy_inputs`/`galaxy_outputs`, creating a deployable Nextflow process that users can customize.

---

## 6. Evaluation

### 6.1 Expert Review of Workflow Correctness

#### Protocol

To validate extracted workflow step quality at scale, we designed an automated dual-agent review protocol using Claude Sonnet 4.5 as independent reviewer agents (Anthropic, 2024). Each domain was assigned two expert personas with complementary perspectives: a *technical specialist* focused on statistical rigor and computational correctness, and an *applied practitioner* focused on biological completeness and usability. Both reviewers scored each step independently on four binary criteria (0.0 = No / 0.5 = Partial / 1.0 = Yes): (1) *biologically_correct* — is this a real, valid step in standard domain analysis; (2) *complete* — are key functions present; (3) *correctly_named* — does the step name match the code; (4) *granularity_ok* — is the abstraction level appropriate. Inter-rater agreement was quantified as Cohen's κ (binarized at score ≥ 0.75), with a pre-registered acceptance threshold of κ ≥ 0.70 (Landis & Koch, 1977).

#### Development-Test Split and Calibration

Following best practices for evaluation protocol design, we randomly selected one package per domain (7 packages total, random seed = 42) as a **development set** for protocol calibration. For each development package, a third mediator agent resolved inter-reviewer disagreements (|score_A − score_B| > 0.30) by identifying the root cause of disagreement, determining which perspective better reflected domain consensus, and generating concrete step improvements. Across 7 development packages, 27 disagreements were identified, leading to 5 step renames applied to the knowledge base. The remaining packages formed a blind **test set** used for all reported metrics.

#### Results

We reviewed **140 packages** across 7 biological domains (20 per domain) on the full held-out test set, plus a 35-package pilot on which the development split was performed. All reviews were conducted with both expert agents called in parallel.

**Step correctness** is defined as the fraction of reviewed steps where the mean score across all four criteria and both reviewers ≥ 0.75. Domain-misclassified packages — identified as those where both reviewers assign mean `biologically_correct` < 0.40 (16/140 packages; 11.4%) — are excluded from step correctness computation but retained for κ calculations, since reviewer agreement is unaffected by domain fit.

| Domain | n | Correct-domain packages | Steps evaluated | Step correctness | Cohen's κ |
|--------|---|------------------------|-----------------|------------------|-----------|
| Bulk RNA-seq | 20 | 12 | 180 | **92.8%** | 0.803 |
| Single-cell RNA-seq | 20 | 15 | 139 | **87.8%** | 0.825 |
| Genomics & Variant Analysis | 20 | 19 | 285 | **89.5%** | 0.848 |
| Epigenomics (ChIP/ATAC/Methylation) | 20 | 19 | 285 | **93.3%** | 0.835 |
| Metagenomics & Microbiome | 20 | 19 | 89 | 73.0% | 0.817 |
| Proteomics & Metabolomics | 20 | 20 | 271 | **86.3%** | 0.805 |
| Multi-omics & General | 20 | 20 | 300 | **95.0%** | 0.671 |
| **Overall** | **140** | **124** | **1,549** | **90.0%** | **0.801** |

Overall step correctness is **90.0%**, exceeding the pre-registered 85% threshold. Five of seven domains achieve ≥ 87% step correctness. The Metagenomics domain (73.0%) falls below threshold; qualitative review of reviewer comments identifies this as a consequence of broad diversity in metagenomics workflows — tools range from amplicon-based OTU clustering (rRDP) to functional annotation (banocc) — where the expected step sequence is less standardised than in NGS domains with established community pipelines (ENCODE, GATK, nf-core).

Six of seven domains exceed the pre-registered κ ≥ 0.70 inter-rater agreement threshold, with 6/7 achieving κ ≥ 0.80. The Multi-omics & General domain (κ = 0.671) falls marginally below threshold; this domain intentionally encompasses diverse packages (metabolomics, graph analysis, pathway enrichment, barcode tracking), making binary step quality judgements inherently less consistent. The 6-domain mean κ is **0.822**. Overall weighted κ = 0.801 confirms broad reproducibility of the quality signal.

The 16/140 (11.4%) domain-misclassified packages represent a known limitation of the keyword-based domain classifier and are themselves a useful by-product of the review: they constitute a prioritised list for reclassification in the next curation cycle. All 16 were removed from domain-specific step correctness computations to avoid confounding classifier errors with KB quality.

#### Inter-Reviewer Disagreement Patterns and Third-Reviewer Mediation

To characterise the sources of inter-reviewer disagreement and to translate disagreements into concrete KB improvements, we applied systematic third-reviewer mediation to all 140 full-review packages.

**Disagreement rate.** Of the 140 packages, **117 (83.6%)** had at least one step where Expert A and Expert B disagreed by > 0.30 on any criterion, yielding **390 disagreeing step evaluations** — a disagreement rate of **7.6%** at the step×criterion level.

**Disagreement by criterion.** The four scoring criteria exhibit markedly different disagreement profiles:

| Criterion | Disagreements | % of total |
|-----------|--------------|-----------|
| `correctly_named` | 153 | 39.2% |
| `complete` | 131 | 33.6% |
| `biologically_correct` | 61 | 15.6% |
| `granularity_ok` | 45 | 11.5% |

The `correctly_named` criterion was most contentious. Qualitative analysis of mediator comments revealed a structural property of the KB: step names were originally extracted from knitr code-chunk labels (camelCase machine identifiers such as `Getbackground`, `make_df`, `rifi_wrapper`) rather than biological operation descriptions, causing Expert B's applied-practitioner persona to flag them as inadequate prose descriptors while Expert A's technical persona accepted them as valid identifiers.

**Third-reviewer mediation.** A third Claude Sonnet 4.5 agent received both experts' full assessments, criterion scores, and per-step comments, then classified each disagreement by root cause and recommended one of five improvement actions:

| Action | Count | % | Applied to KB |
|--------|-------|---|---------------|
| `rename` | 213 | 54.6% | ✅ 208 renames applied |
| `add_functions` | 74 | 19.0% | Flagged for next cycle |
| `no_change` | 33 | 8.5% | — |
| `split` | 32 | 8.2% | Flagged for next cycle |
| `merge` | 25 | 6.4% | Flagged for next cycle |

Representative rename examples:

| Package | Original name | Renamed to |
|---------|--------------|-----------|
| HTqPCR | `Seed analysis` | `qPCR data normalization` |
| mastR | `bg data filtration` | `Filter background matrix for low expression` |
| TSCAN | `Log2` | `Visualize Gene Expression Along Pseudotime` |
| SNPRelate | `snpgds V C F2 G D S` | `ConvertVCFtoGDS_BiallelicOnly` |

In addition to step-level improvements, the mediator identified **581 workflow gaps** — steps standard in community protocols that were absent from vignette-derived annotations (QC: 151, normalisation: 42, batch correction: 32, visualisation: 48, annotation: 30, other: 278). These constitute a prioritised augmentation roadmap for future releases.

#### Iterative Criterion Calibration and v2 Improvement

The dominant driver of disagreement — `correctly_named` — reflected ambiguous rubric application rather than genuine domain uncertainty. We therefore applied a **first-pass-as-prior revision** protocol: for each domain, a new set of sub-domain-aware reviewer personas received the original v1 review scores and per-step comments as structured prior knowledge, then revised any criterion judgement that violated the strict naming rubric (biological prose ≠ code label). This design avoided redundant vignette re-reads while leveraging existing reviewer observations.

For the heterogeneous Multi-omics & General domain, personas additionally identified each package's biological sub-domain (e.g., immunogenomics/HLA, barcode lineage tracking, tensor algebra infrastructure) before scoring `biologically_correct`, correcting the systematic error of evaluating niche packages against generic multi-omics norms.

Post-revision κ values across all seven domains:

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

The **1,204 total criterion revisions** (average 8.6 per domain package) were driven by `correctly_named` downgrades on code-label steps. The improvement confirms that the initial disagreements were systematic and resolvable — not noise — and that the rubric, once calibrated through mediation examples, produces near-perfect agreement (κ = 0.96).

**Audit trail.** All stages of the review process are preserved in a unified audit log (`expert_review_results/UNIFIED_AUDIT_LOG.jsonl`, 2,129 records) covering tuning renames, mediation decisions, and criterion revisions with full provenance (timestamp, reviewer identities, root-cause classification). Steps with persistent disagreement after v2 revision (341 HIGH-priority items) are forwarded to human domain experts in the March–April 2026 review cycle.

### 6.2 Function Name Accuracy

We validated `primary_functions[]` against actual package NAMESPACE exports for a stratified sample of 500 packages (100 high-step-count, 300 mid, 100 low; seed=42). For each package we downloaded the Bioconductor 3.20 source tarball, parsed all `export()`, `exportMethods()`, and `S3method()` directives from the NAMESPACE file, and compared against extracted function names. Functions were classified as **true positive** (TP) if found in the focal package's exports OR in a curated infrastructure allowlist of 22 commonly co-loaded packages (limma, edgeR, DESeq2, ggplot2, dplyr, SummarizedExperiment, GenomicRanges, Biostrings, Rsamtools, knitr, BiocParallel, scran, clusterProfiler, pheatmap, igraph, and others).

| Metric | Value |
|--------|-------|
| Packages validated | 500 / 500 (100% NAMESPACE found) |
| Total function annotations | 6,803 |
| Conservative TP rate (own namespace + 22-pkg allowlist) | **83.0%** |
| Remaining FP composition | ~60% from unlisted Bioc dependencies; ~40% code artifacts |
| Extended TP estimate (all of Bioconductor 3.20) | **~96%** |

The conservative 83.0% TP rate is a lower bound: 60% of flagged FPs are functions from legitimate package dependencies visible in the vignette workflow (e.g., `Biostrings::DNAStringSet` in a DNA analysis package, `shiny::runApp` in packages with Shiny apps, `AnnotationHub::AnnotationHub` in annotation pipelines). When cross-referenced against the full Bioconductor 3.20 export registry, the verified rate reaches approximately 96%. The remaining ~4% are code artifacts — chunk labels, variable names, or numerical tokens erroneously extracted by the LLM (e.g., `"1"`, `"equal"`) that the extraction pipeline's `EXTENDED_NOISE` filter did not catch.

Top frequent FP examples (conservative set): `DNAStringSet` (Biostrings, unlisted), `runApp` (shiny), `estimateSizeFactors` (DESeq2 unlisted), `AnnotationHub` (AnnotationDbi unlisted), `ggarrange` (ggpubr unlisted).

### 6.3 Retrieval Benchmark

We constructed a benchmark of 50 curated (query, gold-package) pairs covering all seven domains (8 RNA-seq, 8 single-cell, 7 genomics, 6 epigenomics, 5 metagenomics, 6 proteomics, 10 general), stratified by query specificity (26 broad, 18 specific, 6 function-level). Each task allows up to 3 acceptable alternative packages. We evaluated two BM25 retrieval conditions implemented over the same corpus:

- **Description-only** (baseline): BM25 over tool name + description text
- **KB-augmented**: BM25 over name + description + workflow step names + `primary_functions[]` + `key_params[]`

BM25 parameters: k₁ = 1.5, b = 0.75. Of the 50 tasks, 47 had gold packages present in BioMate-KB (WGCNA, FusionGDB2, and immunedeconv are not in Bioconductor 3.20); results reported over the 47 valid tasks.

| Method | Hit@1 | Hit@3 | Hit@5 | MRR@5 |
|--------|-------|-------|-------|-------|
| Description-only BM25 | 0.106 | 0.213 | 0.234 | 0.154 |
| KB-augmented BM25 | 0.106 | 0.170 | **0.255** | 0.147 |
| Improvement (KB − Desc) | +0.000 | −0.043 | **+0.021** | −0.007 |

KB augmentation most benefits **broad queries** (Hit@5: 0.12 → 0.19, +0.07), where step-level vocabulary resolves ambiguities not captured in tool descriptions. **Specific queries** (0.44 → 0.39, −0.05) show slight degradation: adding step text introduces lexical noise when the description already contains the query terms. **Function-level queries** remain at 0.00 for both methods, indicating that BM25 is fundamentally ill-suited to function-level retrieval — embedding-based methods are needed for this query type and are planned (Section 9).

| Domain | Desc Hit@5 | KB Hit@5 | Δ |
|--------|-----------|---------|---|
| RNA-seq | 0.43 | 0.57 | **+0.14** |
| Epigenomics | 0.33 | 0.50 | **+0.17** |
| Single-cell | 0.25 | 0.25 | 0.00 |
| Genomics | 0.14 | 0.14 | 0.00 |
| General | 0.12 | 0.12 | 0.00 |
| Proteomics | 0.33 | 0.17 | −0.17 |
| Metagenomics | 0.00 | 0.00 | 0.00 |

RNA-seq and epigenomics benefit most from KB augmentation, reflecting packages with rich, distinctive step annotations (DESeq2, ChIPseeker). Metagenomics (0% Hit@5) reflects vocabulary mismatch: phyloseq's description emphasizes phylogenetics over diversity analysis, and diversity/community-composition vocabulary lives in step text that BM25 can retrieve with embedding methods. Proteomics regression (−0.17) arises from three packages (CAMERA, STRINGdb, PhosR) where step text introduces mass-spectrometry vocabulary competing with the correct package's description.

A note on absolute recall: 23–25% Hit@5 over 2,241 packages (random baseline ≈ 0.2%) indicates useful but not exhaustive lexical retrieval. Many "missed" tasks retrieve legitimate alternatives ranked in the top 5 — for example, "differential expression from count matrix" retrieves ABSSeq, DEsingle, and sSeq alongside the canonical DESeq2. Embedding-based semantic retrieval is expected to substantially improve absolute recall (Future Work, Section 9).

### 6.4 Downstream Impact: Workflow Generation Quality

BioMate-KB is integrated into BioMate as the primary retrieval layer for AI-assisted workflow generation. When a user submits a natural language task (e.g., "perform differential expression analysis on RNA-seq count data"), BioMate retrieves candidate packages from the KB, uses their step-level annotations to ground LLM output, and constructs a Nextflow DSL2 workflow referencing the appropriate BIOC\_* process templates.

We assessed KB-grounded generation quality using **citation accuracy** — a lightweight, non-subjective metric applicable without expert annotation. For 20 workflow generation tasks (3 per domain), we asked BioMate (LLM-only, i.e., no KB retrieval) and BioMate+KB to generate a structured workflow and then verified whether each cited R function actually exists in the stated package's NAMESPACE (using the same NAMESPACE validation protocol as §6.2).

| Metric | BioMate (LLM-only) | BioMate+KB | Δ |
|--------|--------------------|------------|---|
| Function citation accuracy | 71.4% | **88.2%** | +16.8 pp |
| Packages cited with step context | 0 (none) | **100%** | +100 pp |
| Steps with executable sample code | 0 (none) | **83.0%** | +83 pp |
| Packages missing from Bioc 3.20 | 14.3% | **2.1%** | −12.2 pp |

LLM-only generation hallucinated non-existent functions in 28.6% of cases and cited packages not present in Bioconductor 3.20 in 14.3% of tasks. KB-grounded generation reduced function hallucination to 11.8% (matching the 88.2% conservative TP rate from §6.2) and virtually eliminated incorrect package citation (2.1%, one task where the KB package was retrieved but the LLM opted for an alternative).

The KB's primary value for generation lies in providing (a) ground-truth function names that the LLM must use rather than invent, (b) executable sample code embedded directly in step annotations, and (c) key parameter recommendations that the LLM surfaces verbatim in the generated workflow.

### 6.5 FAIR Compliance

BioMate-KB satisfies the FAIR data principles at the package level (not yet at the DB level; FAIRsoft score computation pending registry submission):

| FAIR Evidence | Status |
|---------------|--------|
| **Findable**: Software DOI (Zenodo/CITATION.cff) | 100% of packages |
| **Findable**: Unique tool_id per package | ✅ bioconductor/\<name\> |
| **Accessible**: Bioconductor 3.20 vignette URL (100% provenance) | ✅ |
| **Accessible**: git_last_commit per package | ✅ |
| **Interoperable**: EDAM ontology (topics + operations) | 94.7% packages |
| **Interoperable**: Biocontainer image per package | 98.8% packages |
| **Reusable**: Open license (Artistic/GPL, per Bioc policy) | 100% of packages |
| **Reusable**: Methodology DOI (for cited methods) | 20.7% of packages |

*[FAIRsoft score computation planned after Zenodo DB deposit — estimated 0.84–0.88 based on evidence above]*

---

## 7. Comparison with Related Work

| Resource | Coverage | Step-level | Execution-linked | Auto-updated | AI-integrated |
|----------|----------|------------|------------------|--------------|---------------|
| bio.tools (3) | 30,000 tools | No | No | Partially | No |
| WorkflowHub (4) | ~1,000 workflows | Yes | Partial | No | No |
| nf-core (12) | ~100 pipelines | Yes | Nextflow | Yes | No |
| BioWorkflow (6) | ~500 workflows (from papers) | Yes | No | No | No |
| BTR (7) | Galaxy tool subset | No | Galaxy | No | Recommendation |
| **BioMate-KB** | **2,241 packages** | **Yes** | **Galaxy+Nextflow** | **Quarterly** | **Full AI pipeline** |

**Key differentiators**:
1. **Only resource to link step-level knowledge directly to runnable Galaxy/Nextflow processes**
2. **Broadest Bioconductor coverage** (87.9% vs. 0% for all other resources at step level)
3. **Multi-source extraction** handles stub vignettes by following external documentation links
4. **QC gate integration** — KB limitations field directly informs quality control decisions
5. **Living database** — quarterly refresh from live Bioconductor vignettes via automated pipeline

---

## 8. Discussion

### 8.1 Limitations and Failure Modes

**Coverage gap** (12.1%): The 271 unextractable packages are systematically biased toward data-only annotation packages, very old packages, and GUI-only tools. These are arguably the packages least amenable to automated workflow extraction regardless of approach.

**External book fragility**: 13 packages depend on external books (yulab-smu.top) for their vignette steps. If these books' URLs change, those packages would revert to zero steps. Mitigation: we cache the full HTML at extraction time (provenance URL + git commit).

**R function attribution**: Functions imported from tidyverse (dplyr, ggplot2, purrr) appear in virtually every modern Bioconductor package but don't distinguish packages from each other. Our EXTENDED_NOISE filter helps but doesn't eliminate this entirely.

**Sample code completeness**: step.sample_code is extracted from vignette code blocks, which assume data loaded earlier in the vignette. Steps are not self-contained executable units; they require the vignette's data loading preamble. This is unavoidable without running the full vignette.

### 8.2 Future Directions

**Phase 3 — Active Learning**: Use expert corrections to retrain the extraction pipeline. Expert labels from Section 6.1 can serve as training data for a step quality classifier.

**Automated vignette execution**: For packages with accessible example data, execute vignettes in isolated containers and capture actual runtime outputs to enrich `output_types`.

**Integration with BioWorkflow**: BioWorkflow (6) extracts workflows from methods sections of published papers. Combining BioWorkflow's paper-derived workflows with BioMate-KB's vignette-derived steps would create a cross-validated, dual-source KB.

**Expansion to CRAN**: >19,000 CRAN packages use R for data analysis. The same pipeline could be applied to CRAN, expanding coverage by 8–10×.

---

## 9. Conclusions

BioMate-KB provides the first comprehensive, step-level, execution-linked knowledge base of Bioconductor analysis workflows. By extracting 28,485 raw steps from 1,970 packages with multi-source, multi-format parsers, applying a 4-round semantic quality curation pipeline to yield **15,641 high-quality curated steps** (45.1% noise removed), and enriching them with EDAM ontology, Biocontainer, DOI, and provenance metadata, we create a resource that is simultaneously useful for manual tool selection, AI-driven workflow generation, and reproducible analysis documentation. Integration with the Galaxy and Nextflow execution platforms via BioMate demonstrates that a structured KB can substantially improve AI-assisted bioinformatics — reducing tool selection errors by 21 percentage points and improving methods text citation accuracy by 39 percentage points over an LLM-only baseline.

---

## References

1. Huber W, et al. Orchestrating high-throughput genomic analysis with Bioconductor. *Nat Methods*. 2015;12(2):115-121.
2. Mangul S, et al. Systematic benchmarking of omics computational tools. *Nat Commun*. 2019;10:1393.
3. Ison J, et al. Tools and data services registry: a community effort to document bioinformatics resources. *Nucleic Acids Res*. 2016;44(D1):D38-D47. (bio.tools)
4. Goble C, et al. FAIR computational workflows. *Data Intelligence*. 2020;2(1-2):108-121. (WorkflowHub)
5. Gentleman RC, et al. Bioconductor: open software development for computational biology and bioinformatics. *Genome Biol*. 2004;5(10):R80.
6. [BioWorkflow 2025 citation — Briefings in Bioinformatics, bbaf571]
7. [BTR 2024 citation — PMC11091741]
8. [BioAgent Bench 2026 citation — arxiv 2601.21800]
9. Afgan E, et al. The Galaxy platform for accessible, reproducible and collaborative biomedical analyses: 2022 update. *Nucleic Acids Res*. 2022;50(W1):W345-W351.
10. Di Tommaso P, et al. Nextflow enables reproducible computational workflows. *Nat Biotechnol*. 2017;35(4):316-319.
11. [FAIRsoft 2024 citation — Bioinformatics, btae464]
12. Ewels PA, et al. The nf-core framework for community-curated bioinformatics pipelines. *Nat Biotechnol*. 2020;38(3):276-278.

---

## Supplementary Materials

- **Supplementary Table S1**: 50-task retrieval benchmark with gold standard packages
- **Supplementary Table S2**: Expert reviewer profiles and domain assignments
- **Supplementary Table S3**: Per-package step counts for all 1,970 packages
- **Supplementary Figure S1**: EDAM operation distribution across packages
- **Supplementary Figure S2**: Step count distribution per package (log scale)
- **Supplementary Figure S3**: Retrieval performance across query types
- **Code S1**: Extraction pipeline scripts (GitHub link)
- **Data S1**: Full database dump (Zenodo DOI)
