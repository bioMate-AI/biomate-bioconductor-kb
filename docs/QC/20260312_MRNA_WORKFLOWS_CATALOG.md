# BioMate mRNA/RNA-seq Workflow Catalog (2026-03-12)

This document lists every mRNA and RNA-seq relevant workflow available in BioMate,
describes what each does, and provides user stories with end-to-end information flow.

---

## Contents

1. [Overview](#overview)
2. [Tier 1 — Full End-to-End Pipelines](#tier-1--full-end-to-end-pipelines)
3. [Tier 2 — Analytical Subworkflows](#tier-2--analytical-subworkflows)
4. [Tier 3 — nf-core Galaxy Tool Wrappers](#tier-3--nf-core-galaxy-tool-wrappers)
5. [Tier 4 — miRNA and RNA Structure Tools](#tier-4--mirna-and-rna-structure-tools)
6. [Tier 5 — Quality Control & Metrics Tools](#tier-5--quality-control--metrics-tools)
7. [Tier 6 — Data Lake & Reference Queries](#tier-6--data-lake--reference-queries)
8. [AI Routing for mRNA Queries](#ai-routing-for-mrna-queries)
9. [User Stories with Information Flow](#user-stories-with-information-flow)

---

## Overview

BioMate contains **four tiers** of mRNA/RNA-seq capability:

| Tier | Type | Count | Entry Point |
|---|---|---|---|
| 1 | Full end-to-end Nextflow pipelines | 5 | Chat → auto-selected |
| 2 | Analytical subworkflows (DE, biomarkers, deconvolution, CRISPR) | ~15 | Chat or direct |
| 3 | nf-core Galaxy wrappers (rnaseq, smrnaseq, scrnaseq, rnafusion) | ~10 | Galaxy tool panel |
| 4 | miRNA / RNA structure tools | 6 | Galaxy tool panel |
| 5 | QC and metrics tools | ~10 | Galaxy tool panel |
| 6 | Data lake query tools (miRTarBase, ARCHS4) | 5 | Galaxy tool panel |

All workflows are accessible via the BioMate AI chat interface. The AI assistant routes
"RNA-seq", "differential expression", "transcriptomics", and related queries to the
transcriptomics domain specialist, which proposes and executes the appropriate workflow.

---

## Tier 1 — Full End-to-End Pipelines

### 1.1 Bulk RNA-seq Differential Expression
**File:** `backend/biomni_workflows/nextflow_nfcore/workflows/bioconductor_rnaseq_de/main.nf`

Complete pipeline from quantified transcript counts to biological interpretation.

| Step | Tool | Purpose |
|---|---|---|
| 1 | tximport | Import Salmon/kallisto quantification results |
| 2 | DESeq2 | Negative binomial model for differential expression |
| 3 | edgeR (optional) | Alternative DE testing |
| 4 | limma/voom (optional) | Linear model DE for complex designs |
| 5 | clusterProfiler | GO term and KEGG pathway enrichment |
| 6 | pathview | KEGG pathway diagrams with fold-change overlay |

**Inputs:** Salmon/kallisto quant directories, `coldata.csv` (sample metadata), `tx2gene.csv`
**Outputs:** DE results CSV (logFC, p-value, padj), enriched GO/KEGG terms CSV, KEGG pathway PDFs

---

### 1.2 RNA-seq Patient Stratification
**File:** `backend/biomni_workflows/nextflow_nfcore/workflows/rnaseq_patient_stratification/main.nf`

Unsupervised molecular subtype discovery from bulk RNA-seq expression matrices,
with clinical survival outcome analysis.

| Step | Tool | Purpose |
|---|---|---|
| 1 | ConsensusClusterPlus | Unsupervised clustering to discover molecular subtypes |
| 2 | Kaplan-Meier | Survival curves per subtype |
| 3 | Cox PH regression | Multi-variable survival modeling |

**Inputs:** Expression matrix RDS (genes × samples), clinical metadata CSV (survival time + event columns)
**Outputs:** Cluster assignments CSV, consensus heatmaps PDF, KM fit RDS, Cox hazard ratios CSV

---

### 1.3 Single-Cell RNA-seq (scRNA-seq)
**File:** `backend/biomni_workflows/nextflow_nfcore/workflows/bioconductor_scrna_seq/main.nf`

End-to-end single-cell analysis from count matrix to cell type annotation and
differential abundance testing.

| Step | Tool | Purpose |
|---|---|---|
| 1 | tximeta | Import Cell Ranger / alevin-fry count output |
| 2 | scran | Normalization, HVG selection, PCA, UMAP |
| 3 | SingleR | Automated cell type annotation |
| 4 | miloR | Differential cell abundance between conditions |
| 5 | clusterProfiler | Marker gene GO/KEGG enrichment |

**Inputs:** Cell Ranger output directory or alevin-fry directory
**Outputs:** Normalized count SingleCellExperiment RDS, cell type labels CSV, differential abundance results CSV

---

### 1.4 nf-core/rnaseq — Full Bulk RNA-seq (FASTQ to counts)
**File:** `galaxy_nextflow/tools/nfcore/nfcore_rnaseq.xml`  
**Pipeline version:** nf-core/rnaseq v3.22.1

Industry-standard bulk RNA-seq pipeline from raw reads to gene expression counts.

| Step | Tool options | Purpose |
|---|---|---|
| 1 | FastQC / fastp | Read quality control and trimming |
| 2 | STAR / HISAT2 / Salmon / Kallisto | Alignment or pseudo-alignment |
| 3 | featureCounts / HTSeq | Count generation |
| 4 | Picard / SAMtools | BAM QC and processing |
| 5 | MultiQC | Aggregated QC report |

**Inputs:** FASTQ files (R1/R2), reference genome (FASTA + GTF) or genome alias (e.g. GRCh38)
**Outputs:** Gene-level count matrix TSV, MultiQC HTML, alignment BAMs, Salmon/kallisto quant directories

---

### 1.5 nf-core/rnafusion — RNA Fusion Detection
**File:** `galaxy_nextflow/tools/nextflow_native/rnafusion.xml`

Detects and reports RNA fusion genes from RNA-seq data using multiple callers.

| Step | Tool | Purpose |
|---|---|---|
| 1 | STAR-Fusion | Fusion detection from STAR chimeric alignments |
| 2 | Arriba | Additional sensitive fusion caller |
| 3 | FusionCatcher | Third-pass fusion caller |
| 4 | fusion-report | Aggregate and annotate fusion calls |
| 5 | Pizzly/Squid (optional) | Additional callers |

**Inputs:** Samplesheet CSV (FASTQ paths), GENCODE genome version
**Outputs:** Fusion calls per tool, merged VCF, visualization HTML

---

## Tier 2 — Analytical Subworkflows

### 2.1 Transcriptomic Biomarker Discovery
**File:** `backend/biomni_workflows/nextflow_nfcore/subworkflows/genomics/transcriptomic_biomarker/main.nf`

Identifies and scores disease-relevant transcriptomic biomarkers.

| Step | Tool | Purpose |
|---|---|---|
| 1 | limma/edgeR | Low-count filtering |
| 2 | limma-voom | DE analysis with empirical Bayes |
| 3 | GSVA / ssGSEA | Gene set variation analysis on 50 MSigDB Hallmark pathways |
| 4 | HTML reporter | Volcano plot, heatmap, pathway enrichment table |

**Inputs:** Raw count matrix CSV, sample metadata CSV (condition labels)
**Outputs:** DE table CSV, significant gene list CSV, GSVA score matrix CSV, pathway summary JSON, HTML report

---

### 2.2 RNA-seq Patient Subtype Biomarker Report
Combines 1.2 (patient stratification) + 2.1 (biomarker scoring) to produce a
complete molecular phenotyping report from an expression matrix.

---

### 2.3 Perturb-seq / CRISPR Screen Analysis
**File:** `backend/biomni_workflows/nextflow_nfcore/subworkflows/genomics/perturb_seq_analysis/main.nf`

Analyzes CRISPR genetic perturbation screens (Perturb-seq) using MAGeCK.

| Step | Tool | Purpose |
|---|---|---|
| 1 | MAGeCK count | sgRNA count from sequencing data |
| 2 | MAGeCK MLE/RRA | Gene-level essentiality scoring |
| 3 | DESeq2 (optional) | Transcriptomic response per perturbation |

**Inputs:** FASTQ files (sgRNA library), reference sgRNA library FASTA, sample metadata
**Outputs:** sgRNA count matrix, gene essentiality scores, volcano plots

---

### 2.4 DeconRNASeq — Tissue Deconvolution
**File:** `backend/biomni_workflows/nextflow_nfcore/subworkflows/bioconductor/deconrnaseq/main.nf`

Deconvolves bulk RNA-seq into constituent cell type fractions using reference signatures.

**Inputs:** Bulk RNA-seq count data, cell type reference signature matrix
**Outputs:** Estimated cell type proportions per sample, deconvolution quality metrics

---

### 2.5 txcutr — 3' End mRNA-seq Support
**File:** `backend/biomni_workflows/nextflow_nfcore/subworkflows/bioconductor/txcutr/main.nf`

Prepares transcript annotations for 3'-end sequencing methods (QuantSeq, 10x Chromium).
Truncates 3' UTR annotations to the read length for accurate quantification.

**Inputs:** Count data, annotation GTF
**Outputs:** Corrected count matrix, updated annotations

---

### 2.6 Unsupervised scRNA-seq Cell Type Transfer
**Files:**
- `nextflow/subworkflows/genomics/annotate_celltype_scRNA.nf`
- `nextflow/subworkflows/genomics/unsupervised_celltype_transfer_between_scRNA_datasets.nf`

Transfers cell type labels from a reference atlas to a new scRNA-seq dataset.

**Inputs:** Query scRNA-seq (anndata/h5ad), reference atlas with labels
**Outputs:** Cell type predictions, confidence scores, UMAP visualization

---

### 2.7 scRNA-seq Embedding Workflows
Three complementary dimensionality reduction pipelines:

| Workflow | File | Method | Use Case |
|---|---|---|---|
| Harmony | `create_harmony_embeddings_scRNA.nf` | Linear correction | Multi-batch integration |
| scVI | `create_scvi_embeddings_scRNA.nf` | Variational autoencoder | Deep probabilistic integration |
| UCE | `get_uce_embeddings_scRNA.nf` | Foundation model | Zero-shot cell embedding |

**Inputs:** Processed scRNA-seq h5ad
**Outputs:** Corrected embedding coordinates, integrated UMAP

---

### 2.8 RNA Velocity (Velocyto)
**Files:** `research/official_iwc/workflows/scRNAseq/velocyto/`

Infers RNA transcriptional dynamics (spliced vs unspliced mRNA) to predict future cell states.

**Inputs:** 10x Cell Ranger BAM, filtered barcodes
**Outputs:** Velocity vectors, trajectory plots

---

### 2.9 BREW3R — 3' UTR Extension
**File:** `research/official_iwc/workflows/transcriptomics/brew3r/BREW3R.ga`

Extends 3' UTR gene annotations using RNA-seq read coverage, important for
QuantSeq, 10x scRNA-seq, and other 3'-end protocols.

**Inputs:** RNA-seq BAM aligned with STAR, reference GTF
**Outputs:** Extended annotation GTF

---

### 2.10 Codon Optimization (Synthetic mRNA)
**File:** `backend/biomni_workflows/nextflow_nfcore/subworkflows/synthetic_biology/optimize_codons_for_heterologous_expression/main.nf`

Optimizes a coding sequence for maximum expression in a target host by
substituting synonymous codons based on host codon usage frequency tables.

**Inputs:** Target DNA/mRNA sequence, host codon usage frequency table JSON
**Outputs:** Optimized sequence FASTA, codon adaptation index (CAI), metrics JSON

---

## Tier 3 — nf-core Galaxy Tool Wrappers

These integrate nf-core pipelines as single Galaxy tool steps with full parameter exposure.

| Tool | nf-core Pipeline | Wrapper File |
|---|---|---|
| `nfcore_rnaseq` | nf-core/rnaseq v3.22.1 | `galaxy_nextflow/tools/nfcore/nfcore_rnaseq.xml` |
| `rnaseq` (schema-driven) | nf-core/rnaseq | `galaxy_nextflow/tools/nextflow_native/rnaseq.xml` |
| `smrnaseq` | nf-core/smrnaseq (small RNA/miRNA) | `galaxy_nextflow/tools/nextflow_native/smrnaseq.xml` |
| `scrnaseq` | nf-core/scrnaseq (10x Genomics) | `galaxy_nextflow/tools/nextflow_native/scrnaseq.xml` |
| `rnafusion` | nf-core/rnafusion | `galaxy_nextflow/tools/nextflow_native/rnafusion.xml` |

### nf-core/smrnaseq — Small RNA-seq / miRNA
Processes small RNA-seq libraries to quantify mature and precursor miRNAs.

| Step | Tool | Purpose |
|---|---|---|
| 1 | FastQC / fastp | QC and adapter trimming |
| 2 | Bowtie | Short-read alignment to miRNA loci |
| 3 | miRTrace | Species prediction and contamination check |
| 4 | featureCounts | miRNA count matrix |

**Inputs:** Samplesheet CSV, reference genome, miRBase species code
**Outputs:** miRNA count matrix, miRTrace QC report, MultiQC HTML

---

### nf-core/scrnaseq — 10x Genomics scRNA-seq
**Inputs:** Samplesheet CSV (FASTQ paths), genome FASTA + GTF, 10x barcode whitelist
**Outputs:** Cell-gene count matrix (Market Exchange format), QC metrics, MultiQC HTML

---

## Tier 4 — miRNA and RNA Structure Tools

### 4.1 mirTarRnaSeq — miRNA/mRNA Interaction Analysis
**File:** `backend/biomni_workflows/nextflow_nfcore/subworkflows/bioconductor/mirtarrnaseq/main.nf`

Statistical modeling of miRNA–target mRNA co-expression relationships.

**Inputs:** Paired miRNA and mRNA count matrices from the same samples
**Outputs:** miRNA-mRNA interaction scores, significant pairs CSV, interaction plots PDF

---

### 4.2 RNA Secondary Structure Prediction
**File:** `backend/biomni_workflows/nextflow/subworkflows/microbiology/predict_rna_secondary_structure.nf`
**Galaxy Tool:** `backend/biomni_workflows/galaxy/tools/biomni/microbiology/predict_rna_secondary_structure.xml`

Predicts minimum-free-energy (MFE) secondary structure using ViennaRNA RNAfold.

**Inputs:** RNA sequence (string)
**Outputs:** Dot-bracket structure, MFE value, structure visualization JSON

---

### 4.3 RNA Secondary Structure Feature Analysis
**File:** `backend/biomni_workflows/nextflow/subworkflows/biochemistry/analyze_rna_secondary_structure_features.nf`

Computes quantitative structural features from a dot-bracket RNA structure.

**Inputs:** Dot-bracket structure string, RNA sequence
**Outputs:** Stem count, loop count, GC content, pairing fraction — features JSON

---

### 4.4 ViennaRNA Tool Suite
Individual Galaxy tools for RNA structure analysis:

| Tool | File | Function |
|---|---|---|
| RNAfold | `viennarna_rnafold.xml` | MFE secondary structure + partition function |
| RNAcofold | `viennarna_rnacofold.xml` | RNA–RNA interaction structure prediction |
| RNALfold | `viennarna_rnalfold.xml` | Local structure prediction for long sequences |

---

## Tier 5 — Quality Control & Metrics Tools

| Tool | File | Function |
|---|---|---|
| Qualimap RNAseq | `qualimap_rnaseq.xml` | Alignment QC: coverage, bias, junction stats |
| Picard CollectRnaSeqMetrics | `picard_collectrnaseqmetrics.xml` | Strand specificity, ribosomal fraction, coverage |
| SortMeRNA | `sortmerna.xml` | rRNA contamination removal from mRNA-seq reads |
| rnaQUAST | `rnaquast.xml` | De novo RNA assembly quality assessment |
| Barrnap | `barrnap.xml` | rRNA gene prediction in assemblies |
| tRNAscan-SE | `trnascanse.xml` | tRNA gene prediction |
| Infernal cmsearch | `infernal_cmsearch.xml` | ncRNA covariance model search |
| Parabricks RNA FASTQ→BAM | `parabricks_rnafq2bam.xml` | GPU-accelerated RNA-seq alignment |

---

## Tier 6 — Data Lake & Reference Queries

### 6.1 ARCHS4 Gene Expression Query
**File:** `backend/biomni_workflows/nextflow/subworkflows/genomics/get_rna_seq_archs4.nf`
**Galaxy Tool:** `backend/biomni_workflows/galaxy/tools/biomni/genomics/get_rna_seq_archs4.xml`

Queries the ARCHS4 database (millions of uniformly processed RNA-seq samples)
for tissue-level TPM expression values for any gene.

**Inputs:** Gene name (e.g. `TP53`), K (number of top tissues to return)
**Outputs:** Table of tissue → median TPM expression

---

### 6.2 miRTarBase — miRNA Target Site Database
**Files:**
- `biomate_dm_biomni_data_lake_miRTarBase_MicroRNA_Target_Sites_parquet.xml`
- `biomate_dm_biomni_data_lake_miRTarBase_microRNA_target_interaction_parquet.xml`
- `biomate_dm_biomni_data_lake_miRTarBase_microRNA_target_interaction_pubmed_abtract_txt.xml`

Query validated miRNA–mRNA target interactions from miRTarBase.

**Inputs:** miRNA name or target gene name
**Outputs:** Validated target interactions, experimental evidence types, PubMed abstracts

---

### 6.3 Affinity Capture RNA Data
**File:** `biomate_dm_biomni_data_lake_affinity_capture_rna_parquet.xml`

Query protein–RNA binding interactions from affinity capture RNA experiments (e.g., eCLIP, RIP-seq).

**Inputs:** RNA binding protein name or RNA target
**Outputs:** Binding site records, experimental metadata

---

### 6.4 GOseq Pathway Enrichment
**File:** `research/official_iwc/workflows/transcriptomics/goseq/goseq-go-kegg-enrichment-analsis.ga`

Accounts for mRNA length bias when performing GO and KEGG pathway enrichment on DE gene lists.

**Inputs:** DE gene list (significant genes), gene lengths, genome annotation
**Outputs:** Over-represented GO terms (BP, MF, CC), KEGG pathways, adjusted p-values

---

## AI Routing for mRNA Queries

The BioMate AI assistant uses a keyword-weighted routing system to match user intent to mRNA workflows. High-priority triggers:

| User phrase | Route | Confidence boost |
|---|---|---|
| "RNA-seq", "rnaseq" | Transcriptomics specialist | +3.0 |
| "single cell", "scRNA" | scRNA-seq workflow | +3.0 |
| "differential expression", "DE genes" | DE subworkflow | +2.5 |
| "pathway enrichment", "KEGG", "GO terms" | Enrichment step | +2.0 |
| "fusion gene", "gene fusion" | rnafusion pipeline | +2.5 |
| "miRNA", "microRNA" | smrnaseq or mirTarRnaSeq | +2.0 |
| "RNA structure", "secondary structure" | ViennaRNA tools | +2.0 |
| "codon optimization", "synthetic mRNA" | Codon optimization subworkflow | +2.0 |
| "tissue expression", "ARCHS4" | ARCHS4 query tool | +2.0 |

The standard 7-phase transcriptomics workflow proposed by the AI:
```
QC (FastQC/fastp)
  → Preprocessing (Cutadapt/Trimmomatic)
  → Alignment/Quantification (STAR/HISAT2/Salmon/Kallisto)
  → Count Generation (featureCounts/HTSeq)
  → Differential Expression (DESeq2/edgeR/limma)
  → Functional Enrichment (clusterProfiler)
  → Visualization
```

---

## User Stories with Information Flow

---

### Story 1 — Basic Bulk RNA-seq: "What genes are dysregulated in my tumor samples?"

**User:** "I have paired-end RNA-seq data from 5 tumor and 5 normal samples. Find differentially expressed genes."

**AI routing:** Transcriptomics domain → proposes nf-core/rnaseq + Bioconductor DE workflow

```
User uploads: FASTQ files (R1/R2 per sample)
      ↓
[nf-core/rnaseq v3.22.1]
  FastQC → fastp (trim) → STAR (align to GRCh38) → featureCounts (gene counts)
      ↓
  Gene count matrix TSV  +  MultiQC QC report
      ↓
[bioconductor_rnaseq_de]
  tximport → DESeq2 (tumor vs normal, ~log2FC, Wald test)
      ↓
  DE results: ~500 significant genes (padj < 0.05, |log2FC| > 1)
      ↓
  clusterProfiler → top 20 GO terms + KEGG pathways
      ↓
User receives:
  - DE table CSV (gene, baseMean, log2FC, padj)
  - Volcano plot PNG
  - KEGG pathway diagrams PDF
  - Enriched GO terms table
```

**Time estimate:** 2–4 hours (alignment-dominated), parallelized across 10 samples.

---

### Story 2 — Single-Cell RNA-seq: "What cell types are in my tumor microenvironment?"

**User:** "I ran 10x Genomics Chromium on a breast tumor biopsy. Identify cell types and their proportions."

**AI routing:** scRNA-seq workflow → nf-core/scrnaseq + bioconductor_scrna_seq

```
User provides: 10x Cell Ranger output directory (barcodes.tsv, genes.tsv, matrix.mtx)
      ↓
[bioconductor_scrna_seq]
  tximeta (import) → scran (normalize + log-transform)
      ↓
  PCA → UMAP (2D embedding)
      ↓
  Leiden clustering (resolution 0.5 → ~12 clusters)
      ↓
  SingleR (annotate each cluster vs HumanPrimaryCellAtlasData reference)
      ↓
  Cell type labels: T cells (28%), B cells (12%), Macrophages (18%),
                    Cancer epithelial (32%), Fibroblasts (10%)
      ↓
  miloR → differential abundance between tumor subtypes
      ↓
  clusterProfiler → marker gene enrichment per cell type
      ↓
User receives:
  - Annotated UMAP PNG (colored by cell type)
  - Cell type proportion bar chart
  - Marker gene list per cluster
  - Differential abundance results
```

---

### Story 3 — Patient Stratification: "Can I find molecular subtypes in my cohort?"

**User:** "I have RNA-seq from 200 TCGA breast cancer patients with survival data. Are there survival-predictive subtypes?"

**AI routing:** rnaseq_patient_stratification workflow

```
User provides:
  - Expression matrix RDS (20,000 genes × 200 samples)
  - clinical_metadata.csv (patient_id, OS_time, OS_event, age, stage)
      ↓
[rnaseq_patient_stratification]
  ConsensusClusterPlus (k=2..8, 1000 iterations, Pearson distance)
      ↓
  Optimal k=4 subtypes (consensus CDF plateau)
      ↓
  Kaplan-Meier survival curves (log-rank p < 0.001)
      ↓
  Cox PH regression (subtype + age + stage, HR = 2.3 for subtype 3)
      ↓
User receives:
  - Subtype assignments CSV (patient_id, subtype)
  - Consensus heatmap PDF (similarity matrix)
  - KM survival curves PDF (4 subtypes)
  - Cox results CSV (HR, 95% CI, p-value per covariate)
```

---

### Story 4 — Transcriptomic Biomarker Discovery: "Find a gene signature for my drug response?"

**User:** "I have RNA-seq from responders vs non-responders to immunotherapy. Find a predictive gene signature."

**AI routing:** transcriptomic_biomarker subworkflow

```
User provides:
  - count_matrix.csv (genes × samples, raw counts)
  - metadata.csv (sample_id, response: responder/non-responder)
      ↓
[transcriptomic_biomarker]
  limma/edgeR filtering (remove low-count genes)
      ↓
  limma-voom DE (voom weights → eBayes → topTable)
      ↓
  Top 50 DE genes (FDR < 0.05, ranked by |logFC|)
      ↓
  GSVA / ssGSEA on 50 MSigDB Hallmark gene sets
      ↓
  Enriched pathways: HALLMARK_INTERFERON_GAMMA_RESPONSE (p=0.001),
                     HALLMARK_IL6_JAK_STAT3_SIGNALING (p=0.003)
      ↓
User receives:
  - DE table CSV (gene, logFC, AveExpr, t, P.Value, adj.P.Val)
  - Volcano plot PNG
  - GSVA score matrix CSV (samples × pathways)
  - Heatmap of top 50 genes PNG
  - Pathway summary JSON
  - Full HTML biomarker report
```

---

### Story 5 — Fusion Gene Detection: "Does my leukemia sample have driver fusions?"

**User:** "RNA-seq from a pediatric ALL patient. Find any gene fusions."

**AI routing:** rnafusion pipeline

```
User provides: FASTQ R1 + R2 from tumor RNA-seq
      ↓
[nf-core/rnafusion]
  STAR alignment (chimeric reads enabled)
      ↓
  ┌─ STAR-Fusion → fusion candidate list
  ├─ Arriba       → independent fusion calls + visualizations
  └─ FusionCatcher → third-pass calls
      ↓
  fusion-report (merge, annotate against COSMIC/known fusions)
      ↓
  BCR-ABL1 detected (3 callers concordant), ETV6-RUNX1 detected (2 callers)
      ↓
User receives:
  - Merged fusion calls VCF
  - Per-caller fusion tables TSV
  - Arriba visualization PNG (exon-level structure diagrams)
  - HTML fusion report with COSMIC annotation
```

---

### Story 6 — miRNA Target Discovery: "What miRNAs regulate my DE genes?"

**User:** "I have 200 downregulated genes from my RNA-seq. Which miRNAs might be driving this?"

**AI routing:** miRTarBase data lake query + mirTarRnaSeq subworkflow

```
User provides:
  - Gene list (200 downregulated genes)
  - (Optional) paired small RNA-seq data for the same samples
      ↓
Step A: miRTarBase data lake query
  Query: "miRNAs with validated targets in my gene list"
      ↓
  Returns: 45 miRNAs with ≥3 validated targets in the gene list
  Top hits: miR-21-5p (15 targets), miR-155-5p (12 targets)
      ↓
Step B (if smRNA-seq data available): mirTarRnaSeq subworkflow
  Co-expression analysis (miRNA counts vs mRNA counts)
      ↓
  Significant miRNA–mRNA pairs (negative correlation, FDR < 0.05)
      ↓
User receives:
  - miRNA–target interaction table (miRNA, target gene, evidence type)
  - Co-expression correlation table (if paired data)
  - Network visualization JSON
```

---

### Story 7 — Synthetic mRNA Codon Optimization: "Optimize my therapeutic mRNA for expression in human cells?"

**User:** "I have a coding sequence for a CAR-T therapy. Optimize codons for human expression."

**AI routing:** optimize_codons_for_heterologous_expression subworkflow

```
User provides:
  - target_sequence.fasta (coding sequence, ~1500 bp)
  - human_codon_usage.json (Homo sapiens codon frequency table)
      ↓
[optimize_codons_for_heterologous_expression]
  Calculate per-codon usage frequency from host table
      ↓
  Replace rare codons with most frequent synonymous codons
      ↓
  Verify ORF integrity (start/stop codon preservation)
      ↓
  Calculate Codon Adaptation Index (CAI): original=0.62 → optimized=0.89
      ↓
User receives:
  - Optimized sequence FASTA
  - Codon change log (original → replacement per position)
  - CAI improvement metrics JSON
  - GC content and secondary structure risk flags
```

---

### Story 8 — Tissue Expression Context: "Where is my gene of interest expressed?"

**User:** "What tissues express BRCA1 highly? I want to understand on-target toxicity."

**AI routing:** ARCHS4 data lake query tool

```
User provides: Gene name "BRCA1"
      ↓
[get_rna_seq_archs4]
  Query ARCHS4 database (>800,000 uniformly processed RNA-seq samples)
      ↓
  Return top-K tissues by median TPM
      ↓
User receives:
  Tissue            Median TPM
  ─────────────────────────────
  Breast tissue     48.2
  Ovary             31.4
  Fallopian tube    28.9
  Uterus            22.1
  Testis            18.7
  ...
```

---

### Story 9 — mRNA Secondary Structure: "Does my vaccine mRNA have stable structure?"

**User:** "I'm designing an mRNA vaccine. Predict the secondary structure of my 5'UTR and check for problematic stem-loops."

**AI routing:** predict_rna_secondary_structure + analyze_rna_secondary_structure_features

```
User provides: RNA sequence (5'UTR, ~200 nt)
      ↓
[predict_rna_secondary_structure] (ViennaRNA RNAfold)
  Compute MFE structure
      ↓
  Dot-bracket: ((((....))))..(((...)))....
  MFE: -42.3 kcal/mol
      ↓
[analyze_rna_secondary_structure_features]
  Stem count: 4
  Loop count: 3
  GC content: 0.58
  Base-pair fraction: 0.61
      ↓
User receives:
  - Dot-bracket structure string
  - MFE energy value
  - Structure feature metrics JSON
  - Flag: high pairing fraction may impede ribosome scanning
```

---

## Summary Table

| Workflow | Use Case | Inputs | Outputs | Est. Time |
|---|---|---|---|---|
| bioconductor_rnaseq_de | Bulk DE from quant files | Salmon/kallisto dirs, coldata.csv | DE table, enrichment, KEGG PDFs | 30 min |
| nf-core/rnaseq | Raw FASTQ → counts | FASTQ + genome | Count matrix, MultiQC | 2–4 h |
| bioconductor_scrna_seq | scRNA-seq: QC → cell types | Cell Ranger dir | Annotated clusters, abundance | 1–2 h |
| nf-core/scrnaseq | 10x FASTQ → matrix | FASTQ + genome + whitelist | Count matrix, QC | 1–3 h |
| rnaseq_patient_stratification | Molecular subtypes + survival | Expression RDS, clinical CSV | Subtypes, KM curves, Cox | 30 min |
| transcriptomic_biomarker | Gene signature for condition | Count matrix, metadata | DE, GSVA scores, HTML report | 20 min |
| nf-core/rnafusion | Fusion gene detection | FASTQ (tumor) | Fusion calls, VCF, HTML | 3–6 h |
| nf-core/smrnaseq | miRNA quantification | FASTQ, genome | miRNA count matrix, QC | 1–2 h |
| perturb_seq_analysis | CRISPR screen + transcriptomics | FASTQ, sgRNA library | Gene essentiality scores | 1–2 h |
| deconrnaseq | Cell type deconvolution | Bulk counts, reference | Cell type fractions | 10 min |
| mirtarrnaseq | miRNA–mRNA interactions | Paired miRNA + mRNA counts | Interaction scores | 15 min |
| optimize_codons | Synthetic mRNA design | Coding sequence, host table | Optimized FASTA, CAI | < 1 min |
| get_rna_seq_archs4 | Tissue expression atlas | Gene name | Tissue TPM table | < 1 min |
| miRTarBase query | miRNA target lookup | Gene list or miRNA name | Target interactions | < 1 min |
| predict_rna_secondary_structure | RNA structure | Sequence string | Dot-bracket, MFE | < 1 min |
| brew3r | 3' UTR extension | STAR BAM, GTF | Extended annotation GTF | 30 min |
| velocyto | RNA velocity | 10x BAM | Trajectory vectors, plots | 30 min |
| goseq | Pathway enrichment | DE gene list + lengths | GO/KEGG enrichment | 5 min |
