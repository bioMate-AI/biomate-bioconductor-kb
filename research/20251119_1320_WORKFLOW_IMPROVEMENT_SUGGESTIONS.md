# BioMate Workflow Improvement Suggestions

**Date:** 2025-11-19 13:20
**Based on:** IWC Workflow Analysis (105 workflows, 17 assembly workflows)

---

## Executive Summary

Analysis of IWC assembly workflows reveals a **50/50 split** between biological computation tools and utility/data handling tools. This presents a significant opportunity for BioMate to simplify user experience by abstracting away the utility overhead.

### Key Finding

| Category | Count | Percentage |
|----------|-------|------------|
| Total tool steps (assembly) | 409 | 100% |
| Biology/Analysis tools | 204 | 49.9% |
| Utility/Handling tools | 205 | 50.1% |

---

## Problem Statement

Current Galaxy workflows expose all implementation details to users:
- 62 steps for a Hi-C scaffolding workflow
- Half are text manipulation, parameter passing, collection operations
- Users must understand Galaxy internals, not just biology
- Error-prone and hard to maintain

---

## Suggestions

### 1. Create "Smart Subworkflows" for BioMate

**Concept:** Present logical biological units, hide implementation details

```
User sees:                    System handles internally:
─────────────────────────────────────────────────────────
Assembly (Hifiasm)        →   + 15 utility steps for params/collections
  ↓
QC (gfastats + BUSCO)     →   + 8 utility steps for extraction/formatting
  ↓
Scaffolding (YAHS)        →   + 12 utility steps for Hi-C processing
  ↓
Visualization (Pretext)   →   + 6 utility steps for image montage
```

**Benefit:** User sees 4 meaningful steps instead of 62 implementation steps.

**Implementation:**
- Define subworkflow boundaries based on biological function
- Encapsulate utility operations within subworkflow
- Expose only biological inputs/outputs/parameters

---

### 2. Define Core Pipeline Templates

Based on tool frequency analysis, create standardized reusable pipelines:

#### Assembly Domain

| Pipeline Name | Tools | Purpose | Frequency |
|---------------|-------|---------|-----------|
| **ASSEMBLY_HIFI** | Hifiasm → gfastats → Bandage | Basic HiFi assembly | High |
| **ASSEMBLY_QC** | BUSCO + compleasm + Merqury + gfastats | Quality assessment suite | High |
| **ASSEMBLY_POLISH** | minimap2 → Racon (×4) | Long-read polishing | Medium |
| **ASSEMBLY_SCAFFOLD_HIC** | BWA-MEM2 → pairtools → YAHS → gfastats | Hi-C scaffolding | Medium |
| **ASSEMBLY_DECONTAM** | FCS-GX → BLAST → filter | Contamination removal | Medium |
| **ASSEMBLY_KMER** | Meryl → GenomeScope | K-mer profiling | High |
| **ASSEMBLY_PURGE** | minimap2 → purge_dups | Duplicate removal | Medium |

#### Other Domains (from pattern analysis)

| Pipeline Name | Tools | Purpose |
|---------------|-------|---------|
| **QC_FASTQ** | FastQC → MultiQC | FASTQ quality control |
| **TRIM_READS** | cutadapt/fastp → FastQC | Adapter trimming with QC |
| **MAP_SORT_INDEX** | bowtie2/bwa → samtools sort → index | Read mapping pipeline |
| **BAM_STATS** | samtools stats → flagstat → idxstats | BAM statistics suite |
| **VARIANT_CALL_LOFREQ** | lofreq viterbi → indelqual → call → filter | Sensitive variant calling |
| **PEAK_CALL** | MACS2 → bedtools → wigtobigwig | ChIP-seq peak calling |
| **COVERAGE_TRACK** | bedtools genomecov → wigtobigwig | Coverage visualization |

---

### 3. Auto-generate Utility Steps

BioMate's AI should automatically handle data plumbing:

#### Current Approach (Manual)
```python
# User must explicitly define each utility step
step1 = gfastats(assembly)
step2 = extract_dataset(step1, "stats")           # Manual utility
step3 = text_process(step2, pattern="...")        # Manual utility
step4 = param_from_file(step3)                    # Manual utility
step5 = next_tool(param=step4)
```

#### Proposed Approach (Automatic)
```python
# BioMate auto-generates utility steps based on tool specifications
step1 = gfastats(assembly)
step2 = next_tool(param=step1.stats.genome_size)  # Auto-extracted and formatted
```

#### Implementation Requirements

1. **Tool I/O Specifications**: Define expected input/output formats for each tool
2. **Type System**: Track data types through workflow (FASTA, BAM, tabular, etc.)
3. **Auto-conversion**: Insert format converters when types don't match
4. **Parameter Extraction**: Parse structured outputs automatically

#### Utility Operations to Auto-generate

| Operation | Current Tool | Auto-generation Rule |
|-----------|--------------|---------------------|
| Extract from collection | `__EXTRACT_DATASET__` | Based on output index/name |
| Parameter from file | `param_value_from_file` | Based on file format + field name |
| Text formatting | `text_processing` | Based on target tool requirements |
| Collection filtering | `__FILTER_EMPTY__` | Always after tools that may produce empty |
| Merging | `__MERGE_COLLECTION__` | When multiple inputs needed |

---

### 4. Consolidate Repeated Tool Calls

**Problem:** gfastats called 55 times across 17 workflows

**Current Pattern:**
```python
# Multiple calls for different metrics
gfastats_1 = gfastats(asm, output="scaffold_stats")
gfastats_2 = gfastats(asm, output="gap_stats")
gfastats_3 = gfastats(asm, output="nx_values")
gfastats_4 = gfastats(asm, output="gc_content")
gfastats_5 = gfastats(asm, output="total_length")
gfastats_6 = gfastats(asm, output="contig_count")
```

**Proposed Solution:**
```python
# Single call with composite output
assembly_stats = gfastats_complete(asm)
# Returns structured object:
# {
#   scaffold_stats: ...,
#   gap_stats: ...,
#   nx_values: ...,
#   gc_content: ...,
#   total_length: ...,
#   contig_count: ...
# }
```

**Benefits:**
- Reduce 6 steps to 1
- Single execution (faster)
- Cleaner workflow visualization
- Easier parameter passing

---

### 5. Use nf-core Workflows as Building Blocks

The 93 reformatted nf-core workflows are already modular and biology-focused (many are 100% biology tools).

#### Recommended Usage

| nf-core Subworkflow | Insert After | Purpose |
|---------------------|--------------|---------|
| `bam_sort_stats_samtools` | Any mapping tool | Standard BAM processing |
| `fastq_fastqc_umitools_trimgalore` | Data input | Read QC and trimming |
| `vcf_annotate_ensemblvep` | Variant calling | Variant annotation |

#### Integration Strategy

1. Map nf-core tool IDs to BioMate tool index (already done)
2. Create adapter layer to connect nf-core subworkflows to IWC pipelines
3. Use nf-core for common operations, IWC for complete pipelines

---

### 6. Create Domain-Specific Wizards

For complex analyses, present biological decisions instead of tool choices.

#### Genome Assembly Wizard

```
┌─────────────────────────────────────────────────────┐
│  BioMate Genome Assembly Wizard                     │
├─────────────────────────────────────────────────────┤
│                                                     │
│  1. Input Data Type                                 │
│     ○ PacBio HiFi reads                            │
│     ○ Oxford Nanopore reads                        │
│     ○ Illumina short reads                         │
│                                                     │
│  2. Additional Data (optional)                      │
│     □ Hi-C reads for scaffolding                   │
│     □ Parental reads for trio binning              │
│     □ RNA-seq for annotation                       │
│                                                     │
│  3. Assembly Goal                                   │
│     ○ Haploid reference                            │
│     ○ Diploid phased assembly                      │
│     ○ Metagenome assembly                          │
│                                                     │
│  4. Quality Assessment Level                        │
│     ○ Basic (BUSCO only)                           │
│     ○ Standard (BUSCO + Merqury)                   │
│     ○ Comprehensive (all QC tools)                 │
│                                                     │
│  5. Estimated Genome Size: [___________] Mb        │
│                                                     │
│  [Generate Workflow]                                │
│                                                     │
└─────────────────────────────────────────────────────┘
```

#### System Response

Based on selections, system generates:
- Appropriate workflow from templates
- All utility steps (hidden)
- Sensible default parameters
- Expected outputs

#### Other Wizard Candidates

- **RNA-seq Analysis Wizard**: PE/SE, stranded, DE analysis options
- **ChIP-seq Wizard**: Histone/TF, input control, peak type
- **Variant Calling Wizard**: Germline/somatic, WGS/WES/targeted
- **Amplicon Analysis Wizard**: 16S/ITS, QIIME2/DADA2

---

### 7. Recommended Workflow Architecture

#### User-Facing Layer (Simplified)

```yaml
workflow:
  name: "Genome Assembly"

  inputs:
    - name: hifi_reads
      type: fastq
      description: "PacBio HiFi reads"
    - name: hic_reads
      type: fastq_paired
      description: "Hi-C reads for scaffolding"
      optional: true

  parameters:
    - name: genome_size
      type: integer
      description: "Estimated genome size in Mb"
    - name: ploidy
      type: choice
      options: [haploid, diploid]

  steps:
    - id: assembly
      tool: hifiasm
      description: "Assemble HiFi reads"

    - id: scaffolding
      tool: yahs
      condition: hic_reads provided
      description: "Scaffold with Hi-C"

    - id: quality_check
      tool: assembly_qc_suite
      description: "Assess assembly quality"

  outputs:
    - name: assembly_fasta
      from: scaffolding.fasta
    - name: quality_report
      from: quality_check.report
```

#### Execution Layer (System-Managed)

```yaml
execution:
  # Auto-generated based on user workflow

  pre_processing:
    - validate_inputs
    - check_file_formats
    - estimate_resources

  utility_operations:
    - collection_management
    - parameter_extraction
    - format_conversion
    - intermediate_file_handling

  error_handling:
    - retry_failed_steps
    - checkpoint_progress
    - cleanup_temp_files

  post_processing:
    - collect_outputs
    - generate_report
    - archive_intermediates
```

---

### 8. Implementation Priorities

#### Phase 1: Immediate (1-2 weeks)

1. **Extract core biology tools** from assembly workflows into reusable subworkflows
   - ASSEMBLY_QC (BUSCO + compleasm + Merqury + gfastats)
   - ASSEMBLY_KMER (Meryl + GenomeScope)
   - QC_FASTQ (FastQC + MultiQC)

2. **Create tool I/O specifications** for top 50 most-used tools
   - Input types and formats
   - Output types and formats
   - Required vs optional parameters

#### Phase 2: Short-term (2-4 weeks)

3. **Build auto-generation system** for utility steps
   - Parameter extraction rules
   - Collection operation inference
   - Format conversion logic

4. **Implement subworkflow consolidation**
   - gfastats_complete (single call, multiple outputs)
   - samtools_stats_suite (stats + flagstat + idxstats)

#### Phase 3: Medium-term (1-2 months)

5. **Create domain wizards**
   - Start with Genome Assembly (most complex)
   - Then RNA-seq (most common)
   - Then ChIP-seq/ATAC-seq

6. **Build workflow simplification engine**
   - Hide utility steps in UI
   - Show biological flow only
   - Expand on demand for debugging

#### Phase 4: Long-term (2-3 months)

7. **Train AI for workflow generation**
   - Learn from IWC patterns
   - Predict utility steps from context
   - Suggest optimizations

8. **User feedback integration**
   - Track which simplifications work
   - Identify missing templates
   - Refine wizards based on usage

---

## Expected Outcomes

### User Experience

| Metric | Current | After Implementation |
|--------|---------|---------------------|
| Steps visible to user | 62 | ~10 |
| Time to understand workflow | 30+ min | 5 min |
| Error rate from utility steps | High | Near zero |
| Workflow creation time | Hours | Minutes |

### Technical Benefits

- **Maintainability**: Update utility logic in one place
- **Consistency**: Same patterns across all workflows
- **Performance**: Optimized utility operations
- **Extensibility**: Easy to add new domains

---

## Conclusion

The 50/50 split between biology and utility tools in IWC workflows represents both a problem and an opportunity. By abstracting utility operations, BioMate can:

1. **Simplify** user experience dramatically
2. **Reduce** errors from manual data handling
3. **Accelerate** workflow creation
4. **Focus** users on biological decisions

The key insight is that **users care about biology, not Galaxy internals**. BioMate should present biological workflows while handling implementation details automatically.

---

## Files Generated

- `20251119_1313_IWC_COMPREHENSIVE_ANALYSIS.md` - Full workflow analysis
- `20251119_1313_IWC_ANALYSIS_DATA.json` - Structured analysis data
- `scripts/analyze_assembly_tools.py` - Assembly tool categorization script
- `scripts/analyze_iwc_workflows.py` - Comprehensive analysis script

---

## Next Steps

1. Review suggestions with team
2. Prioritize based on user needs and technical feasibility
3. Start with Phase 1 implementations
4. Iterate based on feedback
