# Galaxy Advanced Capabilities Integration Proposal

**Date**: January 9, 2026
**Status**: P1-P3 Implemented
**Author**: Claude Code Assistant

---

## Implementation Status

| Priority | Feature | Status |
|----------|---------|--------|
| P0 | Auto-pair detection + Collections | Pending |
| P1 | Workflow Reports | **Implemented** |
| P1 | Deferred Datasets | **Implemented** |
| P2 | Interactive Tools (Jupyter/RStudio) | **Implemented** |
| P3 | Subworkflow Extraction | **Implemented** |

### Files Created/Modified

**New Components:**
- `client/src/components/workflow-report-viewer.tsx` - Report generation and viewing
- `client/src/components/interactive-launcher.tsx` - Jupyter/RStudio/CellxGene launcher
- `client/src/components/subworkflow-extractor.tsx` - Extract reusable workflow components

**Modified Components:**
- `client/src/components/workflow-artifact.tsx` - Added completion actions panel
- `client/src/components/file-upload.tsx` - Added deferred/immediate URL import mode

---

## Executive Summary

This document proposes how to integrate five powerful Galaxy capabilities into Biomate's frontend and information flow. These capabilities were identified as underutilized and have been implemented in the backend API. This proposal outlines the user experience design, information flow architecture, and implementation priorities for frontend integration.

---

## Table of Contents

1. [Capabilities Overview](#capabilities-overview)
2. [Information Flow Architecture](#information-flow-architecture)
3. [Frontend Integration Designs](#frontend-integration-designs)
4. [Implementation Priorities](#implementation-priorities)
5. [Technical Specifications](#technical-specifications)

---

## Capabilities Overview

### 1. Dataset Collections (Batch Processing)

**What it does**: Groups multiple datasets into a single logical unit for batch processing.

**Types**:
- `list` - Simple list of files (e.g., 10 BAM files)
- `paired` - Two related files (e.g., R1 + R2 reads)
- `list:paired` - List of pairs (e.g., 10 samples, each with R1 + R2)

**Why it matters**:
- NGS experiments typically have multiple samples
- Without collections, users must run workflows N times
- With collections, one workflow processes all samples in parallel

**Backend API**:
```
POST /api/collections
POST /api/collections/auto-pair
POST /api/collections/create-paired
```

---

### 2. Deferred Datasets (Lazy URL Fetching)

**What it does**: Creates a reference to external data without downloading immediately. Galaxy fetches the data only when a workflow step actually needs it.

**Supported protocols**: HTTP, HTTPS, FTP, S3

**Why it matters**:
- Large datasets (10GB+) take significant time to upload
- Users can start workflow design immediately
- Storage is only used when data is actually needed
- External databases (SRA, ENA, ENCODE) can be referenced directly

**Backend API**:
```
POST /api/datasets/deferred
POST /api/datasets/:id/materialize
```

---

### 3. Workflow Reports (Auto-Generated Analysis Summaries)

**What it does**: Generates markdown or HTML reports from completed workflow invocations, including:
- Parameters used
- Output file summaries
- Embedded visualizations
- Quality metrics

**Why it matters**:
- Reproducibility: exact parameters are documented
- Shareability: reports can be sent to collaborators
- Compliance: audit trail for regulated environments
- Time savings: no manual report writing

**Backend API**:
```
GET /api/invocations/:id/report?format=markdown|html
```

---

### 4. Interactive Tools (Jupyter, RStudio, CellxGene)

**What it does**: Launches interactive computing environments with workflow data pre-loaded.

**Available tools**:
- Jupyter Notebook (Python)
- RStudio (R)
- CellxGene (single-cell visualization)
- Galaxy Interactive Environments

**Why it matters**:
- Exploratory analysis after automated pipeline
- Custom visualizations beyond standard outputs
- Ad-hoc statistical analysis
- Education and training

**Backend API**:
```
POST /api/interactive/launch
GET /api/interactive/sessions
```

---

### 5. Workflow Subworkflows (Reusable Components)

**What it does**: Extracts a portion of a workflow as a standalone, reusable component.

**Example**:
```
Full Pipeline (15 steps)
├── QC Module (steps 1-4)      → Extract as "Standard QC"
├── Alignment Module (5-8)     → Extract as "BWA Alignment"
└── Analysis Module (9-15)     → Keep as main workflow
```

**Why it matters**:
- DRY principle: define once, reuse everywhere
- Standardization: lab-wide protocols as shared subworkflows
- Maintenance: update subworkflow, all dependent workflows update
- Collaboration: share validated components

**Backend API**:
```
POST /api/workflows/:id/extract-subworkflow
```

---

## Information Flow Architecture

### Overall System Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              USER JOURNEY                                    │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  PHASE 1: DATA INPUT                                                        │
│  ════════════════════                                                       │
│                                                                             │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐                     │
│  │ Local File  │    │ URL Import  │    │ Database    │                     │
│  │ Upload      │    │             │    │ Reference   │                     │
│  └──────┬──────┘    └──────┬──────┘    └──────┬──────┘                     │
│         │                  │                  │                             │
│         ▼                  ▼                  ▼                             │
│  ┌─────────────────────────────────────────────────────┐                   │
│  │              SMART DATA DETECTION                    │                   │
│  │  • Detect paired-end patterns (_R1/_R2, _1/_2)      │                   │
│  │  • Detect file types (FASTQ, BAM, VCF, etc.)        │                   │
│  │  • Estimate file sizes for deferred recommendation  │                   │
│  │  • Validate URL accessibility                        │                   │
│  └─────────────────────────────────────────────────────┘                   │
│         │                                                                   │
│         ▼                                                                   │
│  ┌─────────────────────────────────────────────────────┐                   │
│  │              USER DECISION POINTS                    │                   │
│  │  • "Auto-pair detected files?" [Yes/No]             │                   │
│  │  • "Use deferred mode for large URL?" [Yes/No]      │                   │
│  │  • "Create collection from files?" [Yes/No]         │                   │
│  └─────────────────────────────────────────────────────┘                   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  PHASE 2: WORKFLOW GENERATION                                               │
│  ════════════════════════════                                               │
│                                                                             │
│  ┌─────────────────────────────────────────────────────┐                   │
│  │                 CHAT INTERFACE                       │                   │
│  │  User: "Analyze my RNA-seq paired-end samples"      │                   │
│  └─────────────────────────────────────────────────────┘                   │
│         │                                                                   │
│         ▼                                                                   │
│  ┌─────────────────────────────────────────────────────┐                   │
│  │              CONTEXT AWARENESS                       │                   │
│  │  • Uploaded data: 6 files (3 paired samples)        │                   │
│  │  • Collection available: list:paired                │                   │
│  │  • Deferred datasets: 2 reference genomes           │                   │
│  └─────────────────────────────────────────────────────┘                   │
│         │                                                                   │
│         ▼                                                                   │
│  ┌─────────────────────────────────────────────────────┐                   │
│  │              WORKFLOW GENERATION                     │                   │
│  │  • Select tools compatible with collections         │                   │
│  │  • Configure batch processing where applicable      │                   │
│  │  • Map deferred datasets to reference inputs        │                   │
│  │  • Check for reusable subworkflows                  │                   │
│  └─────────────────────────────────────────────────────┘                   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  PHASE 3: PRE-EXECUTION VALIDATION                                          │
│  ═════════════════════════════════                                          │
│                                                                             │
│  ┌─────────────────────────────────────────────────────┐                   │
│  │              VALIDATION CHECKS                       │                   │
│  │  ✓ All input datasets available or deferred        │                   │
│  │  ✓ Collection types match workflow expectations    │                   │
│  │  ✓ Deferred URLs are accessible                    │                   │
│  │  ✓ Sufficient storage for materialization          │                   │
│  │  ✓ Tools support collection inputs                 │                   │
│  └─────────────────────────────────────────────────────┘                   │
│         │                                                                   │
│         ▼                                                                   │
│  ┌─────────────────────────────────────────────────────┐                   │
│  │              PILOT RUN SUGGESTION                    │                   │
│  │  If: > 3 samples OR deferred data OR new workflow  │                   │
│  │  Then: Suggest pilot with 1 sample first           │                   │
│  └─────────────────────────────────────────────────────┘                   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  PHASE 4: EXECUTION                                                         │
│  ══════════════════                                                         │
│                                                                             │
│  ┌─────────────────────────────────────────────────────┐                   │
│  │              SSE REAL-TIME UPDATES                   │                   │
│  │  • Per-sample progress for collections              │                   │
│  │  • Deferred dataset materialization status          │                   │
│  │  • Step-by-step completion events                   │                   │
│  └─────────────────────────────────────────────────────┘                   │
│         │                                                                   │
│         ▼                                                                   │
│  ┌─────────────────────────────────────────────────────┐                   │
│  │              PROGRESS VISUALIZATION                  │                   │
│  │  Sample 1: ████████████████████ 100%               │                   │
│  │  Sample 2: ████████████░░░░░░░░  60%               │                   │
│  │  Sample 3: ████████░░░░░░░░░░░░  40%               │                   │
│  └─────────────────────────────────────────────────────┘                   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  PHASE 5: POST-EXECUTION                                                    │
│  ═══════════════════════                                                    │
│                                                                             │
│  ┌─────────────────────────────────────────────────────┐                   │
│  │              COMPLETION ACTIONS                      │                   │
│  │                                                      │                   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌───────────┐ │                   │
│  │  │ 📊 View      │  │ 📥 Download  │  │ 🔬 Open   │ │                   │
│  │  │    Report    │  │    Outputs   │  │  Jupyter  │ │                   │
│  │  └──────────────┘  └──────────────┘  └───────────┘ │                   │
│  │                                                      │                   │
│  │  ┌──────────────┐  ┌──────────────┐                │                   │
│  │  │ 🔄 Rerun     │  │ ✂️ Extract   │                │                   │
│  │  │    Modified  │  │  Subworkflow │                │                   │
│  │  └──────────────┘  └──────────────┘                │                   │
│  └─────────────────────────────────────────────────────┘                   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Data State Transitions

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         DATASET STATE MACHINE                               │
└─────────────────────────────────────────────────────────────────────────────┘

                    ┌─────────────┐
                    │   UPLOAD    │
                    │   REQUEST   │
                    └──────┬──────┘
                           │
              ┌────────────┼────────────┐
              ▼            ▼            ▼
       ┌──────────┐  ┌──────────┐  ┌──────────┐
       │  LOCAL   │  │   URL    │  │ DEFERRED │
       │  UPLOAD  │  │  IMPORT  │  │   URL    │
       └────┬─────┘  └────┬─────┘  └────┬─────┘
            │             │             │
            ▼             ▼             │
       ┌──────────┐  ┌──────────┐       │
       │ UPLOADED │  │ FETCHING │       │
       └────┬─────┘  └────┬─────┘       │
            │             │             │
            ▼             ▼             │
       ┌──────────────────────┐        │
       │       READY          │        │
       │  (in Galaxy history) │        │
       └──────────┬───────────┘        │
                  │                    │
                  ▼                    ▼
       ┌─────────────────────────────────────┐
       │         WORKFLOW EXECUTION          │
       │  (deferred datasets materialize)    │
       └─────────────────────────────────────┘


┌─────────────────────────────────────────────────────────────────────────────┐
│                       COLLECTION STATE MACHINE                              │
└─────────────────────────────────────────────────────────────────────────────┘

       ┌──────────────┐
       │ FILES UPLOAD │
       └──────┬───────┘
              │
              ▼
       ┌──────────────┐
       │ PATTERN      │──── No patterns found ────→ [Individual Files]
       │ DETECTION    │
       └──────┬───────┘
              │
              │ Patterns found
              ▼
       ┌──────────────┐
       │ USER PROMPT  │──── User declines ────────→ [Individual Files]
       │ "Auto-pair?" │
       └──────┬───────┘
              │
              │ User accepts
              ▼
       ┌──────────────┐
       │ COLLECTION   │
       │ CREATED      │
       └──────┬───────┘
              │
              ▼
       ┌──────────────┐
       │ READY FOR    │
       │ BATCH WORKFLOW│
       └──────────────┘
```

---

## Frontend Integration Designs

### 1. File Upload Component Enhancement

**Location**: `client/src/components/file-upload.tsx`

**Current State**: Simple file upload with size validation

**Proposed Enhancement**:

```
┌─────────────────────────────────────────────────────────────────┐
│ 📁 Upload Files                                    [URL Import] │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Drop files here or click to browse                      │   │
│  │  Max 5GB per file • FASTQ, BAM, VCF, CSV supported      │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│ Uploaded Files (6)                                              │
├─────────────────────────────────────────────────────────────────┤
│  📄 sample1_R1.fastq.gz          2.3 GB    ✅ Uploaded         │
│  📄 sample1_R2.fastq.gz          2.1 GB    ✅ Uploaded         │
│  📄 sample2_R1.fastq.gz          2.4 GB    ✅ Uploaded         │
│  📄 sample2_R2.fastq.gz          2.2 GB    ✅ Uploaded         │
│  📄 sample3_R1.fastq.gz          2.5 GB    ✅ Uploaded         │
│  📄 sample3_R2.fastq.gz          2.3 GB    ✅ Uploaded         │
├─────────────────────────────────────────────────────────────────┤
│ 💡 SMART DETECTION                                              │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ Detected 3 paired-end samples (R1/R2 pattern)               │ │
│ │                                                             │ │
│ │ sample1: sample1_R1.fastq.gz ↔ sample1_R2.fastq.gz         │ │
│ │ sample2: sample2_R1.fastq.gz ↔ sample2_R2.fastq.gz         │ │
│ │ sample3: sample3_R1.fastq.gz ↔ sample3_R2.fastq.gz         │ │
│ │                                                             │ │
│ │ [Create Paired Collection]  [Keep as Individual Files]     │ │
│ └─────────────────────────────────────────────────────────────┘ │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**URL Import with Deferred Option**:

```
┌─────────────────────────────────────────────────────────────────┐
│ 🔗 Import from URL                                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│ URL: ┌─────────────────────────────────────────────────────┐   │
│      │ https://sra-pub-run-odp.s3.amazonaws.com/sra/SRR... │   │
│      └─────────────────────────────────────────────────────┘   │
│                                                                 │
│ Filename (optional): ┌─────────────────────────────────────┐   │
│                      │ SRR12345_reads.fastq.gz             │   │
│                      └─────────────────────────────────────┘   │
│                                                                 │
│ Import Mode:                                                    │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ ○ Immediate Download                                        │ │
│ │   Galaxy downloads the file now. Best for small files.      │ │
│ │   Estimated time: ~45 minutes for 15GB                      │ │
│ │                                                             │ │
│ │ ● Deferred (Recommended for large files)                    │ │
│ │   Galaxy downloads only when workflow needs the data.       │ │
│ │   ✓ Start workflow design immediately                       │ │
│ │   ✓ No storage used until execution                         │ │
│ │   ✓ Can reference multiple large files without waiting      │ │
│ └─────────────────────────────────────────────────────────────┘ │
│                                                                 │
│                              [Cancel]  [Import]                 │
└─────────────────────────────────────────────────────────────────┘
```

---

### 2. Workflow Completion Panel

**Location**: `client/src/components/workflow-artifact.tsx`

**Current State**: Shows completion status and output links

**Proposed Enhancement**:

```
┌─────────────────────────────────────────────────────────────────┐
│ ✅ Workflow Completed Successfully                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│ RNA-seq Differential Expression Analysis                        │
│ Completed: Jan 9, 2026 at 3:45 PM • Duration: 47m 23s          │
│ Samples processed: 3 (via paired collection)                    │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│ OUTPUTS (12 files)                                              │
├─────────────────────────────────────────────────────────────────┤
│ 📊 counts_matrix.tsv              45 MB    [Preview] [Download] │
│ 📊 deseq2_results.csv             1.2 MB   [Preview] [Download] │
│ 📈 volcano_plot.png               340 KB   [View]    [Download] │
│ 📈 pca_plot.png                   280 KB   [View]    [Download] │
│ 📋 multiqc_report.html            2.1 MB   [View]    [Download] │
│ ... and 7 more files                       [Show All]           │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│ ACTIONS                                                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐│
│ │ 📊 Generate │ │ 🔬 Open in  │ │ 📈 Open in  │ │ 📥 Download ││
│ │    Report   │ │   Jupyter   │ │   RStudio   │ │     All     ││
│ └─────────────┘ └─────────────┘ └─────────────┘ └─────────────┘│
│                                                                 │
│ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐                │
│ │ 🔄 Rerun    │ │ ✂️ Extract   │ │ 💾 Save as  │                │
│ │   Modified  │ │ Subworkflow │ │   Template  │                │
│ └─────────────┘ └─────────────┘ └─────────────┘                │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Report View Modal**:

```
┌─────────────────────────────────────────────────────────────────┐
│ 📊 Workflow Analysis Report                          [✕] Close  │
├─────────────────────────────────────────────────────────────────┤
│ [Markdown] [HTML]                      [📥 Download] [📋 Copy]  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│ # RNA-seq Differential Expression Analysis                      │
│                                                                 │
│ **Executed**: January 9, 2026 at 3:45 PM                       │
│ **Duration**: 47 minutes 23 seconds                            │
│ **Samples**: 3 paired-end samples                              │
│                                                                 │
│ ## Parameters Used                                              │
│                                                                 │
│ | Step | Tool | Key Parameters |                               │
│ |------|------|----------------|                               │
│ | 1 | FastQC | default |                                       │
│ | 2 | Trimmomatic | LEADING:3 TRAILING:3 MINLEN:36 |          │
│ | 3 | STAR | genomeDir: hg38, outSAMtype: BAM |               │
│ | 4 | featureCounts | -t exon -g gene_id |                     │
│ | 5 | DESeq2 | padj < 0.05, |log2FC| > 1 |                     │
│                                                                 │
│ ## Results Summary                                              │
│                                                                 │
│ - **Total genes analyzed**: 24,521                             │
│ - **Differentially expressed**: 1,847 (7.5%)                   │
│   - Upregulated: 923                                           │
│   - Downregulated: 924                                         │
│                                                                 │
│ ## Quality Metrics                                              │
│                                                                 │
│ | Sample | Raw Reads | Aligned | Alignment Rate |              │
│ |--------|-----------|---------|----------------|              │
│ | sample1 | 45.2M | 42.1M | 93.1% |                            │
│ | sample2 | 48.7M | 45.3M | 93.0% |                            │
│ | sample3 | 44.9M | 41.8M | 93.1% |                            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

### 3. Subworkflow Extraction Interface

**Trigger**: "Extract Subworkflow" button in completed workflow panel

```
┌─────────────────────────────────────────────────────────────────┐
│ ✂️ Extract Subworkflow                               [✕] Close  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│ Select steps to extract as a reusable subworkflow:              │
│                                                                 │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ ☑️ Step 1: FastQC (Quality Control)                         │ │
│ │ ☑️ Step 2: Trimmomatic (Read Trimming)                      │ │
│ │ ☑️ Step 3: FastQC (Post-trim QC)                            │ │
│ │ ☐ Step 4: STAR (Alignment)                                  │ │
│ │ ☐ Step 5: featureCounts (Quantification)                    │ │
│ │ ☐ Step 6: DESeq2 (Differential Expression)                  │ │
│ └─────────────────────────────────────────────────────────────┘ │
│                                                                 │
│ Selected: 3 steps (QC + Trimming)                               │
│                                                                 │
│ Subworkflow Name:                                               │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ Standard RNA-seq QC Module                                  │ │
│ └─────────────────────────────────────────────────────────────┘ │
│                                                                 │
│ Description:                                                    │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ Quality control and trimming for paired-end RNA-seq reads.  │ │
│ │ Includes pre- and post-trimming FastQC reports.             │ │
│ └─────────────────────────────────────────────────────────────┘ │
│                                                                 │
│ ☑️ Save to my workflow library                                  │
│ ☐ Share with team                                               │
│                                                                 │
│                              [Cancel]  [Extract Subworkflow]    │
└─────────────────────────────────────────────────────────────────┘
```

---

### 4. Interactive Tool Launch

**Trigger**: "Open in Jupyter" or "Open in RStudio" button

```
┌─────────────────────────────────────────────────────────────────┐
│ 🔬 Launch Interactive Environment                    [✕] Close  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│ Choose environment:                                             │
│                                                                 │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ ● Jupyter Notebook (Python 3.10)                            │ │
│ │   Best for: Custom analysis, visualization, machine learning│ │
│ │   Pre-loaded: pandas, numpy, matplotlib, seaborn, scanpy    │ │
│ │                                                             │ │
│ │ ○ RStudio (R 4.3)                                           │ │
│ │   Best for: Statistical analysis, Bioconductor packages     │ │
│ │   Pre-loaded: DESeq2, edgeR, ggplot2, tidyverse             │ │
│ │                                                             │ │
│ │ ○ CellxGene (if single-cell data)                           │ │
│ │   Best for: Interactive single-cell visualization           │ │
│ │   Pre-loaded: Scanpy integration                            │ │
│ └─────────────────────────────────────────────────────────────┘ │
│                                                                 │
│ Data to load:                                                   │
│ ☑️ counts_matrix.tsv (45 MB)                                    │
│ ☑️ deseq2_results.csv (1.2 MB)                                  │
│ ☐ All output files                                              │
│                                                                 │
│ ⚠️ Interactive sessions timeout after 2 hours of inactivity     │
│                                                                 │
│                              [Cancel]  [Launch Environment]     │
└─────────────────────────────────────────────────────────────────┘
```

**After launch**:

```
┌─────────────────────────────────────────────────────────────────┐
│ 🔬 Jupyter Notebook Session Active                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│ Status: Running                                                 │
│ Started: 2 minutes ago                                          │
│ Timeout: 1h 58m remaining                                       │
│                                                                 │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │                                                             │ │
│ │  [🔗 Open Jupyter in New Tab]                               │ │
│ │                                                             │ │
│ └─────────────────────────────────────────────────────────────┘ │
│                                                                 │
│ Pre-loaded data:                                                │
│ • /data/counts_matrix.tsv                                       │
│ • /data/deseq2_results.csv                                      │
│                                                                 │
│ Quick start code:                                               │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ import pandas as pd                                         │ │
│ │ counts = pd.read_csv('/data/counts_matrix.tsv', sep='\t')  │ │
│ │ results = pd.read_csv('/data/deseq2_results.csv')          │ │
│ └─────────────────────────────────────────────────────────────┘ │
│                                  [📋 Copy]                      │
│                                                                 │
│                              [End Session]                      │
└─────────────────────────────────────────────────────────────────┘
```

---

## Implementation Priorities

### Priority Matrix

| Feature | User Value | Implementation Effort | Priority |
|---------|------------|----------------------|----------|
| Auto-pair detection | High | Low | **P0** |
| Collection creation UI | High | Medium | **P0** |
| Workflow reports | High | Low | **P1** |
| Deferred datasets | Medium | Low | **P1** |
| Interactive tools | Medium | Medium | **P2** |
| Subworkflow extraction | Low | High | **P3** |

### Recommended Implementation Order

#### Phase 1: Batch Processing Foundation (P0)
**Goal**: Enable multi-sample NGS workflows

1. Add pattern detection to file upload component
2. Create collection creation UI
3. Update workflow generation to use collections when available
4. Update progress UI to show per-sample status

**Files to modify**:
- `client/src/components/file-upload.tsx`
- `client/src/hooks/useWorkflowExecution.ts`
- `server/galaxy-assistant.ts`

#### Phase 2: Reports & Deferred Data (P1)
**Goal**: Improve user experience for large data and documentation

1. Add "Generate Report" button to completion panel
2. Create report viewer modal
3. Add deferred option to URL import
4. Show deferred status in dataset list

**Files to modify**:
- `client/src/components/workflow-artifact.tsx`
- `client/src/components/file-upload.tsx`

#### Phase 3: Interactive Analysis (P2)
**Goal**: Enable exploratory analysis after workflows

1. Add interactive tool launcher
2. Create session management UI
3. Integrate with existing output viewer

**Files to modify**:
- `client/src/components/workflow-artifact.tsx`
- New: `client/src/components/interactive-launcher.tsx`

#### Phase 4: Advanced Modularity (P3)
**Goal**: Power user features for workflow reuse

1. Add subworkflow extraction UI
2. Create workflow library browser
3. Enable subworkflow insertion in workflow editor

**Files to modify**:
- `client/src/components/workflow-artifact.tsx`
- New: `client/src/components/subworkflow-extractor.tsx`
- New: `client/src/components/workflow-library.tsx`

---

## Technical Specifications

### API Contracts

#### Collection Auto-Detection Request/Response

```typescript
// Client request (implicit - triggered on file upload)
// No explicit API call needed - detection happens client-side

// Pattern detection logic (client-side)
interface PairedEndDetection {
  detected: boolean;
  pairs: Array<{
    name: string;
    forward: UploadedFile;
    reverse: UploadedFile;
  }>;
  unpaired: UploadedFile[];
  pattern: '_R1/_R2' | '_1/_2' | '.R1/.R2' | null;
}

// Collection creation request
POST /api/collections/create-paired
{
  name: string;
  pairs: Array<{
    forward: string;  // dataset ID
    reverse: string;  // dataset ID
  }>;
}

// Response
{
  id: string;
  name: string;
  pairs: number;
  galaxy_history_id: string;
  message: string;
}
```

#### Workflow Report Request/Response

```typescript
// Request
GET /api/invocations/:id/report?format=markdown

// Response
{
  report: string;        // Markdown content
  format: 'markdown' | 'html';
  generated_at: string;  // ISO timestamp
}
```

#### Deferred Dataset Request/Response

```typescript
// Request
POST /api/datasets/deferred
{
  url: string;
  name?: string;
  file_type?: string;
}

// Response
{
  id: string;
  state: 'deferred';
  deferred: true;
  galaxy_history_id: string;
  source_url: string;
  message: string;
}
```

#### Interactive Tool Launch Request/Response

```typescript
// Request
POST /api/interactive/launch
{
  tool_id: 'jupyter' | 'rstudio' | 'cellxgene';
  inputs?: Record<string, any>;
}

// Response
{
  job_id: string;
  entry_point_url?: string;  // URL to open in new tab
  state: string;
  message: string;
}
```

### State Management

```typescript
// New state additions to workflow execution hook
interface WorkflowExecutionState {
  // Existing
  status: ExecutionStatus;
  progress: number;

  // New: Collection support
  collection?: {
    id: string;
    type: 'list' | 'paired' | 'list:paired';
    elementCount: number;
    perElementProgress: Record<string, number>;
  };

  // New: Deferred datasets
  deferredDatasets: Array<{
    id: string;
    url: string;
    state: 'deferred' | 'materializing' | 'ready' | 'error';
  }>;

  // New: Interactive session
  interactiveSession?: {
    jobId: string;
    toolId: string;
    entryPointUrl?: string;
    state: 'starting' | 'running' | 'stopped';
    startedAt: string;
  };
}
```

---

## Appendix: Component Hierarchy

```
App
├── ChatInterface
│   ├── MessageList
│   │   └── ChatMessage
│   │       └── WorkflowArtifact (MODIFY)
│   │           ├── WorkflowProgress
│   │           │   └── CollectionProgress (NEW)
│   │           ├── WorkflowOutputs
│   │           └── WorkflowActions (MODIFY)
│   │               ├── ReportViewer (NEW)
│   │               ├── InteractiveLauncher (NEW)
│   │               └── SubworkflowExtractor (NEW)
│   └── ChatInput
│       └── FileUpload (MODIFY)
│           ├── FileDropzone
│           ├── UploadProgress
│           ├── PairedDetection (NEW)
│           └── UrlImport (MODIFY)
│               └── DeferredOption (NEW)
└── Sidebar
    └── WorkflowLibrary (NEW - Phase 4)
```

---

## Revision History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-01-09 | Initial proposal |
