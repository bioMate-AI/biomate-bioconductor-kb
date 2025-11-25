# Phase 2 Implementation Plan - Hierarchical Conversion

**Date**: 2025-11-24 22:20
**Timeline**: 1-2 weeks
**Goal**: 5-10× efficiency gain for complex workflows
**Status**: 📋 PLANNING - Ready to start

---

## Overview

Phase 2 implements hierarchical/compositional conversion based on user's brilliant insight:

**User's Question**: *"for galaxy workflows, if follow the biological logic, using the grouped chain of subworkflow and independent tool-function as steps, work on the subworkflow and independent tool-function first, then generate the entire workflow, will this makes the work more efficient?"*

**Answer**: YES - this is **perfectly aligned with Nextflow/nf-core architecture** and will provide:
- 5-10× fewer LLM calls for complex workflows
- Higher quality (LLM gets full biological context)
- Modular outputs (subworkflows + main workflow)
- Better maintainability

---

## Problem Statement

### Current Limitation (Phase 1)

**Example**: fastq_create_umi_consensus_fgbio.ga (37 steps)

**Current Conversion**:
```
37 steps → 37 LLM calls → 37 separate process files
- Each LLM sees only ONE tool
- No biological context
- No modularity
- Hard to maintain
```

**Output Structure**:
```
modules/
  step_10/main.nf  (fgbio FastqToBam)
  step_11/main.nf  (samtools fastq)
  step_12/main.nf  (BWA Index 1)
  ...
  step_36/main.nf  (samtools sort 4)
main.nf (37 process calls - massive!)
```

### Desired Outcome (Phase 2)

**Hierarchical Conversion**:
```
37 steps → 7 logical groups → 7 subworkflows → 3-4 LLM calls
- LLM sees GROUPS of tools with biological context
- Subworkflow structure
- Reusable modules
- Matches nf-core patterns
```

**Output Structure**:
```
subworkflows/
  preprocessing/main.nf      (FastqToBam → BAM2FASTQ)
  alignment/main.nf          (Index → BWA_MEM → Sort)
  umi_grouping/main.nf       (GroupReadsByUmi)
  consensus_calling/main.nf  (Duplex/Molecular consensus)
  filtering/main.nf          (FilterConsensusReads)
  postprocessing/main.nf     (Re-align → Re-zip)
  finalization/main.nf       (Final sort)
main.nf (7 subworkflow calls - clean!)
```

---

## Components to Build

### 1. WorkflowHierarchyDetector

**Purpose**: Detect logical subworkflow groups in flat Galaxy workflows

**Estimated Effort**: 2-3 days

**Strategy**:
1. **Dependency Graph Analysis**
   - Build directed acyclic graph (DAG) from step connections
   - Identify strongly connected components
   - Detect linear chains vs branching points

2. **Pattern Detection**
   - Annotation analysis (look for subworkflow mentions)
   - Tool category grouping (alignment, QC, assembly, etc.)
   - Input/output signature analysis

3. **Biological Workflow Patterns**
   - Common patterns: QC → Align → Quantify → DiffExp
   - Tool families: BWA (indexing → alignment → sort)
   - Paired operations: tool + post-processing

**Key Methods**:
```python
class WorkflowHierarchyDetector:
    def detect_subworkflows(self, galaxy_wf: Dict) -> List[SubworkflowGroup]:
        """
        Detect logical subworkflow groups.

        Returns:
            List of subworkflow groups with their steps
        """

    def build_dependency_graph(self, steps: Dict) -> nx.DiGraph:
        """Build DAG from workflow steps."""

    def find_logical_groups(self, graph: nx.DiGraph) -> List[List[str]]:
        """Find groups of steps that form logical units."""

    def classify_group_type(self, group: List[str], steps: Dict) -> str:
        """Classify group (alignment, qc, assembly, etc.)."""
```

**Test Criteria**:
- ✅ Detect 7 groups in fastq_create_umi_consensus_fgbio.ga
- ✅ Group sizes 2-6 steps each
- ✅ No circular dependencies
- ✅ Logical biological grouping

---

### 2. SubworkflowConverter

**Purpose**: Convert subworkflow groups to Nextflow subworkflows

**Estimated Effort**: 2-3 days

**Strategy**:
1. **Subworkflow-Level Prompts**
   - Include ALL tools in the group
   - Provide biological context
   - Specify expected inputs/outputs
   - Request cohesive subworkflow

2. **Input/Output Inference**
   - Analyze first/last steps in group
   - Infer subworkflow input channels
   - Infer subworkflow output channels
   - Match to nf-core patterns

3. **Dual-LLM Conversion**
   - Use existing enhanced converter
   - Enhanced prompts with biological context
   - Quality scoring

**Key Methods**:
```python
class SubworkflowConverter:
    def convert_subworkflow(self,
                          group: SubworkflowGroup,
                          galaxy_steps: List[Dict],
                          type_map: Dict) -> SubworkflowResult:
        """
        Convert a subworkflow group to Nextflow subworkflow.

        Args:
            group: Detected subworkflow group
            galaxy_steps: Galaxy steps in this group
            type_map: Inferred types

        Returns:
            Nextflow subworkflow code + metadata
        """

    def build_subworkflow_prompt(self,
                                group: SubworkflowGroup,
                                steps: List[Dict]) -> str:
        """Build enhanced prompt with biological context."""

    def infer_subworkflow_io(self,
                           group: SubworkflowGroup,
                           steps: List[Dict]) -> Tuple[List, List]:
        """Infer inputs and outputs for subworkflow."""
```

**Output Format**:
```nextflow
// File: subworkflows/alignment/main.nf
workflow ALIGNMENT {
    take:
    reads         // tuple val(meta), path(reads)
    reference     // path(reference_fasta)

    main:
    // Build index
    BWA_INDEX(reference)

    // Align reads
    BWA_MEM(reads, BWA_INDEX.out.index)

    // Sort aligned BAM
    SAMTOOLS_SORT(BWA_MEM.out.bam)

    emit:
    bam = SAMTOOLS_SORT.out.bam
    versions = BWA_INDEX.out.versions.mix(
        BWA_MEM.out.versions,
        SAMTOOLS_SORT.out.versions
    )
}
```

**Test Criteria**:
- ✅ Generates valid Nextflow subworkflow syntax
- ✅ Proper take/emit blocks
- ✅ Correct channel wiring
- ✅ Quality score 85%+

---

### 3. HierarchicalWorkflowGenerator

**Purpose**: Compose main workflow from subworkflows

**Estimated Effort**: 1-2 days

**Strategy**:
1. **Subworkflow Orchestration**
   - Analyze inter-subworkflow dependencies
   - Determine call order
   - Wire subworkflow inputs/outputs

2. **Channel Management**
   - Create input channels
   - Connect subworkflow outputs to next inputs
   - Handle branching/merging

3. **nf-core Compliance**
   - Proper include statements
   - Workflow structure
   - Parameter handling
   - Version collection

**Key Methods**:
```python
class HierarchicalWorkflowGenerator:
    def generate_main_workflow(self,
                              subworkflows: List[SubworkflowResult],
                              dependency_graph: nx.DiGraph) -> str:
        """
        Generate main workflow that calls subworkflows.

        Args:
            subworkflows: List of converted subworkflows
            dependency_graph: Dependencies between subworkflows

        Returns:
            Main workflow Nextflow code
        """

    def build_include_statements(self,
                                subworkflows: List[SubworkflowResult]) -> List[str]:
        """Build include statements for subworkflows."""

    def wire_subworkflow_calls(self,
                              subworkflows: List[SubworkflowResult],
                              graph: nx.DiGraph) -> str:
        """Generate subworkflow call sequence with proper wiring."""
```

**Output Format**:
```nextflow
// File: main.nf
include { PREPROCESSING } from './subworkflows/preprocessing/main'
include { ALIGNMENT } from './subworkflows/alignment/main'
include { UMI_GROUPING } from './subworkflows/umi_grouping/main'
include { CONSENSUS_CALLING } from './subworkflows/consensus_calling/main'
include { FILTERING } from './subworkflows/filtering/main'
include { POSTPROCESSING } from './subworkflows/postprocessing/main'
include { FINALIZATION } from './subworkflows/finalization/main'

workflow FASTQ_CREATE_UMI_CONSENSUS_FGBIO {
    take:
    reads
    reference

    main:
    ch_versions = Channel.empty()

    // Preprocessing
    PREPROCESSING(reads)

    // Alignment
    ALIGNMENT(
        PREPROCESSING.out.fastq,
        reference
    )

    // UMI grouping
    UMI_GROUPING(ALIGNMENT.out.bam)

    // Consensus calling
    CONSENSUS_CALLING(UMI_GROUPING.out.grouped_bam)

    // Filtering
    FILTERING(CONSENSUS_CALLING.out.consensus_bam)

    // Post-processing
    POSTPROCESSING(
        FILTERING.out.filtered_bam,
        reference
    )

    // Finalization
    FINALIZATION(POSTPROCESSING.out.aligned_bam)

    // Collect versions
    ch_versions = ch_versions.mix(
        PREPROCESSING.out.versions,
        ALIGNMENT.out.versions,
        UMI_GROUPING.out.versions,
        CONSENSUS_CALLING.out.versions,
        FILTERING.out.versions,
        POSTPROCESSING.out.versions,
        FINALIZATION.out.versions
    )

    emit:
    bam = FINALIZATION.out.sorted_bam
    versions = ch_versions
}
```

**Test Criteria**:
- ✅ Valid Nextflow DSL2 syntax
- ✅ Correct include statements
- ✅ Proper channel wiring
- ✅ Subworkflow calls in correct order
- ✅ Version collection

---

### 4. Integration into UnifiedGalaxyNextflowConverter

**Estimated Effort**: 1 day

**Changes**:
1. Add `hierarchical_mode` parameter to CLI
2. Add hierarchy detection in Phase 1 (Analysis)
3. Branch conversion logic based on workflow complexity:
   - Simple workflows (< 10 steps): Flat conversion
   - Medium workflows (10-20 steps): Optional hierarchical
   - Complex workflows (> 20 steps): Hierarchical conversion

**Modified Pipeline**:
```python
# PHASE 1: ANALYSIS
if hierarchical_mode or step_count > 20:
    subworkflow_groups = hierarchy_detector.detect_subworkflows(galaxy_wf)
else:
    subworkflow_groups = []

# PHASE 3: CONVERSION
if subworkflow_groups:
    # Hierarchical conversion
    for group in subworkflow_groups:
        subworkflow_result = subworkflow_converter.convert_subworkflow(
            group, steps, type_map
        )
        subworkflows.append(subworkflow_result)

    main_workflow = hierarchical_generator.generate_main_workflow(
        subworkflows, dependency_graph
    )
else:
    # Flat conversion (Phase 1 approach)
    result = self._convert_with_conditionals(...)
```

---

## Implementation Timeline

### Week 1

**Day 1-2: WorkflowHierarchyDetector**
- [ ] Implement dependency graph builder
- [ ] Implement pattern detection algorithms
- [ ] Add biological workflow pattern database
- [ ] Test on 3-5 workflows of varying complexity
- [ ] Document detection logic

**Day 3-4: SubworkflowConverter**
- [ ] Implement subworkflow-level prompt builder
- [ ] Implement I/O inference logic
- [ ] Integrate with existing enhanced_converter
- [ ] Test subworkflow generation
- [ ] Quality scoring for subworkflows

**Day 5-6: HierarchicalWorkflowGenerator**
- [ ] Implement main workflow generator
- [ ] Implement channel wiring logic
- [ ] Add include statement builder
- [ ] Test workflow composition
- [ ] Validate against nf-core patterns

**Day 7: Integration & Testing**
- [ ] Integrate into UnifiedGalaxyNextflowConverter
- [ ] Add CLI parameter for hierarchical mode
- [ ] End-to-end testing on simple workflow

### Week 2

**Day 8-9: Complex Workflow Testing**
- [ ] Test on fastq_create_umi_consensus_fgbio.ga (37 steps)
- [ ] Verify 7 subworkflows generated
- [ ] Validate subworkflow quality
- [ ] Test workflow execution (stub mode)

**Day 10-11: Comparison & Metrics**
- [ ] Compare flat vs hierarchical for 5 workflows
- [ ] Measure LLM call reduction
- [ ] Measure quality score differences
- [ ] Measure code maintainability (LOC, structure)

**Day 12: Documentation & Polish**
- [ ] Document all new components
- [ ] Create usage guide
- [ ] Write test results summary
- [ ] Commit all Phase 2 work

---

## Expected Outcomes

### Quantitative

1. **LLM Call Reduction**: 5-10× fewer calls
   - Before: 37 calls for 37-step workflow
   - After: 3-4 calls for 7 subworkflows

2. **Quality Improvement**: 10-15% higher scores
   - Better biological context
   - More cohesive code
   - Proper subworkflow structure

3. **Code Organization**: 80% reduction in main.nf complexity
   - Before: 37 process calls in main.nf
   - After: 7 subworkflow calls in main.nf

### Qualitative

1. **Better Maintainability**
   - Modular structure
   - Clear separation of concerns
   - Easier to understand and modify

2. **Closer to nf-core**
   - Matches nf-core subworkflow patterns
   - Reusable subworkflows
   - Community-compatible structure

3. **Enhanced Testing**
   - Test subworkflows independently
   - Faster debugging
   - Better error isolation

---

## Success Criteria

### Phase 2 Goals

| Criterion | Target | Measurement |
|-----------|--------|-------------|
| Subworkflow detection accuracy | 90% | Manual validation on 10 workflows |
| LLM call reduction | 5-10× | Count LLM calls: flat vs hierarchical |
| Quality score improvement | +10-15% | Compare average scores |
| Code organization | 7-10 subworkflows for 37-step workflow | Count subworkflows |
| Subworkflow quality | 85%+ | NextflowBestPracticesScorer |
| Main workflow validity | 100% | Nextflow syntax check |

### Validation Tests

1. **fastq_create_umi_consensus_fgbio.ga** (37 steps)
   - Expected: 7 subworkflows
   - Quality: 85%+ for each subworkflow
   - Valid main workflow

2. **Medium complexity workflow** (15-20 steps)
   - Expected: 3-4 subworkflows
   - Quality: 85%+

3. **Simple workflow** (< 10 steps)
   - Expected: Flat conversion (no subworkflows)
   - Quality: 90%+

---

## Risk Assessment

### Technical Risks

**Risk 1**: Incorrect subworkflow boundaries
- **Mitigation**: Conservative grouping, manual validation
- **Impact**: Medium - may require refinement

**Risk 2**: Complex channel wiring
- **Mitigation**: Start with linear workflows, add branching later
- **Impact**: Medium - can simplify initially

**Risk 3**: LLM struggles with multi-tool context
- **Mitigation**: Limit subworkflow size to 5-7 tools
- **Impact**: Low - can fall back to flat conversion

### Schedule Risks

**Risk 1**: Dependency graph analysis more complex than expected
- **Mitigation**: Use networkx library, start simple
- **Impact**: Low - library handles complexity

**Risk 2**: Testing takes longer than estimated
- **Mitigation**: Prioritize critical tests, automate where possible
- **Impact**: Low - can extend timeline

---

## Dependencies

### External Libraries
- `networkx`: For dependency graph analysis
- `pygraphviz` (optional): For graph visualization

### Internal Dependencies
- Phase 1 components (all complete)
- EnhancedProcessConverter
- NextflowBestPracticesScorer

---

## Future Enhancements (Phase 3+)

After Phase 2, can add:

1. **Automatic Subworkflow Library** (Phase 3)
   - Store generated subworkflows
   - Reuse across workflows
   - 2.8-7.2× speedup from caching

2. **Semantic Matching**
   - Match similar subworkflows
   - Suggest reuse opportunities
   - Learn from user edits

3. **Reverse Conversion** (Nextflow → Galaxy)
   - Leverage hierarchical structure
   - Easier to decompose
   - Better fidelity

---

## Next Steps

### Immediate
1. Commit Phase 1 final summary
2. Create WorkflowHierarchyDetector implementation file
3. Start with dependency graph builder
4. Test on fastq_create_umi_consensus_fgbio.ga

### This Week
- Complete WorkflowHierarchyDetector
- Complete SubworkflowConverter
- Start HierarchicalWorkflowGenerator

---

## Conclusion

Phase 2 implements user's brilliant insight about hierarchical conversion:

**User's Vision**: *"work on the subworkflow and independent tool-function first, then generate the entire workflow"*

**Our Implementation**:
1. Detect logical subworkflow groups (WorkflowHierarchyDetector)
2. Convert groups to Nextflow subworkflows (SubworkflowConverter)
3. Compose main workflow from subworkflows (HierarchicalWorkflowGenerator)

**Expected Impact**:
- 5-10× fewer LLM calls
- 10-15% higher quality
- Much better code organization
- Perfect alignment with nf-core

**Status**: Ready to start implementation

---

**Date**: 2025-11-24 22:20
**Phase**: 2 PLANNING
**Status**: 📋 READY TO START
**Timeline**: 1-2 weeks
