"""
Workflow Search RAG System

Searches existing workflow templates and Galaxy workflow library for matches
before generating new workflows from scratch.

Architecture:
1. In-memory template library (3 verified templates from workflow_templates.py)
2. Future: Galaxy workflow database integration
3. RAG-based similarity scoring using keywords and descriptions
"""

import json
import logging
from typing import Dict, List, Optional, Tuple
from difflib import SequenceMatcher

log = logging.getLogger(__name__)


class WorkflowSearchRAG:
    """
    Search existing workflows before generating new ones.

    This implements the "search first, generate as fallback" pattern
    identified as a critical gap in DATASET_AND_WORKFLOW_ARCHITECTURE_CLARIFICATION.md
    """

    def __init__(self, galaxy_app=None):
        """
        Initialize workflow search system.

        Args:
            galaxy_app: Galaxy application instance (optional, for future database access)
        """
        self.galaxy_app = galaxy_app
        self.templates = self._load_workflow_templates()
        log.info(f"WorkflowSearchRAG initialized with {len(self.templates)} templates")

    def _load_workflow_templates(self) -> Dict[str, Dict]:
        """
        Load verified workflow templates.

        Source: Extracted from lib/galaxy/ai/workflow_templates.py (370 lines)
        These are the 3 verified templates that should be searched FIRST.
        """
        templates = {
            "rna_seq_differential_expression": {
                "id": "rna_seq_differential_expression",
                "name": "RNA-seq Differential Expression Analysis",
                "description": "Complete RNA-seq workflow from QC to differential expression analysis",
                "keywords": ["rna-seq", "differential", "expression", "transcriptomics", "deseq2", "hisat2", "alignment"],
                "category": "transcriptomics",
                "workflow_steps": [
                    {"step": 1, "tool_id": "FastQC", "name": "Quality Control", "description": "Quality control of sequencing reads"},
                    {"step": 2, "tool_id": "HISAT2", "name": "Genome Alignment", "description": "Align reads to reference genome"},
                    {"step": 3, "tool_id": "FeatureCounts", "name": "Counting", "description": "Count reads mapping to genes"},
                    {"step": 4, "tool_id": "DESeq2", "name": "Differential Expression", "description": "Identify differentially expressed genes"}
                ],
                "input_requirements": {
                    "required": ["fastq_files", "reference_genome", "gene_annotations"],
                    "optional": ["replicate_info"]
                },
                "estimated_time": "2-4 hours",
                "resource_requirements": {
                    "cpu": 8,
                    "memory": "32GB",
                    "disk": "100GB"
                }
            },

            "variant_calling": {
                "id": "variant_calling",
                "name": "Variant Calling Pipeline",
                "description": "Identify genomic variants from sequencing data using GATK best practices",
                "keywords": ["variant", "calling", "snp", "indel", "gatk", "genomics", "dna-seq"],
                "category": "genomics",
                "workflow_steps": [
                    {"step": 1, "tool_id": "FastQC", "name": "Quality Control", "description": "Quality control of sequencing reads"},
                    {"step": 2, "tool_id": "BWA", "name": "Alignment", "description": "Align reads to reference genome"},
                    {"step": 3, "tool_id": "Picard_MarkDuplicates", "name": "Mark Duplicates", "description": "Mark PCR duplicates"},
                    {"step": 4, "tool_id": "GATK_HaplotypeCaller", "name": "Variant Calling", "description": "Call variants"},
                    {"step": 5, "tool_id": "GATK_VariantFiltration", "name": "Filtering", "description": "Filter variants"}
                ],
                "input_requirements": {
                    "required": ["fastq_files", "reference_genome"],
                    "optional": ["known_variants"]
                },
                "estimated_time": "4-8 hours",
                "resource_requirements": {
                    "cpu": 16,
                    "memory": "64GB",
                    "disk": "200GB"
                }
            },

            "lc_ms_metabolomics": {
                "id": "lc_ms_metabolomics",
                "name": "LC-MS Metabolomics Analysis",
                "description": "Untargeted metabolomics workflow from raw data to compound identification",
                "keywords": ["lc-ms", "metabolomics", "xcms", "peak", "compound", "identification", "untargeted"],
                "category": "metabolomics",
                "workflow_steps": [
                    {"step": 1, "tool_id": "MSConvert", "name": "Format Conversion", "description": "Convert RAW files to mzML"},
                    {"step": 2, "tool_id": "XCMS", "name": "Peak Detection", "description": "Detect and align peaks"},
                    {"step": 3, "tool_id": "MetaboAnalystR", "name": "Compound Identification", "description": "Identify metabolites using HMDB"},
                    {"step": 4, "tool_id": "MetaboAnalystR", "name": "Statistical Analysis", "description": "Multivariate statistical analysis"},
                    {"step": 5, "tool_id": "MetaboAnalystR", "name": "Pathway Analysis", "description": "Metabolic pathway enrichment"}
                ],
                "input_requirements": {
                    "required": ["raw_files", "sample_metadata"],
                    "optional": ["internal_standards"]
                },
                "estimated_time": "1-3 hours",
                "resource_requirements": {
                    "cpu": 8,
                    "memory": "32GB",
                    "disk": "100GB"
                }
            }
        }

        return templates

    def search(self, user_intent: str, limit: int = 5) -> List[Dict]:
        """
        Search for existing workflows matching user intent.

        Args:
            user_intent: User's natural language description of desired analysis
            limit: Maximum number of results to return

        Returns:
            List of workflows with similarity scores, sorted by relevance

        Example:
            >>> searcher = WorkflowSearchRAG()
            >>> results = searcher.search("I want to identify metabolites from LC-MS data")
            >>> results[0]
            {
                "workflow_id": "lc_ms_metabolomics",
                "name": "LC-MS Metabolomics Analysis",
                "score": 0.95,
                "match_type": "high_confidence",
                "reasoning": "Keywords match: lc-ms, metabolomics, identification"
            }
        """
        log.info(f"Searching workflows for intent: {user_intent}")

        # Search templates
        results = []
        for template_id, template in self.templates.items():
            score, reasoning = self._calculate_similarity(user_intent, template)

            if score > 0.1:  # Minimum threshold to include in results
                results.append({
                    "workflow_id": template_id,
                    "name": template["name"],
                    "description": template["description"],
                    "score": score,
                    "match_type": self._classify_match(score),
                    "reasoning": reasoning,
                    "workflow": template,  # Include full template for reuse
                    "source": "template_library"
                })

        # TODO: Future enhancement - search Galaxy workflow database
        # database_results = self._search_galaxy_workflows(user_intent)
        # results.extend(database_results)

        # Sort by score descending
        results.sort(key=lambda x: x["score"], reverse=True)

        log.info(f"Found {len(results)} matching workflows (returning top {limit})")
        return results[:limit]

    def _calculate_similarity(self, user_intent: str, template: Dict) -> Tuple[float, str]:
        """
        Calculate similarity score between user intent and template.

        Scoring algorithm:
        1. Keyword matching (40% weight) - Direct keyword overlap
        2. Description similarity (30% weight) - Fuzzy string matching
        3. Category matching (20% weight) - Category name overlap
        4. Tool name matching (10% weight) - Tool names in template

        Returns:
            (score, reasoning) where score is 0.0-1.0 and reasoning explains the match
        """
        user_lower = user_intent.lower()
        score = 0.0
        reasons = []

        # 1. Keyword matching (40% weight)
        keyword_matches = 0
        total_keywords = len(template.get("keywords", []))

        if total_keywords > 0:
            for keyword in template["keywords"]:
                if keyword.lower() in user_lower:
                    keyword_matches += 1
                    reasons.append(f"keyword '{keyword}'")

            keyword_score = (keyword_matches / total_keywords) * 0.4
            score += keyword_score

        # 2. Description similarity (30% weight)
        description = template.get("description", "").lower()
        description_sim = SequenceMatcher(None, user_lower, description).ratio()
        score += description_sim * 0.3

        if description_sim > 0.3:
            reasons.append(f"description similarity")

        # 3. Category matching (20% weight)
        category = template.get("category", "").lower()
        if category and category in user_lower:
            score += 0.2
            reasons.append(f"category '{category}'")

        # 4. Tool name matching (10% weight)
        tool_matches = 0
        workflow_steps = template.get("workflow_steps", [])

        if workflow_steps:
            for step in workflow_steps:
                tool_name = step.get("tool_id", "").lower()
                if tool_name and tool_name in user_lower:
                    tool_matches += 1
                    reasons.append(f"tool '{step['tool_id']}'")

            if len(workflow_steps) > 0:
                tool_score = (tool_matches / len(workflow_steps)) * 0.1
                score += tool_score

        # Generate reasoning string
        if reasons:
            reasoning = f"Matched: {', '.join(reasons[:3])}"  # Show top 3 reasons
        else:
            reasoning = "Low similarity to template"

        return score, reasoning

    def _classify_match(self, score: float) -> str:
        """
        Classify match confidence based on score.

        Thresholds (from DATASET_AND_WORKFLOW_ARCHITECTURE_CLARIFICATION.md):
        - > 0.8: High confidence - reuse workflow directly
        - 0.5-0.8: Medium confidence - adapt workflow
        - < 0.5: Low confidence - generate new workflow
        """
        if score >= 0.8:
            return "high_confidence"
        elif score >= 0.5:
            return "medium_confidence"
        else:
            return "low_confidence"

    def _search_galaxy_workflows(self, user_intent: str) -> List[Dict]:
        """
        Search Galaxy workflow database (future implementation).

        This will integrate with Galaxy's workflow storage to search
        hundreds of user-created workflows.

        TODO: Implement when Galaxy workflow database is available
        """
        if not self.galaxy_app:
            return []

        # Future implementation:
        # 1. Query Galaxy workflow database
        # 2. Extract workflow metadata (name, tags, description)
        # 3. Calculate similarity scores
        # 4. Return matching workflows

        return []

    def get_template(self, template_id: str) -> Optional[Dict]:
        """
        Get full template by ID.

        Args:
            template_id: Template identifier

        Returns:
            Template dictionary or None if not found
        """
        return self.templates.get(template_id)

    def list_templates(self) -> List[Dict]:
        """
        List all available templates with metadata.

        Returns:
            List of template summaries
        """
        return [
            {
                "id": template_id,
                "name": template["name"],
                "description": template["description"],
                "category": template["category"],
                "keywords": template["keywords"]
            }
            for template_id, template in self.templates.items()
        ]


# Example usage
if __name__ == "__main__":
    # Test the workflow search
    searcher = WorkflowSearchRAG()

    # Test case 1: LC-MS metabolomics
    print("=== Test 1: LC-MS Metabolomics ===")
    results = searcher.search("I want to identify metabolites from human serum LC-MS data")
    for i, result in enumerate(results, 1):
        print(f"{i}. {result['name']} (score: {result['score']:.2f}, {result['match_type']})")
        print(f"   Reasoning: {result['reasoning']}\n")

    # Test case 2: RNA-seq
    print("=== Test 2: RNA-seq ===")
    results = searcher.search("differential gene expression analysis with RNA sequencing")
    for i, result in enumerate(results, 1):
        print(f"{i}. {result['name']} (score: {result['score']:.2f}, {result['match_type']})")
        print(f"   Reasoning: {result['reasoning']}\n")

    # Test case 3: Variant calling
    print("=== Test 3: Variant Calling ===")
    results = searcher.search("find SNPs and indels in whole genome sequencing data")
    for i, result in enumerate(results, 1):
        print(f"{i}. {result['name']} (score: {result['score']:.2f}, {result['match_type']})")
        print(f"   Reasoning: {result['reasoning']}\n")
