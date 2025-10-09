"""
Tool Recommender for Galaxy AI Assistant

Recommends appropriate Galaxy tools for each decomposed task.
"""

import json
import re
from typing import Dict, List, Any, Optional, Tuple
from collections import defaultdict
from .types import Task, Tool, ToolRecommendation, ToolMatch, TaskType, IntentType
from .config import AIConfig
from .llm_client import LLMClient


class ToolRecommender:
    """Recommends Galaxy tools for specific tasks."""
    
    def __init__(self, config: AIConfig, tool_registry=None):
        self.config = config
        self.llm_client = LLMClient(config)
        self.tool_registry = tool_registry or {}
        self.tool_cache = {}
        
        # Tool mapping based on task types and data types
        self.tool_mappings = {
            # Quality Control Tools
            (TaskType.QUALITY_CONTROL, 'fastq'): [
                'fastqc', 'multiqc', 'fastp', 'trimmomatic'
            ],
            
            # Data Processing Tools
            (TaskType.DATA_PROCESSING, 'fastq'): [
                'cutadapt', 'trimmomatic', 'fastp', 'trim_galore'
            ],
            
            # Alignment Tools
            (TaskType.GENOMICS, 'fastq'): [
                'bwa', 'bowtie2', 'hisat2', 'star', 'minimap2'
            ],
            
            # Assembly Tools
            (TaskType.ASSEMBLY, 'fastq'): [
                'spades', 'velvet', 'canu', 'flye', 'unicycler'
            ],
            
            # Variant Calling
            (TaskType.GENOMICS, 'bam'): [
                'freebayes', 'gatk', 'bcftools', 'varscan'
            ],
            
            # RNA-seq Analysis
            (TaskType.TRANSCRIPTOMICS, 'fastq'): [
                'hisat2', 'star', 'kallisto', 'salmon'
            ],
            (TaskType.TRANSCRIPTOMICS, 'bam'): [
                'featurecounts', 'htseq-count', 'cufflinks'
            ],
            (TaskType.TRANSCRIPTOMICS, 'tabular'): [
                'deseq2', 'edger', 'limma'
            ],
            
            # Annotation Tools
            (TaskType.ANNOTATION, 'fasta'): [
                'prokka', 'augustus', 'maker', 'braker'
            ],
            (TaskType.ANNOTATION, 'vcf'): [
                'snpeff', 'vep', 'annovar'
            ],
            
            # Visualization Tools
            (TaskType.VISUALIZATION, 'tabular'): [
                'ggplot2', 'plotly', 'matplotlib'
            ],
            (TaskType.VISUALIZATION, 'bam'): [
                'igv', 'jbrowse', 'trackster'
            ]
        }
        
        # EDAM operation mappings
        self.edam_mappings = {
            IntentType.ALIGN: [
                'operation_0292',  # Sequence alignment
                'operation_3198',  # Read mapping
            ],
            IntentType.ASSEMBLE: [
                'operation_0525',  # Genome assembly
                'operation_0310',  # Sequence assembly
            ],
            IntentType.ANNOTATE: [
                'operation_0362',  # Genome annotation
                'operation_3672',  # Gene functional annotation
            ],
            IntentType.ANALYZE: [
                'operation_2403',  # Sequence analysis
                'operation_3223',  # Differential gene expression
            ],
            IntentType.VISUALIZE: [
                'operation_0337',  # Visualisation
                'operation_3208',  # Genome visualisation
            ]
        }
    
    def recommend_tools(self, task: Task, available_tools: Optional[List[Tool]] = None) -> List[ToolRecommendation]:
        """Recommend tools for a specific task."""
        
        if available_tools is None:
            available_tools = self._get_available_tools()
        
        # Get candidate tools using multiple strategies
        candidates = []
        
        # Strategy 1: Direct mapping based on task type and data types
        mapping_candidates = self._get_mapping_candidates(task)
        candidates.extend(mapping_candidates)
        
        # Strategy 2: EDAM-based matching
        edam_candidates = self._get_edam_candidates(task, available_tools)
        candidates.extend(edam_candidates)
        
        # Strategy 3: Semantic matching using LLM
        if len(candidates) < 3:
            llm_candidates = self._get_llm_candidates(task, available_tools)
            candidates.extend(llm_candidates)
        
        # Remove duplicates and rank
        unique_candidates = self._deduplicate_candidates(candidates)
        ranked_candidates = self._rank_candidates(unique_candidates, task)
        
        # Convert to recommendations with reasoning
        recommendations = []
        for candidate in ranked_candidates[:self.config.max_tools_per_task]:
            recommendation = self._create_recommendation(candidate, task)
            recommendations.append(recommendation)
        
        return recommendations
    
    def _get_available_tools(self) -> List[Tool]:
        """Get list of available Galaxy tools."""
        # In a real implementation, this would query the Galaxy tool registry
        # For now, return a mock list based on common bioinformatics tools
        
        mock_tools = [
            Tool(
                id='fastqc',
                name='FastQC',
                version='0.11.9',
                description='Read quality assessment for high throughput sequence data',
                inputs=[{'name': 'input_file', 'type': 'fastq'}],
                outputs=[{'name': 'html_file', 'type': 'html'}, {'name': 'text_file', 'type': 'txt'}],
                requirements=['fastqc'],
                edam_operations=['operation_3218'],  # Sequencing quality control
                edam_topics=['topic_0622']  # Genomics
            ),
            Tool(
                id='bwa_mem',
                name='BWA-MEM',
                version='0.7.17',
                description='Fast and accurate short read aligner',
                inputs=[
                    {'name': 'reference', 'type': 'fasta'},
                    {'name': 'reads', 'type': 'fastq'}
                ],
                outputs=[{'name': 'output', 'type': 'bam'}],
                requirements=['bwa', 'samtools'],
                edam_operations=['operation_3198'],  # Read mapping
                edam_topics=['topic_0102']  # Mapping
            ),
            Tool(
                id='hisat2',
                name='HISAT2',
                version='2.2.1',
                description='Spliced aligner for RNA-seq data',
                inputs=[
                    {'name': 'reference', 'type': 'fasta'},
                    {'name': 'reads', 'type': 'fastq'}
                ],
                outputs=[{'name': 'output_alignments', 'type': 'bam'}],
                requirements=['hisat2'],
                edam_operations=['operation_3198'],  # Read mapping
                edam_topics=['topic_3170']  # RNA-seq
            ),
            Tool(
                id='featurecounts',
                name='featureCounts',
                version='2.0.1',
                description='Count reads in genomic features',
                inputs=[
                    {'name': 'alignment', 'type': 'bam'},
                    {'name': 'annotation', 'type': 'gff'}
                ],
                outputs=[{'name': 'counts', 'type': 'tabular'}],
                requirements=['subread'],
                edam_operations=['operation_3563'],  # RNA-seq quantification
                edam_topics=['topic_3170']  # RNA-seq
            ),
            Tool(
                id='deseq2',
                name='DESeq2',
                version='1.30.1',
                description='Differential expression analysis',
                inputs=[{'name': 'counts_matrix', 'type': 'tabular'}],
                outputs=[{'name': 'results', 'type': 'tabular'}],
                requirements=['bioconductor-deseq2'],
                edam_operations=['operation_3223'],  # Differential expression
                edam_topics=['topic_3170']  # RNA-seq
            )
        ]
        
        return mock_tools
    
    def _get_mapping_candidates(self, task: Task) -> List[ToolMatch]:
        """Get tool candidates using direct mappings."""
        candidates = []
        
        for input_type in task.input_data_types:
            mapping_key = (task.task_type, input_type.name)
            tool_ids = self.tool_mappings.get(mapping_key, [])
            
            for tool_id in tool_ids:
                # Find the actual tool object
                available_tools = self._get_available_tools()
                tool = next((t for t in available_tools if t.id == tool_id), None)
                
                if tool:
                    candidates.append(ToolMatch(
                        tool=tool,
                        score=0.8,  # High score for direct mappings
                        matching_criteria=['task_type_mapping', 'input_data_type']
                    ))
        
        return candidates
    
    def _get_edam_candidates(self, task: Task, available_tools: List[Tool]) -> List[ToolMatch]:
        """Get tool candidates using EDAM ontology matching."""
        candidates = []
        target_operations = self.edam_mappings.get(task.intent_type, [])
        
        for tool in available_tools:
            if not tool.edam_operations:
                continue
            
            # Calculate overlap between target operations and tool operations
            overlap = set(target_operations) & set(tool.edam_operations)
            if overlap:
                score = len(overlap) / len(target_operations)
                candidates.append(ToolMatch(
                    tool=tool,
                    score=score * 0.7,  # Scale down EDAM scores
                    matching_criteria=['edam_operations']
                ))
        
        return candidates
    
    def _get_llm_candidates(self, task: Task, available_tools: List[Tool]) -> List[ToolMatch]:
        """Get tool candidates using LLM semantic matching."""
        tool_descriptions = []
        for tool in available_tools:
            tool_descriptions.append(f"{tool.id}: {tool.name} - {tool.description}")
        
        schema = {
            "type": "object",
            "properties": {
                "recommendations": {
                    "type": "array",
                    "items": {
                        "type": "object",
                        "properties": {
                            "tool_id": {"type": "string"},
                            "confidence": {"type": "number", "minimum": 0, "maximum": 1},
                            "reasoning": {"type": "string"}
                        },
                        "required": ["tool_id", "confidence", "reasoning"]
                    }
                }
            },
            "required": ["recommendations"]
        }
        
        prompt = f"""
        Recommend the most appropriate bioinformatics tools for this task:
        
        Task: {task.name}
        Description: {task.description}
        Task Type: {task.task_type.value}
        Intent: {task.intent_type.value}
        Input Data Types: {[dt.name for dt in task.input_data_types]}
        Output Data Types: {[dt.name for dt in task.output_data_types]}
        
        Available tools:
        {chr(10).join(tool_descriptions)}
        
        Select the top 3 most suitable tools and provide confidence scores (0-1) and reasoning.
        Consider:
        1. Input/output data type compatibility
        2. Tool purpose alignment with task
        3. Common bioinformatics workflows
        4. Tool reliability and popularity
        """
        
        try:
            response = self.llm_client.generate_structured(prompt, schema)
            candidates = []
            
            for rec in response.get('recommendations', []):
                tool_id = rec['tool_id']
                tool = next((t for t in available_tools if t.id == tool_id), None)
                
                if tool:
                    candidates.append(ToolMatch(
                        tool=tool,
                        score=rec['confidence'] * 0.6,  # Scale down LLM scores
                        matching_criteria=['llm_semantic_match']
                    ))
            
            return candidates
            
        except Exception as e:
            print(f"LLM tool recommendation failed: {e}")
            return []
    
    def _deduplicate_candidates(self, candidates: List[ToolMatch]) -> List[ToolMatch]:
        """Remove duplicate tools and keep highest scoring match."""
        seen_tools = {}
        
        for candidate in candidates:
            tool_id = candidate.tool.id
            if tool_id not in seen_tools or candidate.score > seen_tools[tool_id].score:
                seen_tools[tool_id] = candidate
        
        return list(seen_tools.values())
    
    def _rank_candidates(self, candidates: List[ToolMatch], task: Task) -> List[ToolMatch]:
        """Rank tool candidates by multiple criteria."""
        
        def score_candidate(candidate: ToolMatch) -> float:
            score = candidate.score
            
            # Boost score for input/output type compatibility
            input_compatible = any(
                self._check_type_compatibility(dt.name, candidate.tool.inputs)
                for dt in task.input_data_types
            )
            output_compatible = any(
                self._check_type_compatibility(dt.name, candidate.tool.outputs)
                for dt in task.output_data_types
            )
            
            if input_compatible:
                score += 0.2
            if output_compatible:
                score += 0.2
            
            # Boost score for multiple matching criteria
            score += len(candidate.matching_criteria) * 0.1
            
            return min(score, 1.0)  # Cap at 1.0
        
        # Sort by calculated score
        ranked = sorted(candidates, key=score_candidate, reverse=True)
        return ranked
    
    def _check_type_compatibility(self, data_type: str, tool_ports: List[Dict[str, Any]]) -> bool:
        """Check if data type is compatible with tool inputs/outputs."""
        for port in tool_ports:
            port_type = port.get('type', '').lower()
            if data_type.lower() in port_type or port_type in data_type.lower():
                return True
        return False
    
    def _create_recommendation(self, candidate: ToolMatch, task: Task) -> ToolRecommendation:
        """Create a tool recommendation from a candidate match."""
        
        # Generate reasoning
        reasoning_parts = []
        if 'task_type_mapping' in candidate.matching_criteria:
            reasoning_parts.append(f"Direct mapping for {task.task_type.value} tasks")
        if 'edam_operations' in candidate.matching_criteria:
            reasoning_parts.append("EDAM ontology match")
        if 'llm_semantic_match' in candidate.matching_criteria:
            reasoning_parts.append("Semantic similarity to task description")
        
        reasoning = "; ".join(reasoning_parts) or "General compatibility"
        
        # Estimate runtime based on task type and tool
        runtime_estimates = {
            TaskType.QUALITY_CONTROL: 15,
            TaskType.DATA_PROCESSING: 30,
            TaskType.GENOMICS: 120,
            TaskType.ASSEMBLY: 240,
            TaskType.TRANSCRIPTOMICS: 90
        }
        estimated_runtime = runtime_estimates.get(task.task_type, 60)
        
        # Estimate resource requirements
        resource_reqs = self._estimate_resources(candidate.tool, task)
        
        return ToolRecommendation(
            tool=candidate.tool,
            confidence=candidate.score,
            reasoning=reasoning,
            estimated_runtime=estimated_runtime,
            resource_requirements=resource_reqs
        )
    
    def _estimate_resources(self, tool: Tool, task: Task) -> Dict[str, Any]:
        """Estimate resource requirements for tool execution."""
        
        # Basic resource estimation based on tool type
        base_resources = {
            'cores': 1,
            'memory_gb': 4,
            'disk_gb': 10
        }
        
        # Adjust based on tool requirements
        if 'bwa' in tool.id or 'hisat2' in tool.id:
            base_resources['memory_gb'] = 8
            base_resources['cores'] = 4
        elif 'spades' in tool.id or 'assembly' in tool.name.lower():
            base_resources['memory_gb'] = 16
            base_resources['cores'] = 8
            base_resources['disk_gb'] = 50
        elif 'deseq2' in tool.id or 'r-' in tool.id:
            base_resources['memory_gb'] = 8
        
        return base_resources