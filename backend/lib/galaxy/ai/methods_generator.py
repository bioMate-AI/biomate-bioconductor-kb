"""
Methods Section Generator

Auto-generates publication-ready methods section text from workflow definitions
with proper citations.
"""

import logging
from typing import Dict, List, Any, Optional
from dataclasses import dataclass

from .tool_knowledge_provider import (
    ToolKnowledgeProvider,
    Citation,
    ToolKnowledge,
    get_tool_knowledge_provider
)

log = logging.getLogger(__name__)


@dataclass
class WorkflowStep:
    """Represents a workflow step for methods generation."""
    step_id: int
    tool_id: str
    tool_name: str
    parameters: Dict[str, Any]
    inputs: List[str]
    outputs: List[str]


class MethodsSectionGenerator:
    """
    Generates publication-ready methods sections from workflows.

    Features:
    - Auto-formats tool citations
    - Describes parameter choices
    - Groups related steps into logical sections
    - Supports multiple citation styles
    """

    # Templates for different analysis types
    ANALYSIS_TEMPLATES = {
        "rna_seq": {
            "intro": "RNA sequencing data analysis was performed using the following pipeline.",
            "sections": ["quality_control", "alignment", "quantification", "differential_expression"]
        },
        "variant_calling": {
            "intro": "Variant calling analysis was performed using established best practices.",
            "sections": ["preprocessing", "alignment", "variant_calling", "annotation"]
        },
        "metagenomics": {
            "intro": "Metagenomic analysis was conducted to characterize microbial community composition.",
            "sections": ["quality_control", "taxonomic_classification", "functional_annotation"]
        },
        "proteomics": {
            "intro": "Proteomic data analysis was performed using the following workflow.",
            "sections": ["preprocessing", "identification", "quantification", "statistical_analysis"]
        },
        "default": {
            "intro": "Bioinformatics analysis was performed using the following computational pipeline.",
            "sections": ["preprocessing", "main_analysis", "post_processing"]
        }
    }

    # Tool category mappings for grouping
    TOOL_CATEGORIES = {
        "quality_control": ["fastqc", "multiqc", "fastp", "trimmomatic", "cutadapt", "trim_galore"],
        "alignment": ["star", "hisat2", "bwa", "bowtie2", "minimap2", "tophat"],
        "quantification": ["featurecounts", "htseq", "salmon", "kallisto", "rsem", "stringtie"],
        "differential_expression": ["deseq2", "edger", "limma", "sleuth", "ballgown"],
        "variant_calling": ["gatk", "freebayes", "bcftools", "varscan", "mutect", "strelka"],
        "annotation": ["snpeff", "vep", "annovar", "prokka", "bakta"],
        "taxonomic_classification": ["kraken2", "metaphlan", "bracken", "centrifuge", "kaiju"],
        "assembly": ["spades", "megahit", "flye", "canu", "trinity"],
        "single_cell": ["seurat", "scanpy", "cellranger", "velocyto", "scvelo"]
    }

    def __init__(self, knowledge_provider: ToolKnowledgeProvider = None):
        """
        Initialize the generator.

        Args:
            knowledge_provider: ToolKnowledgeProvider instance
        """
        self.knowledge_provider = knowledge_provider or get_tool_knowledge_provider()
        self._citations_used: Dict[str, Citation] = {}

    def generate(
        self,
        workflow: Dict[str, Any],
        citations: List[Citation] = None,
        analysis_type: str = None,
        citation_style: str = "short",
        include_parameters: bool = True,
        include_versions: bool = True
    ) -> str:
        """
        Generate methods section from workflow.

        Args:
            workflow: Galaxy workflow JSON
            citations: Optional list of Citation objects to include
            analysis_type: Type of analysis (rna_seq, variant_calling, etc.)
            citation_style: Citation format ('short', 'apa', 'numbered')
            include_parameters: Include key parameter values
            include_versions: Include tool versions

        Returns:
            Formatted methods section text
        """
        self._citations_used = {}

        # Pre-populate citations if provided
        if citations:
            for citation in citations:
                if citation and citation.title:
                    # Use a normalized key from the title
                    key = citation.title.split(":")[0].lower().replace(" ", "_")[:20]
                    self._citations_used[key] = citation

        # Parse workflow steps
        steps = self._parse_workflow(workflow)
        if not steps:
            return "No analysis steps found in workflow."

        # Detect analysis type if not specified
        if not analysis_type:
            analysis_type = self._detect_analysis_type(steps)

        template = self.ANALYSIS_TEMPLATES.get(analysis_type, self.ANALYSIS_TEMPLATES["default"])

        # Build methods text
        sections = []

        # Introduction
        sections.append(template["intro"])

        # Group steps by category
        grouped_steps = self._group_steps_by_category(steps)

        # Generate text for each section
        for category in template["sections"]:
            if category in grouped_steps:
                section_text = self._generate_section(
                    category,
                    grouped_steps[category],
                    citation_style,
                    include_parameters,
                    include_versions
                )
                if section_text:
                    sections.append(section_text)

        # Add any ungrouped steps
        if "other" in grouped_steps:
            other_text = self._generate_section(
                "additional_processing",
                grouped_steps["other"],
                citation_style,
                include_parameters,
                include_versions
            )
            if other_text:
                sections.append(other_text)

        # Generate references section
        if self._citations_used:
            sections.append(self._generate_references(citation_style))

        return "\n\n".join(sections)

    def _parse_workflow(self, workflow: Dict[str, Any]) -> List[WorkflowStep]:
        """Parse workflow JSON into WorkflowStep objects."""
        steps = []
        workflow_steps = workflow.get("steps", {})

        for step_id, step_data in workflow_steps.items():
            if step_data.get("type") == "tool":
                tool_id = step_data.get("tool_id", "")
                tool_name = step_data.get("name", step_data.get("label", "Unknown"))

                # Extract parameters
                params = {}
                tool_state = step_data.get("tool_state", {})
                if isinstance(tool_state, str):
                    import json
                    try:
                        tool_state = json.loads(tool_state)
                    except:
                        tool_state = {}

                for key, value in tool_state.items():
                    if not key.startswith("__") and value is not None:
                        params[key] = value

                # Extract inputs/outputs
                inputs = [i.get("name", "") for i in step_data.get("inputs", [])]
                outputs = [o.get("name", "") for o in step_data.get("outputs", [])]

                steps.append(WorkflowStep(
                    step_id=int(step_id),
                    tool_id=tool_id,
                    tool_name=tool_name,
                    parameters=params,
                    inputs=inputs,
                    outputs=outputs
                ))

        # Sort by step ID
        steps.sort(key=lambda s: s.step_id)
        return steps

    def _detect_analysis_type(self, steps: List[WorkflowStep]) -> str:
        """Detect analysis type from tools used."""
        tool_names = [self._normalize_tool_name(s.tool_id) for s in steps]

        # Score each analysis type
        scores = {}
        for analysis_type, template in self.ANALYSIS_TEMPLATES.items():
            if analysis_type == "default":
                continue

            score = 0
            for category in template["sections"]:
                category_tools = self.TOOL_CATEGORIES.get(category, [])
                for tool in tool_names:
                    if any(ct in tool for ct in category_tools):
                        score += 1

            scores[analysis_type] = score

        # Return highest scoring type
        if scores:
            best_type = max(scores, key=scores.get)
            if scores[best_type] > 0:
                return best_type

        return "default"

    def _normalize_tool_name(self, tool_id: str) -> str:
        """Normalize tool ID to simple name."""
        name = tool_id.lower()
        if "/" in name:
            parts = name.split("/")
            for i, part in enumerate(parts):
                if part == "repos" and i + 2 < len(parts):
                    return parts[i + 2]
            return parts[-1]
        return name

    def _group_steps_by_category(
        self,
        steps: List[WorkflowStep]
    ) -> Dict[str, List[WorkflowStep]]:
        """Group steps by analysis category."""
        grouped = {}

        for step in steps:
            tool_name = self._normalize_tool_name(step.tool_id)
            category_found = False

            for category, tools in self.TOOL_CATEGORIES.items():
                if any(t in tool_name for t in tools):
                    if category not in grouped:
                        grouped[category] = []
                    grouped[category].append(step)
                    category_found = True
                    break

            if not category_found:
                if "other" not in grouped:
                    grouped["other"] = []
                grouped["other"].append(step)

        return grouped

    def _generate_section(
        self,
        category: str,
        steps: List[WorkflowStep],
        citation_style: str,
        include_parameters: bool,
        include_versions: bool
    ) -> str:
        """Generate text for a section of the methods."""
        section_titles = {
            "quality_control": "Quality Control",
            "alignment": "Read Alignment",
            "quantification": "Expression Quantification",
            "differential_expression": "Differential Expression Analysis",
            "variant_calling": "Variant Calling",
            "annotation": "Variant Annotation",
            "taxonomic_classification": "Taxonomic Classification",
            "preprocessing": "Data Preprocessing",
            "main_analysis": "Main Analysis",
            "post_processing": "Post-processing",
            "additional_processing": "Additional Processing",
            "assembly": "Sequence Assembly",
            "single_cell": "Single-Cell Analysis"
        }

        title = section_titles.get(category, category.replace("_", " ").title())
        sentences = []

        for step in steps:
            sentence = self._generate_step_sentence(
                step, citation_style, include_parameters, include_versions
            )
            if sentence:
                sentences.append(sentence)

        if not sentences:
            return ""

        return f"**{title}**: " + " ".join(sentences)

    def _generate_step_sentence(
        self,
        step: WorkflowStep,
        citation_style: str,
        include_parameters: bool,
        include_versions: bool
    ) -> str:
        """Generate a sentence describing a workflow step."""
        tool_name = step.tool_name
        tool_id_normalized = self._normalize_tool_name(step.tool_id)

        # Get knowledge for citation
        knowledge = self.knowledge_provider.get_tool_knowledge(tool_id_normalized)

        # Build tool reference with citation
        if knowledge and knowledge.citation:
            citation = knowledge.citation
            self._citations_used[tool_id_normalized] = citation

            if citation_style == "numbered":
                citation_ref = f"[{len(self._citations_used)}]"
            elif citation_style == "apa":
                citation_ref = f"({citation.format_short()})"
            else:  # short
                citation_ref = f"({citation.format_short()})"

            tool_ref = f"{tool_name} {citation_ref}"
        else:
            tool_ref = tool_name

        # Build parameter description
        param_desc = ""
        if include_parameters and step.parameters:
            key_params = self._get_key_parameters(step.parameters, knowledge)
            if key_params:
                param_desc = f" with parameters: {', '.join(key_params)}"

        # Build version info
        version_desc = ""
        if include_versions:
            version = self._extract_version(step.tool_id)
            if version:
                version_desc = f" (version {version})"

        # Generate action verb based on tool category
        action = self._get_action_verb(tool_id_normalized)

        return f"{action} was performed using {tool_ref}{version_desc}{param_desc}."

    def _get_key_parameters(
        self,
        parameters: Dict[str, Any],
        knowledge: Optional[ToolKnowledge]
    ) -> List[str]:
        """Extract key parameters worth mentioning."""
        key_params = []

        # Priority parameters to mention
        priority_params = ["threads", "quality", "min_length", "max_mismatch",
                          "e_value", "identity", "coverage", "confidence"]

        for param_name, value in parameters.items():
            # Skip internal parameters
            if param_name.startswith("__") or param_name in ["input", "output", "reference"]:
                continue

            # Include if it's a priority parameter
            if any(p in param_name.lower() for p in priority_params):
                key_params.append(f"{param_name}={value}")
                if len(key_params) >= 3:
                    break

        return key_params

    def _extract_version(self, tool_id: str) -> Optional[str]:
        """Extract version from tool ID."""
        parts = tool_id.split("/")
        for part in reversed(parts):
            # Check if it looks like a version number
            if any(c.isdigit() for c in part) and "." in part:
                return part
        return None

    def _get_action_verb(self, tool_name: str) -> str:
        """Get appropriate action verb for tool."""
        action_mapping = {
            "fastqc": "Quality assessment",
            "multiqc": "Quality report aggregation",
            "trimmomatic": "Adapter trimming",
            "fastp": "Read preprocessing",
            "cutadapt": "Adapter removal",
            "star": "Spliced alignment",
            "hisat2": "Alignment",
            "bwa": "Alignment",
            "bowtie2": "Alignment",
            "minimap2": "Long-read alignment",
            "featurecounts": "Read counting",
            "htseq": "Read counting",
            "salmon": "Transcript quantification",
            "kallisto": "Pseudoalignment and quantification",
            "deseq2": "Differential expression analysis",
            "edger": "Differential expression analysis",
            "gatk": "Variant calling",
            "freebayes": "Variant calling",
            "bcftools": "Variant processing",
            "snpeff": "Variant annotation",
            "vep": "Variant effect prediction",
            "kraken2": "Taxonomic classification",
            "metaphlan": "Metagenomic profiling",
            "seurat": "Single-cell analysis",
            "scanpy": "Single-cell analysis"
        }

        for key, action in action_mapping.items():
            if key in tool_name.lower():
                return action

        return "Analysis"

    def _generate_references(self, citation_style: str) -> str:
        """Generate references section."""
        if not self._citations_used:
            return ""

        refs = ["**References**"]

        if citation_style == "numbered":
            for i, (tool, citation) in enumerate(self._citations_used.items(), 1):
                refs.append(f"[{i}] {citation.format_apa()}")
        else:
            for tool, citation in self._citations_used.items():
                refs.append(f"- {citation.format_apa()}")
                if citation.doi:
                    refs[-1] += f" https://doi.org/{citation.doi}"

        return "\n".join(refs)

    def generate_bibtex(self, workflow: Dict[str, Any]) -> str:
        """Generate BibTeX entries for all tools in workflow."""
        steps = self._parse_workflow(workflow)

        bibtex_entries = []
        seen_tools = set()

        for step in steps:
            tool_name = self._normalize_tool_name(step.tool_id)
            if tool_name in seen_tools:
                continue
            seen_tools.add(tool_name)

            knowledge = self.knowledge_provider.get_tool_knowledge(tool_name)
            if knowledge and knowledge.citation:
                bibtex_entries.append(knowledge.citation.format_bibtex(tool_name))

        return "\n\n".join(bibtex_entries)

    def get_citations_summary(self, workflow: Dict[str, Any]) -> Dict[str, Any]:
        """Get summary of citations for workflow."""
        steps = self._parse_workflow(workflow)

        summary = {
            "total_steps": len(steps),
            "steps_with_citations": 0,
            "citations": [],
            "missing_citations": []
        }

        seen_tools = set()
        for step in steps:
            tool_name = self._normalize_tool_name(step.tool_id)
            if tool_name in seen_tools:
                continue
            seen_tools.add(tool_name)

            knowledge = self.knowledge_provider.get_tool_knowledge(tool_name)
            if knowledge and knowledge.citation:
                summary["steps_with_citations"] += 1
                summary["citations"].append({
                    "tool": tool_name,
                    "citation": knowledge.citation.to_dict()
                })
            else:
                summary["missing_citations"].append(tool_name)

        return summary
