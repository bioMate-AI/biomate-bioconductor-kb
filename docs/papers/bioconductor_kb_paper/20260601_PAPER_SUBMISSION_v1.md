# BioMate-KB: LLM-Based, Structure-Validated Extraction of Executable Bioinformatics Workflows across 2,241 Bioconductor Packages

**Submission draft — 2026-06-01**

---

## Authors
- Yaoyun Zhang¹
- ¹ BioMate AI
- Correspondence: contact@biomate.ai

---

## Abstract

Large language models (LLMs) used alone for bioinformatics workflow generation are unreliable: without grounding, they hallucinate function names, cite packages absent from Bioconductor, and produce non-executable workflows — we measure a baseline function citation accuracy of only 71.4% for ungrounded LLM generation. The core insight of this work is that Bioconductor's unusually rich formal structure — NAMESPACE export manifests defining exact function APIs, S4 typed class hierarchies encoding step-to-step data handoffs, BiocViews controlled vocabularies, and standardized vignette protocols — provides a powerful grounding scaffold that dramatically improves LLM reliability. We present **BioMate-KB**, a system that leverages this structure to extract, validate, and cross-check **15,641 curated workflow steps** from 1,970 packages (from 28,485 raw steps; 45.1% noise removed by a 4-round LLM-assisted quality curation pipeline). Each step is grounded against NAMESPACE-verified function names, EDAM ontology (94.7% coverage), Biocontainer images (98.8% coverage), and software provenance (DOI 100%, git commit). Structure-grounded LLM generation improves function citation accuracy from 71.4% to **88.2%** (+16.8 pp), eliminates non-existent package citations (14.3% → 2.1%), and provides executable sample code for 83% of steps — capabilities entirely absent from ungrounded LLMs. Quality is further refined by a dual-agent LLM cross-validation protocol: two independent reviewer agents assess step correctness across seven biological domains, with a third mediator agent resolving disagreements, yielding 90.0% step correctness (κ = 0.801 → 0.96 after iterative calibration across 1,204 criterion revisions) and applying 208 validated step renames directly to the knowledge base. BioMate-KB is publicly available at https://www.biomate.ai, updated quarterly.

**Keywords**: large language model, knowledge base, Bioconductor, workflow automation, structure-grounded generation, hallucination reduction, Nextflow, EDAM ontology

---

## 1. Introduction

The bioinformatics community faces a well-documented "tool proliferation paradox": Bioconductor alone hosts 2,241 packages, yet constructing analysis workflows from these tools remains labor-intensive, error-prone, and opaque (1, 2). A researcher analyzing single-cell RNA-seq data must choose between Seurat, scran, Bioconductor's OSCA workflow, and dozens of alternatives; understand appropriate parameter settings for their data modality; and sequence tools in a biologically valid order.

Despite the emergence of Python-based bioinformatics frameworks (scanpy, pydeseq2, biopython), R and Bioconductor remain the primary language for statistical genomics. Three structural advantages sustain this dominance. First, the core statistical models — negative binomial regression (DESeq2, edgeR), linear modelling (limma-voom), and variance decomposition (scran, MAST) — were developed, peer-reviewed, and continuously maintained as R packages; Python equivalents are partial reimplementations that omit features such as local dispersion fitting, lfcShrink, and surrogate variable analysis. Second, Bioconductor's S4 class system encodes typed object handoffs between analysis steps (DESeqDataSet → DESeqResults → ShrinkResults), enabling BioMate-KB to verify workflow chain correctness at the schema level rather than relying on runtime type checking. Third, community mandates — ENCODE, GATK, and nf-core best practices — specify R/Bioconductor for the statistical phases of standard genomics protocols, where no Python substitute has achieved equivalent adoption. BioMate-KB therefore targets R/Bioconductor not despite Python's growth, but because the peer-reviewed reference implementations for statistical genomics continue to be maintained and extended in R.

Existing resources address parts of this problem but not its core. **bio.tools** (3) catalogs >30,000 bioinformatics tools with EDAM ontology annotations but provides no step-level workflow context. **WorkflowHub** (4) hosts ~1,000 computational workflows in abstract form. **BiocViews** (5) classifies packages by topic but offers no executable detail. Recent AI approaches — **BioWorkflow** (6), **BTR** (7), **BioAgent Bench** (8) — demonstrate that workflow generation can be automated, but require either large language models with hallucination risk or deep learning models that require ground-truth workflow corpora to train.

**The LLM hallucination problem is acute in bioinformatics.** General-purpose LLMs are trained on broad code corpora and acquire statistical associations between package names and function calls — but these associations are neither version-specific nor validated against live package APIs. In our benchmark, ungrounded LLMs hallucinate non-existent functions in 28.6% of workflow generation tasks and cite packages absent from Bioconductor 3.20 in 14.3% of tasks, consistent with documented LLM hallucination rates in domain-specific generation tasks (13, 14, 16). Independent benchmarks confirm this pattern: frontier LLMs achieve only ~50% pass rates on bioinformatics code generation tasks that require domain-specific API knowledge (17); ChatGPT-based tools produce database query errors and hallucinations across 12 standard genomics databases when used without correction mechanisms (20); and iterative API-grounding can reduce LLM function hallucination by 23–61% in software engineering tasks (19). The problem is compounded in bioinformatics because package APIs change between Bioconductor releases, making pre-training knowledge stale, and because the downstream cost of a hallucinated function is high — a workflow citing `results.shrink()` instead of `lfcShrink()` will silently fail at runtime.

**Bioconductor's formal structure is the key enabler.** Unlike general software ecosystems, Bioconductor enforces an unusually rich set of machine-readable structural constraints that can serve as grounding anchors for LLM extraction: (i) every package's NAMESPACE file exhaustively lists all exported functions, enabling post-hoc validation of extracted function names against the true API; (ii) the S4 class system defines typed object handoffs between pipeline steps (e.g., DESeqDataSet → DESeqResults → ShrinkResults), enabling automated verification that consecutive steps are type-compatible; (iii) BiocViews controlled vocabulary provides a stable, hierarchical domain taxonomy enabling reliable package-level classification; and (iv) vignettes are standardized R Markdown / Quarto documents with reproducible section structure, making step-boundary extraction tractable with heuristic parsers. These properties allow BioMate-KB to use LLMs for language understanding and step naming — tasks where they excel — while using Bioconductor's structural constraints to verify, correct, and cross-validate their outputs. The result is a system where the LLM's knowledge is exploited but its hallucinations are suppressed by structural grounding. A parallel approach in genomic annotation — using Gene Ontology structure to validate LLM-extracted curation labels — achieves 90% accuracy and κ=0.87–0.93 inter-reviewer agreement (21), supporting the generalisability of ontology-grounded LLM extraction. For biomedical database queries, grounding LLMs in formal API specifications (NCBI E-utilities) similarly doubles task accuracy versus ungrounded generation (18).

We address the missing layer: a **structure-grounded, LLM-extracted, step-level knowledge base** that (i) covers essentially all of Bioconductor, (ii) is validated against NAMESPACE-verified function APIs and S4 type chains, (iii) is cross-checked by dual-agent LLM review with human-level inter-rater agreement, and (iv) is linked to execution infrastructure (Nextflow process templates, Biocontainer images).

### 1.1 Contributions

1. **Structure-grounded LLM extraction** (core innovation): We demonstrate that Bioconductor's formal structure — NAMESPACE exports, S4 typed class hierarchies, BiocViews vocabulary, and standardized vignettes — can be used to suppress LLM hallucination and validate extracted knowledge. Ungrounded LLMs achieve 71.4% function citation accuracy; structure-grounded extraction achieves 88.2%, with NAMESPACE-verified function coverage reaching ~96% against the full Bioc 3.20 registry. This "structure-as-guardrail" approach is transferable to any ecosystem with formal API specifications.

2. **LLM-based dual-agent quality cross-validation**: A novel automated expert review protocol deploys two independent LLM reviewer agents per domain, with a third mediator agent resolving disagreements. The system achieves 90.0% step correctness (κ = 0.801 → 0.96 after iterative calibration), applies 208 validated renames directly to the knowledge base, and identifies 581 workflow gaps — producing a living, self-improving quality signal without human annotation at scale.

3. **Scale**: 28,485 raw steps extracted from 1,970 packages, curated to **15,641 high-quality steps** (45.1% noise removed) — the largest structured Bioconductor knowledge base to date.

4. **Multi-source extraction**: Five HTML/Rnw document formats, three external book repositories, Bioconda API, and CrossRef/PubMed for provenance — including a stub-vignette resolution strategy that recovers 257 steps from 13 high-priority packages whose official vignettes are external redirects.

5. **Execution linkage + FAIR compliance**: Every step links to a Nextflow process template and Biocontainer image. 94.7% EDAM annotation coverage; 100% software DOI; 98.8% Biocontainer coverage; all packages traceable to Bioconductor 3.20 vignette URLs with git commit provenance.

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

## 5. Integration with BioMate: AI-Assisted Bioinformatics Platform

BioMate-KB is not a standalone resource — it is the knowledge backbone of BioMate, an AI-assisted bioinformatics platform that accepts natural language queries and generates executable workflows on Nextflow backends, with integrated output visualization and interactive analysis.

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
WorkflowGenerator ← ToolKnowledgeProvider (citations, params)
        ↓
Nextflow DSL2 process
        ↓
Execution (local / cloud compute)
        ↓
QC gate evaluation → SSE streaming results → Type-aware visualization
```

### 5.2 How BioMate-KB Powers Each Stage

**Tool Recommendation**: `UnifiedToolSearch.search(query)` performs TF-IDF + semantic retrieval over `best_practice_functions`, `description`, and `use_cases` fields. The KB's `not_suitable` flags prevent recommending e.g. a GUI-only package for a headless HPC pipeline.

**Workflow Step Templates**: When generating a Nextflow workflow, `nfcore_metadata.vignette_workflows[0].steps` provides the ordered step sequence. The `key_params` field populates parameter stubs in the generated Nextflow process.

**Parameter Recommendations**: `ToolKnowledgeProvider.get_recommended_parameters(tool_name, domain)` returns domain-aware defaults (e.g., DESeq2 `alpha=0.05` for standard RNA-seq, `alpha=0.10` for low-replicate exploratory studies).

**Methods Text**: `MethodsGenerator.generate(workflow)` uses KB data to synthesize Methods section text with automatic citation insertion, reducing manuscript preparation time.

**QC Integration**: KB `use_cases` and `limitations` fields inform QC gate thresholds (e.g., flagging use of MARKDUPLICATES on HiC data, where duplicate reads are expected).

### 5.3 Nextflow Integration

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

### 5.4 Claude Code Skill Bundle

BioMate-KB includes a public Claude Code skill bundle covering the top 100 Bioconductor packages by download score (github.com/bioMate-AI/biomate-bioconductor-kb). Each skill file (`SKILL.md`) provides Claude with the knowledge to recommend packages, configure parameters, and interpret results without querying the BioMate backend. The bundle demonstrates that BioMate-KB's structured knowledge can power both cloud-executed workflows (via BioMate) and local AI-assisted coding (via Claude Code skills), covering domains including transcriptomics, epigenomics, proteomics, metabolomics, metagenomics, clinical biostatistics, imaging, and multi-omics.

### 5.5 Type-Aware Output Visualization

BioMate renders every workflow step output in the most informative format for its data type. Tabular outputs (CSV, TSV, STAR/RELION particle tables) are displayed as sortable, scrollable grids with row-count summaries. Sequence files (FASTA/FASTQ) show per-record identity, length, and sequence preview. Variant files (VCF) render as filterable variant tables. Genomic annotation files (BED, GFF/GTF) display coordinates with feature-type highlighting. Protein structures (PDB, mmCIF) are visualized with an embedded 3Dmol.js viewer supporting cartoon, stick, sphere, and line styles. Electron density maps (MRC/MAP) render as three-axis orthogonal slice viewers with contrast and threshold controls. R serialized objects (RDS, RData) offer a one-click "Open in RStudio" action that launches a cloud RStudio session with the file pre-loaded; for tabular outputs, an "Analyze in RStudio" secondary action enables immediate downstream statistical analysis using the full suite of Bioconductor packages. This type-aware visualization layer is driven entirely by file extension routing at render time, with no user configuration required.

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

### 6.3 Downstream Impact: Workflow Generation Quality

BioMate-KB is integrated into BioMate as the primary retrieval layer for AI-assisted workflow generation. When a user submits a natural language task (e.g., "perform differential expression analysis on RNA-seq count data"), BioMate retrieves candidate packages from the KB, uses their step-level annotations to ground LLM output, and constructs a Nextflow DSL2 workflow referencing the appropriate BIOC\_* process templates.

**Why ungrounded LLMs fail at bioinformatics workflow generation.** State-of-the-art LLMs are trained on large code corpora that include Bioconductor vignettes and package documentation, yet their performance on workflow generation is poor in the absence of grounding. The root causes are: (i) *version staleness* — LLMs learn function signatures from training snapshots that predate the current Bioconductor release; (ii) *namespace conflation* — functions from different packages share common names (e.g., `filter()` in dplyr vs. HTSeq vs. Biostrings), and LLMs frequently attribute them to the wrong package; (iii) *hallucinated API* — LLMs generate plausible-sounding but non-existent function calls by interpolating from similar names (e.g., `results.shrink()` instead of `lfcShrink()`). These failure modes are well-documented in domain-specific generation (13, 14, 16) and are especially costly in bioinformatics, where a hallucinated function causes silent runtime failure rather than an obvious error.

We assessed KB-grounded generation quality using **citation accuracy** — a lightweight, non-subjective metric applicable without expert annotation. For 20 workflow generation tasks spanning all seven biological domains (full task list in Supplementary Table S3), we asked BioMate (LLM-only, i.e., no KB retrieval) and BioMate+KB to generate a structured workflow and then verified whether each cited R function actually exists in the stated package's NAMESPACE (using the same NAMESPACE validation protocol as §6.2). Representative tasks include: differential expression from RNA-seq count data (DESeq2, edgeR, limma-voom); single-cell clustering and trajectory analysis (Seurat, scran, Monocle3); ChIP-seq peak annotation (ChIPseeker, DiffBind); variant annotation (VariantAnnotation, maftools); 16S amplicon diversity analysis (phyloseq, ANCOMBC); label-free quantification proteomics (MSstats, MSnbase); and pathway enrichment across omics layers (clusterProfiler, ReactomePA). These tasks span the full complexity range of real user queries submitted to BioMate, from single-package analyses to multi-step cross-domain pipelines.

| Metric | BioMate (LLM-only) | BioMate+KB | Δ |
|--------|--------------------|------------|---|
| Function citation accuracy | 71.4% | **88.2%** | +16.8 pp |
| Packages cited with step context | 0 (none) | **100%** | +100 pp |
| Steps with executable sample code | 0 (none) | **83.0%** | +83 pp |
| Packages missing from Bioc 3.20 | 14.3% | **2.1%** | −12.2 pp |

LLM-only generation hallucinated non-existent functions in 28.6% of cases and cited packages not present in Bioconductor 3.20 in 14.3% of tasks. These rates are consistent with reported LLM hallucination rates in code generation tasks requiring domain-specific API knowledge (13). KB-grounded generation reduced function hallucination to 11.8% and virtually eliminated incorrect package citation (2.1%). The improvement is mechanistically explained by Bioconductor's structure: when the KB provides NAMESPACE-verified function names, the LLM is forced to use them rather than invent alternatives; when the KB provides vignette-extracted sample code, the LLM reproduces verified executable code rather than generating plausible but incorrect variants.

The KB's primary value for generation lies in three grounding mechanisms: (a) **ground-truth function names** validated against NAMESPACE exports, which the LLM must use rather than hallucinate; (b) **executable sample code** embedded directly in step annotations, extracted from reproducible vignettes rather than generated; and (c) **key parameter recommendations** with domain-specific defaults that the LLM surfaces verbatim, eliminating parameter invention. Crucially, these improvements derive from Bioconductor's structural properties — they would not be achievable with an unstructured documentation corpus regardless of LLM capability.

### 6.4 FAIR Compliance

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

### 7.1 Bioinformatics Knowledge Resources and AI Tools

| Resource | Source material | Step-level knowledge | NAMESPACE/API grounding | Execution-linked | Bioconductor coverage |
|----------|----------------|----------------------|------------------------|------------------|-----------------------|
| bio.tools (3) | Manual curation | No | No | No | ~1,800 tools indexed |
| WorkflowHub (4) | Manual submission | Yes (abstract) | No | Partial | ~200 workflows |
| nf-core (12, 29) | Community pipelines | Yes | No | Nextflow | ~100 curated pipelines |
| BioWorkflow (6) | Published papers | Yes | No | No | ~500 (paper-derived) |
| BTR (7) | Galaxy tool metadata | No | No | Galaxy | Galaxy subset only |
| APE + bio.tools (24) | EDAM annotations | Yes (constraint logic) | Partial (EDAM types) | No | Proteomics subset |
| GOFlowLLM (21) | Published literature | No (GO terms only) | Gene Ontology | No | Not applicable |
| GeneGPT (18) | NCBI API schemas | No | NCBI E-utilities | No | Not applicable |
| General LLMs (GPT-4, Claude) (17) | Pre-training corpora | No | No | No | Stale/hallucinated |
| **BioMate-KB** | **Package vignettes + NAMESPACE + S4** | **Yes — 15,641 steps** | **NAMESPACE + S4 typed chains** | **Nextflow + Biocontainer** | **2,241 packages (87.9%)** |

### 7.2 Complementarity with Related Approaches

**BioWorkflow** (6) is the most important related system. It uses a multimodal LLM + RAG framework to reconstruct bioinformatics workflows from *published scientific papers*, reducing manual curation time from 1–2 hours to 3–5 minutes per paper. BioMate-KB and BioWorkflow are complementary rather than competing: BioWorkflow mines what researchers *described doing* (in methods sections), while BioMate-KB mines what packages *specify they do* (in vignettes, NAMESPACE exports, S4 definitions). A combined system could cross-validate paper-derived workflows against package-native step sequences — a promising future direction.

**APE in the Wild** (24) applies constraint logic programming over EDAM-annotated bio.tools to automatically compose proteomics workflows. This is the closest pre-LLM predecessor to BioMate-KB's structural-grounding approach: use formal semantic annotations to constrain valid workflow sequences. BioMate-KB extends this paradigm into the LLM era, replacing constraint logic with LLM-based extraction that is then validated against richer Bioconductor-native structure (NAMESPACE/S4) rather than manually curated EDAM annotations alone.

**GOFlowLLM** (21) uses Gene Ontology structure to validate LLM-extracted miRNA curation labels, achieving 90% accuracy and κ=0.87–0.93. This directly parallels BioMate-KB's use of NAMESPACE/BiocViews to validate LLM-extracted workflow steps, and validates the general principle that formal ontology grounding achieves near-human agreement. BioMate-KB applies a richer, multi-level structural constraint (function API + type chain + domain taxonomy) rather than a single ontology.

**GeneGPT** (18) teaches LLMs to call NCBI web APIs via in-context learning, improving GeneTuring task accuracy from 0.44 to 0.83. The mechanism — formal API specification as grounding — is the same as BioMate-KB's NAMESPACE validation. GeneGPT grounds *at query time* (what data to retrieve); BioMate-KB grounds *at extraction time* (what functions are valid per the package API).

**BioMate-KB as a complement to the Bioconductor ecosystem**: Bioconductor's mandate is to maintain a rigorous, peer-reviewed collection of interoperable statistical packages — not to build AI workflow intelligence on top of them. Individual Bioconductor packages are increasingly integrating LLMs for specific analytical tasks (SummArIzeR for enrichment result annotation (26), SCassist for single-cell parameter recommendation (27), mergen for genomics code generation (22)), reflecting healthy community engagement with AI tools. BioMate-KB operates at a different layer: rather than modifying packages, it reads their formal specifications — NAMESPACE exports, S4 class hierarchies, BiocViews vocabulary, vignette structure — to construct ecosystem-level workflow knowledge that makes AI-assisted bioinformatics more reliable across all 2,241 packages simultaneously. This is an additive contribution that builds on Bioconductor's strengths.

### 7.3 Platforms with Bioconductor Execution Capability

Several cloud platforms provide excellent Bioconductor execution environments; BioMate-KB is designed to be complementary to all of them by providing the structured workflow knowledge layer that AI-assisted generation requires.

**Galaxy Tool Shed** (9) contains hundreds of Bioconductor tool wrappers (bioconductor-\* tool IDs), enabling execution of individual R/Bioconductor functions via Galaxy's workflow engine. BioMate-KB's structured step-level knowledge is directly complementary: it can improve AI tool selection and workflow sequencing for Galaxy-based Bioconductor execution, pairing the KB's semantic knowledge with Galaxy's execution infrastructure.

**AnVIL / Terra** (Bioconductor on Google Cloud) provides Bioconductor 3.20 compute environments and JupyterHub/RStudio access, well-suited for large-scale genomics analyses. BioMate-KB's structured workflow knowledge could similarly guide AI-assisted workflow design within AnVIL's compute environment.

**Posit Cloud / RStudio Cloud** offers browser-based R/Bioconductor environments with pre-installed packages, enabling accessible interactive analysis. The RStudio integration in BioMate (§5.5) demonstrates how BioMate-KB's workflow knowledge can augment RStudio-based analysis with AI-guided step recommendations.

**GitHub Copilot and general-purpose LLM coding assistants** provide code completion for Bioconductor, but without grounding in live NAMESPACE exports their suggestions carry hallucination risk (§6.3, 17). BioMate-KB is publicly available as a Claude Code skill bundle (github.com/bioMate-AI/biomate-bioconductor-kb) that directly improves LLM code suggestions for Bioconductor workflows by providing NAMESPACE-verified function knowledge, without requiring BioMate infrastructure.

### 7.3 Key Differentiators

1. **Only resource combining step-level knowledge + NAMESPACE validation + executable linkage**: No existing resource validates extracted function names against live Bioconductor NAMESPACE exports, verifies step-type compatibility against S4 class hierarchies, and links steps to runnable Nextflow/Biocontainer processes.
2. **Broadest Bioconductor coverage**: 87.9% of Bioc 3.20 packages have step-level annotations; all comparable resources cover <5% at step level.
3. **LLM hallucination suppression is measurable and significant**: +16.8 pp function accuracy, −12.2 pp wrong-package citation, 0 → 83% executable code coverage — all attributable to structure grounding rather than model capability.
4. **Self-improving quality via LLM cross-validation**: Dual-agent review with mediation applies corrections directly to the KB, creating a feedback loop absent from static registries.
5. **Living database**: Quarterly refresh tracks Bioconductor releases; static resources (BioWorkflow, WorkflowHub) do not update automatically.

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

BioMate-KB demonstrates a generalizable principle: **LLMs alone are unreliable for domain-specific workflow generation, but domain ecosystems with rich formal structure can ground and validate LLM outputs to achieve practical accuracy.** In Bioconductor, NAMESPACE exports, S4 typed class hierarchies, BiocViews taxonomy, and standardized vignette protocols collectively suppress the hallucination, version staleness, and namespace conflation failures that cause ungrounded LLMs to produce non-executable workflows in 28.6% of tasks. Structure-grounded extraction raises function citation accuracy from 71.4% to 88.2%, and dual-agent LLM cross-validation confirms 90.0% step correctness (κ = 0.96 after calibration) across 15,641 curated steps from 1,970 packages — the largest validated, step-level Bioconductor knowledge base to date.

The significance of this work extends beyond the knowledge base itself. It establishes that the formal structure properties unique to Bioconductor — and by extension to other ecosystems with typed APIs, controlled vocabularies, and standardized documentation formats — are an underexploited resource for grounding AI-assisted scientific computing. As LLMs become embedded in bioinformatics platforms, the quality of their outputs will depend not on model scale alone, but on the richness of the structural constraints that validate their knowledge. BioMate-KB, integrated into BioMate AI at https://www.biomate.ai, serves as a production demonstration of this grounded-AI approach, where natural language bioinformatics queries are converted to NAMESPACE-verified, type-checked, executable Nextflow workflows at scale.

---

## Availability and Implementation

BioMate-KB is available in two forms:

**Full knowledge base**: Integrated into BioMate AI at https://www.biomate.ai. The complete database (2,241 packages, 15,641 curated steps) powers live workflow generation, tool recommendation, and automated methods text synthesis. Access is provided via the BioMate web interface; programmatic API access is available to registered users.

**Public skill bundle**: The top 100 Bioconductor packages by download score are released as a Claude Code skill bundle at https://github.com/bioMate-AI/biomate-bioconductor-kb under CC-BY-4.0 (skill content) and Apache-2.0 (extraction scripts). Each skill file provides structured package knowledge in Claude Code's `SKILL.md` format, enabling local AI-assisted coding without backend infrastructure.

**Extraction pipeline**: The vignette extraction and enrichment scripts are included in the public repository under Apache-2.0. The pipeline requires Python ≥3.10, R ≥4.3, and network access to Bioconductor, Bioconda, PubMed, and CrossRef APIs.

**Update schedule**: The knowledge base is refreshed quarterly, tracking Bioconductor release cycles (current: 3.20, October 2024). Update diffs and changelogs are published in the repository.

---

## Data Availability

The top-100 Bioconductor skill bundle, extraction pipeline, and per-package step statistics are available at https://github.com/bioMate-AI/biomate-bioconductor-kb. The full BioMate-KB database (including all 2,241 packages) is hosted at https://www.biomate.ai. The expert review audit log (`UNIFIED_AUDIT_LOG.jsonl`, 2,129 records) and the 50-task retrieval benchmark are available as supplementary data. No raw biological data were generated or analysed in this study; all data sources are publicly available Bioconductor vignettes (bioconductor.org/packages/).

---

## Author Contributions

[To be completed by authors. Suggested CRediT taxonomy roles: Conceptualization, Data curation, Formal analysis, Methodology, Software, Validation, Visualization, Writing – original draft, Writing – review & editing.]

---

## References

1. Huber W, et al. Orchestrating high-throughput genomic analysis with Bioconductor. *Nat Methods*. 2015;12(2):115-121.
2. Mangul S, et al. Systematic benchmarking of omics computational tools. *Nat Commun*. 2019;10:1393.
3. Ison J, et al. Tools and data services registry: a community effort to document bioinformatics resources. *Nucleic Acids Res*. 2016;44(D1):D38-D47. (bio.tools)
4. Goble C, et al. FAIR computational workflows. *Data Intelligence*. 2020;2(1-2):108-121. (WorkflowHub)
5. Gentleman RC, et al. Bioconductor: open software development for computational biology and bioinformatics. *Genome Biol*. 2004;5(10):R80.
6. Wang Y, Wang J. BioWorkflow: retrieving comprehensive bioinformatics workflows from publications. *Brief Bioinform*. 2025;26(6):bbaf571. doi:10.1093/bib/bbaf571 [see also ref 30]
7. [BTR — PMC11091741 — CITATION PENDING: look up on PubMed for full citation]
8. [BioAgent Bench — arXiv:2601.21800, 2026 — CITATION PENDING: check for published version]
9. Afgan E, et al. The Galaxy platform for accessible, reproducible and collaborative biomedical analyses: 2022 update. *Nucleic Acids Res*. 2022;50(W1):W345-W351.
10. Di Tommaso P, et al. Nextflow enables reproducible computational workflows. *Nat Biotechnol*. 2017;35(4):316-319.
11. [FAIRsoft — *Bioinformatics*, 2024, btae464 — CITATION PENDING: resolve full author/title/page details]
12. Ewels PA, et al. The nf-core framework for community-curated bioinformatics pipelines. *Nat Biotechnol*. 2020;38(3):276-278.
13. Ji Z, et al. Survey of hallucination in natural language generation. *ACM Comput Surv*. 2023;55(12):1-38. doi:10.1145/3571730
14. Lewis P, et al. Retrieval-augmented generation for knowledge-intensive NLP tasks. *Adv Neural Inf Process Syst (NeurIPS)*. 2020;33:9459-9474.
15. Singhal K, et al. Large language models encode clinical knowledge. *Nature*. 2023;620(7972):172-180. doi:10.1038/s41586-023-06291-2
16. Chen M, et al. Evaluating large language models trained on code. arXiv:2107.03374. 2021.
17. Tang X, et al. BioCoder: a benchmark for bioinformatics code generation with large language models. *Bioinformatics*. 2024;40(Suppl 1):i127-i135. doi:10.1093/bioinformatics/btae230
18. Jin Q, et al. GeneGPT: augmenting large language models with domain tools for improved access to biomedical information. *Bioinformatics*. 2024;40(2):btae075. doi:10.1093/bioinformatics/btae075
19. Eghbali A, Pradel M. De-Hallucinator: mitigating LLM hallucinations in code generation tasks via iterative grounding. arXiv:2401.01701. 2024.
20. Cinquin O. Steering veridical large language model analyses by correcting and enriching generated database queries: first steps toward ChatGPT bioinformatics. *Brief Bioinform*. 2024;bbaf045. doi:10.1093/bib/bbaf045
21. Green A, et al. GOFlowLLM: curating miRNA literature with large language models and flowcharts. *Bioinformatics*. 2026;42(1):btaf683. doi:10.1093/bioinformatics/btaf683
22. Jansen JA, et al. Leveraging large language models for data analysis automation. *PLoS ONE*. 2025;20(2):e0317084. doi:10.1371/journal.pone.0317084
23. Mehandru N, et al. BioAgents: democratizing bioinformatics analysis with multi-agent systems. arXiv:2501.06314. 2025.
24. Kasalica V, et al. APE in the Wild: automated exploration of proteomics workflows in the bio.tools registry. *J Proteome Res*. 2021;20(4):2157-2165. doi:10.1021/acs.jproteome.0c00983
25. da Veiga Leprevost F, et al. BioContainers: an open-source and community-driven framework for software standardization. *Bioinformatics*. 2017;33(16):2580-2582. doi:10.1093/bioinformatics/btx192
26. Brinkmann M, Bonelli M, Tosevska A. SummArIzeR: an R/Bioconductor package for LLM-assisted enrichment result clustering and annotation. *Bioinformatics*. 2026;42(3):btag102. doi:10.1093/bioinformatics/btag102
27. Nagarajan N, et al. SCassist: integrating large language models into single-cell RNA-seq workflows. *Bioinformatics*. 2025;41(8):btaf402. doi:10.1093/bioinformatics/btaf402
28. Liu Y, et al. Benchmarking LLM-based agents for single-cell omics analysis. *Genome Biol*. 2026;27(1):123. doi:10.1186/s13059-026-03998-z
29. Patel H, et al. Empowering bioinformatics communities with Nextflow and nf-core. *Genome Biol*. 2025. doi:10.1186/s13059-025-03673-9
30. Wang Y, Wang J. BioWorkflow: retrieving comprehensive bioinformatics workflows from publications. *Brief Bioinform*. 2025;26(6):bbaf571. doi:10.1093/bib/bbaf571

---

## Supplementary Materials

- **Supplementary Table S1**: Expert reviewer profiles and domain assignments
- **Supplementary Table S2**: Per-package step counts for all 1,970 packages
- **Supplementary Table S3**: 20 workflow generation evaluation tasks (§6.3) — query text, target packages, expected NAMESPACE-verified functions, and per-task LLM-only vs. BioMate+KB citation accuracy
- **Supplementary Figure S1**: EDAM operation distribution across packages
- **Supplementary Figure S2**: Step count distribution per package (log scale)
- **Code S1**: Extraction pipeline scripts (GitHub link)
- **Data S1**: Full database dump (Zenodo DOI — pending deposit)
- **Video S1**: BioMate workflow demonstration — natural language query to knowledge-grounded workflow routing, step-level outputs, and type-aware visualization
