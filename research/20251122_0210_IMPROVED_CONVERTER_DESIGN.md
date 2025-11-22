# Improved Galaxy ↔ Nextflow Converter Design

**Date**: 2025-11-22 02:10
**Based on**: Comprehensive comparison analysis
**Goal**: Bi-directional converter with Galaxy→Nextflow as primary direction

---

## Current System Analysis

### What We Have (dual_llm_converter_system_part2.py)

**Components**:
1. ✅ **ProcessConverter**: Converts Galaxy steps to Nextflow processes using both LLMs
2. ✅ **AssemblyAuditor**: Compares and merges outputs from Claude and Gemini
3. ✅ **NextflowTester**: Executes Nextflow to catch errors
4. ✅ **IterativeRefiner**: Refinement loop with error feedback

**Architecture**:
```
Galaxy Workflow (.ga)
        ↓
[Parse] → Extract processes
        ↓
┌───────────────────────────┐
│   Parallel Conversion     │
│  ┌─────────┐ ┌─────────┐ │
│  │ Claude  │ │ Gemini  │ │
│  └─────────┘ └─────────┘ │
└───────────────────────────┘
        ↓
[Audit & Merge] → Best from both
        ↓
[Test] → Nextflow execution
        ↓
[Refine] → Fix errors (loop)
        ↓
Nextflow Workflow (.nf + modules)
```

**Current Capabilities**:
- ✅ Converts each Galaxy step to one Nextflow process
- ✅ Generates process definitions with input/output
- ✅ Uses dual-LLM for quality (Claude vs Gemini)
- ✅ Tests with real Nextflow execution
- ✅ Iterative refinement on errors

**Current Limitations** (discovered from comparison):
- ❌ **No conditional detection**: Ignores "tool1 or tool2" in annotations (47.9% of workflows!)
- ❌ **No type inference**: Doesn't distinguish path vs val vs tuple
- ❌ **No tool grouping**: Creates separate processes instead of merging alternatives
- ❌ **Basic prompts**: Doesn't leverage Nextflow best practices (labels, tuples, nf-core patterns)
- ❌ **No Galaxy data type mapping**: Doesn't use Galaxy datatype metadata
- ❌ **Simple script generation**: LLM generates scripts without context about proper patterns

---

## Improved Architecture

### New Pipeline Design

```
Galaxy Workflow (.ga)
        ↓
┌─────────────────────────────────────────────┐
│  PHASE 1: Analysis & Planning               │
│  ────────────────────────────────────────   │
│  [1] Parse Galaxy workflow structure        │
│  [2] Extract metadata & annotations         │
│  [3] Detect conditional patterns ⭐ NEW     │
│  [4] Infer data types ⭐ NEW                │
│  [5] Group alternative tools ⭐ NEW         │
│  [6] Build dependency graph                 │
└─────────────────────────────────────────────┘
        ↓
┌─────────────────────────────────────────────┐
│  PHASE 2: Conversion Strategy               │
│  ────────────────────────────────────────   │
│  For each process/group:                    │
│  - Determine conversion type:               │
│    • Simple: 1 step → 1 process             │
│    • Conditional: N steps → 1 if/else       │
│    • Collection: List → Tuple               │
│  - Assign types (path/val/tuple)            │
│  - Select Nextflow patterns (nf-core)       │
└─────────────────────────────────────────────┘
        ↓
┌─────────────────────────────────────────────┐
│  PHASE 3: Dual-LLM Conversion               │
│  ────────────────────────────────────────   │
│  Parallel conversion with enhanced prompts: │
│  ┌─────────────┐       ┌─────────────┐     │
│  │   Claude    │       │   Gemini    │     │
│  │  + context  │       │  + context  │     │
│  │  + types    │       │  + types    │     │
│  │  + patterns │       │  + patterns │     │
│  └─────────────┘       └─────────────┘     │
└─────────────────────────────────────────────┘
        ↓
┌─────────────────────────────────────────────┐
│  PHASE 4: Assembly & Audit                  │
│  ────────────────────────────────────────   │
│  [1] Compare Claude vs Gemini               │
│  [2] Score on Nextflow best practices       │
│  [3] Merge best components                  │
│  [4] Generate main.nf with proper wiring    │
│  [5] Generate nextflow.config               │
└─────────────────────────────────────────────┘
        ↓
┌─────────────────────────────────────────────┐
│  PHASE 5: Testing & Refinement              │
│  ────────────────────────────────────────   │
│  [1] Nextflow syntax check                  │
│  [2] Nextflow dry-run test                  │
│  [3] Parse errors                           │
│  [4] Refine (up to 3 iterations)            │
└─────────────────────────────────────────────┘
        ↓
Nextflow Workflow (main.nf + modules/)
```

---

## New Components to Implement

### 1. ConditionalPatternDetector ⭐ NEW

**Purpose**: Detect implicit conditional logic in Galaxy workflows

```python
class ConditionalPatternDetector:
    """
    Detect conditional patterns from:
    1. Annotation text ("tool1 or tool2", "selectable aligner")
    2. Multiple tools with same inputs
    3. Alternative steps with similar purpose
    """

    def detect_patterns(self, galaxy_workflow: Dict) -> List[ConditionalGroup]:
        """
        Returns groups of steps that should be merged into conditionals.

        Example:
        {
            'type': 'tool_alternatives',
            'steps': [5, 6, 7],  # Bowtie2, BWA-MEM, DRAGMAP
            'parameter': 'aligner',
            'pattern': 'if/else',
            'annotation': "selectable aligner (bowtie2, bwamem, dragmap)"
        }
        """

        groups = []

        # Pattern 1: Annotation mentions "or", "vs", "choice"
        annotation = galaxy_workflow.get('annotation', '')
        if self._has_branching_keywords(annotation):
            groups.append(self._extract_tool_alternatives(galaxy_workflow))

        # Pattern 2: Multiple tools with identical inputs
        similar_tools = self._find_tools_with_same_inputs(galaxy_workflow)
        groups.extend(similar_tools)

        return groups

    def _has_branching_keywords(self, text: str) -> bool:
        keywords = [' or ', ' vs ', 'choice', 'selectable', 'alternative',
                   'either', 'option', 'branch']
        return any(kw in text.lower() for kw in keywords)
```

---

### 2. GalaxyTypeInferencer ⭐ NEW

**Purpose**: Infer Nextflow types from Galaxy implicit types

```python
class GalaxyTypeInferencer:
    """
    Infer Nextflow channel types from Galaxy metadata.

    Galaxy → Nextflow mappings:
    - data_input (fastq) → path(reads)
    - data_input (bam) → path(bam)
    - data_collection_input (paired) → tuple val(meta), path(reads)
    - parameter_input (text) → val(param)
    """

    def infer_type(self, galaxy_step: Dict) -> str:
        """
        Returns Nextflow type spec, e.g.:
        - "path(reads)"
        - "tuple val(meta), path(reads)"
        - "val(sample_id)"
        """

        step_type = galaxy_step.get('type')

        if step_type == 'data_input':
            # Check if it's a collection
            return "path(input_file)"

        elif step_type == 'data_collection_input':
            collection_type = galaxy_step.get('collection_type', 'list')
            if collection_type == 'paired':
                return "tuple val(meta), path(reads)"
            else:
                return "path(files)"

        elif step_type == 'parameter_input':
            param_type = self._extract_param_type(galaxy_step)
            if param_type in ['integer', 'float', 'boolean']:
                return f"val({galaxy_step['label']})"
            else:
                return f"val({galaxy_step['label']})"

        return "path(input)"

    def infer_from_tool_id(self, tool_id: str) -> str:
        """Infer type from tool ID patterns."""
        if 'fastq' in tool_id.lower():
            return 'fastq'
        elif 'bam' in tool_id.lower():
            return 'bam'
        elif 'vcf' in tool_id.lower():
            return 'vcf'
        # ... etc
        return 'generic'
```

---

### 3. ToolGrouper ⭐ NEW

**Purpose**: Group alternative tools that should be merged

```python
class ToolGrouper:
    """
    Group Galaxy steps that represent alternative tools.

    Example:
    Steps 5, 6, 7 (Bowtie2, BWA, DRAGMAP) with same inputs
    → Group them for conditional conversion
    """

    def group_alternative_tools(self, steps: Dict,
                                conditional_patterns: List) -> List[ToolGroup]:
        """
        Returns groups of steps that should be merged.

        Example output:
        [
            {
                'group_id': 'aligner_choice',
                'steps': [5, 6, 7],
                'tools': ['bowtie2', 'bwamem', 'dragmap'],
                'parameter': 'aligner',
                'merge_strategy': 'if_else'  # or 'when_directive'
            }
        ]
        """

        groups = []

        for pattern in conditional_patterns:
            if pattern['type'] == 'tool_alternatives':
                # Check if tools have same inputs
                step_ids = pattern['steps']
                if self._have_same_inputs(steps, step_ids):
                    groups.append({
                        'group_id': pattern['parameter'],
                        'steps': step_ids,
                        'tools': [steps[str(sid)]['tool_id'] for sid in step_ids],
                        'parameter': pattern['parameter'],
                        'merge_strategy': 'if_else' if len(step_ids) <= 4 else 'when_directive'
                    })

        return groups
```

---

### 4. EnhancedPromptBuilder ⭐ NEW

**Purpose**: Build context-rich prompts for LLMs

```python
class EnhancedPromptBuilder:
    """
    Build enhanced prompts with:
    - Inferred types
    - Nextflow best practices
    - Conditional patterns
    - nf-core examples
    """

    def build_process_prompt(self,
                            galaxy_step: Dict,
                            inferred_types: Dict,
                            is_conditional_group: bool = False,
                            group_info: Optional[Dict] = None) -> str:
        """
        Build enhanced prompt for converting Galaxy step to Nextflow process.
        """

        if is_conditional_group:
            return self._build_conditional_process_prompt(galaxy_step, group_info)
        else:
            return self._build_simple_process_prompt(galaxy_step, inferred_types)

    def _build_simple_process_prompt(self, step: Dict, types: Dict) -> str:
        """Build prompt for simple 1:1 conversion."""

        prompt = f"""
# Task: Convert Galaxy step to Nextflow process

## Galaxy Step Information:
- Tool ID: {step['tool_id']}
- Label: {step.get('label', 'unlabeled')}
- Type: {step.get('type')}

## Inferred Nextflow Types:
{json.dumps(types, indent=2)}

## Requirements:
1. Follow nf-core best practices
2. Use proper input types: {', '.join(types.values())}
3. Include:
   - tag directive for logging
   - label for resource management
   - conda/container specifications
   - proper emit names for outputs
4. Generate realistic script that matches the tool purpose
5. Include version capture in script

## Example nf-core process structure:
```groovy
process TOOL_NAME {{
    tag "$meta.id"
    label 'process_medium'

    conda "bioconda::tool=1.0"
    container "biocontainers/tool:1.0"

    input:
    tuple val(meta), path(reads)

    output:
    tuple val(meta), path("*.bam"), emit: bam
    path "versions.yml", emit: versions

    script:
    def prefix = meta.id
    \"\"\"
    tool -i $reads -o ${{prefix}}.bam

    cat <<-END_VERSIONS > versions.yml
    "${{task.process}}":
        tool: \$(tool --version | cut -d' ' -f2)
    END_VERSIONS
    \"\"\"
}}
```

Now convert the Galaxy step to Nextflow process following this pattern.
"""
        return prompt

    def _build_conditional_process_prompt(self, step: Dict, group_info: Dict) -> str:
        """Build prompt for conditional process (multiple tools merged)."""

        prompt = f"""
# Task: Convert Galaxy tool alternatives to conditional Nextflow process

## Situation:
The Galaxy workflow has {len(group_info['tools'])} alternative tools for the same purpose:
{', '.join(group_info['tools'])}

These should be merged into ONE Nextflow process with conditional logic.

## Tools to merge:
{json.dumps(group_info['tools'], indent=2)}

## Requirements:
1. Create a SINGLE process that handles all alternatives
2. Use if/else blocks to switch between tools based on params.{group_info['parameter']}
3. Follow nf-core patterns for conditional processes
4. All branches should have same output structure

## Example pattern:
```groovy
process ALIGN {{
    tag "$meta.id"
    label 'process_high'

    conda "bioconda::bwa=0.7.17 bioconda::bowtie2=2.4.5"

    input:
    tuple val(meta), path(reads)
    path index

    output:
    tuple val(meta), path("*.bam"), emit: bam

    script:
    def prefix = meta.id
    if (params.aligner == 'bwa') {{
        \"\"\"
        bwa mem -t ${{task.cpus}} $index $reads | samtools view -bS - > ${{prefix}}.bam
        \"\"\"
    }} else if (params.aligner == 'bowtie2') {{
        \"\"\"
        bowtie2 -x $index -U $reads -S ${{prefix}}.sam
        samtools view -bS ${{prefix}}.sam > ${{prefix}}.bam
        \"\"\"
    }}
}}
```

Now create the conditional process for these tools.
"""
        return prompt
```

---

### 5. NextflowBestPracticesScorer ⭐ ENHANCED

**Purpose**: Score processes based on Nextflow/nf-core best practices

```python
class NextflowBestPracticesScorer:
    """
    Enhanced scoring based on comprehensive comparison findings.
    """

    def score_process(self, nextflow_code: str, galaxy_source: Dict) -> float:
        """
        Score on 100-point scale based on best practices.

        Criteria:
        1. Proper input types (tuple val(meta), path(...)) - 20 points
        2. Label directives for resource management - 15 points
        3. Container/conda specifications - 15 points
        4. Named emit outputs - 10 points
        5. Version capture - 10 points
        6. Tag directive for logging - 10 points
        7. Proper variable naming (prefix = meta.id) - 10 points
        8. Script quality (realistic commands) - 10 points
        """

        score = 0.0

        # Check for tuple val(meta), path(...) pattern
        if re.search(r'tuple\s+val\(meta\),\s+path\(', nextflow_code):
            score += 20
        elif re.search(r'path\(', nextflow_code):
            score += 10  # At least has path

        # Check for label directive
        if re.search(r'label\s+[\'"]process_', nextflow_code):
            score += 15

        # Check for conda/container
        if 'conda' in nextflow_code or 'container' in nextflow_code:
            score += 15

        # Check for emit names
        if re.search(r'emit:\s+\w+', nextflow_code):
            score += 10

        # Check for version capture
        if 'versions.yml' in nextflow_code or 'END_VERSIONS' in nextflow_code:
            score += 10

        # Check for tag directive
        if 'tag ' in nextflow_code:
            score += 10

        # Check for proper prefix usage
        if 'prefix = meta.id' in nextflow_code or 'def prefix' in nextflow_code:
            score += 10

        # Basic script quality check
        if '"""' in nextflow_code and len(nextflow_code) > 200:
            score += 10

        return score
```

---

## Updated Workflow

### Main Conversion Function (Enhanced)

```python
class ImprovedGalaxyToNextflowConverter:
    """
    Improved converter with all new components.
    """

    def __init__(self):
        self.pattern_detector = ConditionalPatternDetector()
        self.type_inferencer = GalaxyTypeInferencer()
        self.tool_grouper = ToolGrouper()
        self.prompt_builder = EnhancedPromptBuilder()
        self.scorer = NextflowBestPracticesScorer()

        # Existing components
        self.process_converter = ProcessConverter(...)
        self.auditor = AssemblyAuditor()
        self.tester = NextflowTester()
        self.refiner = IterativeRefiner()

    def convert(self, galaxy_workflow_path: str) -> Dict:
        """
        Complete conversion pipeline with all enhancements.
        """

        # PHASE 1: Analysis & Planning
        print("=" * 80)
        print("PHASE 1: Analysis & Planning")
        print("=" * 80)

        galaxy_wf = self._load_galaxy_workflow(galaxy_workflow_path)

        # Detect conditional patterns
        conditional_patterns = self.pattern_detector.detect_patterns(galaxy_wf)
        print(f"✓ Detected {len(conditional_patterns)} conditional patterns")

        # Infer types for all inputs
        type_map = {}
        for step_id, step in galaxy_wf['steps'].items():
            if step.get('type') in ['data_input', 'data_collection_input', 'parameter_input']:
                type_map[step_id] = self.type_inferencer.infer_type(step)
        print(f"✓ Inferred types for {len(type_map)} inputs")

        # Group alternative tools
        tool_groups = self.tool_grouper.group_alternative_tools(
            galaxy_wf['steps'], conditional_patterns
        )
        print(f"✓ Grouped {len(tool_groups)} sets of alternative tools")

        # PHASE 2: Conversion Strategy
        print("\n" + "=" * 80)
        print("PHASE 2: Conversion Strategy")
        print("=" * 80)

        conversion_plan = self._build_conversion_plan(
            galaxy_wf, tool_groups, type_map
        )
        print(f"✓ Created conversion plan for {len(conversion_plan)} processes")

        # PHASE 3: Dual-LLM Conversion
        print("\n" + "=" * 80)
        print("PHASE 3: Dual-LLM Conversion")
        print("=" * 80)

        results = self._convert_with_dual_llm(conversion_plan, type_map)

        # PHASE 4: Assembly & Audit
        print("\n" + "=" * 80)
        print("PHASE 4: Assembly & Audit")
        print("=" * 80)

        merged = self.auditor.audit_and_merge(results)

        # PHASE 5: Testing & Refinement
        print("\n" + "=" * 80)
        print("PHASE 5: Testing & Refinement")
        print("=" * 80)

        final = self.refiner.refine_until_working(merged, galaxy_wf)

        return final
```

---

## Implementation Priority

### Week 1: Core Improvements (High Impact)

1. **Day 1-2**: ConditionalPatternDetector
   - Implement annotation parsing
   - Test on 45 workflows with conditionals
   - Validate pattern detection

2. **Day 3-4**: ToolGrouper + EnhancedPromptBuilder
   - Group alternative tools
   - Build conditional process prompts
   - Test on `fastq_align_dna.ga` (5 aligners)

3. **Day 5**: GalaxyTypeInferencer
   - Implement type inference
   - Test on workflows with collections
   - Validate tuple generation

4. **Day 6-7**: Integration + Testing
   - Integrate all components
   - Test on 10 diverse workflows
   - Compare before/after quality

### Week 2: Testing & Refinement

1. **Day 1-3**: Test on all 94 workflows
   - Measure improvement in conditional handling
   - Track success rate
   - Identify remaining issues

2. **Day 4-5**: Documentation
   - Write user guide
   - Document limitations
   - Create example gallery

3. **Day 6-7**: Nextflow → Galaxy (Reverse)
   - Design reverse converter
   - Implement basic version
   - Test on simple workflows

---

## Expected Improvements

### Before (Current System)

```json
// Galaxy: "selectable aligner (bowtie2, bwamem, dragmap)"
{
  "steps": {
    "5": {"tool_id": "bowtie2"},
    "6": {"tool_id": "bwamem"},
    "7": {"tool_id": "dragmap"}
  }
}
```

**Current Output**: 3 separate processes
```groovy
process BOWTIE2 { ... }
process BWAMEM { ... }
process DRAGMAP { ... }
```

---

### After (Improved System)

**New Output**: 1 conditional process
```groovy
process ALIGN {
    tag "$meta.id"
    label 'process_high'

    conda "bioconda::bowtie2=2.4.5 bioconda::bwa=0.7.17 bioconda::dragmap=1.3.0"

    input:
    tuple val(meta), path(reads)
    path index

    output:
    tuple val(meta), path("*.bam"), emit: bam
    path "versions.yml", emit: versions

    script:
    def prefix = meta.id
    if (params.aligner == 'bowtie2') {
        """
        bowtie2 -x $index -U $reads -S ${prefix}.sam
        samtools view -bS ${prefix}.sam > ${prefix}.bam
        """
    } else if (params.aligner == 'bwa') {
        """
        bwa mem -t ${task.cpus} $index $reads | samtools view -bS - > ${prefix}.bam
        """
    } else if (params.aligner == 'dragmap') {
        """
        dragen-os -r $index -1 $reads | samtools view -bS - > ${prefix}.bam
        """
    }
}
```

**Improvement**: Semantic preservation, follows nf-core patterns, actually executable

---

## Success Metrics

### Quantitative

| Metric | Before | Target |
|--------|--------|--------|
| Conditional detection | 0% | 90%+ |
| Workflows with proper types (tuples) | ~10% | 80%+ |
| nf-core pattern compliance | ~30% | 85%+ |
| Nextflow execution success | ~60% | 90%+ |
| Process count reduction (for conditional workflows) | 0% | 50%+ |

### Qualitative

- Converted workflows follow nf-core best practices
- Semantic meaning preserved (conditionals, alternatives)
- Code is readable and maintainable
- Follows Nextflow community standards

---

## Next Steps

1. ✅ Complete this design document
2. ⏭ Implement ConditionalPatternDetector (test on 45 workflows)
3. ⏭ Implement ToolGrouper
4. ⏭ Enhance ProcessConverter with new prompts
5. ⏭ Test on sample workflows
6. ⏭ Full evaluation on 94 workflows
7. ⏭ Design reverse converter (Nextflow → Galaxy)

---

**Status**: Design complete, ready for implementation ✅
