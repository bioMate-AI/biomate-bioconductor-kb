"""
RAG-based Galaxy Tool Discovery System

Integrates with Galaxy's actual tool registry to provide accurate tool recommendations
based on real tool availability and capabilities.
"""

import json
import logging
from typing import Dict, List, Any, Optional, Tuple
from collections import defaultdict

log = logging.getLogger(__name__)


class GalaxyToolRAG:
    """RAG system for Galaxy tool discovery and recommendation."""
    
    def __init__(self, galaxy_app=None):
        self.galaxy_app = galaxy_app
        self.tool_index = {}
        self.tool_embeddings = {}
        self.category_index = {}
        
        if galaxy_app:
            self._build_tool_index()
    
    def _build_tool_index(self):
        """Build searchable index from Galaxy's actual tools."""
        try:
            toolbox = self.galaxy_app.toolbox
            
            for tool_id, tool in toolbox.tools():
                if tool and hasattr(tool, 'name'):
                    tool_info = self._extract_tool_info(tool)
                    self.tool_index[tool_id] = tool_info
                    self._index_tool_by_category(tool_id, tool_info)
            
            log.info(f"Built tool index with {len(self.tool_index)} tools")
            
        except Exception as e:
            log.warning(f"Could not build tool index from Galaxy: {e}")
            self._build_fallback_index()
    
    def _extract_tool_info(self, tool) -> Dict[str, Any]:
        """Extract relevant information from Galaxy tool object."""
        tool_info = {
            "id": tool.id,
            "name": getattr(tool, 'name', ''),
            "description": getattr(tool, 'description', ''),
            "version": getattr(tool, 'version', ''),
            "tool_type": getattr(tool, 'tool_type', 'tool'),
            "inputs": [],
            "outputs": [],
            "requirements": [],
            "edam_operations": [],
            "edam_topics": []
        }
        
        # Extract input information
        if hasattr(tool, 'inputs'):
            for input_param in tool.inputs.values():
                if hasattr(input_param, 'type'):
                    tool_info["inputs"].append({
                        "name": getattr(input_param, 'name', ''),
                        "type": input_param.type,
                        "format": getattr(input_param, 'format', '')
                    })
        
        # Extract output information
        if hasattr(tool, 'outputs'):
            for output_name, output_param in tool.outputs.items():
                tool_info["outputs"].append({
                    "name": output_name,
                    "format": getattr(output_param, 'format', ''),
                    "type": getattr(output_param, 'type', 'data')
                })
        
        # Extract requirements
        if hasattr(tool, 'requirements'):
            for req in tool.requirements:
                tool_info["requirements"].append({
                    "name": getattr(req, 'name', ''),
                    "type": getattr(req, 'type', ''),
                    "version": getattr(req, 'version', '')
                })
        
        # Extract EDAM annotations if available
        if hasattr(tool, 'edam_operations'):
            tool_info["edam_operations"] = list(tool.edam_operations)
        
        if hasattr(tool, 'edam_topics'):
            tool_info["edam_topics"] = list(tool.edam_topics)
        
        return tool_info
    
    def _index_tool_by_category(self, tool_id: str, tool_info: Dict[str, Any]):
        """Index tools by functional categories."""
        categories = self._categorize_tool(tool_info)
        
        for category in categories:
            if category not in self.category_index:
                self.category_index[category] = []
            self.category_index[category].append(tool_id)
    
    def _categorize_tool(self, tool_info: Dict[str, Any]) -> List[str]:
        """Categorize tool based on name, description, and functionality."""
        categories = []
        
        name_lower = tool_info["name"].lower()
        desc_lower = tool_info["description"].lower()
        tool_text = f"{name_lower} {desc_lower}"
        
        # Quality control tools
        if any(term in tool_text for term in ["fastqc", "quality", "qc", "trim", "filter"]):
            categories.append("quality_control")
        
        # Alignment tools
        if any(term in tool_text for term in ["align", "map", "bwa", "bowtie", "hisat", "star", "minimap"]):
            categories.append("alignment")
        
        # Assembly tools
        if any(term in tool_text for term in ["assembl", "spades", "velvet", "canu", "flye", "unicycler"]):
            categories.append("assembly")
        
        # Variant calling
        if any(term in tool_text for term in ["variant", "snp", "freebayes", "gatk", "bcftools", "varscan"]):
            categories.append("variant_calling")
        
        # RNA-seq analysis
        if any(term in tool_text for term in ["rna", "transcript", "expression", "deseq", "cufflinks", "htseq"]):
            categories.append("rna_seq")
        
        # Annotation tools
        if any(term in tool_text for term in ["annotat", "blast", "interpro", "pfam", "go"]):
            categories.append("annotation")
        
        # Visualization
        if any(term in tool_text for term in ["plot", "visualiz", "graph", "chart", "heatmap"]):
            categories.append("visualization")
        
        # File manipulation
        if any(term in tool_text for term in ["convert", "format", "sort", "merge", "split"]):
            categories.append("file_manipulation")
        
        return categories if categories else ["other"]
    
    def _build_fallback_index(self):
        """Build fallback tool index when Galaxy toolbox is not available."""
        log.info("Building fallback tool index")
        
        fallback_tools = {
            # Quality Control
            "fastqc": {
                "id": "toolshed.g2.bx.psu.edu/repos/devteam/fastqc/fastqc/0.73+galaxy0",
                "name": "FastQC",
                "description": "Read Quality reports",
                "inputs": [{"type": "fastq"}],
                "outputs": [{"type": "html"}, {"type": "txt"}],
                "category": "quality_control"
            },
            "multiqc": {
                "id": "toolshed.g2.bx.psu.edu/repos/iuc/multiqc/multiqc/1.11+galaxy1",
                "name": "MultiQC",
                "description": "Aggregate results from bioinformatics analyses",
                "inputs": [{"type": "txt"}],
                "outputs": [{"type": "html"}],
                "category": "quality_control"
            },
            
            # Trimming
            "cutadapt": {
                "id": "toolshed.g2.bx.psu.edu/repos/lparsons/cutadapt/cutadapt/4.4+galaxy0",
                "name": "Cutadapt",
                "description": "Remove adapter sequences from sequencing reads",
                "inputs": [{"type": "fastq"}],
                "outputs": [{"type": "fastq"}],
                "category": "quality_control"
            },
            
            # Alignment
            "bwa_mem": {
                "id": "toolshed.g2.bx.psu.edu/repos/devteam/bwa/bwa_mem/0.7.17.2",
                "name": "BWA-MEM",
                "description": "Map sequencing reads to reference genome",
                "inputs": [{"type": "fastq"}, {"type": "fasta"}],
                "outputs": [{"type": "bam"}],
                "category": "alignment"
            },
            "hisat2": {
                "id": "toolshed.g2.bx.psu.edu/repos/iuc/hisat2/hisat2/2.2.1+galaxy0",
                "name": "HISAT2",
                "description": "Splice-aware alignment for RNA-seq data",
                "inputs": [{"type": "fastq"}, {"type": "fasta"}],
                "outputs": [{"type": "bam"}],
                "category": "alignment"
            },
            
            # Feature counting
            "featurecounts": {
                "id": "toolshed.g2.bx.psu.edu/repos/iuc/featurecounts/featurecounts/2.0.3+galaxy0",
                "name": "featureCounts",
                "description": "Count reads mapping to genomic features",
                "inputs": [{"type": "bam"}, {"type": "gtf"}],
                "outputs": [{"type": "tabular"}],
                "category": "rna_seq"
            },
            
            # Differential expression
            "deseq2": {
                "id": "toolshed.g2.bx.psu.edu/repos/iuc/deseq2/deseq2/1.40.2+galaxy0",
                "name": "DESeq2",
                "description": "Differential gene expression analysis",
                "inputs": [{"type": "tabular"}],
                "outputs": [{"type": "tabular"}, {"type": "png"}],
                "category": "rna_seq"
            },
            
            # Variant calling
            "freebayes": {
                "id": "toolshed.g2.bx.psu.edu/repos/devteam/freebayes/freebayes/1.3.6+galaxy0",
                "name": "FreeBayes",
                "description": "Bayesian genetic variant detector",
                "inputs": [{"type": "bam"}, {"type": "fasta"}],
                "outputs": [{"type": "vcf"}],
                "category": "variant_calling"
            }
        }
        
        for tool_id, tool_info in fallback_tools.items():
            self.tool_index[tool_info["id"]] = tool_info
            category = tool_info["category"]
            if category not in self.category_index:
                self.category_index[category] = []
            self.category_index[category].append(tool_info["id"])
    
    def search_tools(self, query: str, data_types: List[str] = None, 
                    category: str = None, limit: int = 10) -> List[Dict[str, Any]]:
        """Search for tools based on query and constraints."""
        
        results = []
        query_lower = query.lower()
        
        for tool_id, tool_info in self.tool_index.items():
            score = 0
            
            # Text matching
            if query_lower in tool_info["name"].lower():
                score += 20
            if query_lower in tool_info["description"].lower():
                score += 10
            
            # Category matching
            if category:
                tool_categories = self._categorize_tool(tool_info)
                if category in tool_categories:
                    score += 15
            
            # Data type compatibility
            if data_types:
                for data_type in data_types:
                    for input_info in tool_info["inputs"]:
                        if data_type.lower() in str(input_info.get("type", "")).lower():
                            score += 12
                    for output_info in tool_info["outputs"]:
                        if data_type.lower() in str(output_info.get("type", "")).lower():
                            score += 8
            
            if score > 0:
                result = tool_info.copy()
                result["relevance_score"] = score
                results.append(result)
        
        # Sort by relevance and limit results
        results.sort(key=lambda x: x["relevance_score"], reverse=True)
        return results[:limit]
    
    def get_tools_by_category(self, category: str) -> List[Dict[str, Any]]:
        """Get all tools in a specific category."""
        if category not in self.category_index:
            return []
        
        tools = []
        for tool_id in self.category_index[category]:
            if tool_id in self.tool_index:
                tools.append(self.tool_index[tool_id])
        
        return tools
    
    def get_tool_by_id(self, tool_id: str) -> Optional[Dict[str, Any]]:
        """Get tool information by ID."""
        return self.tool_index.get(tool_id)
    
    def get_compatible_tools(self, input_type: str, output_type: str = None) -> List[Dict[str, Any]]:
        """Find tools that accept specific input types and produce specific outputs."""
        compatible = []
        
        for tool_id, tool_info in self.tool_index.items():
            # Check input compatibility
            input_match = False
            for input_info in tool_info["inputs"]:
                if input_type.lower() in str(input_info.get("type", "")).lower():
                    input_match = True
                    break
            
            if not input_match:
                continue
            
            # Check output compatibility if specified
            if output_type:
                output_match = False
                for output_info in tool_info["outputs"]:
                    if output_type.lower() in str(output_info.get("type", "")).lower():
                        output_match = True
                        break
                if not output_match:
                    continue
            
            compatible.append(tool_info)
        
        return compatible
    
    def get_pipeline_suggestions(self, start_data_type: str, end_data_type: str) -> List[List[str]]:
        """Suggest tool pipelines to transform start_data_type to end_data_type."""
        # This is a simplified implementation
        # In practice, you'd use graph algorithms to find optimal paths
        
        pipelines = []
        
        # Common pipeline patterns
        pipeline_patterns = {
            ("fastq", "bam"): ["fastqc", "cutadapt", "bwa_mem"],
            ("fastq", "vcf"): ["fastqc", "cutadapt", "bwa_mem", "freebayes"],
            ("fastq", "tabular"): ["fastqc", "cutadapt", "hisat2", "featurecounts"],
            ("bam", "vcf"): ["freebayes"],
            ("tabular", "png"): ["deseq2"]
        }
        
        pattern_key = (start_data_type.lower(), end_data_type.lower())
        if pattern_key in pipeline_patterns:
            pipeline = []
            for tool_name in pipeline_patterns[pattern_key]:
                # Find actual tool ID
                for tool_id, tool_info in self.tool_index.items():
                    if tool_name.lower() in tool_info["name"].lower():
                        pipeline.append(tool_id)
                        break
            if pipeline:
                pipelines.append(pipeline)
        
        return pipelines