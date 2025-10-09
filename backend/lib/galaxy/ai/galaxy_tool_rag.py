"""
RAG-based Galaxy Tool Discovery System

Integrates with Galaxy's comprehensive tool database (6,295 tools from ToolShed)
to provide accurate tool recommendations based on real tool availability and capabilities.
"""

import json
import logging
import sqlite3
from pathlib import Path
from typing import Dict, List, Any, Optional, Tuple
from collections import defaultdict

log = logging.getLogger(__name__)


class GalaxyToolRAG:
    """RAG system for Galaxy tool discovery and recommendation using comprehensive database."""

    def __init__(self, galaxy_app=None, db_path=None):
        self.galaxy_app = galaxy_app
        self.tool_index = {}
        self.tool_embeddings = {}
        self.category_index = {}

        # Set database path
        if db_path is None:
            db_path = str(Path(__file__).parent.parent.parent.parent / "galaxy_ai_tools.db")
        self.db_path = db_path

        # Build index from comprehensive database
        self._build_tool_index()

    def _build_tool_index(self):
        """Build searchable index from comprehensive tool database (6,295 tools)."""
        try:
            # First try to load from database
            if Path(self.db_path).exists():
                self._load_from_database()
                log.info(f"Loaded {len(self.tool_index)} tools from comprehensive database")
            else:
                log.warning(f"Database not found at {self.db_path}, trying Galaxy toolbox")
                self._build_from_galaxy_toolbox()

        except Exception as e:
            log.error(f"Could not build tool index: {e}")
            # Last resort: build from Galaxy toolbox if available
            if self.galaxy_app:
                self._build_from_galaxy_toolbox()

    def _load_from_database(self):
        """Load tools from comprehensive SQLite database."""
        with sqlite3.connect(self.db_path) as conn:
            conn.row_factory = sqlite3.Row
            cursor = conn.cursor()

            cursor.execute("""
                SELECT id, name, version, description, category, repo_owner, repo_name,
                       parameters, help_text, inputs, outputs, requirements
                FROM tools
            """)

            for row in cursor.fetchall():
                tool_id = row['id']
                tool_info = {
                    "id": tool_id,
                    "name": row['name'],
                    "description": row['description'] or '',
                    "version": row['version'] or '',
                    "category": row['category'] or '',
                    "repo_owner": row['repo_owner'] or '',
                    "repo_name": row['repo_name'] or '',
                    "tool_type": "tool",
                    "inputs": json.loads(row['inputs']) if row['inputs'] else [],
                    "outputs": json.loads(row['outputs']) if row['outputs'] else [],
                    "requirements": json.loads(row['requirements']) if row['requirements'] else [],
                    "parameters": json.loads(row['parameters']) if row['parameters'] else [],
                    "help_text": json.loads(row['help_text']) if row['help_text'] else {},
                    "edam_operations": [],
                    "edam_topics": []
                }

                self.tool_index[tool_id] = tool_info
                self._index_tool_by_category(tool_id, tool_info)

    def _build_from_galaxy_toolbox(self):
        """Build from Galaxy's actual toolbox (fallback method)."""
        if not self.galaxy_app:
            return

        try:
            toolbox = self.galaxy_app.toolbox

            for tool_id, tool in toolbox.tools():
                if tool and hasattr(tool, 'name'):
                    tool_info = self._extract_tool_info(tool)
                    self.tool_index[tool_id] = tool_info
                    self._index_tool_by_category(tool_id, tool_info)

            log.info(f"Built tool index from Galaxy toolbox with {len(self.tool_index)} tools")

        except Exception as e:
            log.error(f"Could not build tool index from Galaxy toolbox: {e}")
    
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