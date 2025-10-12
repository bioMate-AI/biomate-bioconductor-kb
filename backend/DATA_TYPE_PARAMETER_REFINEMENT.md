# Data Type Parameters: Refined Decision Criteria
**Date:** 2025-10-12
**Status:** Critical Refinement

---

## The Corrected Rule

**Original (Too Simplistic):**
> "Is parameter a data/sample characteristic? → YES → Separate workflows"

**Refined (Correct):**
> "Does the data type require calling **different tool functions or modules**?
> - YES → Separate workflows
> - NO → Single workflow with parameter"

---

## The Key Distinction

### **Same Tool Function → Single Workflow**

If the **same tool/module** handles multiple data types through its own parameters, keep it as a single workflow.

#### **Example 1: STAR Aligner (Single vs Paired Reads)**

**Nextflow Module:**
```groovy
process STAR {
    input:
    tuple val(meta), path(reads)  // Can be 1 file (single) or 2 files (paired)
    path index

    script:
    // STAR automatically detects single vs paired based on number of input files
    """
    STAR \\
        --genomeDir ${index} \\
        --readFilesIn ${reads} \\
        --outSAMtype BAM SortedByCoordinate
    """
}
```

**Analysis:**
- ✅ **Same tool** (STAR)
- ✅ **Same module/function** called
- ✅ STAR internally handles both single-end and paired-end
- ✅ Only difference: 1 input file vs 2 input files

**Galaxy Conversion:** **SINGLE WORKFLOW** with conditional input

```xml
<tool id="star" name="STAR Aligner">
  <inputs>
    <!-- Conditional input based on read type -->
    <conditional name="read_type">
      <param name="type" type="select" label="Read Type">
        <option value="single">Single-end</option>
        <option value="paired">Paired-end</option>
      </param>

      <when value="single">
        <param name="reads" type="data" format="fastq" label="Reads"/>
      </when>

      <when value="paired">
        <param name="reads1" type="data" format="fastq" label="Forward Reads"/>
        <param name="reads2" type="data" format="fastq" label="Reverse Reads"/>
      </when>
    </conditional>

    <param name="index" type="data" format="star_index"/>
  </inputs>

  <command><![CDATA[
    STAR
    --genomeDir '$index'
    --readFilesIn
    #if $read_type.type == 'single':
      '$read_type.reads'
    #else:
      '$read_type.reads1' '$read_type.reads2'
    #end if
    --outSAMtype BAM SortedByCoordinate
  ]]></command>
</tool>
```

**Rationale:**
✅ Same STAR binary handles both
✅ No algorithmic difference
✅ Input structure is the only difference
✅ User chooses in tool interface

---

#### **Example 2: SAMtools Sort (BAM or SAM Input)**

**Nextflow Module:**
```groovy
process SAMTOOLS_SORT {
    input:
    tuple val(meta), path(input)  // Can be BAM or SAM

    script:
    """
    samtools sort ${input} -o sorted.bam
    """
}
```

**Analysis:**
- ✅ **Same tool** (samtools sort)
- ✅ **Same command**
- ✅ SAMtools auto-detects input format

**Galaxy Conversion:** **SINGLE TOOL**

```xml
<tool id="samtools_sort">
  <inputs>
    <param name="input" type="data" format="bam,sam" label="Input alignment"/>
  </inputs>

  <command><![CDATA[
    samtools sort '$input' -o sorted.bam
  ]]></command>
</tool>
```

**Rationale:**
✅ Tool handles both formats natively
✅ No parameter needed - auto-detection

---

#### **Example 3: FastQC (Any Read Format)**

**Nextflow Module:**
```groovy
process FASTQC {
    input:
    tuple val(meta), path(reads)  // fastq, fq.gz, bam, sam

    script:
    """
    fastqc ${reads}
    """
}
```

**Analysis:**
- ✅ **Same tool** (FastQC)
- ✅ FastQC auto-detects format (FASTQ, BAM, SAM)
- ✅ No behavioral change

**Galaxy Conversion:** **SINGLE TOOL**

```xml
<tool id="fastqc">
  <inputs>
    <param name="reads" type="data" format="fastq,fastqsanger,bam,sam" label="Input reads"/>
  </inputs>
</tool>
```

**Rationale:**
✅ Multiple formats accepted by Galaxy datatype system
✅ Tool behavior unchanged

---

### **Different Tool Functions → Separate Workflows**

If different **tool modules or functions** are needed for different data types, create separate workflows.

#### **Example 1: ChIP-seq vs RNA-seq Peak Calling**

**Nextflow Code:**
```groovy
workflow PEAK_CALLING {
    take:
    bam
    data_type  // 'chip-seq' or 'rna-seq'

    main:
    if (data_type == 'chip-seq') {
        MACS2(bam)  // <-- Different tool
        peaks = MACS2.out.peaks
    } else if (data_type == 'rna-seq') {
        PIRANHA(bam)  // <-- Different tool (RNA-specific)
        peaks = PIRANHA.out.peaks
    }

    emit:
    peaks
}
```

**Analysis:**
- ❌ **Different tools** (MACS2 vs Piranha)
- ❌ Different algorithms (ChIP-seq vs RNA-seq peaks)
- ❌ Data type determines **which tool**

**Galaxy Conversion:** **2 SEPARATE WORKFLOWS**

**Workflow 1:** `Peak Calling (ChIP-seq - MACS2).ga`
```xml
<workflow name="ChIP-seq Peak Calling">
  <step id="1" tool_id="macs2">
    <input name="bam" value="input_bam"/>
  </step>
</workflow>
```

**Workflow 2:** `Peak Calling (RNA-seq - Piranha).ga`
```xml
<workflow name="RNA-seq Peak Calling">
  <step id="1" tool_id="piranha">
    <input name="bam" value="input_bam"/>
  </step>
</workflow>
```

**Rationale:**
❌ Different tools for different data types
❌ Methodological difference

---

#### **Example 2: Long-Read vs Short-Read Assembly**

**Nextflow Code:**
```groovy
workflow GENOME_ASSEMBLY {
    take:
    reads
    read_length_type  // 'short' or 'long'

    main:
    if (read_length_type == 'short') {
        SPADES(reads)  // <-- Short-read assembler
        assembly = SPADES.out.contigs
    } else {
        FLYE(reads)  // <-- Long-read assembler
        assembly = FLYE.out.contigs
    }

    emit:
    assembly
}
```

**Analysis:**
- ❌ **Different tools** (SPAdes vs Flye)
- ❌ Different algorithms optimized for read length
- ❌ Data characteristic requires **different tool**

**Galaxy Conversion:** **2 SEPARATE WORKFLOWS**

- `Genome Assembly (Short Reads - SPAdes).ga`
- `Genome Assembly (Long Reads - Flye).ga`

**Rationale:**
❌ Data type requires fundamentally different tools

---

#### **Example 3: DNA vs RNA Alignment**

**Nextflow Code:**
```groovy
workflow SEQUENCE_ALIGNMENT {
    take:
    reads
    sequence_type  // 'dna' or 'rna'

    main:
    if (sequence_type == 'dna') {
        BWA_MEM(reads, dna_index)  // <-- DNA aligner
        bam = BWA_MEM.out.bam
    } else {
        STAR(reads, star_index)  // <-- RNA aligner (handles splicing)
        bam = STAR.out.bam
    }

    emit:
    bam
}
```

**Analysis:**
- ❌ **Different tools** (BWA-MEM vs STAR)
- ❌ RNA needs splice-aware aligner
- ❌ Data type determines **tool choice**

**Galaxy Conversion:** **2 SEPARATE WORKFLOWS**

- `DNA Alignment (BWA-MEM).ga`
- `RNA-seq Alignment (STAR).ga`

**Rationale:**
❌ Biological data type requires different algorithmic approach

---

## The Refined Decision Tree

```
Does data/sample type parameter exist?
        ↓ YES
        ↓
Does it select WHICH tool/module runs?
        ↓ YES
    SEPARATE WORKFLOWS
        (e.g., ChIP-seq MACS2 vs RNA-seq Piranha)

        ↓ NO
Does the SAME tool handle both data types?
        ↓ YES
    SINGLE WORKFLOW with parameter/conditional input
        (e.g., STAR with single-end vs paired-end)
```

---

## Detailed Examples with Rationale

### **Case 1: SAME TOOL, Different Input Structure**

#### **Tool: Bowtie2 Alignment**

**Nextflow:**
```groovy
process BOWTIE2 {
    input:
    tuple val(meta), path(reads)  // 1 or 2 files

    script:
    def input = meta.single_end ? "-U ${reads}" : "-1 ${reads[0]} -2 ${reads[1]}"

    """
    bowtie2 -x index ${input} -S output.sam
    """
}
```

**Galaxy:** **SINGLE TOOL**
```xml
<tool id="bowtie2">
  <conditional name="input">
    <param name="type" type="select">
      <option value="single">Single-end</option>
      <option value="paired">Paired-end</option>
    </param>
    <when value="single">
      <param name="reads" type="data"/>
    </when>
    <when value="paired">
      <param name="reads1" type="data"/>
      <param name="reads2" type="data"/>
    </when>
  </conditional>

  <command><![CDATA[
    bowtie2 -x index
    #if $input.type == 'single':
      -U '$input.reads'
    #else:
      -1 '$input.reads1' -2 '$input.reads2'
    #end if
    -S output.sam
  ]]></command>
</tool>
```

**Why Single Tool:**
✅ Same bowtie2 binary
✅ Only input format differs (-U vs -1/-2)
✅ Algorithm identical

---

### **Case 2: SAME TOOL, Different Modes**

#### **Tool: HISAT2 with DNA or RNA Mode**

**Nextflow:**
```groovy
process HISAT2 {
    input:
    tuple val(meta), path(reads)
    val sequencing_type  // 'dna' or 'rna'

    script:
    def rna_strandness = sequencing_type == 'rna' ? '--rna-strandness RF' : ''

    """
    hisat2 ${rna_strandness} -x index -U ${reads} -S output.sam
    """
}
```

**Galaxy:** **SINGLE TOOL** with parameter
```xml
<tool id="hisat2">
  <inputs>
    <param name="reads" type="data"/>
    <param name="seq_type" type="select" label="Sequencing Type">
      <option value="dna">DNA-seq</option>
      <option value="rna">RNA-seq</option>
    </param>
  </inputs>

  <command><![CDATA[
    hisat2
    #if $seq_type == 'rna':
      --rna-strandness RF
    #end if
    -x index -U '$reads' -S output.sam
  ]]></command>
</tool>
```

**Why Single Tool:**
✅ Same HISAT2 binary
✅ Just adds --rna-strandness flag
✅ User configuration choice

---

### **Case 3: DIFFERENT TOOLS Required**

#### **Differential Expression: Bulk vs Single-Cell**

**Nextflow:**
```groovy
workflow DIFFERENTIAL_EXPRESSION {
    take:
    counts
    experiment_type  // 'bulk' or 'single-cell'

    main:
    if (experiment_type == 'bulk') {
        DESEQ2(counts)  // <-- Bulk RNA-seq tool
        results = DESEQ2.out.results
    } else {
        MAST(counts)  // <-- Single-cell tool
        results = MAST.out.results
    }

    emit:
    results
}
```

**Galaxy:** **2 SEPARATE WORKFLOWS**

**Why Separate:**
❌ Different tools (DESeq2 vs MAST)
❌ Different statistical models
❌ Data type requires different analysis method

---

### **Case 4: SAME TOOL, Optional Features**

#### **Tool: Samtools with Optional Reference**

**Nextflow:**
```groovy
process SAMTOOLS_STATS {
    input:
    tuple val(meta), path(bam)
    path fasta  // Optional reference

    script:
    def reference = fasta ? "--reference ${fasta}" : ''

    """
    samtools stats ${reference} ${bam} > stats.txt
    """
}
```

**Galaxy:** **SINGLE TOOL** with optional input
```xml
<tool id="samtools_stats">
  <inputs>
    <param name="bam" type="data" format="bam"/>
    <param name="fasta" type="data" format="fasta" optional="true" label="Reference (optional)"/>
  </inputs>

  <command><![CDATA[
    samtools stats
    #if $fasta:
      --reference '$fasta'
    #end if
    '$bam' > stats.txt
  ]]></command>
</tool>
```

**Why Single Tool:**
✅ Same samtools stats command
✅ Optional input, not different tool
✅ Enhanced output if provided, but same tool

---

## Updated Decision Matrix

| Scenario | Same Tool? | Galaxy Strategy | Example |
|----------|-----------|-----------------|---------|
| Single-end vs Paired-end reads | ✅ YES (STAR) | ✅ **Single workflow** | STAR handles both with different input |
| BAM vs SAM input | ✅ YES (samtools) | ✅ **Single workflow** | Auto-detected format |
| ChIP-seq vs RNA-seq peaks | ❌ NO (MACS2 vs Piranha) | ❌ **Separate workflows** | Different tools needed |
| Short vs Long read assembly | ❌ NO (SPAdes vs Flye) | ❌ **Separate workflows** | Different assemblers |
| DNA vs RNA alignment | ❌ NO (BWA vs STAR) | ❌ **Separate workflows** | Different algorithmic needs |
| DNA-seq vs RNA-seq (HISAT2) | ✅ YES (HISAT2) | ✅ **Single workflow** | Same tool, flag difference |
| Bulk vs Single-cell DE | ❌ NO (DESeq2 vs MAST) | ❌ **Separate workflows** | Different statistical models |
| With/without reference | ✅ YES (samtools) | ✅ **Single workflow** | Optional input |

---

## The Critical Test

**Ask this question:**

> "If I were running this analysis **on the command line**, would I:
> - A) Run the **same command** with different arguments/inputs?
> - B) Run **completely different commands/tools**?"

**Answer A → Single Galaxy workflow with parameters**
**Answer B → Separate Galaxy workflows**

---

## Corrected Examples from Previous Document

### **Example: Single-End vs Paired-End**

**Previous Classification:** "Separate workflows (data characteristic)"

**Corrected Classification:** **Depends on the tool!**

**If using STAR, BWA, Bowtie2:** ✅ Single workflow
- Same tool, different input structure
- Tool handles both natively

**If using specialized aligners:** ❌ Separate workflows
- e.g., if one tool only works with paired-end

---

### **Example: Tumor-Only vs Tumor-Normal**

**Previous Classification:** "Separate workflows (sample type)"

**Corrected Classification:** **Still separate - but for a different reason!**

**Why Separate:**
- ❌ Mutect2 **tumor-only mode** vs **tumor-normal mode** = different module calls
- ❌ Different input requirements (1 BAM vs 2 BAMs)
- ❌ Different downstream processing (contamination calculation requires both)

This is NOT just a data characteristic - it's a **structural workflow difference**.

---

## Summary: The Refined Rule

### **Original Rule (Too Broad):**
> "Data/sample characteristic → Separate workflows"

### **Refined Rule (Correct):**
> "Data/sample characteristic → Check if same tool handles it:
> - **YES** → Single workflow with conditional input/parameters
> - **NO** → Separate workflows"

### **The Ultimate Test:**
**Does the data type require calling a different tool or module?**
- YES → Separate workflows
- NO → Single workflow

---

**Document Version:** 1.0
**Last Updated:** 2025-10-12
**Purpose:** Refine data type parameter handling criteria
