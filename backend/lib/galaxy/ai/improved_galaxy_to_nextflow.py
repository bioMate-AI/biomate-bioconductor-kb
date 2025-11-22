#!/usr/bin/env python3
"""
Improved Galaxy to Nextflow Converter

Based on comprehensive comparison analysis, this converter addresses:
1. Conditional pattern detection (47.9% of workflows)
2. Type inference (path vs val vs tuple)
3. Tool grouping (merge alternatives into if/else)
4. Nextflow best practices (nf-core patterns)

Author: BioMate Team
Date: 2025-11-22
"""

import json
import re
from pathlib import Path
from typing import Dict, List, Any, Optional, Set
from dataclasses import dataclass
from collections import defaultdict


# ==============================================================================
# Data Structures
# ==============================================================================

@dataclass
class ConditionalGroup:
    """Represents a group of steps that should be merged into conditional."""
    type: str  # 'tool_alternatives', 'workflow_branch', etc.
    steps: List[str]  # Step IDs
    tools: List[str]  # Tool IDs
    parameter: str  # Parameter name for conditional (e.g., 'aligner')
    pattern: str  # 'if_else', 'when_directive', 'branch'
    annotation: str  # Original annotation text
    common_inputs: Dict[str, Any]  # Inputs shared by all tools


@dataclass
class ToolGroup:
    """Group of alternative tools that should be merged."""
    group_id: str
    steps: List[str]
    tools: List[str]
    parameter: str
    merge_strategy: str  # 'if_else' or 'when_directive'
    inputs: Dict  # Shared inputs
    outputs: Dict  # Expected outputs


@dataclass
class TypeInference:
    """Inferred Nextflow type for a Galaxy input."""
    nextflow_type: str  # e.g., "path(reads)", "tuple val(meta), path(reads)"
    galaxy_type: str  # e.g., "fastq", "bam"
    is_collection: bool
    collection_type: Optional[str]  # 'list', 'paired', etc.


# ==============================================================================
# Component 1: Conditional Pattern Detector
# ==============================================================================

class ConditionalPatternDetector:
    """
    Detect implicit conditional logic in Galaxy workflows.

    Patterns detected:
    1. Annotation mentions "tool1 or tool2"
    2. Multiple tools with identical inputs
    3. Alternative steps with similar purpose
    """

    # Keywords that indicate branching/conditionals
    BRANCHING_KEYWORDS = [
        ' or ', ' vs ', ' vs. ',
        'choice', 'choose', 'select',
        'alternative', 'alternatively',
        'either', 'option',
        'branch', 'selectable'
    ]

    def detect_patterns(self, galaxy_workflow: Dict) -> List[ConditionalGroup]:
        """
        Detect all conditional patterns in workflow.

        Returns:
            List of ConditionalGroup objects representing detected patterns
        """

        patterns = []

        # Pattern 1: Annotation-based detection
        annotation = galaxy_workflow.get('annotation', '')
        if self._has_branching_keywords(annotation):
            pattern = self._extract_annotation_pattern(galaxy_workflow, annotation)
            if pattern:
                patterns.append(pattern)

        # Pattern 2: Multiple tools with same inputs
        similar_tool_groups = self._find_tools_with_same_inputs(galaxy_workflow)
        patterns.extend(similar_tool_groups)

        return patterns

    def _has_branching_keywords(self, text: str) -> bool:
        """Check if text contains branching keywords."""
        text_lower = text.lower()
        return any(kw in text_lower for kw in self.BRANCHING_KEYWORDS)

    def _extract_annotation_pattern(self, workflow: Dict, annotation: str) -> Optional[ConditionalGroup]:
        """
        Extract conditional pattern from annotation text.

        Example annotations:
        - "Align with bowtie2, bwamem, or dragmap"
        - "Pseudoalignment with Salmon or Kallisto"
        - "selectable aligner (bowtie2, bwamem2, dragmap, snap, or strobealign)"
        """

        steps = workflow.get('steps', {})

        # Extract tool names from annotation
        # Pattern: "tool1, tool2, or tool3" or "tool1/tool2"
        tool_mentions = self._extract_tool_names_from_text(annotation)

        if len(tool_mentions) < 2:
            return None

        # Find steps that match these tools
        matching_steps = []
        matching_tools = []

        for step_id, step in steps.items():
            if step.get('type') != 'tool':
                continue

            tool_id = step.get('tool_id', '').lower()
            tool_label = step.get('label', '').lower()

            # Check if any mentioned tool name appears in tool_id or label
            for mentioned_tool in tool_mentions:
                if mentioned_tool in tool_id or mentioned_tool in tool_label:
                    matching_steps.append(step_id)
                    matching_tools.append(step.get('tool_id', ''))
                    break

        if len(matching_steps) < 2:
            return None

        # Check if these steps have similar inputs (they should for alternatives)
        if not self._have_similar_inputs(steps, matching_steps):
            return None

        # Infer parameter name from annotation or tools
        parameter = self._infer_parameter_name(annotation, matching_tools)

        # Determine pattern type
        pattern_type = 'if_else' if len(matching_steps) <= 4 else 'when_directive'

        # Get common inputs
        common_inputs = self._extract_common_inputs(steps, matching_steps)

        return ConditionalGroup(
            type='tool_alternatives',
            steps=matching_steps,
            tools=matching_tools,
            parameter=parameter,
            pattern=pattern_type,
            annotation=annotation,
            common_inputs=common_inputs
        )

    def _extract_tool_names_from_text(self, text: str) -> List[str]:
        """
        Extract tool names from annotation text.

        Example:
        "Align with bowtie2, bwamem, or dragmap" → ['bowtie2', 'bwamem', 'dragmap']
        """

        text_lower = text.lower()

        # Common bioinformatics tool names
        known_tools = [
            'bowtie2', 'bowtie', 'bwa', 'bwamem', 'bwamem2', 'bwa-mem', 'bwa-mem2',
            'dragmap', 'snap', 'strobealign', 'minimap2',
            'salmon', 'kallisto', 'rsem',
            'star', 'hisat2', 'tophat',
            'samtools', 'bcftools', 'picard',
            'fastqc', 'multiqc', 'trimmomatic', 'cutadapt',
            'gatk', 'freebayes', 'varscan',
            'featurecounts', 'htseq', 'stringtie'
        ]

        found_tools = []
        for tool in known_tools:
            if tool in text_lower:
                found_tools.append(tool)

        return found_tools

    def _have_similar_inputs(self, steps: Dict, step_ids: List[str]) -> bool:
        """Check if steps have similar input connections."""

        if len(step_ids) < 2:
            return False

        # Get input connection keys for first step
        first_step_id = step_ids[0]
        first_inputs = set(steps[first_step_id].get('input_connections', {}).keys())

        # Check if other steps have similar inputs (allow some variation)
        for step_id in step_ids[1:]:
            step_inputs = set(steps[step_id].get('input_connections', {}).keys())

            # Calculate overlap
            overlap = len(first_inputs & step_inputs)
            total = len(first_inputs | step_inputs)

            if total == 0 or overlap / total < 0.5:  # Less than 50% overlap
                return False

        return True

    def _infer_parameter_name(self, annotation: str, tools: List[str]) -> str:
        """Infer parameter name from annotation or tools."""

        annotation_lower = annotation.lower()

        # Common parameter patterns
        if 'align' in annotation_lower:
            return 'aligner'
        elif 'quant' in annotation_lower:
            return 'quantifier'
        elif 'trim' in annotation_lower:
            return 'trimmer'
        elif 'variant' in annotation_lower or 'call' in annotation_lower:
            return 'variant_caller'

        # Default: use first tool category
        if tools:
            first_tool = Path(tools[0]).stem.lower()
            return f"{first_tool}_choice"

        return 'tool_choice'

    def _extract_common_inputs(self, steps: Dict, step_ids: List[str]) -> Dict:
        """Extract inputs that are common to all steps."""

        if not step_ids:
            return {}

        # Get inputs from first step
        common_inputs = dict(steps[step_ids[0]].get('input_connections', {}))

        # Keep only inputs that appear in ALL steps
        for step_id in step_ids[1:]:
            step_inputs = steps[step_id].get('input_connections', {})

            # Keep only keys that exist in both
            common_inputs = {
                k: v for k, v in common_inputs.items()
                if k in step_inputs
            }

        return common_inputs

    def _find_tools_with_same_inputs(self, workflow: Dict) -> List[ConditionalGroup]:
        """
        Find groups of tools with identical inputs (likely alternatives).
        """

        steps = workflow.get('steps', {})
        groups = []

        # Group steps by their input signature
        input_signatures: Dict[str, List[str]] = defaultdict(list)

        for step_id, step in steps.items():
            if step.get('type') != 'tool':
                continue

            # Create signature from input connections
            inputs = step.get('input_connections', {})
            signature = self._create_input_signature(inputs)

            if signature:  # Only consider steps with inputs
                input_signatures[signature].append(step_id)

        # Find groups with multiple tools (potential alternatives)
        for signature, step_ids in input_signatures.items():
            if len(step_ids) >= 2:  # At least 2 tools with same inputs
                tools = [steps[sid].get('tool_id', '') for sid in step_ids]

                # Check if tools are actually different (not duplicates)
                unique_tools = set(tools)
                if len(unique_tools) >= 2:
                    parameter = self._infer_parameter_from_tools(tools)

                    groups.append(ConditionalGroup(
                        type='same_inputs',
                        steps=step_ids,
                        tools=tools,
                        parameter=parameter,
                        pattern='if_else' if len(step_ids) <= 4 else 'when_directive',
                        annotation=f"Alternative tools: {', '.join(unique_tools)}",
                        common_inputs=steps[step_ids[0]].get('input_connections', {})
                    ))

        return groups

    def _create_input_signature(self, inputs: Dict) -> str:
        """Create a signature string from input connections."""

        # Sort by input name for consistency
        sorted_inputs = sorted(inputs.items())

        # Create signature: "input1:step0,input2:step1"
        signature_parts = []
        for input_name, connection in sorted_inputs:
            if isinstance(connection, dict):
                source_id = connection.get('id', '')
                signature_parts.append(f"{input_name}:step{source_id}")
            elif isinstance(connection, list):
                source_ids = ','.join(str(c.get('id', '')) for c in connection)
                signature_parts.append(f"{input_name}:steps{source_ids}")

        return '|'.join(signature_parts)

    def _infer_parameter_from_tools(self, tools: List[str]) -> str:
        """Infer parameter name from tool IDs."""

        # Extract common categories from tool names
        tool_names_lower = [Path(t).stem.lower() for t in tools]

        # Check for common patterns
        if any('align' in name for name in tool_names_lower):
            return 'aligner'
        elif any('quant' in name for name in tool_names_lower):
            return 'quantifier'
        elif any('trim' in name or 'cut' in name for name in tool_names_lower):
            return 'trimmer'

        return 'tool_choice'


# ==============================================================================
# Component 2: Galaxy Type Inferencer
# ==============================================================================

class GalaxyTypeInferencer:
    """
    Infer Nextflow channel types from Galaxy implicit types.

    Galaxy → Nextflow mappings:
    - data_input (fastq) → path(reads)
    - data_input (bam) → path(bam)
    - data_collection_input (paired) → tuple val(meta), path(reads)
    - parameter_input (text) → val(param)
    """

    # Known Galaxy datatypes and their Nextflow equivalents
    DATATYPE_MAP = {
        'fastq': 'fastq',
        'fastqsanger': 'fastq',
        'fastqillumina': 'fastq',
        'bam': 'bam',
        'sam': 'sam',
        'cram': 'cram',
        'vcf': 'vcf',
        'vcf_bgzip': 'vcf',
        'bcf': 'bcf',
        'fasta': 'fasta',
        'fa': 'fasta',
        'bed': 'bed',
        'gtf': 'gtf',
        'gff': 'gff',
        'gff3': 'gff3',
        'tabular': 'tsv',
        'txt': 'txt',
        'csv': 'csv',
        'json': 'json',
        'yaml': 'yaml',
        'html': 'html',
        'pdf': 'pdf',
        'png': 'png',
        'svg': 'svg'
    }

    def infer_type(self, galaxy_step: Dict, label: Optional[str] = None) -> TypeInference:
        """
        Infer Nextflow type from Galaxy step.

        Returns:
            TypeInference object with Nextflow type specification
        """

        step_type = galaxy_step.get('type')

        if step_type == 'data_input':
            return self._infer_data_input_type(galaxy_step, label)

        elif step_type == 'data_collection_input':
            return self._infer_collection_type(galaxy_step, label)

        elif step_type == 'parameter_input':
            return self._infer_parameter_type(galaxy_step, label)

        # Default fallback
        return TypeInference(
            nextflow_type="path(input)",
            galaxy_type="unknown",
            is_collection=False,
            collection_type=None
        )

    def _infer_data_input_type(self, step: Dict, label: Optional[str]) -> TypeInference:
        """Infer type for data_input step."""

        # Try to infer from label
        if label:
            label_lower = label.lower()

            # Check for known patterns in label
            for galaxy_type, nf_type in self.DATATYPE_MAP.items():
                if galaxy_type in label_lower:
                    var_name = self._sanitize_var_name(label)
                    return TypeInference(
                        nextflow_type=f"path({var_name})",
                        galaxy_type=nf_type,
                        is_collection=False,
                        collection_type=None
                    )

        # Default: generic path
        var_name = self._sanitize_var_name(label or "input")
        return TypeInference(
            nextflow_type=f"path({var_name})",
            galaxy_type="generic",
            is_collection=False,
            collection_type=None
        )

    def _infer_collection_type(self, step: Dict, label: Optional[str]) -> TypeInference:
        """Infer type for data_collection_input step."""

        collection_type = step.get('collection_type', 'list')

        # Paired collections → tuple val(meta), path(reads)
        if collection_type == 'paired':
            var_name = self._sanitize_var_name(label or "reads")
            return TypeInference(
                nextflow_type=f"tuple val(meta), path({var_name})",
                galaxy_type="paired_fastq",
                is_collection=True,
                collection_type='paired'
            )

        # List collections → path(files)
        elif collection_type == 'list' or collection_type.startswith('list:'):
            var_name = self._sanitize_var_name(label or "files")
            return TypeInference(
                nextflow_type=f"path({var_name})",
                galaxy_type="list",
                is_collection=True,
                collection_type=collection_type
            )

        # Default: generic collection
        var_name = self._sanitize_var_name(label or "collection")
        return TypeInference(
            nextflow_type=f"path({var_name})",
            galaxy_type="collection",
            is_collection=True,
            collection_type=collection_type
        )

    def _infer_parameter_type(self, step: Dict, label: Optional[str]) -> TypeInference:
        """Infer type for parameter_input step."""

        tool_state = step.get('tool_state', '{}')

        try:
            state = json.loads(tool_state)
            param_type = state.get('parameter_type', 'text')
        except:
            param_type = 'text'

        var_name = self._sanitize_var_name(label or "param")

        return TypeInference(
            nextflow_type=f"val({var_name})",
            galaxy_type=param_type,
            is_collection=False,
            collection_type=None
        )

    def _sanitize_var_name(self, name: str) -> str:
        """Sanitize variable name for Nextflow."""

        # Remove special characters, replace spaces with underscores
        sanitized = re.sub(r'[^a-zA-Z0-9_]', '_', name)

        # Remove leading/trailing underscores
        sanitized = sanitized.strip('_')

        # Ensure it doesn't start with a number
        if sanitized and sanitized[0].isdigit():
            sanitized = 'ch_' + sanitized

        # Default if empty
        if not sanitized:
            sanitized = 'input'

        return sanitized.lower()

    def infer_from_tool_id(self, tool_id: str) -> str:
        """Infer datatype from tool ID."""

        tool_id_lower = tool_id.lower()

        for galaxy_type, nf_type in self.DATATYPE_MAP.items():
            if galaxy_type in tool_id_lower:
                return nf_type

        return 'generic'


# ==============================================================================
# Component 3: Tool Grouper
# ==============================================================================

class ToolGrouper:
    """
    Group alternative tools that should be merged into conditional processes.
    """

    def group_alternative_tools(self,
                               steps: Dict,
                               conditional_patterns: List[ConditionalGroup]) -> List[ToolGroup]:
        """
        Create ToolGroup objects from detected conditional patterns.

        Returns:
            List of ToolGroup objects ready for conversion
        """

        groups = []

        for pattern in conditional_patterns:
            if pattern.type in ['tool_alternatives', 'same_inputs']:

                # Extract tool information
                tool_steps = [steps[sid] for sid in pattern.steps if sid in steps]

                if len(tool_steps) < 2:
                    continue

                # Determine merge strategy
                if len(tool_steps) <= 4:
                    strategy = 'if_else'
                else:
                    strategy = 'when_directive'

                # Create ToolGroup
                group = ToolGroup(
                    group_id=pattern.parameter,
                    steps=pattern.steps,
                    tools=pattern.tools,
                    parameter=pattern.parameter,
                    merge_strategy=strategy,
                    inputs=pattern.common_inputs,
                    outputs=self._extract_common_outputs(tool_steps)
                )

                groups.append(group)

        return groups

    def _extract_common_outputs(self, steps: List[Dict]) -> Dict:
        """Extract outputs that should be common across all alternatives."""

        if not steps:
            return {}

        # For now, assume all alternatives should have same output structure
        # In practice, we'd need to analyze and harmonize outputs
        first_outputs = steps[0].get('outputs', [])

        return {
            'outputs': first_outputs,
            'count': len(first_outputs)
        }


# ==============================================================================
# Component 4: Enhanced Prompt Builder
# ==============================================================================

class EnhancedPromptBuilder:
    """
    Build context-rich prompts for LLMs with:
    - Inferred types
    - Nextflow best practices
    - Conditional patterns
    - nf-core examples
    """

    def build_process_prompt(self,
                            galaxy_step: Dict,
                            inferred_types: Dict[str, TypeInference],
                            is_conditional_group: bool = False,
                            group_info: Optional[ToolGroup] = None,
                            doc_context: str = "") -> str:
        """
        Build enhanced prompt for converting Galaxy step to Nextflow process.

        Args:
            galaxy_step: Galaxy step definition
            inferred_types: Map of input_name → TypeInference
            is_conditional_group: Whether this is a group of alternative tools
            group_info: ToolGroup information if conditional
            doc_context: nf-core documentation context

        Returns:
            Formatted prompt string
        """

        if is_conditional_group and group_info:
            return self._build_conditional_process_prompt(galaxy_step, group_info, inferred_types, doc_context)
        else:
            return self._build_simple_process_prompt(galaxy_step, inferred_types, doc_context)

    def _build_simple_process_prompt(self,
                                     step: Dict,
                                     types: Dict[str, TypeInference],
                                     doc_context: str) -> str:
        """Build prompt for simple 1:1 conversion."""

        tool_id = step.get('tool_id', 'unknown')
        label = step.get('label', tool_id)
        step_type = step.get('type', 'tool')

        # Build input type specifications
        input_specs = []
        for input_name, type_info in types.items():
            input_specs.append(f"  {input_name}: {type_info.nextflow_type}  // {type_info.galaxy_type}")

        input_specs_str = '\n'.join(input_specs) if input_specs else "  // No inputs specified"

        prompt = f"""# Task: Convert Galaxy tool to Nextflow process following nf-core best practices

## Galaxy Tool Information
- Tool ID: {tool_id}
- Label: {label}
- Type: {step_type}

## Inferred Input Types
{input_specs_str}

## Required Nextflow Structure

You MUST follow this nf-core template exactly:

```groovy
process TOOL_NAME {{
    tag "$meta.id"                    // REQUIRED: Logging tag
    label 'process_medium'            // REQUIRED: Resource label (low/medium/high)

    conda "bioconda::tool=version"    // REQUIRED: Conda environment
    container "${{workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/tool:version' :
        'biocontainers/tool:version'}}"  // REQUIRED: Container

    input:
    tuple val(meta), path(reads)      // Use inferred types above
    path index                        // Additional inputs as needed

    output:
    tuple val(meta), path("*.bam"), emit: bam       // REQUIRED: Named emit
    path "versions.yml",           emit: versions   // REQUIRED: Version tracking

    script:
    def prefix = meta.id              // REQUIRED: Use meta.id for output names
    def args = task.ext.args ?: ''    // REQUIRED: Allow external args
    \"\"\"
    tool \\
        -t ${{task.cpus}} \\          // Use task.cpus for parallelism
        $args \\                      // Insert external args
        -i $reads \\
        -o ${{prefix}}.bam

    cat <<-END_VERSIONS > versions.yml
    "${{task.process}}":
        tool: \$(tool --version 2>&1 | sed 's/^.*tool //; s/ .*\$//')
    END_VERSIONS
    \"\"\"
}}
```

## Key Requirements
1. ✅ Use tuple val(meta), path(...) for file inputs
2. ✅ Include tag, label, conda, container directives
3. ✅ Use named emit for all outputs
4. ✅ Capture software versions in versions.yml
5. ✅ Use task.cpus, task.memory for resources
6. ✅ Define prefix = meta.id for output naming
7. ✅ Include task.ext.args for flexibility

## nf-core Documentation Context
{doc_context if doc_context else "// No specific documentation available"}

Now generate the Nextflow process for this Galaxy tool following the template above.
Return ONLY the process definition, no explanations.
"""
        return prompt

    def _build_conditional_process_prompt(self,
                                         step: Dict,
                                         group_info: ToolGroup,
                                         types: Dict[str, TypeInference],
                                         doc_context: str) -> str:
        """Build prompt for conditional process (multiple tools merged)."""

        # Extract tool names for clarity
        tool_names = []
        for tool_id in group_info.tools:
            # Extract readable name from tool ID
            name = Path(tool_id).stem.upper()
            if '/' in name:
                name = name.split('/')[-1]
            tool_names.append(name)

        # Build input type specifications
        input_specs = []
        for input_name, type_info in types.items():
            input_specs.append(f"  {input_name}: {type_info.nextflow_type}  // {type_info.galaxy_type}")

        input_specs_str = '\n'.join(input_specs) if input_specs else "  // No inputs specified"

        prompt = f"""# Task: Convert Galaxy tool alternatives to SINGLE conditional Nextflow process

## Situation
The Galaxy workflow has {len(group_info.tools)} alternative tools that do the same job:
{chr(10).join(f'  - {name}' for name in tool_names)}

These MUST be merged into ONE process with if/else conditional logic.

## Tools to Merge
{json.dumps(group_info.tools, indent=2)}

## Inferred Input Types (shared by all alternatives)
{input_specs_str}

## Parameter for Conditional
params.{group_info.parameter}  // User selects which tool to use

## Required Nextflow Structure

You MUST create ONE process with if/else blocks:

```groovy
process {group_info.group_id.upper()} {{
    tag "$meta.id"
    label 'process_high'

    conda "bioconda::tool1=version bioconda::tool2=version"  // All tools

    input:
    tuple val(meta), path(reads)
    path index

    output:
    tuple val(meta), path("*.bam"), emit: bam      // SAME output for all branches
    path "versions.yml",           emit: versions

    script:
    def prefix = meta.id
    if (params.{group_info.parameter} == 'tool1') {{
        \"\"\"
        tool1 -t ${{task.cpus}} $index $reads > ${{prefix}}.bam

        cat <<-END_VERSIONS > versions.yml
        "${{task.process}}":
            tool1: \$(tool1 --version)
        END_VERSIONS
        \"\"\"
    }} else if (params.{group_info.parameter} == 'tool2') {{
        \"\"\"
        tool2 -x $index -U $reads -S ${{prefix}}.sam
        samtools view -bS ${{prefix}}.sam > ${{prefix}}.bam

        cat <<-END_VERSIONS > versions.yml
        "${{task.process}}":
            tool2: \$(tool2 --version)
        END_VERSIONS
        \"\"\"
    }} else {{
        error "Unknown {group_info.parameter}: ${{params.{group_info.parameter}}}"
    }}
}}
```

## Critical Requirements
1. ✅ ONE process only (not {len(group_info.tools)} separate processes)
2. ✅ Use if/else blocks to switch between tools
3. ✅ All branches MUST produce the SAME output structure
4. ✅ Include all tools in conda directive
5. ✅ Use params.{group_info.parameter} for branching
6. ✅ Include error handling for unknown parameter values

## nf-core Documentation Context
{doc_context if doc_context else "// No specific documentation available"}

Now generate the SINGLE conditional process that merges these {len(group_info.tools)} tools.
Return ONLY the process definition, no explanations.
"""
        return prompt


# ==============================================================================
# Component 5: Nextflow Best Practices Scorer
# ==============================================================================

class NextflowBestPracticesScorer:
    """
    Score Nextflow processes based on best practices.

    Scoring criteria (100 points total):
    - Proper input types (tuple val(meta), path) - 20 pts
    - Label directives - 15 pts
    - Container/conda specs - 15 pts
    - Named emit outputs - 10 pts
    - Version tracking - 10 pts
    - Tag directive - 10 pts
    - Proper variable naming - 10 pts
    - Script quality - 10 pts
    """

    def score_process(self, nextflow_code: str, galaxy_source: Dict) -> float:
        """
        Score process code on 100-point scale.

        Args:
            nextflow_code: Nextflow process code
            galaxy_source: Original Galaxy step for context

        Returns:
            Score from 0.0 to 100.0
        """

        score = 0.0

        # 1. Input types (20 points)
        if re.search(r'tuple\s+val\(meta\),\s+path\(', nextflow_code):
            score += 20  # Perfect: uses meta tuple
        elif re.search(r'tuple\s+val\(\w+\),\s+path\(', nextflow_code):
            score += 15  # Good: uses tuple but not meta
        elif re.search(r'path\(', nextflow_code):
            score += 10  # OK: has path but no tuple

        # 2. Label directive (15 points)
        if re.search(r'label\s+[\'"]process_(low|medium|high)[\'"]', nextflow_code):
            score += 15
        elif re.search(r'label\s+', nextflow_code):
            score += 10  # Has label but non-standard

        # 3. Container/conda (15 points)
        has_conda = 'conda' in nextflow_code and 'bioconda::' in nextflow_code
        has_container = 'container' in nextflow_code and ('biocontainers/' in nextflow_code or
                                                          'singularity/' in nextflow_code)

        if has_conda and has_container:
            score += 15  # Perfect: both
        elif has_conda or has_container:
            score += 10  # Good: one of them

        # 4. Named emit (10 points)
        emit_count = len(re.findall(r'emit:\s*\w+', nextflow_code))
        if emit_count >= 2:
            score += 10  # Multiple named outputs
        elif emit_count == 1:
            score += 7   # At least one

        # 5. Version tracking (10 points)
        if 'versions.yml' in nextflow_code or 'END_VERSIONS' in nextflow_code:
            score += 10

        # 6. Tag directive (10 points)
        if re.search(r'tag\s+["\']?\$', nextflow_code):  # Dynamic tag
            score += 10
        elif 'tag ' in nextflow_code:
            score += 5   # Static tag

        # 7. Variable naming (10 points)
        if 'prefix = meta.id' in nextflow_code or 'def prefix = meta' in nextflow_code:
            score += 10
        elif 'def prefix' in nextflow_code:
            score += 5  # Has prefix but not from meta

        # 8. Script quality (10 points)
        script_indicators = [
            '"""' in nextflow_code,  # Uses triple-quoted string
            len(nextflow_code) > 200,  # Substantial code
            r'\$\{task\.cpus\}' in nextflow_code or '${task.cpus}' in nextflow_code,  # Uses task vars
            '\\' in nextflow_code  # Has line continuations
        ]

        script_score = sum(2.5 for indicator in script_indicators if indicator)
        score += script_score

        return min(score, 100.0)  # Cap at 100

    def provide_feedback(self, nextflow_code: str, score: float) -> List[str]:
        """Provide improvement suggestions based on score."""

        suggestions = []

        if score < 20:
            if not re.search(r'tuple\s+val\(meta\),\s+path\(', nextflow_code):
                suggestions.append("❌ Use 'tuple val(meta), path(...)' for file inputs")

        if score < 35:
            if not re.search(r'label\s+[\'"]process_', nextflow_code):
                suggestions.append("❌ Add 'label' directive for resource management")

        if score < 50:
            if 'conda' not in nextflow_code:
                suggestions.append("❌ Add 'conda' directive for software environment")

        if score < 60:
            if 'emit:' not in nextflow_code:
                suggestions.append("❌ Use named 'emit' for outputs")

        if score < 70:
            if 'versions.yml' not in nextflow_code:
                suggestions.append("❌ Add version tracking in script")

        if score < 80:
            if not re.search(r'tag\s+["\']?\$', nextflow_code):
                suggestions.append("❌ Add dynamic 'tag' directive for logging")

        if score < 90:
            if 'prefix = meta.id' not in nextflow_code:
                suggestions.append("❌ Use 'prefix = meta.id' for output naming")

        if not suggestions:
            suggestions.append("✅ Code follows nf-core best practices!")

        return suggestions


# ==============================================================================
# Testing
# ==============================================================================

if __name__ == '__main__':
    print("Improved Galaxy to Nextflow Converter - Component Tests")
    print("=" * 80)

    # Test ConditionalPatternDetector
    print("\n1. Testing ConditionalPatternDetector")
    print("-" * 80)

    detector = ConditionalPatternDetector()

    # Load a sample workflow with conditionals
    sample_wf_path = Path('/home/yzhang/biomate/backend/galaxy_workflows_reformatted/fastq_align_dna.ga')

    if sample_wf_path.exists():
        with open(sample_wf_path) as f:
            wf = json.load(f)

        patterns = detector.detect_patterns(wf)

        print(f"Workflow: {wf.get('name')}")
        print(f"Annotation: {wf.get('annotation', '')[:100]}...")
        print(f"\nDetected patterns: {len(patterns)}")

        for i, pattern in enumerate(patterns, 1):
            print(f"\nPattern {i}:")
            print(f"  Type: {pattern.type}")
            print(f"  Steps: {pattern.steps}")
            print(f"  Tools: {len(pattern.tools)} tools")
            print(f"  Parameter: {pattern.parameter}")
            print(f"  Strategy: {pattern.pattern}")
            print(f"  Annotation: {pattern.annotation[:80]}...")

    # Test GalaxyTypeInferencer
    print("\n\n2. Testing GalaxyTypeInferencer")
    print("-" * 80)

    inferencer = GalaxyTypeInferencer()

    test_steps = [
        ({'type': 'data_input'}, 'ch_reads'),
        ({'type': 'data_collection_input', 'collection_type': 'paired'}, 'paired_reads'),
        ({'type': 'data_collection_input', 'collection_type': 'list'}, 'bam_files'),
        ({'type': 'parameter_input', 'tool_state': '{"parameter_type": "text"}'}, 'sample_name'),
    ]

    for step, label in test_steps:
        inference = inferencer.infer_type(step, label)
        print(f"\nGalaxy: {step['type']}")
        if 'collection_type' in step:
            print(f"  Collection: {step['collection_type']}")
        print(f"Nextflow: {inference.nextflow_type}")
        print(f"Inferred type: {inference.galaxy_type}")

    # Test ToolGrouper
    print("\n\n3. Testing ToolGrouper")
    print("-" * 80)

    if sample_wf_path.exists():
        grouper = ToolGrouper()

        # Use patterns from earlier
        tool_groups = grouper.group_alternative_tools(wf['steps'], patterns)

        print(f"Created {len(tool_groups)} tool groups")

        for i, group in enumerate(tool_groups, 1):
            print(f"\nGroup {i}:")
            print(f"  ID: {group.group_id}")
            print(f"  Steps: {group.steps}")
            print(f"  Tools: {len(group.tools)}")
            print(f"  Parameter: {group.parameter}")
            print(f"  Strategy: {group.merge_strategy}")

    print("\n" + "=" * 80)
    print("✅ Component tests complete!")
