"""
Tool Discovery System for Galaxy AI Assistant

Intelligent discovery and indexing of Galaxy tools with semantic understanding.
"""

import json
import re
from typing import Dict, List, Any, Optional, Set, Tuple
from collections import defaultdict
from datetime import datetime
import sqlite3
from pathlib import Path

from .types import Tool, DataType, TaskType, IntentType
from .config import AIConfig
from .llm_client import LLMClient


class ToolIndexer:
    """Indexes Galaxy tools with semantic metadata for intelligent discovery."""
    
    def __init__(self, config: AIConfig, db_path: Optional[str] = None):
        self.config = config
        self.llm_client = LLMClient(config)
        self.db_path = db_path or "galaxy_ai_tools.db"
        self.init_database()
        
        # EDAM ontology mappings for semantic understanding
        self.edam_operations = self._load_edam_operations()
        self.edam_topics = self._load_edam_topics()
        
        # Tool category mappings
        self.tool_categories = {
            'quality_control': ['fastqc', 'multiqc', 'fastp', 'qualimap'],
            'alignment': ['bwa', 'bowtie', 'hisat2', 'star', 'minimap2'],
            'assembly': ['spades', 'velvet', 'canu', 'flye', 'unicycler'],
            'variant_calling': ['freebayes', 'gatk', 'bcftools', 'varscan'],
            'rna_seq': ['hisat2', 'star', 'kallisto', 'salmon', 'featurecounts', 'deseq2'],
            'annotation': ['prokka', 'augustus', 'maker', 'snpeff', 'vep'],
            'visualization': ['igv', 'jbrowse', 'ggplot2', 'plotly'],
            'preprocessing': ['cutadapt', 'trimmomatic', 'trim_galore', 'fastp']
        }
    
    def init_database(self):
        """Initialize the tool index database."""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        # Create tools table
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS tools (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                version TEXT,
                description TEXT,
                category TEXT,
                inputs TEXT,  -- JSON
                outputs TEXT, -- JSON
                requirements TEXT, -- JSON
                edam_operations TEXT, -- JSON
                edam_topics TEXT, -- JSON
                citations TEXT, -- JSON
                popularity_score REAL DEFAULT 0.0,
                usage_count INTEGER DEFAULT 0,
                last_updated TIMESTAMP,
                semantic_embedding TEXT, -- JSON for vector embeddings
                tags TEXT -- JSON
            )
        """)
        
        # Create tool compatibility table
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS tool_compatibility (
                tool_id TEXT,
                data_type TEXT,
                compatibility_type TEXT, -- 'input' or 'output'
                confidence REAL,
                FOREIGN KEY (tool_id) REFERENCES tools (id)
            )
        """)
        
        # Create tool usage patterns table
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS tool_usage_patterns (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                tool_sequence TEXT, -- JSON array of tool IDs
                frequency INTEGER DEFAULT 1,
                context TEXT, -- Description of usage context
                task_type TEXT,
                success_rate REAL DEFAULT 1.0,
                last_used TIMESTAMP
            )
        """)
        
        # Create indexes for faster queries
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_tools_category ON tools (category)")
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_tools_popularity ON tools (popularity_score)")
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_compatibility_tool ON tool_compatibility (tool_id)")
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_compatibility_type ON tool_compatibility (data_type)")
        
        conn.commit()
        conn.close()
    
    def index_tool(self, tool: Tool, force_reindex: bool = False) -> bool:
        """Index a single tool with semantic metadata."""
        
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        try:
            # Check if tool already exists
            cursor.execute("SELECT id FROM tools WHERE id = ?", (tool.id,))
            exists = cursor.fetchone() is not None
            
            if exists and not force_reindex:
                return True
            
            # Generate semantic metadata
            category = self._categorize_tool(tool)
            tags = self._generate_tool_tags(tool)
            semantic_embedding = self._generate_semantic_embedding(tool)
            
            # Insert or update tool
            if exists:
                cursor.execute("""
                    UPDATE tools SET 
                        name=?, version=?, description=?, category=?, inputs=?, outputs=?,
                        requirements=?, edam_operations=?, edam_topics=?, citations=?,
                        last_updated=?, semantic_embedding=?, tags=?
                    WHERE id=?
                """, (
                    tool.name, tool.version, tool.description, category,
                    json.dumps(tool.inputs), json.dumps(tool.outputs),
                    json.dumps(tool.requirements), json.dumps(tool.edam_operations),
                    json.dumps(tool.edam_topics), json.dumps(tool.citations),
                    datetime.now().isoformat(), json.dumps(semantic_embedding),
                    json.dumps(tags), tool.id
                ))
            else:
                cursor.execute("""
                    INSERT INTO tools (
                        id, name, version, description, category, inputs, outputs,
                        requirements, edam_operations, edam_topics, citations,
                        last_updated, semantic_embedding, tags
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, (
                    tool.id, tool.name, tool.version, tool.description, category,
                    json.dumps(tool.inputs), json.dumps(tool.outputs),
                    json.dumps(tool.requirements), json.dumps(tool.edam_operations),
                    json.dumps(tool.edam_topics), json.dumps(tool.citations),
                    datetime.now().isoformat(), json.dumps(semantic_embedding),
                    json.dumps(tags)
                ))
            
            # Index data type compatibility
            self._index_tool_compatibility(cursor, tool)
            
            conn.commit()
            return True
            
        except Exception as e:
            print(f"Error indexing tool {tool.id}: {e}")
            conn.rollback()
            return False
        finally:
            conn.close()
    
    def _categorize_tool(self, tool: Tool) -> str:
        """Categorize a tool based on its characteristics."""
        
        tool_text = f"{tool.name} {tool.description}".lower()
        
        # Check predefined categories
        for category, tool_names in self.tool_categories.items():
            if any(name in tool.id.lower() or name in tool_text for name in tool_names):
                return category
        
        # Use EDAM operations for categorization
        if tool.edam_operations:
            operation_categories = {
                'operation_3218': 'quality_control',  # Sequencing quality control
                'operation_3198': 'alignment',        # Read mapping
                'operation_0525': 'assembly',         # Genome assembly
                'operation_3227': 'variant_calling',  # Variant calling
                'operation_3223': 'rna_seq',         # Differential expression
                'operation_0362': 'annotation',      # Genome annotation
                'operation_0337': 'visualization'    # Visualisation
            }
            
            for operation in tool.edam_operations:
                if operation in operation_categories:
                    return operation_categories[operation]
        
        # Fallback to LLM categorization
        return self._llm_categorize_tool(tool)
    
    def _llm_categorize_tool(self, tool: Tool) -> str:
        """Use LLM to categorize a tool."""
        categories = list(self.tool_categories.keys())
        
        prompt = f"""
        Categorize this bioinformatics tool into one of these categories:
        
        Categories: {', '.join(categories)}
        
        Tool: {tool.name}
        Description: {tool.description}
        Inputs: {[inp.get('type', 'unknown') for inp in tool.inputs]}
        Outputs: {[out.get('type', 'unknown') for out in tool.outputs]}
        
        Respond with just the category name, no explanation.
        """
        
        try:
            response = self.llm_client.generate(prompt, max_tokens=50).strip().lower()
            if response in categories:
                return response
        except Exception as e:
            print(f"LLM categorization failed: {e}")
        
        return 'unknown'
    
    def _generate_tool_tags(self, tool: Tool) -> List[str]:
        """Generate semantic tags for a tool."""
        tags = []
        
        # Add category-based tags
        category = self._categorize_tool(tool)
        tags.append(category)
        
        # Add data type tags
        for inp in tool.inputs:
            input_type = inp.get('type', '')
            if input_type:
                tags.append(f"input_{input_type}")
        
        for out in tool.outputs:
            output_type = out.get('type', '')
            if output_type:
                tags.append(f"output_{output_type}")
        
        # Add technology tags
        tool_text = f"{tool.name} {tool.description}".lower()
        
        tech_tags = {
            'illumina': ['illumina', 'sanger'],
            'nanopore': ['nanopore', 'oxford'],
            'pacbio': ['pacbio', 'smrt'],
            'rna_seq': ['rna-seq', 'transcriptome'],
            'dna_seq': ['dna-seq', 'genome', 'wgs'],
            'single_cell': ['single-cell', 'scrnaseq'],
            'paired_end': ['paired-end', 'paired end'],
            'single_end': ['single-end', 'single end']
        }
        
        for tag, keywords in tech_tags.items():
            if any(keyword in tool_text for keyword in keywords):
                tags.append(tag)
        
        # Add requirement-based tags
        for req in tool.requirements:
            if isinstance(req, str):
                # Extract package names
                package = req.split('==')[0].split('>=')[0].split('<=')[0]
                tags.append(f"requires_{package}")
        
        return list(set(tags))  # Remove duplicates
    
    def _generate_semantic_embedding(self, tool: Tool) -> List[float]:
        """Generate semantic embedding for tool (placeholder implementation)."""
        # In a real implementation, this would use a proper embedding model
        # For now, return a simple hash-based embedding
        
        text = f"{tool.name} {tool.description}"
        # Simple hash-based embedding (replace with proper embeddings)
        embedding = [float(hash(text + str(i)) % 1000) / 1000.0 for i in range(128)]
        return embedding
    
    def _index_tool_compatibility(self, cursor, tool: Tool):
        """Index tool data type compatibility."""
        
        # Clear existing compatibility data
        cursor.execute("DELETE FROM tool_compatibility WHERE tool_id = ?", (tool.id,))
        
        # Index input compatibility
        for inp in tool.inputs:
            input_type = inp.get('type', '')
            if input_type:
                cursor.execute("""
                    INSERT INTO tool_compatibility (tool_id, data_type, compatibility_type, confidence)
                    VALUES (?, ?, 'input', 1.0)
                """, (tool.id, input_type))
        
        # Index output compatibility
        for out in tool.outputs:
            output_type = out.get('type', '')
            if output_type:
                cursor.execute("""
                    INSERT INTO tool_compatibility (tool_id, data_type, compatibility_type, confidence)
                    VALUES (?, ?, 'output', 1.0)
                """, (tool.id, output_type))
    
    def _load_edam_operations(self) -> Dict[str, str]:
        """Load EDAM operation definitions."""
        # Simplified EDAM operations mapping
        return {
            'operation_3218': 'Sequencing quality control',
            'operation_3198': 'Read mapping',
            'operation_0525': 'Genome assembly',
            'operation_3227': 'Variant calling',
            'operation_3223': 'Differential gene expression analysis',
            'operation_0362': 'Genome annotation',
            'operation_0337': 'Visualisation',
            'operation_2403': 'Sequence analysis',
            'operation_0292': 'Sequence alignment',
            'operation_0310': 'Sequence assembly'
        }
    
    def _load_edam_topics(self) -> Dict[str, str]:
        """Load EDAM topic definitions."""
        return {
            'topic_0622': 'Genomics',
            'topic_3170': 'RNA-seq',
            'topic_0080': 'Sequence analysis',
            'topic_0102': 'Mapping',
            'topic_0196': 'Sequence assembly',
            'topic_3053': 'Genetics',
            'topic_0092': 'Data visualisation',
            'topic_3168': 'Sequencing'
        }


class ToolDiscoveryEngine:
    """Intelligent tool discovery engine."""
    
    def __init__(self, config: AIConfig, indexer: ToolIndexer):
        self.config = config
        self.indexer = indexer
        self.llm_client = LLMClient(config)
    
    def discover_tools(
        self,
        task_description: str,
        input_types: List[str],
        output_types: List[str],
        task_type: Optional[TaskType] = None,
        intent_type: Optional[IntentType] = None
    ) -> List[Tool]:
        """Discover relevant tools for a given task."""
        
        # Multi-strategy discovery
        discovered_tools = []
        
        # Strategy 1: Data type compatibility
        type_tools = self._discover_by_data_types(input_types, output_types)
        discovered_tools.extend(type_tools)
        
        # Strategy 2: Category-based discovery
        if task_type:
            category_tools = self._discover_by_category(task_type)
            discovered_tools.extend(category_tools)
        
        # Strategy 3: Semantic similarity
        semantic_tools = self._discover_by_semantics(task_description)
        discovered_tools.extend(semantic_tools)
        
        # Strategy 4: Usage pattern matching
        pattern_tools = self._discover_by_patterns(task_description, input_types)
        discovered_tools.extend(pattern_tools)
        
        # Deduplicate and rank
        unique_tools = self._deduplicate_tools(discovered_tools)
        ranked_tools = self._rank_discovered_tools(unique_tools, task_description, input_types, output_types)
        
        return ranked_tools[:self.config.max_tools_per_task]
    
    def _discover_by_data_types(self, input_types: List[str], output_types: List[str]) -> List[Tool]:
        """Discover tools based on input/output data type compatibility."""
        tools = []
        
        conn = sqlite3.connect(self.indexer.db_path)
        cursor = conn.cursor()
        
        try:
            # Find tools that accept the input types
            input_placeholders = ','.join(['?' for _ in input_types])
            cursor.execute(f"""
                SELECT DISTINCT t.* FROM tools t
                JOIN tool_compatibility tc ON t.id = tc.tool_id
                WHERE tc.data_type IN ({input_placeholders}) 
                AND tc.compatibility_type = 'input'
            """, input_types)
            
            rows = cursor.fetchall()
            for row in rows:
                tool = self._row_to_tool(row)
                tools.append(tool)
                
        finally:
            conn.close()
        
        return tools
    
    def _discover_by_category(self, task_type: TaskType) -> List[Tool]:
        """Discover tools based on task category."""
        category_map = {
            TaskType.QUALITY_CONTROL: 'quality_control',
            TaskType.GENOMICS: 'alignment',
            TaskType.ASSEMBLY: 'assembly',
            TaskType.TRANSCRIPTOMICS: 'rna_seq',
            TaskType.ANNOTATION: 'annotation',
            TaskType.VISUALIZATION: 'visualization'
        }
        
        category = category_map.get(task_type)
        if not category:
            return []
        
        conn = sqlite3.connect(self.indexer.db_path)
        cursor = conn.cursor()
        
        try:
            cursor.execute("SELECT * FROM tools WHERE category = ?", (category,))
            rows = cursor.fetchall()
            return [self._row_to_tool(row) for row in rows]
        finally:
            conn.close()
    
    def _discover_by_semantics(self, task_description: str) -> List[Tool]:
        """Discover tools using semantic similarity."""
        # In a real implementation, this would use vector similarity search
        # For now, use keyword matching with LLM assistance
        
        conn = sqlite3.connect(self.indexer.db_path)
        cursor = conn.cursor()
        
        try:
            cursor.execute("SELECT * FROM tools")
            all_tools = [self._row_to_tool(row) for row in cursor.fetchall()]
            
            # Use LLM to find semantically similar tools
            relevant_tools = self._llm_filter_tools(task_description, all_tools)
            return relevant_tools
            
        finally:
            conn.close()
    
    def _discover_by_patterns(self, task_description: str, input_types: List[str]) -> List[Tool]:
        """Discover tools based on usage patterns."""
        # This would analyze historical usage patterns
        # For now, return empty list (to be implemented with usage data)
        return []
    
    def _llm_filter_tools(self, task_description: str, tools: List[Tool]) -> List[Tool]:
        """Use LLM to filter tools based on semantic relevance."""
        
        if len(tools) > 20:  # Limit to avoid token limits
            tools = tools[:20]
        
        tool_list = []
        for tool in tools:
            tool_list.append(f"{tool.id}: {tool.name} - {tool.description}")
        
        prompt = f"""
        Given this task description: "{task_description}"
        
        Which of these tools are most relevant? Rank them by relevance.
        
        Available tools:
        {chr(10).join(tool_list)}
        
        Respond with a JSON array of the top 5 most relevant tool IDs in order of relevance:
        ["tool_id1", "tool_id2", "tool_id3", "tool_id4", "tool_id5"]
        """
        
        try:
            response = self.llm_client.generate(prompt)
            tool_ids = json.loads(response)
            
            relevant_tools = []
            for tool_id in tool_ids:
                tool = next((t for t in tools if t.id == tool_id), None)
                if tool:
                    relevant_tools.append(tool)
            
            return relevant_tools
            
        except Exception as e:
            print(f"LLM tool filtering failed: {e}")
            return []
    
    def _deduplicate_tools(self, tools: List[Tool]) -> List[Tool]:
        """Remove duplicate tools."""
        seen = set()
        unique_tools = []
        
        for tool in tools:
            if tool.id not in seen:
                seen.add(tool.id)
                unique_tools.append(tool)
        
        return unique_tools
    
    def _rank_discovered_tools(
        self,
        tools: List[Tool],
        task_description: str,
        input_types: List[str],
        output_types: List[str]
    ) -> List[Tool]:
        """Rank discovered tools by relevance."""
        
        def score_tool(tool: Tool) -> float:
            score = 0.0
            
            # Data type compatibility score
            input_compatible = any(
                any(inp.get('type') == input_type for inp in tool.inputs)
                for input_type in input_types
            )
            output_compatible = any(
                any(out.get('type') == output_type for out in tool.outputs)
                for output_type in output_types
            )
            
            if input_compatible:
                score += 0.4
            if output_compatible:
                score += 0.3
            
            # Popularity score (from database)
            score += getattr(tool, 'popularity_score', 0.0) * 0.2
            
            # Description relevance (simple keyword matching)
            task_words = set(task_description.lower().split())
            tool_words = set(tool.description.lower().split())
            relevance = len(task_words & tool_words) / max(len(task_words), 1)
            score += relevance * 0.1
            
            return score
        
        return sorted(tools, key=score_tool, reverse=True)
    
    def _row_to_tool(self, row) -> Tool:
        """Convert database row to Tool object."""
        return Tool(
            id=row[0],
            name=row[1],
            version=row[2] or "unknown",
            description=row[3] or "",
            inputs=json.loads(row[5]) if row[5] else [],
            outputs=json.loads(row[6]) if row[6] else [],
            requirements=json.loads(row[7]) if row[7] else [],
            edam_operations=json.loads(row[8]) if row[8] else [],
            edam_topics=json.loads(row[9]) if row[9] else [],
            citations=json.loads(row[10]) if row[10] else []
        )
    
    def update_tool_usage(self, tool_id: str, success: bool = True):
        """Update tool usage statistics."""
        conn = sqlite3.connect(self.indexer.db_path)
        cursor = conn.cursor()
        
        try:
            # Update usage count
            cursor.execute("""
                UPDATE tools SET 
                    usage_count = usage_count + 1,
                    popularity_score = popularity_score + ?
                WHERE id = ?
            """, (0.1 if success else -0.05, tool_id))
            
            conn.commit()
            
        finally:
            conn.close()