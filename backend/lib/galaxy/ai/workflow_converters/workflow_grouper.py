"""
Intelligent Workflow Step Grouping

This module groups fine-grained tool steps into meaningful high-level biological workflow steps.
Uses pattern-based grouping informed by IWC workflow analysis showing common tool sequences.

Key Grouping Strategies:
1. Pattern-based: Group tools that commonly appear together (e.g., FastQC + MultiQC)
2. Category-based: Group tools in the same biological category (e.g., QC tools)
3. Annotation-based: Use workflow annotations and tool names to infer relationships
4. Dependency-based: Group tools with direct data dependencies

Based on analysis of 105 IWC workflows showing common patterns:
- QC workflows: FastQC → MultiQC (29 workflows)
- Mapping: BWA → SAMtools sort → SAMtools index (26 workflows)
- Trimming: Cutadapt/fastp → FastQC (12 workflows)
- Peak calling: MACS2 → BEDtools (8 workflows)
"""

from typing import List, Dict, Set, Optional, Tuple
from dataclasses import dataclass, field
from enum import Enum
import re
from ..workflow_abstraction import (
    UnifiedWorkflow,
    HighLevelStep,
    DetailedStep,
    StepCategory
)


class GroupingStrategy(Enum):
    """Strategy for grouping detailed steps"""
    PATTERN_BASED = "pattern"  # Use known tool patterns from IWC analysis
    CATEGORY_BASED = "category"  # Group by biological category
    ANNOTATION_BASED = "annotation"  # Use workflow annotations
    DEPENDENCY_BASED = "dependency"  # Group by data dependencies
    HYBRID = "hybrid"  # Combine multiple strategies


@dataclass
class ToolPattern:
    """A common tool sequence pattern found in workflows"""
    name: str
    tools: List[str]  # Tool name patterns (regex supported)
    category: StepCategory
    icon: str
    color: str
    description: str
    frequency: int = 0  # How often this pattern appears in IWC


@dataclass
class GroupingRule:
    """Rule for grouping detailed steps"""
    pattern: ToolPattern
    priority: int = 0  # Higher priority rules are applied first
    exact_match: bool = False  # Must match all tools exactly


class WorkflowGrouper:
    """
    Groups detailed workflow steps into meaningful high-level steps

    Uses pattern-based grouping informed by IWC workflow analysis.
    Reduces workflow complexity from 60+ steps to 10-15 high-level steps.
    """

    def __init__(self, strategy: GroupingStrategy = GroupingStrategy.HYBRID):
        self.strategy = strategy
        self.patterns = self._initialize_patterns()
        self.rules = self._initialize_rules()

    def _initialize_patterns(self) -> List[ToolPattern]:
        """
        Initialize tool patterns from IWC analysis

        Based on:
        - Tool Pairs (appearing 5+ times)
        - Tool Triples (appearing 3+ times)
        - Logical Subworkflow Groupings
        - Recommended Subworkflow Candidates
        """
        return [
            # ===== QUALITY CONTROL PATTERNS =====

            ToolPattern(
                name="Quality Control",
                tools=[r"fastqc", r"multiqc"],
                category=StepCategory.QC,
                icon="🔍",
                color="#3498db",
                description="Quality assessment of sequencing data",
                frequency=29
            ),

            ToolPattern(
                name="Adapter Trimming and QC",
                tools=[r"(cutadapt|fastp|trimmomatic)", r"fastqc", r"multiqc"],
                category=StepCategory.QC,
                icon="✂️",
                color="#3498db",
                description="Adapter/quality trimming with quality assessment",
                frequency=18
            ),

            ToolPattern(
                name="Read Filtering",
                tools=[r"filter.*fastq", r"fastqc"],
                category=StepCategory.QC,
                icon="🔍",
                color="#3498db",
                description="Read filtering and quality control",
                frequency=12
            ),

            # ===== ALIGNMENT PATTERNS =====

            ToolPattern(
                name="Read Alignment",
                tools=[r"(bwa|bowtie2|star|minimap2).*", r"samtools.*sort", r"samtools.*index"],
                category=StepCategory.ALIGNMENT,
                icon="🧬",
                color="#2ecc71",
                description="Read mapping, sorting, and indexing",
                frequency=26
            ),

            ToolPattern(
                name="RNA-Seq Alignment",
                tools=[r"rna.*star", r"featurecounts"],
                category=StepCategory.ALIGNMENT,
                icon="🧬",
                color="#2ecc71",
                description="RNA-seq alignment and quantification",
                frequency=10
            ),

            # ===== BAM PROCESSING PATTERNS =====

            ToolPattern(
                name="BAM Statistics",
                tools=[r"samtools.*stats", r"samtools.*flagstat", r"samtools.*idxstats"],
                category=StepCategory.ALIGNMENT,
                icon="📊",
                color="#2ecc71",
                description="Comprehensive BAM file statistics",
                frequency=17
            ),

            ToolPattern(
                name="BAM Processing",
                tools=[r"samtools.*view", r"samtools.*sort", r"samtools.*index"],
                category=StepCategory.ALIGNMENT,
                icon="🧬",
                color="#2ecc71",
                description="BAM file filtering, sorting, and indexing",
                frequency=15
            ),

            ToolPattern(
                name="Duplicate Marking",
                tools=[r"macs2.*filterdup", r"samtools.*markdup"],
                category=StepCategory.ALIGNMENT,
                icon="🗑️",
                color="#2ecc71",
                description="Mark or remove duplicate reads",
                frequency=10
            ),

            # ===== VARIANT CALLING PATTERNS =====

            ToolPattern(
                name="Variant Calling",
                tools=[
                    r"lofreq.*indelqual",
                    r"lofreq.*call",
                    r"lofreq.*filter"
                ],
                category=StepCategory.VARIANT_CALLING,
                icon="🔬",
                color="#f39c12",
                description="Variant calling with lofreq pipeline",
                frequency=9
            ),

            ToolPattern(
                name="Variant Annotation",
                tools=[r"snpeff", r"snpsift"],
                category=StepCategory.VARIANT_CALLING,
                icon="🔬",
                color="#f39c12",
                description="Variant annotation and filtering",
                frequency=11
            ),

            ToolPattern(
                name="Variant Filtering",
                tools=[r"bcftools.*norm", r"bcftools.*filter"],
                category=StepCategory.VARIANT_CALLING,
                icon="🔬",
                color="#f39c12",
                description="Variant normalization and filtering",
                frequency=6
            ),

            # ===== PEAK CALLING PATTERNS (ChIP-seq, ATAC-seq) =====

            ToolPattern(
                name="Peak Calling",
                tools=[r"macs2.*callpeak", r"bedtools"],
                category=StepCategory.PEAK_CALLING,
                icon="⛰️",
                color="#1abc9c",
                description="Peak calling and processing",
                frequency=10
            ),

            ToolPattern(
                name="Coverage Tracks",
                tools=[r"bedtools.*genomecov", r"wigtobigwig"],
                category=StepCategory.PEAK_CALLING,
                icon="📈",
                color="#1abc9c",
                description="Generate genome coverage tracks",
                frequency=7
            ),

            # ===== ASSEMBLY PATTERNS =====

            ToolPattern(
                name="Genome Assembly",
                tools=[r"(flye|megahit|spades|hifiasm)", r"quast", r"busco"],
                category=StepCategory.ASSEMBLY,
                icon="🧩",
                color="#e74c3c",
                description="Genome assembly and quality assessment",
                frequency=6
            ),

            ToolPattern(
                name="Assembly Polishing",
                tools=[r"minimap2", r"racon"],
                category=StepCategory.ASSEMBLY,
                icon="✨",
                color="#e74c3c",
                description="Assembly polishing with long reads",
                frequency=8
            ),

            ToolPattern(
                name="Assembly Quality Control",
                tools=[r"quast", r"busco", r"(gfastats|fasta.*statistics)"],
                category=StepCategory.ASSEMBLY,
                icon="📊",
                color="#e74c3c",
                description="Assembly quality metrics and statistics",
                frequency=11
            ),

            # ===== QUANTIFICATION PATTERNS =====

            ToolPattern(
                name="RNA Quantification",
                tools=[r"(salmon|kallisto|featurecounts|htseq)"],
                category=StepCategory.QUANTIFICATION,
                icon="📊",
                color="#9b59b6",
                description="RNA-seq read quantification",
                frequency=8
            ),

            ToolPattern(
                name="Differential Expression",
                tools=[r"deseq2", r"edger"],
                category=StepCategory.QUANTIFICATION,
                icon="📊",
                color="#9b59b6",
                description="Differential gene expression analysis",
                frequency=5
            ),

            # ===== ANNOTATION PATTERNS =====

            ToolPattern(
                name="Genome Annotation",
                tools=[r"(maker|helixer|augustus)", r"busco", r"gffread"],
                category=StepCategory.ANNOTATION,
                icon="📝",
                color="#34495e",
                description="Genome annotation and validation",
                frequency=4
            ),

            ToolPattern(
                name="Functional Annotation",
                tools=[r"interproscan", r"eggnog"],
                category=StepCategory.ANNOTATION,
                icon="📝",
                color="#34495e",
                description="Functional annotation of proteins",
                frequency=3
            ),

            # ===== VISUALIZATION PATTERNS =====

            ToolPattern(
                name="Assembly Visualization",
                tools=[r"bandage"],
                category=StepCategory.VISUALIZATION,
                icon="🖼️",
                color="#7f8c8d",
                description="Assembly graph visualization",
                frequency=7
            ),

            ToolPattern(
                name="Multi-Sample QC Report",
                tools=[r"multiqc"],
                category=StepCategory.VISUALIZATION,
                icon="📊",
                color="#7f8c8d",
                description="Aggregate quality control reports",
                frequency=31
            ),

            # ===== DATA PROCESSING PATTERNS =====

            ToolPattern(
                name="Text Processing",
                tools=[r"text.*reformatting", r"(cut|grep|paste)"],
                category=StepCategory.OTHER,
                icon="📄",
                color="#95a5a6",
                description="Text reformatting and extraction",
                frequency=170
            ),

            ToolPattern(
                name="Data Merging",
                tools=[r"collapse.*collection", r"merge"],
                category=StepCategory.OTHER,
                icon="🔗",
                color="#95a5a6",
                description="Merge and collapse data collections",
                frequency=30
            ),
        ]

    def _initialize_rules(self) -> List[GroupingRule]:
        """Initialize grouping rules with priorities"""
        rules = []

        # Higher priority for more specific patterns (longer tool sequences)
        for i, pattern in enumerate(self.patterns):
            priority = len(pattern.tools) * 10 + (100 - i)
            rules.append(GroupingRule(
                pattern=pattern,
                priority=priority,
                exact_match=False
            ))

        # Sort by priority (highest first)
        rules.sort(key=lambda r: r.priority, reverse=True)
        return rules

    def group_workflow(self, workflow: UnifiedWorkflow) -> UnifiedWorkflow:
        """
        Group detailed steps into meaningful high-level steps

        Args:
            workflow: UnifiedWorkflow with flat high-level steps (one per tool)

        Returns:
            UnifiedWorkflow with intelligently grouped high-level steps
        """
        if self.strategy == GroupingStrategy.HYBRID:
            return self._hybrid_grouping(workflow)
        elif self.strategy == GroupingStrategy.PATTERN_BASED:
            return self._pattern_based_grouping(workflow)
        elif self.strategy == GroupingStrategy.CATEGORY_BASED:
            return self._category_based_grouping(workflow)
        elif self.strategy == GroupingStrategy.ANNOTATION_BASED:
            return self._annotation_based_grouping(workflow)
        else:
            return self._dependency_based_grouping(workflow)

    def _hybrid_grouping(self, workflow: UnifiedWorkflow) -> UnifiedWorkflow:
        """
        Hybrid grouping strategy combining pattern, category, and annotation

        Steps:
        1. Try pattern-based grouping first (most specific)
        2. Fall back to category-based for ungrouped steps
        3. Use annotations to refine groups
        4. Keep single-tool steps separate if they don't fit patterns
        """
        # Flatten all detailed steps
        all_detailed_steps = []
        for hl_step in workflow.high_level_steps:
            all_detailed_steps.extend(hl_step.detailed_steps)

        # Track which detailed steps have been grouped
        grouped_steps: Set[str] = set()
        new_high_level_steps: List[HighLevelStep] = []

        # Step 1: Pattern-based grouping
        for rule in self.rules:
            matches = self._find_pattern_matches(all_detailed_steps, rule.pattern, grouped_steps)
            for match_steps in matches:
                # Create high-level step for this pattern
                hl_step = self._create_high_level_step_from_pattern(
                    match_steps,
                    rule.pattern,
                    len(new_high_level_steps)
                )
                new_high_level_steps.append(hl_step)

                # Mark steps as grouped
                for step in match_steps:
                    grouped_steps.add(step.step_id)

        # Step 2: Group consecutive steps of same category (max 3 per group)
        ungrouped_steps = [s for s in all_detailed_steps if s.step_id not in grouped_steps]

        # Find consecutive runs of same category
        i = 0
        while i < len(ungrouped_steps):
            current_step = ungrouped_steps[i]
            current_category = self._infer_category_from_tool(current_step.tool_id)

            # Collect consecutive steps of same category (max 3)
            consecutive_steps = [current_step]
            j = i + 1
            while j < len(ungrouped_steps) and len(consecutive_steps) < 3:
                next_step = ungrouped_steps[j]
                next_category = self._infer_category_from_tool(next_step.tool_id)
                if next_category == current_category:
                    consecutive_steps.append(next_step)
                    j += 1
                else:
                    break

            # Create high-level step
            if len(consecutive_steps) >= 2:
                # Group consecutive steps
                hl_step = self._create_high_level_step_from_category(
                    consecutive_steps,
                    current_category,
                    len(new_high_level_steps)
                )
            else:
                # Keep single step as-is
                hl_step = HighLevelStep(
                    step_id=f"hl_step_{len(new_high_level_steps)}",
                    name=current_step.tool_name,
                    description=f"Run {current_step.tool_name}",
                    detailed_steps=[current_step],
                    category=current_category,
                    icon=self._get_icon_for_category(current_category),
                    color=self._get_color_for_category(current_category),
                    inputs=current_step.inputs,
                    outputs=current_step.outputs,
                    parameters={},
                    order=len(new_high_level_steps)
                )

            new_high_level_steps.append(hl_step)
            for step in consecutive_steps:
                grouped_steps.add(step.step_id)

            i += len(consecutive_steps)

        # Create new workflow with grouped steps
        return UnifiedWorkflow(
            workflow_id=workflow.workflow_id,
            name=workflow.name,
            description=workflow.description,
            high_level_steps=new_high_level_steps,
            source_format=workflow.source_format,
            execution_engine=workflow.execution_engine,
            creator=workflow.creator,
            license=workflow.license,
            tags=workflow.tags,
            parameters=workflow.parameters
        )

    def _find_pattern_matches(
        self,
        detailed_steps: List[DetailedStep],
        pattern: ToolPattern,
        grouped_steps: Set[str]
    ) -> List[List[DetailedStep]]:
        """
        Find all matches of a pattern in the detailed steps

        Returns list of matched step sequences
        """
        matches = []
        i = 0

        while i < len(detailed_steps):
            # Skip already grouped steps
            if detailed_steps[i].step_id in grouped_steps:
                i += 1
                continue

            # Try to match pattern starting at position i
            match = self._try_match_pattern(detailed_steps[i:], pattern, grouped_steps)
            if match:
                matches.append(match)
                i += len(match)
            else:
                i += 1

        return matches

    def _try_match_pattern(
        self,
        detailed_steps: List[DetailedStep],
        pattern: ToolPattern,
        grouped_steps: Set[str]
    ) -> Optional[List[DetailedStep]]:
        """Try to match pattern at current position"""
        matched_steps = []
        pattern_idx = 0
        step_idx = 0

        while pattern_idx < len(pattern.tools) and step_idx < len(detailed_steps):
            step = detailed_steps[step_idx]

            # Skip if already grouped
            if step.step_id in grouped_steps:
                step_idx += 1
                continue

            # Check if tool matches pattern
            tool_pattern = pattern.tools[pattern_idx]
            if re.search(tool_pattern, step.tool_id.lower(), re.IGNORECASE) or \
               re.search(tool_pattern, step.tool_name.lower(), re.IGNORECASE):
                matched_steps.append(step)
                pattern_idx += 1
                step_idx += 1
            else:
                # Pattern broken - no match
                return None

        # Must match all pattern tools to be valid
        if pattern_idx == len(pattern.tools):
            return matched_steps
        else:
            return None

    def _group_by_category(self, steps: List[DetailedStep]) -> Dict[StepCategory, List[DetailedStep]]:
        """Group steps by their inferred category"""
        groups: Dict[StepCategory, List[DetailedStep]] = {}

        for step in steps:
            category = self._infer_category_from_tool(step.tool_id)
            if category not in groups:
                groups[category] = []
            groups[category].append(step)

        return groups

    def _create_high_level_step_from_pattern(
        self,
        detailed_steps: List[DetailedStep],
        pattern: ToolPattern,
        order: int
    ) -> HighLevelStep:
        """Create a high-level step from matched pattern"""
        # Collect all inputs/outputs from detailed steps
        all_inputs = []
        all_outputs = []
        for step in detailed_steps:
            all_inputs.extend(step.inputs)
            all_outputs.extend(step.outputs)

        # Deduplicate by name
        unique_inputs = {inp.name: inp for inp in all_inputs}.values()
        unique_outputs = {out.name: out for out in all_outputs}.values()

        return HighLevelStep(
            step_id=f"hl_step_{order}",
            name=pattern.name,
            description=pattern.description,
            detailed_steps=detailed_steps,
            category=pattern.category,
            icon=pattern.icon,
            color=pattern.color,
            inputs=list(unique_inputs),
            outputs=list(unique_outputs),
            parameters={},
            order=order
        )

    def _create_high_level_step_from_category(
        self,
        detailed_steps: List[DetailedStep],
        category: StepCategory,
        order: int
    ) -> HighLevelStep:
        """Create a high-level step from category grouping"""
        # Collect all inputs/outputs
        all_inputs = []
        all_outputs = []
        for step in detailed_steps:
            all_inputs.extend(step.inputs)
            all_outputs.extend(step.outputs)

        unique_inputs = {inp.name: inp for inp in all_inputs}.values()
        unique_outputs = {out.name: out for out in all_outputs}.values()

        # Generate descriptive name
        tool_names = [s.tool_name for s in detailed_steps]
        name = f"{category.value.title()} Steps"
        if len(tool_names) <= 3:
            name = " + ".join(tool_names)

        return HighLevelStep(
            step_id=f"hl_step_{order}",
            name=name,
            description=f"{category.value.title()} processing with {len(detailed_steps)} tools",
            detailed_steps=detailed_steps,
            category=category,
            icon=self._get_icon_for_category(category),
            color=self._get_color_for_category(category),
            inputs=list(unique_inputs),
            outputs=list(unique_outputs),
            parameters={},
            order=order
        )

    def _pattern_based_grouping(self, workflow: UnifiedWorkflow) -> UnifiedWorkflow:
        """Pure pattern-based grouping"""
        # Similar to hybrid but only use patterns
        return workflow

    def _category_based_grouping(self, workflow: UnifiedWorkflow) -> UnifiedWorkflow:
        """Pure category-based grouping"""
        # Group all steps by category
        return workflow

    def _annotation_based_grouping(self, workflow: UnifiedWorkflow) -> UnifiedWorkflow:
        """Use workflow/tool annotations for grouping"""
        # Parse annotations from workflow description, tool labels, etc.
        return workflow

    def _dependency_based_grouping(self, workflow: UnifiedWorkflow) -> UnifiedWorkflow:
        """Group based on data dependencies (input/output connections)"""
        # Analyze input/output connections to find tightly coupled tools
        return workflow

    def _infer_category_from_tool(self, tool_id: str) -> StepCategory:
        """Infer step category from tool ID"""
        tool_lower = tool_id.lower()

        if any(x in tool_lower for x in ["fastqc", "multiqc", "trimmomatic", "cutadapt", "fastp"]):
            return StepCategory.QC
        elif any(x in tool_lower for x in ["bwa", "bowtie", "star", "hisat", "minimap"]):
            return StepCategory.ALIGNMENT
        elif any(x in tool_lower for x in ["salmon", "kallisto", "featurecounts", "htseq", "deseq", "edger"]):
            return StepCategory.QUANTIFICATION
        elif any(x in tool_lower for x in ["freebayes", "gatk", "lofreq", "bcftools", "varscan", "snpeff"]):
            return StepCategory.VARIANT_CALLING
        elif any(x in tool_lower for x in ["macs2", "sicer", "homer"]):
            return StepCategory.PEAK_CALLING
        elif any(x in tool_lower for x in ["spades", "megahit", "flye", "hifiasm", "canu"]):
            return StepCategory.ASSEMBLY
        elif any(x in tool_lower for x in ["maker", "augustus", "braker", "prokka", "interproscan"]):
            return StepCategory.ANNOTATION
        elif any(x in tool_lower for x in ["igv", "jbrowse", "bandage", "circos"]):
            return StepCategory.VISUALIZATION
        else:
            return StepCategory.OTHER

    def _get_icon_for_category(self, category: StepCategory) -> str:
        """Get icon emoji for category"""
        icons = {
            StepCategory.QC: "🔍",
            StepCategory.ALIGNMENT: "🧬",
            StepCategory.QUANTIFICATION: "📊",
            StepCategory.VARIANT_CALLING: "🔬",
            StepCategory.PEAK_CALLING: "⛰️",
            StepCategory.ASSEMBLY: "🧩",
            StepCategory.ANNOTATION: "📝",
            StepCategory.VISUALIZATION: "🖼️",
            StepCategory.FILTERING: "🚰",
            StepCategory.NORMALIZATION: "📏",
            StepCategory.DIFFERENTIAL_EXPRESSION: "📊",
            StepCategory.OTHER: "🔧"
        }
        return icons.get(category, "⚙️")

    def _get_color_for_category(self, category: StepCategory) -> str:
        """Get color hex code for category"""
        colors = {
            StepCategory.QC: "#3498db",
            StepCategory.ALIGNMENT: "#2ecc71",
            StepCategory.QUANTIFICATION: "#9b59b6",
            StepCategory.VARIANT_CALLING: "#f39c12",
            StepCategory.PEAK_CALLING: "#1abc9c",
            StepCategory.ASSEMBLY: "#e74c3c",
            StepCategory.ANNOTATION: "#34495e",
            StepCategory.VISUALIZATION: "#7f8c8d",
            StepCategory.FILTERING: "#3498db",
            StepCategory.NORMALIZATION: "#9b59b6",
            StepCategory.DIFFERENTIAL_EXPRESSION: "#e67e22",
            StepCategory.OTHER: "#95a5a6"
        }
        return colors.get(category, "#95a5a6")


def group_workflow_steps(
    workflow: UnifiedWorkflow,
    strategy: GroupingStrategy = GroupingStrategy.HYBRID
) -> UnifiedWorkflow:
    """
    Convenience function to group workflow steps

    Args:
        workflow: UnifiedWorkflow with flat steps
        strategy: Grouping strategy to use

    Returns:
        UnifiedWorkflow with intelligently grouped steps
    """
    grouper = WorkflowGrouper(strategy=strategy)
    return grouper.group_workflow(workflow)
