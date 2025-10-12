# Parameter-Driven Workflow Conversion: Critical Distinctions
**Date:** 2025-10-12
**Status:** Clarification Document

---

## The Key Question

**When should Nextflow conditional logic become multiple Galaxy workflows vs. single workflow with parameters?**

---

## Rule 1: Different Tool Modules → Separate Workflows

### **Criterion:**
If the parameter **selects which tool to run**, create separate Galaxy workflows.

### **Why:**
- Different tools have different capabilities
- Different input/output requirements
- Different computational resources
- User is making a **methodological choice**

### **Example 1: Aligner Selection**

**Nextflow Code:**
```groovy
workflow ALIGNMENT {
    take:
    reads
    aligner  // Parameter: 'star', 'hisat2', 'bwa'

    main:
    if (aligner == 'star') {
        STAR(reads, star_index)
        bam = STAR.out.bam
    } else if (aligner == 'hisat2') {
        HISAT2(reads, hisat2_index)
        bam = HISAT2.out.bam
    } else if (aligner == 'bwa') {
        BWA_MEM(reads, bwa_index)
        bam = BWA_MEM.out.bam
    }

    emit:
    bam
}
```

**Analysis:**
- ❌ Parameter `aligner` selects **different tools** (STAR vs HISAT2 vs BWA)
- ❌ Each tool has different algorithms, outputs, performance
- ❌ This is a **methodological decision**, not a tool parameter

**Galaxy Conversion:** **3 SEPARATE WORKFLOWS**

**Workflow 1:** `RNA-seq Alignment (STAR).ga`
```xml
<workflow name="RNA-seq Alignment (STAR)">
  <step id="1" tool_id="star">
    <input name="reads" value="input_fastq"/>
    <input name="index" value="star_index"/>
  </step>
  <output name="bam" from="1.bam"/>
</workflow>
```

**Workflow 2:** `RNA-seq Alignment (HISAT2).ga`
```xml
<workflow name="RNA-seq Alignment (HISAT2)">
  <step id="1" tool_id="hisat2">
    <input name="reads" value="input_fastq"/>
    <input name="index" value="hisat2_index"/>
  </step>
  <output name="bam" from="1.bam"/>
</workflow>
```

**Workflow 3:** `RNA-seq Alignment (BWA).ga`
```xml
<workflow name="RNA-seq Alignment (BWA-MEM)">
  <step id="1" tool_id="bwa_mem">
    <input name="reads" value="input_fastq"/>
    <input name="index" value="bwa_index"/>
  </step>
  <output name="bam" from="1.bam"/>
</workflow>
```

**Rationale:**
✅ User selects workflow by name (clear intent)
✅ Each workflow optimized for specific tool
✅ Different reference index requirements explicit
✅ Tool-specific parameters exposed appropriately

---

### **Example 2: Variant Caller Selection**

**Nextflow Code:**
```groovy
workflow VARIANT_CALLING {
    take:
    bam
    variant_caller  // 'mutect2', 'strelka', 'freebayes'

    main:
    if (variant_caller == 'mutect2') {
        GATK_MUTECT2(bam, fasta, panel_of_normals)
        vcf = GATK_MUTECT2.out.vcf
    } else if (variant_caller == 'strelka') {
        STRELKA(bam, fasta)
        vcf = STRELKA.out.vcf
    } else if (variant_caller == 'freebayes') {
        FREEBAYES(bam, fasta)
        vcf = FREEBAYES.out.vcf
    }

    emit:
    vcf
}
```

**Galaxy Conversion:** **3 SEPARATE WORKFLOWS**

- `Variant Calling (GATK Mutect2).ga`
- `Variant Calling (Strelka).ga`
- `Variant Calling (FreeBayes).ga`

**Reason:** Different variant callers = different tools = separate workflows

---

## Rule 2: Same Tool, Different Parameters → Single Workflow

### **Criterion:**
If the parameter **changes how ONE tool runs**, keep it as a single Galaxy workflow with tool parameters.

### **Why:**
- Same tool, same algorithm
- Parameters control tool behavior (not tool selection)
- User is making a **configuration choice**

### **Example 1: FastQC with Different Settings**

**Nextflow Code:**
```groovy
process FASTQC {
    input:
    tuple val(meta), path(reads)
    val skip_duplicates  // boolean parameter
    val kmer_size        // integer parameter

    script:
    def skip_flag = skip_duplicates ? '--nogroup' : ''
    def kmer_flag = kmer_size ? "-k ${kmer_size}" : ''

    """
    fastqc ${skip_flag} ${kmer_flag} ${reads}
    """
}
```

**Analysis:**
- ✅ Same tool (FastQC)
- ✅ Parameters only change tool options (--nogroup, -k)
- ✅ This is a **configuration choice**, not a tool choice

**Galaxy Conversion:** **SINGLE WORKFLOW** with exposed parameters

```xml
<tool id="fastqc" name="FastQC">
  <inputs>
    <param name="reads" type="data" format="fastq"/>
    <param name="skip_duplicates" type="boolean" label="Skip duplicate analysis"/>
    <param name="kmer_size" type="integer" value="7" label="K-mer size"/>
  </inputs>

  <command><![CDATA[
    fastqc
    #if $skip_duplicates
      --nogroup
    #end if
    -k $kmer_size
    $reads
  ]]></command>
</tool>
```

**Rationale:**
✅ User sets parameters in tool form
✅ Same underlying analysis method
✅ No methodological difference

---

### **Example 2: TrimGalore with Different Quality Thresholds**

**Nextflow Code:**
```groovy
process TRIMGALORE {
    input:
    tuple val(meta), path(reads)
    val quality_cutoff    // e.g., 20, 30
    val min_length        // e.g., 20, 50

    script:
    """
    trim_galore -q ${quality_cutoff} --length ${min_length} ${reads}
    """
}
```

**Galaxy Conversion:** **SINGLE TOOL** with parameters

```xml
<tool id="trimgalore">
  <inputs>
    <param name="reads" type="data"/>
    <param name="quality_cutoff" type="integer" value="20" label="Quality cutoff"/>
    <param name="min_length" type="integer" value="20" label="Minimum length"/>
  </inputs>
</tool>
```

**Reason:** Same tool (TrimGalore), just different quality settings

---

## Rule 3: Skip/Include Steps → Separate Workflow Variants

### **Criterion:**
If the parameter **controls whether a step runs**, create workflow variants.

### **Why:**
- Changes workflow structure (not just parameters)
- Affects which tools run in the pipeline
- Different computational paths

### **Example: Optional QC Step**

**Nextflow Code:**
```groovy
workflow FASTQ_PROCESSING {
    take:
    reads
    skip_fastqc    // boolean: skip QC?
    skip_trimming  // boolean: skip trimming?

    main:
    processed_reads = reads

    if (!skip_fastqc) {
        FASTQC(reads)
        qc_html = FASTQC.out.html
    }

    if (!skip_trimming) {
        TRIMGALORE(processed_reads)
        processed_reads = TRIMGALORE.out.reads
    }

    emit:
    reads = processed_reads
}
```

**Analysis:**
- ❌ Parameters control **which tools run** (not just how they run)
- ❌ Affects workflow structure
- ❌ This is an **analysis strategy choice**

**Galaxy Conversion:** **4 WORKFLOW VARIANTS**

1. **`FASTQ Processing (Full QC + Trimming).ga`**
   - FastQC → TrimGalore

2. **`FASTQ Processing (QC Only).ga`**
   - FastQC only

3. **`FASTQ Processing (Trimming Only).ga`**
   - TrimGalore only

4. **`FASTQ Processing (No QC).ga`**
   - Pass-through (no processing)

**Rationale:**
✅ User selects workflow by analysis needs
✅ Workflow structure explicit
✅ No hidden conditional logic
✅ Clearer for reproducibility

---

## Rule 4: Data Type / Sample Type → Separate Workflows

### **Criterion:**
If the parameter indicates **different data types or sample types**, create separate workflows.

### **Why:**
- Different data types need different tools
- Sample metadata is not a "parameter" - it's a characteristic
- User is providing **biological context**

### **Example 1: Single-End vs Paired-End Reads**

**Nextflow Code:**
```groovy
workflow ALIGNMENT {
    take:
    reads
    single_end  // boolean from metadata

    main:
    if (single_end) {
        STAR(reads, star_index, '--single-end')
        bam = STAR.out.bam
    } else {
        STAR(reads, star_index, '--paired-end')
        bam = STAR.out.bam
    }
}
```

**Analysis:**
- ⚠️ Same tool (STAR) but fundamentally different data
- ⚠️ `single_end` is **data characteristic**, not user choice
- ⚠️ Affects multiple downstream steps

**Galaxy Conversion:** **2 SEPARATE WORKFLOWS**

**Workflow 1:** `RNA-seq Alignment (Single-End).ga`
```xml
<workflow name="RNA-seq Alignment (Single-End)">
  <step id="1" tool_id="star">
    <param name="read_mode" value="single"/>
    <input name="reads" value="input_fastq"/>
  </step>
</workflow>
```

**Workflow 2:** `RNA-seq Alignment (Paired-End).ga`
```xml
<workflow name="RNA-seq Alignment (Paired-End)">
  <step id="1" tool_id="star">
    <param name="read_mode" value="paired"/>
    <input name="reads1" value="input_fastq_r1"/>
    <input name="reads2" value="input_fastq_r2"/>
  </step>
</workflow>
```

**Rationale:**
✅ Input requirements are different (1 file vs 2 files)
✅ Data type is intrinsic property, not a choice
✅ Clearer workflow names for users

---

### **Example 2: Tumor-Only vs Tumor-Normal**

**Nextflow Code:**
```groovy
workflow SOMATIC_VARIANT_CALLING {
    take:
    bam
    mode  // 'tumor_only' or 'tumor_normal'

    main:
    if (mode == 'tumor_only') {
        MUTECT2_TUMOR_ONLY(bam, fasta)
        vcf = MUTECT2_TUMOR_ONLY.out.vcf
    } else {
        MUTECT2_TUMOR_NORMAL(bam, normal_bam, fasta)
        vcf = MUTECT2_TUMOR_NORMAL.out.vcf
    }
}
```

**Galaxy Conversion:** **2 SEPARATE WORKFLOWS**

- `Somatic Variant Calling (Tumor Only).ga`
- `Somatic Variant Calling (Tumor-Normal Paired).ga`

**Reason:** Different **sample types** = different workflows

---

## Decision Matrix

| Scenario | Example | Galaxy Strategy | Rationale |
|----------|---------|-----------------|-----------|
| **Different tools** | STAR vs HISAT2 | ❌ **Separate workflows** | Methodological choice |
| **Same tool, different params** | FastQC -k 5 vs -k 7 | ✅ **Single workflow** | Configuration choice |
| **Optional steps** | Skip FastQC vs Run FastQC | ❌ **Workflow variants** | Structural difference |
| **Different data types** | Single-end vs Paired-end | ❌ **Separate workflows** | Data characteristic |
| **Tool version** | STAR v2.7 vs v2.8 | ✅ **Single workflow** | Implementation detail |
| **Resource allocation** | 4 cores vs 8 cores | ✅ **Single workflow** | Runtime parameter |
| **Output format** | BAM vs CRAM | ✅ **Single workflow** | Format conversion |
| **Reference genome** | hg38 vs mm10 | ✅ **Single workflow** | Input data |

---

## Corrected Examples from nf-core Document

### **Correction 1: `FASTQ_FASTQC_UMITOOLS_TRIMGALORE`**

**Original Claim:**
> "Create 4 workflow variants for skip_fastqc, with_umi, skip_trimming"

**Corrected Analysis:**

| Parameter | Type | Galaxy Strategy |
|-----------|------|-----------------|
| `skip_fastqc` | Step inclusion | ❌ Workflow variants (With QC / Without QC) |
| `with_umi` | Step inclusion | ❌ Workflow variants (UMI / No UMI) |
| `skip_trimming` | Step inclusion | ❌ Workflow variants (Trim / No Trim) |
| `umi_discard_read` (1 or 2) | Tool parameter | ✅ Single workflow parameter |
| `min_trimmed_reads` | Tool parameter | ✅ Single workflow parameter |

**Corrected Workflow Variants:** Still 4, but reasoning clarified

1. **Full Pipeline (QC + UMI + Trim)**
2. **QC + Trim (No UMI)**
3. **UMI + Trim (Skip QC)**
4. **Trimming Only**

Within each variant, `umi_discard_read` and `min_trimmed_reads` are **workflow parameters**.

---

### **Correction 2: RNA-seq Aligner Choice**

**Original Claim:**
> "Create separate workflows for STAR vs HISAT2"

**Corrected:** ✅ This was CORRECT

**Reasoning:**
- Different tools (STAR vs HISAT2)
- Different algorithms, performance characteristics
- Methodological choice, not parameter choice

---

### **Correction 3: FastQC Parameters**

**New Example (was missing):**

**Nextflow Code:**
```groovy
process FASTQC {
    input:
    tuple val(meta), path(reads)

    script:
    def args = task.ext.args ?: ''  // User-provided extra arguments

    """
    fastqc ${args} --threads ${task.cpus} ${reads}
    """
}
```

**Analysis:**
- ✅ Same tool (FastQC)
- ✅ `args` changes tool options
- ✅ `task.cpus` is runtime resource allocation

**Galaxy Conversion:** **SINGLE TOOL** with parameter field

```xml
<tool id="fastqc">
  <inputs>
    <param name="reads" type="data"/>
    <param name="extra_args" type="text" optional="true" label="Additional FastQC arguments"/>
  </inputs>

  <command><![CDATA[
    fastqc
    $extra_args
    --threads \${GALAXY_SLOTS:-1}
    $reads
  ]]></command>
</tool>
```

---

## Updated Conversion Guidelines

### **Step 1: Identify Parameter Type**

Ask these questions:

1. **Does the parameter select which tool to run?**
   - YES → Create separate workflows
   - NO → Continue to question 2

2. **Does the parameter include/exclude entire workflow steps?**
   - YES → Create workflow variants
   - NO → Continue to question 3

3. **Does the parameter indicate different data types or sample types?**
   - YES → Create separate workflows
   - NO → Continue to question 4

4. **Does the parameter only change tool options within the same tool?**
   - YES → Single workflow with tool parameters
   - NO → Re-evaluate (may be complex case)

---

### **Step 2: Apply Decision Tree**

```
Parameter Analysis
        ↓
Does it select WHICH tool runs?
        ↓ YES
    SEPARATE WORKFLOWS
        (e.g., STAR vs HISAT2)

        ↓ NO
Does it include/exclude steps?
        ↓ YES
    WORKFLOW VARIANTS
        (e.g., Skip QC vs Run QC)

        ↓ NO
Is it a data characteristic?
        ↓ YES
    SEPARATE WORKFLOWS
        (e.g., Single-end vs Paired-end)

        ↓ NO
Is it a tool configuration?
        ↓ YES
    SINGLE WORKFLOW PARAMETER
        (e.g., Quality threshold)
```

---

## Practical Examples

### **Example 1: `bam_markduplicates_picard`**

**Nextflow Code:**
```groovy
workflow BAM_MARKDUPLICATES_PICARD {
    take:
    bam
    skip_markduplicates  // boolean

    main:
    if (skip_markduplicates) {
        marked_bam = bam
    } else {
        PICARD_MARKDUPLICATES(bam)
        marked_bam = PICARD_MARKDUPLICATES.out.bam
    }

    emit:
    bam = marked_bam
}
```

**Analysis:**
- Parameter: `skip_markduplicates`
- Controls: Whether PICARD_MARKDUPLICATES **runs at all**
- Type: **Step inclusion parameter**

**Galaxy Conversion:** **2 WORKFLOW VARIANTS**

1. `BAM Mark Duplicates (Picard).ga` - Runs Picard
2. `BAM Processing (Skip Duplicate Marking).ga` - Pass-through

**NOT:** Single workflow with "skip" checkbox (would be confusing)

---

### **Example 2: GATK Mutect2 Parameters**

**Nextflow Code:**
```groovy
process GATK4_MUTECT2 {
    input:
    tuple val(meta), path(tumor_bam), path(normal_bam)
    path fasta
    val af_alleles_threshold  // Allele frequency threshold

    script:
    """
    gatk Mutect2 \\
        -I ${tumor_bam} \\
        -I ${normal_bam} \\
        -R ${fasta} \\
        --af-of-alleles-not-in-resource ${af_alleles_threshold}
    """
}
```

**Analysis:**
- Parameter: `af_alleles_threshold`
- Controls: Mutect2 allele frequency filtering
- Type: **Tool configuration parameter**

**Galaxy Conversion:** **SINGLE TOOL** with parameter

```xml
<tool id="gatk_mutect2">
  <inputs>
    <param name="tumor_bam" type="data"/>
    <param name="normal_bam" type="data"/>
    <param name="af_threshold" type="float" value="0.001"
           label="Allele frequency threshold"/>
  </inputs>
</tool>
```

---

## Summary Table: When to Split Workflows

| Parameter Behavior | Galaxy Strategy | Example |
|-------------------|-----------------|---------|
| Selects **different tools** | ❌ Separate workflows | STAR vs HISAT2 |
| Includes/excludes **workflow steps** | ❌ Workflow variants | Skip QC vs Run QC |
| Indicates **data type** | ❌ Separate workflows | Single-end vs Paired-end |
| Indicates **sample type** | ❌ Separate workflows | Tumor-only vs Tumor-normal |
| Changes **tool parameters** | ✅ Single workflow | Quality threshold 20 vs 30 |
| Controls **output format** | ✅ Single workflow | BAM vs CRAM |
| Allocates **resources** | ✅ Single workflow | 4 cores vs 8 cores |
| Selects **reference genome** | ✅ Single workflow | hg38 vs mm10 (input data) |

---

## Updated nf-core Subworkflow Conversion Counts

Based on this clarification, here's the corrected conversion estimate:

| Subworkflow | Conditional Parameters | Workflow Variants | Tool Parameters |
|-------------|------------------------|-------------------|-----------------|
| `bam_stats_samtools` | None | 1 | 0 |
| `fastq_fastqc_umitools_trimgalore` | skip_fastqc, with_umi, skip_trimming | 4 | 2 (umi_discard_read, min_trimmed_reads) |
| `bam_markduplicates_picard` | skip_markduplicates | 2 | 0 |
| `fastq_align_star` | None | 1 | Multiple (STAR params) |
| `bam_tumor_normal_somatic_variant_calling_gatk` | None | 1 | Multiple (GATK params) |

**Total:** ~150 Galaxy workflow files (including all variants)

---

**Document Version:** 1.0
**Last Updated:** 2025-10-12
**Purpose:** Clarify parameter-driven workflow conversion decisions
