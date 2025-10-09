"""
Human-Verified Workflow Templates for Galaxy AI Assistant

Contains curated, tested workflow templates for common bioinformatics analyses.
These templates are manually verified to ensure quality and correctness.
"""

import json
from typing import Dict, List, Any, Optional
from datetime import datetime


class WorkflowTemplateLibrary:
    """Library of human-verified workflow templates."""
    
    def __init__(self):
        self.templates = self._load_verified_templates()
        self.template_index = self._build_template_index()
    
    def _load_verified_templates(self) -> Dict[str, Dict[str, Any]]:
        """Load human-verified workflow templates."""
        
        templates = {
            "rna_seq_differential_expression": {
                "name": "RNA-seq Differential Expression Analysis",
                "description": "Complete RNA-seq analysis pipeline for differential gene expression",
                "category": "transcriptomics",
                "keywords": ["rna-seq", "differential expression", "transcriptome", "gene expression"],
                "difficulty": "intermediate",
                "estimated_time": "2-4 hours",
                "input_requirements": [
                    {"type": "fastq", "description": "Raw RNA-seq reads", "required": True},
                    {"type": "fasta", "description": "Reference genome", "required": True},
                    {"type": "gtf", "description": "Gene annotation", "required": True}
                ],
                "workflow_steps": [
                    {
                        "step": 1,
                        "name": "Quality Control",
                        "tool_id": "toolshed.g2.bx.psu.edu/repos/devteam/fastqc/fastqc/0.73+galaxy0",
                        "description": "Assess raw read quality with FastQC",
                        "inputs": ["raw_reads"],
                        "outputs": ["qc_report"]
                    },
                    {
                        "step": 2,
                        "name": "Read Trimming",
                        "tool_id": "toolshed.g2.bx.psu.edu/repos/lparsons/cutadapt/cutadapt/4.4+galaxy0",
                        "description": "Remove adapters and low-quality bases",
                        "inputs": ["raw_reads"],
                        "outputs": ["trimmed_reads"],
                        "parameters": {
                            "minimum_length": 20,
                            "quality_cutoff": 20
                        }
                    },
                    {
                        "step": 3,
                        "name": "Reference Alignment",
                        "tool_id": "toolshed.g2.bx.psu.edu/repos/iuc/hisat2/hisat2/2.2.1+galaxy0",
                        "description": "Align reads to reference genome with HISAT2",
                        "inputs": ["trimmed_reads", "reference_genome"],
                        "outputs": ["aligned_reads"]
                    },
                    {
                        "step": 4,
                        "name": "Count Features",
                        "tool_id": "toolshed.g2.bx.psu.edu/repos/iuc/featurecounts/featurecounts/2.0.3+galaxy0",
                        "description": "Count reads mapping to genes",
                        "inputs": ["aligned_reads", "gene_annotation"],
                        "outputs": ["count_matrix"]
                    },
                    {
                        "step": 5,
                        "name": "Differential Expression",
                        "tool_id": "toolshed.g2.bx.psu.edu/repos/iuc/deseq2/deseq2/1.40.2+galaxy0",
                        "description": "Identify differentially expressed genes",
                        "inputs": ["count_matrix"],
                        "outputs": ["de_results", "plots"]
                    }
                ],
                "expected_outputs": [
                    {"name": "Quality Control Report", "type": "html"},
                    {"name": "Differential Expression Results", "type": "tabular"},
                    {"name": "MA Plot", "type": "png"},
                    {"name": "Volcano Plot", "type": "png"}
                ],
                "validation_status": "verified",
                "last_updated": "2025-08-20",
                "curator": "Galaxy AI Team"
            },
            
            "variant_calling_pipeline": {
                "name": "Variant Calling Pipeline",
                "description": "Comprehensive variant calling workflow for whole genome/exome sequencing",
                "category": "genomics",
                "keywords": ["variant calling", "snp", "indel", "genomics", "wgs", "wes"],
                "difficulty": "advanced",
                "estimated_time": "3-6 hours",
                "input_requirements": [
                    {"type": "fastq", "description": "Raw sequencing reads", "required": True},
                    {"type": "fasta", "description": "Reference genome", "required": True}
                ],
                "workflow_steps": [
                    {
                        "step": 1,
                        "name": "Quality Assessment",
                        "tool_id": "toolshed.g2.bx.psu.edu/repos/devteam/fastqc/fastqc/0.73+galaxy0",
                        "description": "Quality control of raw reads",
                        "inputs": ["raw_reads"],
                        "outputs": ["qc_report"]
                    },
                    {
                        "step": 2,
                        "name": "Read Alignment",
                        "tool_id": "toolshed.g2.bx.psu.edu/repos/devteam/bwa/bwa_mem/0.7.17.2",
                        "description": "Align reads to reference genome",
                        "inputs": ["raw_reads", "reference_genome"],
                        "outputs": ["aligned_reads"]
                    },
                    {
                        "step": 3,
                        "name": "Mark Duplicates",
                        "tool_id": "toolshed.g2.bx.psu.edu/repos/devteam/picard/picard_MarkDuplicates/2.18.2.0",
                        "description": "Mark PCR duplicates",
                        "inputs": ["aligned_reads"],
                        "outputs": ["dedup_reads"]
                    },
                    {
                        "step": 4,
                        "name": "Variant Calling",
                        "tool_id": "toolshed.g2.bx.psu.edu/repos/devteam/freebayes/freebayes/1.3.6+galaxy0",
                        "description": "Call variants with FreeBayes",
                        "inputs": ["dedup_reads", "reference_genome"],
                        "outputs": ["raw_variants"]
                    },
                    {
                        "step": 5,
                        "name": "Variant Filtering",
                        "tool_id": "toolshed.g2.bx.psu.edu/repos/devteam/vcffilter/vcffilter2/1.0.0_rc3+galaxy3",
                        "description": "Filter variants by quality",
                        "inputs": ["raw_variants"],
                        "outputs": ["filtered_variants"],
                        "parameters": {
                            "min_quality": 30,
                            "min_depth": 10
                        }
                    }
                ],
                "expected_outputs": [
                    {"name": "Quality Report", "type": "html"},
                    {"name": "Filtered Variants", "type": "vcf"},
                    {"name": "Variant Statistics", "type": "tabular"}
                ],
                "validation_status": "verified",
                "last_updated": "2025-08-20",
                "curator": "Galaxy AI Team"
            },
            
            "genome_assembly_pipeline": {
                "name": "Genome Assembly Pipeline",
                "description": "De novo genome assembly using long-read sequencing data",
                "category": "assembly",
                "keywords": ["genome assembly", "long reads", "nanopore", "pacbio", "de novo"],
                "difficulty": "advanced",
                "estimated_time": "4-8 hours",
                "input_requirements": [
                    {"type": "fastq", "description": "Long-read sequencing data", "required": True}
                ],
                "workflow_steps": [
                    {
                        "step": 1,
                        "name": "Read Statistics",
                        "tool_id": "toolshed.g2.bx.psu.edu/repos/iuc/nanoplot/nanoplot/1.41.0+galaxy0",
                        "description": "Analyze long-read quality and statistics",
                        "inputs": ["long_reads"],
                        "outputs": ["read_stats"]
                    },
                    {
                        "step": 2,
                        "name": "Read Filtering",
                        "tool_id": "toolshed.g2.bx.psu.edu/repos/iuc/filtlong/filtlong/0.2.1+galaxy0",
                        "description": "Filter low-quality reads",
                        "inputs": ["long_reads"],
                        "outputs": ["filtered_reads"],
                        "parameters": {
                            "min_length": 1000,
                            "min_mean_q": 10
                        }
                    },
                    {
                        "step": 3,
                        "name": "Genome Assembly",
                        "tool_id": "toolshed.g2.bx.psu.edu/repos/bgruening/flye/flye/2.9.1+galaxy0",
                        "description": "Assemble genome with Flye",
                        "inputs": ["filtered_reads"],
                        "outputs": ["assembly"]
                    },
                    {
                        "step": 4,
                        "name": "Assembly Polish",
                        "tool_id": "toolshed.g2.bx.psu.edu/repos/iuc/medaka_consensus/medaka_consensus/1.7.2+galaxy0",
                        "description": "Polish assembly with Medaka",
                        "inputs": ["assembly", "filtered_reads"],
                        "outputs": ["polished_assembly"]
                    },
                    {
                        "step": 5,
                        "name": "Assembly Quality",
                        "tool_id": "toolshed.g2.bx.psu.edu/repos/iuc/quast/quast/5.2.0+galaxy1",
                        "description": "Assess assembly quality",
                        "inputs": ["polished_assembly"],
                        "outputs": ["quality_report"]
                    }
                ],
                "expected_outputs": [
                    {"name": "Polished Assembly", "type": "fasta"},
                    {"name": "Assembly Quality Report", "type": "html"},
                    {"name": "Read Statistics", "type": "html"}
                ],
                "validation_status": "verified",
                "last_updated": "2025-08-20",
                "curator": "Galaxy AI Team"
            }
        }
        
        return templates
    
    def _build_template_index(self) -> Dict[str, List[str]]:
        """Build search index for templates."""
        index = {}
        
        for template_id, template in self.templates.items():
            # Index by keywords
            for keyword in template["keywords"]:
                if keyword not in index:
                    index[keyword] = []
                index[keyword].append(template_id)
            
            # Index by category
            category = template["category"]
            if category not in index:
                index[category] = []
            index[category].append(template_id)
        
        return index
    
    def search_templates(self, query: str, user_request: str = "") -> List[Dict[str, Any]]:
        """Search for relevant workflow templates."""
        query_lower = query.lower()
        user_request_lower = user_request.lower()
        
        matched_templates = []
        
        for template_id, template in self.templates.items():
            score = 0
            
            # Check keywords
            for keyword in template["keywords"]:
                if keyword in query_lower or keyword in user_request_lower:
                    score += 10
            
            # Check category
            if template["category"] in query_lower or template["category"] in user_request_lower:
                score += 5
            
            # Check name and description
            if any(word in template["name"].lower() for word in query_lower.split()):
                score += 8
            
            if any(word in template["description"].lower() for word in query_lower.split()):
                score += 3
            
            if score > 0:
                template_result = template.copy()
                template_result["template_id"] = template_id
                template_result["relevance_score"] = score
                matched_templates.append(template_result)
        
        # Sort by relevance score
        matched_templates.sort(key=lambda x: x["relevance_score"], reverse=True)
        
        return matched_templates
    
    def get_template(self, template_id: str) -> Optional[Dict[str, Any]]:
        """Get a specific template by ID."""
        return self.templates.get(template_id)
    
    def get_all_templates(self) -> Dict[str, Dict[str, Any]]:
        """Get all available templates."""
        return self.templates.copy()
    
    def get_categories(self) -> List[str]:
        """Get all available workflow categories."""
        categories = set()
        for template in self.templates.values():
            categories.add(template["category"])
        return sorted(list(categories))