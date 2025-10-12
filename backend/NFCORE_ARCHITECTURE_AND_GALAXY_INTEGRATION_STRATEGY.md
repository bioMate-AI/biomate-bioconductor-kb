# nf-core Architecture & Galaxy Integration Strategy
**Date:** 2025-10-12
**Status:** Comprehensive Analysis & Workflow Conversion Plan

---

## Executive Summary

nf-core uses a **3-tier hierarchical architecture**:
1. **Modules** (1,629 implementations) - Atomic tool wrappers
2. **Subworkflows** (88 workflows) - Reusable multi-step pipelines
3. **Pipelines** (Full workflows) - Complete analysis workflows with branching logic

This document analyzes how nf-core organizes bioinformatics tools and provides a detailed strategy for converting this structure to Galaxy, including handling conditional branches, parameter inheritance, and workflow composition.

---

## Part 1: nf-core Architecture Deep Dive

### **1.1 The 3-Tier Hierarchy**

```
nf-core-modules/
├── modules/nf-core/           # Tier 1: Atomic Tools
│   ├── fastqc/               # 748 module directories
│   │   └── main.nf           # 1,629 module implementations
│   ├── samtools/
│   │   ├── stats/main.nf
│   │   ├── flagstat/main.nf
│   │   └── idxstats/main.nf
│   └── gatk4/
│       ├── mutect2/main.nf
│       └── (40+ sub-modules)
│
├── subworkflows/nf-core/      # Tier 2: Reusable Workflows
│   ├── bam_stats_samtools/    # 88 subworkflows
│   │   └── main.nf            # Uses 3 modules
│   ├── fastq_fastqc_umitools_trimgalore/
│   │   └── main.nf            # Uses 3 modules + conditional logic
│   └── bam_tumor_normal_somatic_variant_calling_gatk/
│       └── main.nf            # Uses 6 modules + complex logic
│
└── (Full pipelines would be separate repos)
    nf-core/rnaseq/
    nf-core/sarek/
    nf-core/viralrecon/
    └── workflows/main.nf       # Uses modules + subworkflows
```

---

### **1.2 Tier 1: Modules (Atomic Tools)**

**Statistics:**
- 748 module directories
- 1,629 module implementations (many tools have multiple sub-commands)
- Examples: fastqc, samtools (13 sub-commands), gatk4 (40+ sub-commands)

**Module Structure:** Each module is a **single-tool wrapper**

**Example: FastQC Module** (`modules/nf-core/fastqc/main.nf`)

```groovy
process FASTQC {
    tag "${meta.id}"
    label 'process_medium'

    // Container specification (Singularity or Docker)
    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' ?
        'https://depot.galaxyproject.org/singularity/fastqc:0.12.1--hdfd78af_0' :
        'biocontainers/fastqc:0.12.1--hdfd78af_0' }"

    // Inputs: tuple with metadata + file(s)
    input:
    tuple val(meta), path(reads)

    // Outputs: multiple named outputs
    output:
    tuple val(meta), path("*.html"), emit: html
    tuple val(meta), path("*.zip") , emit: zip
    path  "versions.yml"           , emit: versions

    // Conditional execution
    when:
    task.ext.when == null || task.ext.when

    // Script template with parameter expansion
    script:
    def args          = task.ext.args ?: ''
    def prefix        = task.ext.prefix ?: "${meta.id}"
    def memory_in_mb  = task.memory ? task.memory.toUnit('MB') / task.cpus : null
    def fastqc_memory = memory_in_mb > 10000 ? 10000 : (memory_in_mb < 100 ? 100 : memory_in_mb)

    """
    fastqc \\
        ${args} \\
        --threads ${task.cpus} \\
        --memory ${fastqc_memory} \\
        ${reads}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        fastqc: \$( fastqc --version | sed '/FastQC v/!d; s/.*v//' )
    END_VERSIONS
    """
}
```

**Key Features:**
1. ✅ **Metadata passing** - `tuple val(meta), path(reads)` carries sample info
2. ✅ **Container support** - Both Singularity and Docker
3. ✅ **Conda environment** - `environment.yml` for dependencies
4. ✅ **Multiple outputs** - Named output channels (html, zip, versions)
5. ✅ **Resource management** - Dynamic memory/CPU allocation
6. ✅ **Version tracking** - Automatic version capture
7. ✅ **Conditional execution** - `when:` clause for optional steps

---

### **1.3 Tier 2: Subworkflows (Reusable Multi-Step Pipelines)**

**Statistics:**
- 88 subworkflows
- Each subworkflow uses 2-6 modules on average
- Includes conditional logic, data splitting/joining, filtering

**Subworkflows are NOT just linear pipelines** - they include:
- Conditional branching (`if/else`)
- Parameter-driven execution
- Data transformations
- Channel operations (join, split, filter)

---

#### **Example 1: Simple Subworkflow**

**`BAM_STATS_SAMTOOLS`** - Runs 3 SAMtools commands in parallel

```groovy
include { SAMTOOLS_STATS    } from '../../../modules/nf-core/samtools/stats/main'
include { SAMTOOLS_IDXSTATS } from '../../../modules/nf-core/samtools/idxstats/main'
include { SAMTOOLS_FLAGSTAT } from '../../../modules/nf-core/samtools/flagstat/main'

workflow BAM_STATS_SAMTOOLS {
    take:
    ch_bam_bai // channel: [ val(meta), path(bam), path(bai) ]
    ch_fasta   // channel: [ val(meta), path(fasta) ]

    main:
    ch_versions = Channel.empty()

    // Run 3 tools in parallel
    SAMTOOLS_STATS ( ch_bam_bai, ch_fasta )
    SAMTOOLS_FLAGSTAT ( ch_bam_bai )
    SAMTOOLS_IDXSTATS ( ch_bam_bai )

    // Collect versions
    ch_versions = ch_versions.mix(SAMTOOLS_STATS.out.versions)
                             .mix(SAMTOOLS_FLAGSTAT.out.versions)
                             .mix(SAMTOOLS_IDXSTATS.out.versions)

    emit:
    stats    = SAMTOOLS_STATS.out.stats
    flagstat = SAMTOOLS_FLAGSTAT.out.flagstat
    idxstats = SAMTOOLS_IDXSTATS.out.idxstats
    versions = ch_versions
}
```

**Analysis:**
- **Pattern:** Parallel execution of 3 independent tools
- **Galaxy equivalent:** Simple workflow with 3 parallel steps
- **No conditionals** - always runs all 3 tools

---

#### **Example 2: Conditional Subworkflow**

**`FASTQ_FASTQC_UMITOOLS_TRIMGALORE`** - QC pipeline with optional steps

```groovy
include { FASTQC           } from '../../../modules/nf-core/fastqc/main'
include { UMITOOLS_EXTRACT } from '../../../modules/nf-core/umitools/extract/main'
include { TRIMGALORE       } from '../../../modules/nf-core/trimgalore/main'

workflow FASTQ_FASTQC_UMITOOLS_TRIMGALORE {
    take:
    reads             // channel: [ val(meta), [ reads ] ]
    skip_fastqc       // boolean: true/false
    with_umi          // boolean: true/false
    skip_umi_extract  // boolean: true/false
    skip_trimming     // boolean: true/false
    umi_discard_read  // integer: 0, 1 or 2
    min_trimmed_reads // integer: > 0

    main:
    ch_versions = Channel.empty()
    fastqc_html = Channel.empty()

    // STEP 1: Optional FastQC
    if (!skip_fastqc) {
        FASTQC(reads)
        fastqc_html = FASTQC.out.html
        ch_versions = ch_versions.mix(FASTQC.out.versions.first())
    }

    // STEP 2: Optional UMI extraction
    umi_reads = reads
    if (with_umi && !skip_umi_extract) {
        UMITOOLS_EXTRACT(reads)
        umi_reads = UMITOOLS_EXTRACT.out.reads
        ch_versions = ch_versions.mix(UMITOOLS_EXTRACT.out.versions.first())

        // Optional: Discard R1 or R2
        if (umi_discard_read in [1, 2]) {
            UMITOOLS_EXTRACT.out.reads
                .map { meta, reads ->
                    meta.single_end ? [meta, reads] : [meta + ['single_end': true], reads[umi_discard_read % 2]]
                }
                .set { umi_reads }
        }
    }

    // STEP 3: Optional trimming with filtering
    trim_reads = umi_reads
    if (!skip_trimming) {
        TRIMGALORE(umi_reads)

        // Filter reads by minimum count
        TRIMGALORE.out.reads
            .join(TRIMGALORE.out.log)
            .map { meta, reads_, trim_log_ ->
                def num_reads = getTrimGaloreReadsAfterFiltering(trim_log_)
                [meta, reads_, num_reads]
            }
            .filter { _meta, _reads, num_reads -> num_reads >= min_trimmed_reads.toFloat() }
            .map { meta, reads_, _num_reads -> [meta, reads_] }
            .set { trim_reads }
    }

    emit:
    reads = trim_reads
    fastqc_html
    // ... other outputs
}
```

**Analysis:**
- **Conditional Steps:** 3 optional stages (FastQC, UMI extract, TrimGalore)
- **Data Filtering:** Removes samples with too few reads
- **Channel Transformations:** `.map`, `.filter`, `.join` operations
- **Nested Conditionals:** UMI discard logic within UMI extraction
- **Galaxy Challenge:** How to represent optional steps?

---

#### **Example 3: Complex Subworkflow**

**`BAM_TUMOR_NORMAL_SOMATIC_VARIANT_CALLING_GATK`** - Tumor/normal variant calling

```groovy
include { GATK4_MUTECT2                                               } from '...'
include { GATK4_LEARNREADORIENTATIONMODEL                             } from '...'
include { GATK4_GETPILEUPSUMMARIES as GATK4_GETPILEUPSUMMARIES_TUMOR  } from '...'
include { GATK4_GETPILEUPSUMMARIES as GATK4_GETPILEUPSUMMARIES_NORMAL } from '...'
include { GATK4_CALCULATECONTAMINATION                                } from '...'
include { GATK4_FILTERMUTECTCALLS                                     } from '...'

workflow BAM_TUMOR_NORMAL_SOMATIC_VARIANT_CALLING_GATK {
    take:
    ch_input                 // [ val(meta), path(tumor_bam), path(normal_bam), ... ]
    ch_fasta
    ch_germline_resource
    ch_panel_of_normals
    ch_interval_file
    // ... 10+ input channels

    main:
    // STEP 1: Call variants (Mutect2)
    GATK4_MUTECT2(ch_input, ch_fasta, ...)

    // STEP 2: Learn orientation artifacts
    GATK4_LEARNREADORIENTATIONMODEL(GATK4_MUTECT2.out.f1r2.collect())

    // STEP 3: Split input into tumor/normal
    ch_pileup_tumor_input = ch_input
        .map { meta, input_file, input_index, _which_norm, intervals ->
            [meta, input_file[0], input_index[0], intervals]  // Extract tumor
        }

    ch_pileup_normal_input = ch_input
        .map { meta, input_file, input_index, _which_norm, intervals ->
            [meta, input_file[1], input_index[1], intervals]  // Extract normal
        }

    // STEP 4: Get pileup summaries (parallel for tumor + normal)
    GATK4_GETPILEUPSUMMARIES_TUMOR(ch_pileup_tumor_input, ...)
    GATK4_GETPILEUPSUMMARIES_NORMAL(ch_pileup_normal_input, ...)

    // STEP 5: Join tumor/normal pileups
    ch_pileup_tumor = GATK4_GETPILEUPSUMMARIES_TUMOR.out.table.collect()
    ch_pileup_normal = GATK4_GETPILEUPSUMMARIES_NORMAL.out.table.collect()
    ch_calccon_in = ch_pileup_tumor.join(ch_pileup_normal)

    // STEP 6: Calculate contamination
    GATK4_CALCULATECONTAMINATION(ch_calccon_in)

    // STEP 7: Join all outputs for filtering
    ch_filtermutect_in = GATK4_MUTECT2.out.vcf
        .join(GATK4_MUTECT2.out.tbi)
        .join(GATK4_MUTECT2.out.stats)
        .join(GATK4_LEARNREADORIENTATIONMODEL.out.artifactprior)
        .join(GATK4_CALCULATECONTAMINATION.out.segmentation)
        .join(GATK4_CALCULATECONTAMINATION.out.contamination)

    // STEP 8: Filter variant calls
    GATK4_FILTERMUTECTCALLS(ch_filtermutect_in, ch_fasta, ...)

    emit:
    vcf         = GATK4_FILTERMUTECTCALLS.out.vcf
    tbi         = GATK4_FILTERMUTECTCALLS.out.tbi
    stats       = GATK4_FILTERMUTECTCALLS.out.stats
    // ... other outputs
}
```

**Analysis:**
- **Complex Data Flow:** 8 sequential + parallel steps
- **Channel Splitting:** Separates tumor/normal from paired input
- **Module Reuse:** GATK4_GETPILEUPSUMMARIES used twice with different inputs
- **Multi-way Joins:** 6-way join before filtering step
- **Galaxy Challenge:** How to represent data splitting and joining?

---

### **1.4 Tier 3: Full Pipelines (How They Use Modules + Subworkflows)**

Full nf-core pipelines (e.g., nf-core/rnaseq, nf-core/sarek) combine:
- **20-50 modules** directly
- **5-15 subworkflows** as reusable blocks
- **Conditional branches** based on user parameters
- **Scatter-gather** patterns for parallelization

**Example Pipeline Structure** (nf-core/rnaseq simplified):

```groovy
workflow RNASEQ {
    take:
    ch_reads

    main:
    // Branch 1: Quality Control
    if (!params.skip_qc) {
        FASTQ_FASTQC_UMITOOLS_TRIMGALORE(
            ch_reads,
            params.skip_fastqc,
            params.with_umi,
            ...
        )
        ch_processed_reads = FASTQ_FASTQC_UMITOOLS_TRIMGALORE.out.reads
    } else {
        ch_processed_reads = ch_reads
    }

    // Branch 2: Alignment (choose aligner)
    if (params.aligner == 'star') {
        FASTQ_ALIGN_STAR(ch_processed_reads, ch_star_index, ...)
        ch_bam = FASTQ_ALIGN_STAR.out.bam
    } else if (params.aligner == 'hisat2') {
        ALIGN_HISAT2(ch_processed_reads, ch_hisat2_index, ...)
        ch_bam = ALIGN_HISAT2.out.bam
    }

    // Branch 3: BAM processing
    BAM_SORT_STATS_SAMTOOLS(ch_bam, ch_fasta)

    if (params.mark_duplicates) {
        BAM_MARKDUPLICATES_PICARD(BAM_SORT_STATS_SAMTOOLS.out.bam)
        ch_final_bam = BAM_MARKDUPLICATES_PICARD.out.bam
    } else {
        ch_final_bam = BAM_SORT_STATS_SAMTOOLS.out.bam
    }

    // Branch 4: Quantification
    if (params.quantify_salmon) {
        SALMON_QUANT(ch_reads, ch_salmon_index)
    }
    if (params.quantify_featurecounts) {
        FEATURECOUNTS(ch_final_bam, ch_gtf)
    }

    emit:
    bam = ch_final_bam
    counts = FEATURECOUNTS.out.counts
}
```

**Key Patterns:**
1. **Conditional Branches** - `if (params.skip_qc)`, `if (params.aligner == 'star')`
2. **Alternative Paths** - Different aligners, different quantification methods
3. **Sequential Dependencies** - QC → Alignment → Quantification
4. **Optional Steps** - Mark duplicates, multiple quantifiers
5. **Parameter-Driven** - User controls which steps run

---

## Part 2: Answering Your Questions

### **Q1: Are modules in my analysis also part of subworkflows?**

**Answer: YES - Most modules are used BOTH independently and within subworkflows**

**Statistics:**
- **748 module directories** total
- **82 of 88 subworkflows** use modules from the main module library
- **Shared modules** are the norm, not the exception

**Examples:**

| Module | Used Standalone | Used in Subworkflows | Subworkflow Examples |
|--------|-----------------|---------------------|---------------------|
| `fastqc` | ✅ Yes | ✅ Yes (3 subworkflows) | `fastq_fastqc_umitools_trimgalore`, `fastq_fastqc_umitools_fastp` |
| `samtools/stats` | ✅ Yes | ✅ Yes (5 subworkflows) | `bam_stats_samtools`, `bam_sort_stats_samtools`, `bam_split_by_region` |
| `gatk4/mutect2` | ✅ Yes | ✅ Yes (2 subworkflows) | `bam_tumor_normal_somatic_variant_calling_gatk`, `bam_tumor_only_somatic_variant_calling_gatk` |
| `trimgalore` | ✅ Yes | ✅ Yes (2 subworkflows) | `fastq_fastqc_umitools_trimgalore` |

**Key Insight:** Modules are **building blocks** used everywhere - there's NO separate set of "subworkflow-only modules"

---

### **Q2: Are there additional modules only used in subworkflows?**

**Answer: NO - All modules are from the shared `modules/nf-core/` directory**

**Evidence:**
```groovy
// Every subworkflow includes modules from the shared library
include { FASTQC } from '../../../modules/nf-core/fastqc/main'
include { SAMTOOLS_STATS } from '../../../modules/nf-core/samtools/stats/main'
```

The path `../../../modules/nf-core/` confirms modules are shared.

**Why This Matters for Galaxy:**
- ✅ Converting the 1,629 modules to Galaxy tools covers BOTH standalone use and subworkflow use
- ✅ No need to convert different versions of tools for subworkflows
- ✅ Galaxy workflows can reuse the same tool XMLs

---

### **Q3: How are multiple workflows with different parameters handled in Nextflow?**

**Answer: Nextflow uses CONDITIONAL BRANCHING and PARAMETER-DRIVEN EXECUTION**

**Mechanism 1: Conditional Steps** (if/else)

```groovy
workflow MY_WORKFLOW {
    take:
    reads
    skip_qc
    aligner

    main:
    // Conditional QC
    if (!skip_qc) {
        FASTQC(reads)
        processed_reads = FASTQC.out.reads
    } else {
        processed_reads = reads
    }

    // Conditional aligner choice
    if (aligner == 'star') {
        STAR(processed_reads, star_index)
        bam = STAR.out.bam
    } else if (aligner == 'hisat2') {
        HISAT2(processed_reads, hisat2_index)
        bam = HISAT2.out.bam
    }

    emit:
    bam
}
```

**Mechanism 2: `when:` Clauses in Modules**

```groovy
process OPTIONAL_TOOL {
    input:
    tuple val(meta), path(input)

    when:
    !params.skip_this_step  // <-- Only runs if parameter is true

    script:
    """
    tool --input ${input}
    """
}
```

**Mechanism 3: Branching Channels**

```groovy
// Split reads into long and short
ch_reads
    .branch { meta, reads ->
        long: reads.size() > 1000000
        short: reads.size() <= 1000000
    }
    .set { branched_reads }

// Process each branch differently
LONG_READ_ALIGNER(branched_reads.long)
SHORT_READ_ALIGNER(branched_reads.short)
```

---

### **Q4: Should Nextflow workflows be split into multiple Galaxy workflows?**

**Answer: YES - Different execution paths should be SEPARATE Galaxy workflows**

**Rationale:**

| Nextflow Approach | Galaxy Approach | Reason |
|-------------------|-----------------|--------|
| Single workflow with conditionals | Multiple workflow variants | Galaxy doesn't support complex conditionals |
| Parameter-driven branching | User selects workflow upfront | Galaxy workflows are static |
| Runtime decision (if/else) | Design-time choice | Clearer user experience |

**Conversion Strategy:**

#### **Nextflow Workflow with Branches:**

```groovy
workflow VARIANT_CALLING {
    if (params.mode == 'tumor_only') {
        BAM_TUMOR_ONLY_VARIANT_CALLING(bam)
    } else if (params.mode == 'tumor_normal') {
        BAM_TUMOR_NORMAL_VARIANT_CALLING(tumor_bam, normal_bam)
    }
}
```

#### **Galaxy Conversion: 2 Separate Workflows**

**Workflow 1:** `Variant Calling (Tumor Only).ga`
```
Input: Tumor BAM
↓
GATK Mutect2 (Tumor Only Mode)
↓
Learn Read Orientation
↓
Get Pileup Summaries
↓
Filter Calls
↓
Output: Filtered VCF
```

**Workflow 2:** `Variant Calling (Tumor-Normal).ga`
```
Input: Tumor BAM, Normal BAM
↓
GATK Mutect2 (Tumor-Normal Mode)
↓
Split: Tumor Pileup | Normal Pileup
         ↓                ↓
Get Pileup Summaries (parallel)
         ↓                ↓
     Join tumor + normal
              ↓
     Calculate Contamination
              ↓
       Filter Calls
              ↓
    Output: Filtered VCF
```

**Benefits:**
- ✅ Clearer to users (explicit workflow names)
- ✅ Simpler parameter interfaces
- ✅ No hidden conditional logic
- ✅ Better documentation per use case

---

## Part 3: Galaxy Integration Strategy for nf-core

### **3.1 Three-Tier Conversion Approach**

| nf-core Tier | Galaxy Equivalent | Conversion Strategy |
|--------------|-------------------|---------------------|
| **Tier 1: Modules** | Individual Galaxy Tools | Convert each module to tool XML (already done: 311 tools) |
| **Tier 2: Subworkflows** | Galaxy Sub-workflows | Convert to reusable workflow components |
| **Tier 3: Pipelines** | Multiple Galaxy Workflows | Split conditional branches into separate workflows |

---

### **3.2 Module → Galaxy Tool Conversion** (Already Complete)

✅ **Status:** 311 nf-core modules converted to Galaxy XML

**What Was Converted:**
- Single-module wrappers (e.g., fastqc.xml, samtools_stats.xml)
- Container specifications (Docker/Singularity)
- Parameter mappings
- Output declarations

**What Still Needs Work:**
- Testing with real data
- Parameter validation
- Metadata handling (`tuple val(meta)`)

---

### **3.3 Subworkflow → Galaxy Workflow Conversion**

#### **Step 1: Simple Subworkflows (No Conditionals)**

**Example:** `BAM_STATS_SAMTOOLS` → Direct Galaxy workflow

**Nextflow Subworkflow:**
```groovy
workflow BAM_STATS_SAMTOOLS {
    SAMTOOLS_STATS(ch_bam_bai, ch_fasta)
    SAMTOOLS_FLAGSTAT(ch_bam_bai)
    SAMTOOLS_IDXSTATS(ch_bam_bai)
}
```

**Galaxy Workflow XML:**
```xml
<workflow name="BAM Stats (SAMtools)">
  <!-- Step 1: SAMtools stats -->
  <step id="1" tool_id="samtools_stats">
    <input name="bam" value="input_bam"/>
    <input name="fasta" value="input_fasta"/>
  </step>

  <!-- Step 2: SAMtools flagstat (parallel) -->
  <step id="2" tool_id="samtools_flagstat">
    <input name="bam" value="input_bam"/>
  </step>

  <!-- Step 3: SAMtools idxstats (parallel) -->
  <step id="3" tool_id="samtools_idxstats">
    <input name="bam" value="input_bam"/>
  </step>

  <!-- Outputs -->
  <output name="stats" from="1.stats"/>
  <output name="flagstat" from="2.flagstat"/>
  <output name="idxstats" from="3.idxstats"/>
</workflow>
```

**Conversion:** Straightforward 1:1 mapping

---

#### **Step 2: Conditional Subworkflows**

**Challenge:** Galaxy doesn't support `if/else` in workflows

**Solution:** Create workflow VARIANTS

**Example:** `FASTQ_FASTQC_UMITOOLS_TRIMGALORE` → 4 Galaxy workflow variants

**Variant 1:** `FASTQ QC (Full Pipeline).ga`
- Runs: FastQC → UMI Extract → TrimGalore

**Variant 2:** `FASTQ QC (Skip FastQC).ga`
- Runs: UMI Extract → TrimGalore

**Variant 3:** `FASTQ QC (No UMI).ga`
- Runs: FastQC → TrimGalore

**Variant 4:** `FASTQ QC (Trimming Only).ga`
- Runs: TrimGalore only

**Implementation:**
```python
# Script to generate workflow variants
def generate_fastq_qc_variants():
    steps = {
        'fastqc': {'tool': 'fastqc', 'optional': True},
        'umi_extract': {'tool': 'umitools_extract', 'optional': True},
        'trimgalore': {'tool': 'trimgalore', 'optional': False}
    }

    variants = [
        {'name': 'Full Pipeline', 'steps': ['fastqc', 'umi_extract', 'trimgalore']},
        {'name': 'Skip FastQC', 'steps': ['umi_extract', 'trimgalore']},
        {'name': 'No UMI', 'steps': ['fastqc', 'trimgalore']},
        {'name': 'Trimming Only', 'steps': ['trimgalore']}
    ]

    for variant in variants:
        generate_galaxy_workflow(variant['name'], variant['steps'])
```

---

#### **Step 3: Complex Data Flow Subworkflows**

**Challenge:** Channel splitting, joining, filtering

**Example:** `BAM_TUMOR_NORMAL_VARIANT_CALLING` has:
- Input splitting (tumor/normal separation)
- Parallel processing
- Multi-way joins (6 inputs for final filter step)

**Galaxy Solution:** Use workflow **data collections** and **list operations**

**Galaxy Workflow (Simplified):**
```xml
<workflow name="Tumor-Normal Variant Calling (GATK)">
  <!-- Step 1: Split tumor/normal input -->
  <step id="1" tool_id="split_bam_collection">
    <input name="input_collection" value="tumor_normal_bams"/>
    <output name="tumor_bam" label="tumor"/>
    <output name="normal_bam" label="normal"/>
  </step>

  <!-- Step 2: Mutect2 variant calling -->
  <step id="2" tool_id="gatk_mutect2">
    <input name="tumor" value="1.tumor_bam"/>
    <input name="normal" value="1.normal_bam"/>
    <input name="fasta" value="reference_fasta"/>
  </step>

  <!-- Step 3: Learn orientation (uses Mutect2 f1r2 output) -->
  <step id="3" tool_id="gatk_learnreadorientationmodel">
    <input name="f1r2" value="2.f1r2"/>
  </step>

  <!-- Step 4: Get pileup summaries (tumor) -->
  <step id="4" tool_id="gatk_getpileupsummaries">
    <input name="bam" value="1.tumor_bam"/>
    <input name="fasta" value="reference_fasta"/>
  </step>

  <!-- Step 5: Get pileup summaries (normal) -->
  <step id="5" tool_id="gatk_getpileupsummaries">
    <input name="bam" value="1.normal_bam"/>
    <input name="fasta" value="reference_fasta"/>
  </step>

  <!-- Step 6: Calculate contamination -->
  <step id="6" tool_id="gatk_calculatecontamination">
    <input name="tumor_pileup" value="4.pileup"/>
    <input name="normal_pileup" value="5.pileup"/>
  </step>

  <!-- Step 7: Filter calls (joins 6 inputs) -->
  <step id="7" tool_id="gatk_filtermutectcalls">
    <input name="vcf" value="2.vcf"/>
    <input name="stats" value="2.stats"/>
    <input name="orientation" value="3.artifact_prior"/>
    <input name="contamination" value="6.contamination"/>
    <input name="segmentation" value="6.segmentation"/>
    <input name="fasta" value="reference_fasta"/>
  </step>

  <output name="filtered_vcf" from="7.vcf"/>
</workflow>
```

**Key Techniques:**
- ✅ **Collection splitting** - Separate tumor/normal at start
- ✅ **Parallel steps** - Steps 4 & 5 run independently
- ✅ **Multiple inputs** - Step 7 takes 6 inputs (joins)
- ✅ **Explicit connections** - `value="2.vcf"` syntax

---

### **3.4 Full Pipeline Conversion**

**Approach:** Create **workflow collections** for different analysis modes

**Example: nf-core/rnaseq → Galaxy Workflow Suite**

**Collection Name:** "RNA-seq Analysis Suite"

**Workflows:**

1. **RNA-seq (STAR + featureCounts).ga**
   - Aligner: STAR
   - Quantification: featureCounts
   - QC: Full pipeline

2. **RNA-seq (HISAT2 + StringTie).ga**
   - Aligner: HISAT2
   - Quantification: StringTie
   - QC: Full pipeline

3. **RNA-seq (Salmon Pseudo-alignment).ga**
   - Aligner: None (pseudo-alignment)
   - Quantification: Salmon
   - QC: FastQC + MultiQC only

4. **RNA-seq (STAR + Salmon).ga**
   - Aligner: STAR (for BAM output)
   - Quantification: Salmon (for counts)
   - QC: Full pipeline

**Why Multiple Workflows:**
- Different aligner choices
- Different quantification methods
- Optional steps (UMI handling, duplicate marking)
- Different starting points (FASTQ vs BAM)

**Benefits:**
- ✅ Clear naming (users know what they're running)
- ✅ Optimized parameters per workflow
- ✅ Easier troubleshooting
- ✅ Better documentation per use case

---

## Part 4: Implementation Plan

### **Phase 1: Module Testing** (Week 1-2)
✅ Test the 311 converted Galaxy tool XMLs
- Run with sample data
- Verify container execution
- Check output formats

### **Phase 2: Simple Subworkflows** (Week 3-4)
✅ Convert 10 simple subworkflows (no conditionals)
- `bam_stats_samtools`
- `bam_sort_stats_samtools`
- `fastq_align_star`
- (7 more)

### **Phase 3: Conditional Subworkflows** (Week 5-8)
✅ Convert 5 subworkflows with conditionals → Multiple variants
- `fastq_fastqc_umitools_trimgalore` → 4 variants
- `bam_markduplicates_picard` → 2 variants
- (3 more)

### **Phase 4: Complex Subworkflows** (Week 9-12)
✅ Convert 3 complex subworkflows with data splitting/joining
- `bam_tumor_normal_somatic_variant_calling_gatk`
- `vcf_phase_shapeit5`
- `bam_variant_calling_sort_freebayes_bcftools`

### **Phase 5: Full Pipeline Conversion** (Week 13-16)
✅ Create workflow collections for 2-3 full pipelines
- nf-core/rnaseq → "RNA-seq Analysis Suite" (4-6 workflows)
- nf-core/sarek → "Variant Calling Suite" (3-4 workflows)

---

## Part 5: Technical Solutions for Galaxy Challenges

### **Challenge 1: Metadata Handling**

**Nextflow:** Uses `tuple val(meta), path(file)` everywhere
```groovy
tuple val(meta), path(reads)  // meta = [id: "sample1", single_end: false]
```

**Galaxy Solution:** Use **dataset tags** and **identifiers**
```xml
<param name="reads" type="data" format="fastq">
  <label>Sequencing Reads</label>
  <metadata name="sample_id" value="$reads.element_identifier"/>
</param>
```

---

### **Challenge 2: Conditional Steps**

**Nextflow:** `if (!params.skip_qc) { FASTQC(reads) }`

**Galaxy Solution:** Create **workflow variants**
- Workflow A: With QC
- Workflow B: Without QC

---

### **Challenge 3: Channel Operations**

**Nextflow Operations:**
```groovy
ch_reads.branch { meta, reads ->
    long: reads.size() > 1000000
    short: reads.size() <= 1000000
}

ch_tumor_normal.join(ch_reference)

ch_results.collect()
```

**Galaxy Solutions:**

| Nextflow Operation | Galaxy Equivalent |
|-------------------|-------------------|
| `.branch` | Collection filtering + separate workflows |
| `.join` | Multiple inputs to same tool |
| `.collect` | Collection creation |
| `.map` | Tool with transformation script |
| `.filter` | Filter collection tool |

---

### **Challenge 4: Module Reuse with Different Parameters**

**Nextflow:** Same module called multiple times
```groovy
GATK4_GETPILEUPSUMMARIES_TUMOR(tumor_bam, ...)
GATK4_GETPILEUPSUMMARIES_NORMAL(normal_bam, ...)
```

**Galaxy Solution:** Same tool used in multiple workflow steps
```xml
<step id="4" tool_id="gatk_getpileupsummaries" label="Pileup (Tumor)">
  <input name="bam" value="tumor_bam"/>
</step>

<step id="5" tool_id="gatk_getpileupsummaries" label="Pileup (Normal)">
  <input name="bam" value="normal_bam"/>
</step>
```

---

## Part 6: Conversion Priority List

### **High Priority Subworkflows** (Convert First)

| Subworkflow | Complexity | Variants Needed | Impact |
|-------------|------------|----------------|--------|
| `bam_stats_samtools` | Low | 1 | High (widely used) |
| `fastq_fastqc_umitools_trimgalore` | Medium | 4 | High (QC essential) |
| `bam_markduplicates_picard` | Low | 1 | High (standard step) |
| `bam_sort_stats_samtools` | Low | 1 | High (alignment post-processing) |
| `fastq_align_star` | Medium | 2 | High (RNA-seq) |
| `bam_tumor_normal_somatic_variant_calling_gatk` | High | 2 | Medium (cancer genomics) |
| `vcf_phase_shapeit5` | High | 1 | Low (specialized) |

---

## Part 7: Summary & Answers

### **Your Questions Answered:**

1. ✅ **Are modules part of subworkflows?**
   → YES - Most modules are used both standalone and in subworkflows

2. ✅ **Are there subworkflow-only modules?**
   → NO - All modules come from the shared `modules/nf-core/` library

3. ✅ **How are multiple workflows with different parameters handled?**
   → Nextflow uses conditional branching and parameter-driven execution

4. ✅ **Should they be split into multiple workflows in Galaxy?**
   → YES - Create separate Galaxy workflows for each execution path

### **Key Takeaways:**

1. **nf-core is hierarchical** - Modules → Subworkflows → Pipelines
2. **Modules are reusable** - Same tools used everywhere
3. **Subworkflows have logic** - Conditionals, branching, data transformations
4. **Galaxy needs explicit workflows** - Convert conditional branches to separate workflows
5. **Already converted 311 modules** - Good foundation, need to convert subworkflows next

---

**Document Version:** 1.0
**Last Updated:** 2025-10-12
**Status:** Complete analysis with actionable conversion plan
