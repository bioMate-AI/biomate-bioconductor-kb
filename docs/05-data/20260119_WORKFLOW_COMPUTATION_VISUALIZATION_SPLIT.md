# Workflow Computation vs Visualization Split Architecture

**Date**: 2026-01-19
**Author**: BioMate Architecture Team
**Status**: Analysis Complete, Implementation Proposed

---

## Executive Summary

Analysis of 951 indexed workflows reveals that **70.7% (672 workflows) mix computation and visualization tools**. This creates a fundamental challenge for AWS Batch execution, as interactive visualization tools cannot run in batch environments.

### Key Findings:
- **Pure Computation**: 72 workflows (7.6%) - Ready for AWS Batch today
- **Pure Visualization**: 28 workflows (2.9%) - Interactive tools only
- **Mixed (Need Splitting)**: 672 workflows (70.7%) - Require architecture changes
- **Unclassified**: 179 workflows (18.8%) - Manual review needed

---

## Problem Statement

### Current Architecture Challenge

```
┌─────────────────────────────────────────────────────────────────────┐
│                     CURRENT: MONOLITHIC WORKFLOW                    │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  [Input Data] → [Cutadapt] → [Bowtie2] → [Samtools] → [MultiQC]    │
│                                                                     │
│  Problem: MultiQC requires web server, cannot run on AWS Batch      │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### AWS Batch Constraints

AWS Batch is designed for:
- Headless, batch-mode computation
- No persistent web servers
- No user interaction during execution
- Ephemeral containers that exit when job completes

### Interactive Tools Incompatible with AWS Batch

| Tool Category | Examples | Reason |
|--------------|----------|--------|
| QC Reporting | MultiQC, FastQC HTML | Generates interactive HTML, can run in batch |
| R Shiny Apps | Pavian, iSEE | Requires persistent R Shiny server |
| Jupyter/RStudio | Analysis notebooks | Requires persistent web server |
| Specialized Viewers | CellxGene, HiGlass | Requires persistent visualization server |
| Real-time Plotting | ggplot2 interactive | May require display server |

### Tools Compatible with AWS Batch (Batch-Mode Outputs)

| Tool Category | Examples | Output Type |
|--------------|----------|-------------|
| Read Processing | Cutadapt, Trimmomatic | FASTQ files |
| Alignment | Bowtie2, BWA, STAR, minimap2 | BAM/SAM files |
| Quantification | featureCounts, Salmon, kallisto | Count matrices |
| Variant Calling | GATK, FreeBayes, DeepVariant | VCF files |
| Assembly | SPAdes, Flye, MEGAHIT | FASTA contigs |
| Differential Expression | DESeq2 (core), limma (core) | TSV tables |

**Note**: MultiQC and FastQC can technically run in batch mode (they generate static HTML), but the *viewing* of these reports requires a web server or file download.

---

## Proposed Architecture: Two-Phase Workflows

### Design: Computation + Visualization Phases

```
┌─────────────────────────────────────────────────────────────────────┐
│                  PROPOSED: TWO-PHASE ARCHITECTURE                   │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  PHASE 1: COMPUTATION (AWS Batch)                                   │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │ [Input] → [Cutadapt] → [Bowtie2] → [Samtools] → [Outputs]    │  │
│  │                                                               │  │
│  │ Outputs: BAM, counts.tsv, stats.json                         │  │
│  └───────────────────────────────────────────────────────────────┘  │
│                              │                                      │
│                              ▼                                      │
│                    [S3/Storage Handoff]                             │
│                              │                                      │
│                              ▼                                      │
│  PHASE 2: VISUALIZATION (Interactive Container)                     │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │ [Outputs] → [MultiQC] → [Jupyter Notebook] → [Interactive]   │  │
│  │                                                               │  │
│  │ Tools: MultiQC, CellxGene, Pavian, Jupyter, RStudio          │  │
│  └───────────────────────────────────────────────────────────────┘  │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Phase Definitions

#### Phase 1: Computation Phase
- **Execution Environment**: AWS Batch (spot instances, parallel execution)
- **Characteristics**:
  - Headless execution (no display)
  - File I/O only (no web servers)
  - Parallelizable across samples
  - Cost-optimized (spot instances)
- **Output Types**: BAM, VCF, FASTQ, TSV, counts, matrices, FASTA

#### Phase 2: Visualization Phase
- **Execution Environment**: Galaxy Interactive Tools / Kubernetes pods
- **Characteristics**:
  - Interactive web servers
  - User-driven exploration
  - Single-user sessions
  - Real-time rendering
- **Tool Types**: MultiQC, CellxGene, Pavian, Jupyter, RStudio, HiGlass, iSEE

---

## Workflow Splitting Strategy

### Automatic Split Point Detection

The system should automatically detect where to split workflows based on:

1. **Tool Classification Database**
   ```python
   BATCH_COMPATIBLE_TOOLS = {
       'cutadapt', 'bowtie2', 'bwa', 'star', 'salmon', 'kallisto',
       'samtools_*', 'bcftools_*', 'bedtools_*', 'gatk_*',
       'featurecounts', 'htseq_count', 'deseq2', 'limma',
       'megahit', 'spades', 'flye', 'minimap2'
   }

   VISUALIZATION_TOOLS = {
       'multiqc', 'fastqc', 'pavian', 'cellxgene', 'isee',
       'jupyter_*', 'rstudio', 'higlass', 'openrefine',
       'ggplot2_*', 'scatterplot_*', 'heatmap_*', 'volcano_plot'
   }
   ```

2. **Split Point Rules**
   - Split BEFORE first visualization tool
   - Keep downstream visualization tools together
   - Ensure data handoff formats are compatible

### Example: RNA-Seq Workflow Split

**Original Workflow (Mixed)**:
```
1. Cutadapt (trim)
2. STAR (align)
3. featureCounts (quantify)
4. DESeq2 (DE analysis)
5. MultiQC (QC report)        ← Split point
6. Volcano Plot (visualize)
7. Pathway Enrichment (analyze)
```

**Split Result**:

**Computation Workflow** (AWS Batch):
```
1. Cutadapt → 2. STAR → 3. featureCounts → 4. DESeq2
Outputs: counts.tsv, de_results.tsv, alignment_stats.json
```

**Visualization Workflow** (Interactive):
```
5. MultiQC → 6. Volcano Plot → 7. Pathway Enrichment
Inputs: counts.tsv, de_results.tsv, alignment_stats.json
```

---

## Implementation Plan

### Phase 1: Workflow Analysis & Classification (Week 1-2)

1. **Create Tool Classification Database**
   - Classify all 951 workflows' tools as batch-compatible or interactive
   - Store classification in `tool_execution_mode` table

2. **Build Split Point Detector**
   - Analyze workflow DAG structure
   - Identify split points automatically
   - Handle edge cases (tools that can run both ways)

### Phase 2: Workflow Splitting Infrastructure (Week 2-4)

1. **Workflow Splitter Service**
   ```python
   class WorkflowSplitter:
       def split_workflow(self, workflow_id: str) -> Tuple[Workflow, Workflow]:
           """Split a workflow into computation and visualization phases."""
           original = self.load_workflow(workflow_id)
           split_point = self.detect_split_point(original)

           compute_workflow = self.extract_compute_phase(original, split_point)
           viz_workflow = self.extract_visualization_phase(original, split_point)

           # Link outputs to inputs
           self.create_data_handoff(compute_workflow, viz_workflow)

           return compute_workflow, viz_workflow
   ```

2. **Data Handoff Protocol**
   - Define intermediate data formats
   - S3 staging area between phases
   - Metadata passing (sample info, parameters)

### Phase 3: Execution Orchestration (Week 4-6)

1. **Two-Phase Executor**
   ```python
   class TwoPhaseExecutor:
       async def execute(self, workflow_id: str, inputs: Dict) -> ExecutionResult:
           # Phase 1: Computation
           compute_workflow, viz_workflow = self.splitter.split(workflow_id)

           compute_result = await self.batch_executor.run(
               compute_workflow,
               inputs,
               environment='aws_batch'
           )

           # Phase 2: Visualization (triggered when computation completes)
           if compute_result.success:
               viz_result = await self.interactive_executor.run(
                   viz_workflow,
                   compute_result.outputs,
                   environment='interactive_container'
               )

           return ExecutionResult(compute_result, viz_result)
   ```

2. **User Notification Flow**
   - Notify when computation completes
   - Provide link to launch interactive visualization
   - Allow scheduling visualization for later

### Phase 4: Integration with Interactive Tools (Week 6-8)

1. **Connect to BioMate Interactive Container**
   - Route to appropriate visualization tool based on output types
   - Use `interactive_tool_mapping.py` for tool selection
   - Pre-load data into containers

2. **Template-Based Visualization**
   - Launch Jupyter with domain-specific templates
   - Pre-configure RStudio with relevant packages
   - Auto-load data into CellxGene, Pavian, etc.

---

## Workflow Categories & Splitting Recommendations

### Category 1: RNA-Seq Pipelines (150+ workflows)

**Pattern**: Read QC → Alignment → Quantification → DE → Reporting
**Split Point**: After DE analysis, before MultiQC/plotting
**Compute Phase**: Cutadapt, STAR/HISAT2, featureCounts, DESeq2
**Viz Phase**: MultiQC, Volcano plots, Heatmaps, Pathway enrichment

### Category 2: Single-Cell RNA-Seq (30-40 workflows)

**Pattern**: Cellranger/STARsolo → Scanpy processing → Visualization
**Split Point**: After clustering/annotation, before interactive exploration
**Compute Phase**: Alignment, filtering, normalization, clustering
**Viz Phase**: CellxGene, UMAP plots, Marker gene exploration

### Category 3: ChIP-seq/ATAC-seq (80-100 workflows)

**Pattern**: Alignment → Peak calling → Annotation → Motif analysis
**Split Point**: After peak calling/annotation, before browser visualization
**Compute Phase**: Bowtie2, MACS2, bedtools, HOMER
**Viz Phase**: HiGlass, IGV tracks, Peak annotation plots

### Category 4: Metagenomics (40+ workflows)

**Pattern**: QC → Classification → Abundance → Diversity analysis
**Split Point**: After taxonomic classification, before interactive exploration
**Compute Phase**: Cutadapt, Kraken2/Bracken, Metaphlan
**Viz Phase**: Pavian, Krona, Diversity plots

### Category 5: Variant Calling (40-50 workflows)

**Pattern**: Alignment → Variant calling → Annotation → Filtering
**Split Point**: After annotation, before variant exploration
**Compute Phase**: BWA, GATK, SnpEff/VEP
**Viz Phase**: Variant browsers, Quality plots, Circos plots

---

## Data Handoff Formats

### Standard Intermediate Outputs

| Data Type | Format | Use Case |
|-----------|--------|----------|
| Alignments | BAM + BAI | Genome browsers, coverage analysis |
| Counts | TSV matrix | DE analysis, clustering |
| Variants | VCF.gz + TBI | Variant browsers, annotation |
| DE Results | TSV with headers | Volcano plots, pathway analysis |
| QC Metrics | JSON | MultiQC aggregation |
| Taxonomy | Kraken reports | Pavian visualization |
| Single-cell | H5AD | CellxGene, Scanpy notebooks |

### Metadata Handoff

```json
{
  "execution_id": "uuid",
  "workflow_id": "rna_seq_deseq2",
  "phase": "computation_complete",
  "outputs": {
    "counts_matrix": "s3://bucket/outputs/counts.tsv",
    "de_results": "s3://bucket/outputs/de_results.tsv",
    "qc_metrics": "s3://bucket/outputs/qc_metrics.json"
  },
  "sample_metadata": {
    "samples": ["sample1", "sample2", "sample3"],
    "conditions": ["control", "treatment", "treatment"]
  },
  "recommended_visualizations": [
    {"tool": "multiqc", "confidence": 0.95},
    {"tool": "deseq2_visualization", "confidence": 0.9},
    {"tool": "pathway_enrichment", "confidence": 0.85}
  ]
}
```

---

## Cost & Performance Benefits

### Expected Improvements

| Metric | Current | After Split | Improvement |
|--------|---------|-------------|-------------|
| Computation Cost | 1x (on-demand) | 0.3-0.5x (spot) | 50-70% reduction |
| Parallelization | Limited | Full sample parallelism | 2-5x faster |
| Interactive Responsiveness | Waiting for compute | Instant after compute | Better UX |
| Resource Utilization | Mixed | Specialized per phase | More efficient |

### ROI Timeline

- **Month 1-2**: Infrastructure development
- **Month 3**: Pilot with top 10 workflows
- **Month 4-6**: Roll out to all 672 mixed workflows
- **Month 6+**: Full cost savings realized

---

## Integration with Existing Systems

### Interactive Tool Mapping (`interactive_tool_mapping.py`)

The existing tool mapping system will be extended to:
1. Classify tools as batch-compatible or interactive
2. Suggest split points based on tool classification
3. Recommend visualization tools based on computation outputs

### Enhanced Workflow Generator

Add methods to:
1. Detect if workflow needs splitting
2. Generate split workflow variants
3. Create data handoff specifications

### BioMate Interactive Container

Already supports all required visualization tools:
- JupyterLab with domain templates
- RStudio with Bioconductor packages
- CellxGene, Pavian, HiGlass, iSEE, OpenRefine, EtherCalc

---

## Next Steps

1. **Immediate**: Review this architecture with team
2. **Week 1**: Implement tool classification database
3. **Week 2**: Build workflow split point detector
4. **Week 3-4**: Develop data handoff protocol
5. **Week 5-6**: Integrate with AWS Batch executor
6. **Week 7-8**: Connect visualization phase to interactive containers
7. **Ongoing**: Migrate existing workflows to two-phase architecture

---

## Appendix: Workflow Analysis Statistics

### Tool Occurrence Counts

**Top Computation Tools**:
1. Cutadapt: 411 workflows
2. Bowtie2: 324 workflows
3. Samtools view: 322 workflows
4. bedtools: 188-210 workflows
5. minimap2: 121 workflows

**Top Visualization Tools**:
1. MultiQC: 575 workflows
2. Wig/BedGraph-to-bigWig: 452 workflows
3. BUSCO: 178 workflows
4. FastQC: 62 workflows
5. ggplot2 plots: 70 workflows

### Splitting Complexity Distribution

- **Easy splits** (1-3 viz tools): 222 workflows
- **Medium splits** (4-6 viz tools): 23 workflows
- **Complex splits** (7+ viz tools): 3 workflows
