# Hierarchical/Compositional Conversion Strategy Analysis

**Question**: Would converting Galaxy workflows using a hierarchical approach (subworkflows → tools → complete workflow) make conversion easier and more efficient?

**Date**: 2025-11-22 02:30
**Context**: User proposed biological-logic-based grouping strategy

---

## TL;DR Answer

**YES, this makes excellent sense** - but with important caveats:

1. ✅ **Galaxy workflows are already conceptually hierarchical** (converted from nf-core subworkflows)
2. ✅ **Nextflow natively supports this** (nested subworkflows are a core pattern)
3. ✅ **Would significantly improve conversion quality and maintainability**
4. ⚠️ **Current Galaxy workflows lost the hierarchy** (flattened during conversion)
5. ⚠️ **Need to reconstruct logical groups** (dependency analysis + LLM understanding)

**Recommendation**: **Implement this as a Phase 2 enhancement** - it's valuable but requires dependency graph analysis.

---

## Current State Analysis

### Galaxy Workflow Structure (94 workflows analyzed)

```
Subworkflow usage: 0% (0/94 workflows have explicit subworkflow steps)
Step type distribution:
  - tool: 464 (actual computation)
  - data_input: 316 (inputs)
  - data_output: 217 (outputs)
  - parameter_input: 71 (parameters)
  - data_collection_input: 10 (collections)

Complexity:
  - Simple (1-5 steps): 13.8%
  - Medium (6-15 steps): 69.1%
  - Complex (16-30 steps): 16.0%
  - Very complex (>30 steps): 1.1%
```

**Key Finding**: Despite being "converted from nf-core subworkflows" (as stated in annotations), Galaxy workflows are **completely flat** - no explicit subworkflow structure preserved.

---

## Case Study: FASTQ_CREATE_UMI_CONSENSUS_FGBIO

**Complexity**: 37 steps (most complex workflow)
**Annotation**: "Converted from nf-core subworkflow"

**Current structure** (flattened):
```
Step 0-9:   Inputs (reads, index, params)
Step 10:    fgbio FastqToBam
Step 11:    samtools fastq (BAM2FASTQ_PRE)
Step 12-13: BWA Index (2 alternatives: bwa-mem1, bwa-mem2)
Step 14-15: BWA MEM PRE (2 alternatives)
Step 16-17: fgbio ZipperBams PRE (2 branches)
Step 18:    fgbio GroupReadsByUmi
Step 19-20: Consensus calling (2 alternatives: duplex, non-duplex)
Step 21-22: FilterConsensusReads (2 branches)
Step 23-24: BAM2FASTQ POST (2 branches)
Step 25-28: BWA MEM POST (4 combinations: 2 aligners × 2 branches)
Step 29-32: ZipperBams POST (4 combinations)
Step 33-36: SORTBAM (4 combinations)
```

**Logical groups** (reconstructed):

```
GROUP 1: PRE-PROCESSING (Steps 10-11)
  - FastqToBam: Convert FASTQ to unmapped BAM
  - BAM2FASTQ: Convert back to FASTQ for alignment

GROUP 2: ALIGNMENT (Steps 12-17)
  - Index building (2 alternatives: BWA-MEM1, BWA-MEM2)
  - Alignment (2 alternatives)
  - Zipping (merge with original BAM)

GROUP 3: UMI GROUPING (Step 18)
  - GroupReadsByUmi: Group reads by UMI tags

GROUP 4: CONSENSUS CALLING (Steps 19-20)
  - Duplex consensus (paired reads)
  - Molecular consensus (single reads)

GROUP 5: FILTERING (Steps 21-22)
  - Filter duplex consensus
  - Filter molecular consensus

GROUP 6: POST-PROCESSING (Steps 23-32)
  - BAM2FASTQ (2 branches)
  - Re-alignment (4 combinations)
  - Re-zipping (4 combinations)

GROUP 7: FINALIZATION (Steps 33-36)
  - Sort BAM (4 outputs)
```

**Hierarchical representation** (ideal):

```groovy
workflow FASTQ_CREATE_UMI_CONSENSUS_FGBIO {
    take:
    reads
    index

    main:
    // SUBWORKFLOW 1: Pre-processing
    PREPARE_UMI_READS(reads)

    // SUBWORKFLOW 2: Initial alignment
    ALIGN_PRE(PREPARE_UMI_READS.out, index)

    // SUBWORKFLOW 3: UMI consensus
    UMI_CONSENSUS(ALIGN_PRE.out)

    // SUBWORKFLOW 4: Post-consensus alignment
    ALIGN_POST(UMI_CONSENSUS.out, index)

    // SUBWORKFLOW 5: Finalize
    FINALIZE(ALIGN_POST.out)

    emit:
    bam = FINALIZE.out
}
```

---

## Nextflow Support for Hierarchical Workflows

### ✅ Nextflow Natively Supports This

**nf-core pattern** (exactly what you described):

```groovy
// File: workflows/rnaseq.nf
include { FASTQC } from '../modules/fastqc/main'
include { TRIMMING } from '../subworkflows/trimming/main'
include { ALIGNMENT } from '../subworkflows/alignment/main'
include { QUANTIFICATION } from '../subworkflows/quantification/main'

workflow RNASEQ {
    take:
    reads

    main:
    // Independent tool
    FASTQC(reads)

    // Subworkflow (contains multiple tools)
    TRIMMING(reads)

    // Subworkflow (contains multiple tools + conditionals)
    ALIGNMENT(TRIMMING.out.reads, params.aligner)

    // Subworkflow
    QUANTIFICATION(ALIGNMENT.out.bam, params.quantifier)

    emit:
    counts = QUANTIFICATION.out
    qc = FASTQC.out
}
```

**Subworkflow structure** (alignment example):

```groovy
// File: subworkflows/alignment/main.nf
include { BWA_INDEX } from '../../modules/bwa/index/main'
include { BWA_MEM } from '../../modules/bwa/mem/main'
include { BOWTIE2_INDEX } from '../../modules/bowtie2/index/main'
include { BOWTIE2_ALIGN } from '../../modules/bowtie2/align/main'
include { SAMTOOLS_SORT } from '../../modules/samtools/sort/main'

workflow ALIGNMENT {
    take:
    reads
    reference
    aligner  // Parameter for conditional

    main:
    if (aligner == 'bwa') {
        BWA_INDEX(reference)
        BWA_MEM(reads, BWA_INDEX.out)
        aligned = BWA_MEM.out
    } else if (aligner == 'bowtie2') {
        BOWTIE2_INDEX(reference)
        BOWTIE2_ALIGN(reads, BOWTIE2_INDEX.out)
        aligned = BOWTIE2_ALIGN.out
    }

    SAMTOOLS_SORT(aligned)

    emit:
    bam = SAMTOOLS_SORT.out
}
```

**Module structure** (individual tools):

```groovy
// File: modules/bwa/mem/main.nf
process BWA_MEM {
    tag "$meta.id"
    label 'process_high'

    conda "bioconda::bwa=0.7.17"

    input:
    tuple val(meta), path(reads)
    path index

    output:
    tuple val(meta), path("*.bam"), emit: bam

    script:
    """
    bwa mem -t ${task.cpus} $index $reads | samtools view -bS - > ${meta.id}.bam
    """
}
```

---

## Benefits of Hierarchical Conversion

### 1. **Modularity and Reusability** ✅

**Current approach**: 37-step flat workflow = massive monolithic conversion

**Hierarchical approach**:
```
7 subworkflows × ~5 tools each = easier to manage
Each subworkflow can be:
  - Converted independently
  - Tested independently
  - Reused across workflows
```

**Example**: ALIGNMENT subworkflow used in:
- RNA-seq pipeline
- ChIP-seq pipeline
- WGS pipeline
- Methylation pipeline

**Benefit**: Convert once, reuse everywhere

---

### 2. **Better LLM Context and Quality** ✅

**Current approach**: LLM sees one tool at a time, no biological context

**Hierarchical approach**:
```python
# Prompt for subworkflow
prompt = """
Convert this ALIGNMENT subworkflow.

Biological purpose: Align sequencing reads to reference genome

Tools in this logical group:
1. BWA_INDEX: Build index for BWA aligner
2. BWA_MEM: Align paired-end reads using BWA-MEM algorithm
3. SAMTOOLS_SORT: Sort aligned BAM file by coordinate

Input: Paired-end FASTQ reads, reference genome FASTA
Output: Sorted BAM file

This is a cohesive unit - generate a Nextflow subworkflow.
"""
```

**Better understanding**:
- LLM knows the tools work together
- Can infer proper data flow
- Understands biological logic
- Generates more coherent code

---

### 3. **Easier Testing and Debugging** ✅

**Current approach**: Test entire 37-step workflow at once
- Hard to identify which part failed
- Long feedback cycles
- Difficult to fix errors

**Hierarchical approach**: Test each subworkflow independently
```bash
# Test ALIGNMENT subworkflow alone
nextflow run subworkflows/alignment/main.nf --reads test_reads.fq --reference test_ref.fa

# Test UMI_CONSENSUS subworkflow alone
nextflow run subworkflows/umi_consensus/main.nf --bam test.bam

# Then test complete workflow
nextflow run workflows/umi_pipeline.nf
```

**Benefit**: Faster iteration, pinpoint errors to specific biological steps

---

### 4. **Natural Parallelism** ✅

**Biological workflows often have independent branches**:

```
INPUT
  ├─→ QC (independent)
  ├─→ ALIGNMENT (depends on INPUT)
  │     ├─→ VARIANT_CALLING (depends on ALIGNMENT)
  │     └─→ COVERAGE_ANALYSIS (depends on ALIGNMENT)
  └─→ ASSEMBLY (independent alternative path)
```

**Hierarchical structure makes this explicit**:
```groovy
workflow VARIANT_PIPELINE {
    main:
    // These can run in parallel
    QC(reads)
    ALIGNMENT(reads, ref)

    // These depend on ALIGNMENT but are independent of each other
    VARIANT_CALLING(ALIGNMENT.out.bam)
    COVERAGE_ANALYSIS(ALIGNMENT.out.bam)
}
```

**Benefit**: Nextflow automatically parallelizes independent subworkflows

---

### 5. **Handles Conditionals Naturally** ✅

**Example**: Alternative aligners in ALIGNMENT subworkflow

**Flat approach** (current):
- 6 separate BWA processes
- User manually chooses which to run
- No clear relationship

**Hierarchical approach**:
```groovy
workflow ALIGNMENT {
    take:
    reads
    ref

    main:
    if (params.aligner == 'bwa') {
        BWA_ALIGN(reads, ref)
        bam = BWA_ALIGN.out
    } else if (params.aligner == 'bowtie2') {
        BOWTIE2_ALIGN(reads, ref)
        bam = BOWTIE2_ALIGN.out
    }

    emit:
    bam = bam
}
```

**Benefit**: Conditional logic encapsulated in subworkflow, clean interface

---

## Challenges and Solutions

### Challenge 1: Galaxy Workflows Are Flat

**Problem**: No explicit subworkflow structure in Galaxy .ga files

**Solution**: Reconstruct logical groups using:

1. **Dependency graph analysis**
   - Find clusters of tightly connected steps
   - Identify clear input/output boundaries

2. **Annotation/label analysis**
   - Many tools have labels like "BWA_MEM_PRE", "BWA_MEM_POST"
   - Prefixes/suffixes indicate grouping

3. **Tool sequence patterns**
   - Common patterns: `index → align → sort`
   - LLM can recognize biological workflows

4. **User hints** (optional)
   - Allow users to specify groupings
   - Or confirm auto-detected groups

**Implementation**:
```python
class WorkflowHierarchyDetector:
    """
    Detect logical subworkflow groups in flat Galaxy workflows.
    """

    def detect_subworkflows(self, galaxy_workflow: Dict) -> List[SubworkflowGroup]:
        """
        1. Build dependency graph
        2. Find connected components with clear boundaries
        3. Apply biological workflow patterns
        4. Suggest groupings to LLM for validation
        """

        groups = []

        # Pattern 1: Common biological units
        alignment_group = self._find_alignment_subworkflow(workflow)
        if alignment_group:
            groups.append(alignment_group)

        qc_group = self._find_qc_subworkflow(workflow)
        if qc_group:
            groups.append(qc_group)

        # Pattern 2: Label-based grouping
        label_groups = self._group_by_label_prefix(workflow)
        groups.extend(label_groups)

        # Pattern 3: Dependency clustering
        cluster_groups = self._cluster_by_dependencies(workflow)
        groups.extend(cluster_groups)

        return groups
```

---

### Challenge 2: Subworkflow Boundaries

**Problem**: Where does one subworkflow end and another begin?

**Heuristics**:

1. **Fan-out/fan-in points**
   - One output → multiple consumers = potential boundary
   - Multiple inputs → one step = potential boundary

2. **Biological semantics**
   - QC is separate from alignment
   - Alignment is separate from variant calling
   - Each has clear purpose

3. **Tool type clustering**
   - fgbio tools together
   - BWA tools together
   - Samtools tools together

4. **Input/output types**
   - FASTQ → BAM = alignment subworkflow
   - BAM → VCF = variant calling subworkflow

**Example**:
```
Steps 10-17: All work with unmapped BAM and FASTQ
              → PRE-ALIGNMENT group

Step 18: Single step, clear purpose (UMI grouping)
         → Independent tool (not subworkflow)

Steps 19-22: Consensus calling and filtering
              → CONSENSUS group

Steps 23-32: Re-alignment after consensus
              → POST-ALIGNMENT group
```

---

### Challenge 3: Conversion Complexity

**Current**: Single-pass conversion (all steps at once)

**Hierarchical**: Multi-level conversion

**Strategy**:

```python
class HierarchicalConverter:
    """
    Convert Galaxy → Nextflow using hierarchical strategy.
    """

    def convert(self, galaxy_workflow: Dict):
        # Step 1: Detect logical groups
        groups = self.hierarchy_detector.detect_subworkflows(galaxy_workflow)

        # Step 2: Convert each group to Nextflow subworkflow
        subworkflows = {}
        for group in groups:
            if group.size <= 3:
                # Small group: convert as inline steps
                subworkflows[group.name] = self.convert_inline(group)
            else:
                # Large group: convert as subworkflow
                subworkflows[group.name] = self.convert_subworkflow(group)

        # Step 3: Convert independent tools
        tools = self.extract_independent_tools(galaxy_workflow, groups)
        modules = {tool.id: self.convert_tool(tool) for tool in tools}

        # Step 4: Generate main workflow that composes subworkflows
        main_workflow = self.generate_main_workflow(
            subworkflows, modules, galaxy_workflow
        )

        return {
            'main': main_workflow,
            'subworkflows': subworkflows,
            'modules': modules
        }
```

---

## Efficiency Analysis

### Time Complexity

**Flat approach**:
- Convert 37 steps: 37 LLM calls
- Test entire workflow: 1 test (long feedback loop)
- Fix errors: Re-convert all 37 steps
- **Total**: ~37 conversions × 3 iterations = ~111 LLM calls

**Hierarchical approach**:
- Detect 7 subworkflows: 1 analysis pass
- Convert 7 subworkflows: 7 LLM calls (with more context)
- Convert 5 independent tools: 5 LLM calls
- Generate main workflow: 1 LLM call
- Test each subworkflow: 7 tests (fast feedback)
- Fix errors in specific subworkflows: ~3 subworkflows × 2 iterations = 6 LLM calls
- **Total**: ~13 conversions + 6 fixes = ~19 LLM calls

**Improvement**: **5.8× fewer LLM calls**, better quality (more context per call)

---

### Quality Comparison

| Aspect | Flat | Hierarchical | Winner |
|--------|------|--------------|--------|
| **LLM context** | 1 tool at a time | Full biological unit | ✅ Hierarchical |
| **Code organization** | Monolithic | Modular | ✅ Hierarchical |
| **Reusability** | None | High | ✅ Hierarchical |
| **Testing** | All-or-nothing | Unit testable | ✅ Hierarchical |
| **Debugging** | Hard to pinpoint errors | Clear error location | ✅ Hierarchical |
| **Maintenance** | Difficult | Easy | ✅ Hierarchical |
| **nf-core compliance** | Moderate | High | ✅ Hierarchical |
| **Implementation complexity** | Low | Medium | ❌ Flat |

**Winner**: Hierarchical (6/7 metrics)

---

## Implementation Recommendation

### Phase 1: Current Implementation (In Progress)

**Status**: Implementing enhanced flat converter
- Conditional detection ✅
- Type inference ✅
- Tool grouping ✅ (for conditionals only)
- Enhanced prompts ✅

**Benefit**: Quick wins, handles 47.9% of workflows better

**Timeline**: Complete this first (next 1-2 days)

---

### Phase 2: Hierarchical Enhancement (Recommended Next)

**Add hierarchical conversion**:

1. **WorkflowHierarchyDetector** (new component)
   - Analyze dependency graph
   - Detect logical subworkflow groups
   - Use biological workflow patterns
   - **Estimated effort**: 2-3 days

2. **SubworkflowConverter** (new component)
   - Convert groups to Nextflow subworkflows
   - Handle subworkflow inputs/outputs
   - Generate subworkflow-level tests
   - **Estimated effort**: 2-3 days

3. **HierarchicalWorkflowGenerator** (new component)
   - Compose main workflow from subworkflows
   - Proper include/require statements
   - Wire subworkflow calls
   - **Estimated effort**: 1-2 days

4. **Integration and testing**
   - Test on complex workflows (30+ steps)
   - Compare flat vs hierarchical quality
   - Measure efficiency gains
   - **Estimated effort**: 2-3 days

**Total timeline**: 1-2 weeks

**Expected improvement**:
- 5-10× faster conversion for complex workflows
- Higher quality (better LLM context)
- More maintainable outputs
- Closer to nf-core patterns

---

### Phase 3: Reverse Converter (Nextflow → Galaxy)

**After Phase 2**, reverse conversion becomes easier:

- Nextflow subworkflows → Galaxy subworkflow steps (if Galaxy supports)
- Or: Flatten Nextflow subworkflows → Galaxy flat workflow
- Benefit: Hierarchical structure aids decomposition

---

## Concrete Example: Before vs After

### Before (Flat Conversion)

```
INPUT: fastq_create_umi_consensus_fgbio.ga (37 steps)

CONVERSION:
- 37 LLM calls (one per step)
- Each LLM sees only one tool
- No biological context
- Result: 37 separate process files

OUTPUT:
modules/
  step_10/main.nf  (fgbio FastqToBam)
  step_11/main.nf  (samtools fastq)
  step_12/main.nf  (BWA Index 1)
  step_13/main.nf  (BWA Index 2)
  ...
  step_36/main.nf  (samtools sort 4)
main.nf (calls all 37 processes sequentially)
```

**Problems**:
- Massive main.nf with 37 process calls
- No reusability
- Hard to understand
- Doesn't match nf-core patterns

---

### After (Hierarchical Conversion)

```
INPUT: fastq_create_umi_consensus_fgbio.ga (37 steps)

ANALYSIS:
- Detect 7 logical subworkflows
- Detect 5 reusable patterns

CONVERSION:
- 7 subworkflow conversions (with full biological context)
- 5 independent tool conversions
- 1 main workflow composition

OUTPUT:
subworkflows/
  prepare_umi_reads/
    main.nf  (FastqToBam → BAM2FASTQ)

  alignment/
    main.nf  (Index → Align → Zipper, with BWA/BWA-MEM2 conditional)

  umi_consensus/
    main.nf  (GroupByUmi → CallConsensus → Filter, with duplex/molecular branches)

  post_alignment/
    main.nf  (Re-align after consensus)

  finalize/
    main.nf  (Sort and output)

modules/
  fgbio/fastqtobam/main.nf
  fgbio/groupreadsby umi/main.nf
  samtools/sort/main.nf
  ...

workflows/
  umi_consensus_pipeline/
    main.nf  (composes subworkflows)
```

**Benefits**:
- Clean, modular structure
- Matches nf-core patterns exactly
- Each subworkflow reusable
- Easy to test and maintain
- Biological logic preserved

---

## Conclusion

### Answer to Original Question

**Q**: "Will hierarchical/compositional conversion (subworkflows → tools → workflow) make conversion easier?"

**A**: **YES, absolutely** - with significant benefits:

1. ✅ **Efficiency**: 5-10× faster conversion (fewer LLM calls, better caching)
2. ✅ **Quality**: Better LLM context → better code
3. ✅ **Maintainability**: Modular structure, easy to debug
4. ✅ **Reusability**: Subworkflows shared across pipelines
5. ✅ **nf-core compliance**: Matches nf-core patterns exactly
6. ✅ **Testing**: Unit test subworkflows independently
7. ✅ **Nextflow native**: Nextflow is designed for this pattern

### Recommendation

**Implement in 2 phases**:

1. **Phase 1 (current)**: Enhanced flat converter with conditionals
   - Quick wins for 47.9% of workflows
   - Foundation for Phase 2
   - **Timeline**: Complete this week

2. **Phase 2 (next)**: Add hierarchical conversion
   - For complex workflows (16+ steps)
   - Detect subworkflow groups automatically
   - Generate modular Nextflow code
   - **Timeline**: Next 1-2 weeks

**Expected result**: Best-in-class Galaxy→Nextflow converter that produces nf-core-quality code

---

**Status**: Recommendation is to proceed with hierarchical approach as Phase 2 enhancement ✅
