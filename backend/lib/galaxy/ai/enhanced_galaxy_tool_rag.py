"""
Enhanced RAG-based Galaxy Tool Discovery System

Integrates with updated Galaxy tool database (9,103 tools + 122 datasets)
to provide accurate tool and dataset recommendations with compatibility mapping.

Updates:
- Supports dataset discovery and recommendations
- Uses FTS5 full-text search for better matching
- Leverages dataset-tool compatibility mappings
- Uses cleaned tool names from v3 integration
"""

import json
import logging
import sqlite3
from pathlib import Path
from typing import Dict, List, Any, Optional, Tuple
from collections import defaultdict

log = logging.getLogger(__name__)


class EnhancedGalaxyToolRAG:
    """Enhanced RAG system for Galaxy tool and dataset discovery."""

    def __init__(self, galaxy_app=None, db_path=None):
        self.galaxy_app = galaxy_app
        self.tool_index = {}
        self.dataset_index = {}
        self.category_index = {}
        self.dataset_tool_mapping = defaultdict(list)  # dataset_id -> [compatible_tool_ids]

        # Set database path
        if db_path is None:
            db_path = str(Path(__file__).parent.parent.parent.parent / "galaxy_ai_tools.db")
        self.db_path = db_path

        # Build enhanced index
        self._build_enhanced_index()

    def _build_enhanced_index(self):
        """Build searchable index with datasets and tool-dataset mappings."""
        try:
            if Path(self.db_path).exists():
                self._load_from_enhanced_database()
                log.info(f"Loaded {len(self.tool_index)} tools and {len(self.dataset_index)} datasets")
            else:
                log.error(f"Database not found at {self.db_path}")
        except Exception as e:
            log.error(f"Could not build enhanced index: {e}")

    def _load_from_enhanced_database(self):
        """Load tools and datasets from updated database schema."""
        with sqlite3.connect(self.db_path) as conn:
            conn.row_factory = sqlite3.Row
            cursor = conn.cursor()

            # Load tools (is_dataset = 0 or NULL)
            cursor.execute("""
                SELECT tool_id, name, version, category, repo_owner, repo_name,
                       rawText, url, created_at, updated_at, data_version, is_dataset
                FROM tools
                WHERE is_dataset IS NULL OR is_dataset = 0
            """)

            for row in cursor.fetchall():
                tool_id = row['tool_id']
                tool_info = {
                    "id": tool_id,
                    "name": row['name'] or '',
                    "version": row['version'] or '',
                    "category": row['category'] or '',
                    "repo_owner": row['repo_owner'] or '',
                    "repo_name": row['repo_name'] or '',
                    "description": (row['rawText'] or '')[:500],  # First 500 chars
                    "url": row['url'] or '',
                    "data_version": row['data_version'],
                    "tool_type": "tool",
                    "is_dataset": False
                }
                self.tool_index[tool_id] = tool_info
                self._index_by_category(tool_id, tool_info)

            # Load datasets (is_dataset = 1)
            cursor.execute("""
                SELECT tool_id, name, version, category, repo_owner, repo_name,
                       rawText, url, dataset_metadata, created_at, updated_at
                FROM tools
                WHERE is_dataset = 1
            """)

            for row in cursor.fetchall():
                dataset_id = row['tool_id']
                metadata = json.loads(row['dataset_metadata']) if row['dataset_metadata'] else {}

                dataset_info = {
                    "id": dataset_id,
                    "name": row['name'] or '',
                    "version": row['version'] or '1.0.0',
                    "category": row['category'] or '',
                    "description": (row['rawText'] or '')[:500],
                    "url": row['url'] or '',
                    "tool_type": "dataset",
                    "is_dataset": True,
                    "metadata": metadata,
                    "format": metadata.get('format', 'unknown'),
                    "data_category": metadata.get('category', 'unknown'),
                    "use_cases": metadata.get('use_cases', []),
                    "index_columns": metadata.get('index_columns', []),
                    "access_method": metadata.get('access_method', 'unknown'),
                    "compatible_tools_count": metadata.get('compatible_tools_count', 0)
                }
                self.dataset_index[dataset_id] = dataset_info
                self._index_by_category(dataset_id, dataset_info)

            # Load dataset-tool compatibility mappings
            cursor.execute("""
                SELECT dataset_tool_id, target_tool_id, parameter_name,
                       confidence, reasoning
                FROM dataset_tool_mapping
            """)

            for row in cursor.fetchall():
                dataset_id = row['dataset_tool_id']
                mapping = {
                    "tool_id": row['target_tool_id'],
                    "parameter_name": row['parameter_name'],
                    "confidence": row['confidence'],
                    "reasoning": row['reasoning']
                }
                self.dataset_tool_mapping[dataset_id].append(mapping)

    def _index_by_category(self, item_id: str, item_info: Dict[str, Any]):
        """Index items by functional categories."""
        categories = self._categorize_item(item_info)
        for category in categories:
            if category not in self.category_index:
                self.category_index[category] = []
            self.category_index[category].append(item_id)

    def _categorize_item(self, item_info: Dict[str, Any]) -> List[str]:
        """Categorize item based on name, description, and functionality."""
        categories = []

        # Use actual category if available
        if item_info.get("category"):
            categories.append(item_info["category"].lower().replace(' ', '_'))

        # Add derived categories from content
        name_lower = item_info["name"].lower()
        desc_lower = item_info.get("description", "").lower()
        text = f"{name_lower} {desc_lower}"

        # Common bioinformatics categories
        category_keywords = {
            "quality_control": ["fastqc", "quality", "qc", "trim", "filter"],
            "alignment": ["align", "map", "bwa", "bowtie", "hisat", "star", "minimap"],
            "variant_calling": ["variant", "snp", "vcf", "gatk", "freebayes", "mutation"],
            "rna_seq": ["rna-seq", "rna seq", "rnaseq", "expression", "deseq", "edger"],
            "assembly": ["assembly", "assembl", "spades", "velvet", "canu"],
            "annotation": ["annotat", "predict", "gene", "feature"],
            "visualization": ["plot", "graph", "chart", "visual", "heatmap"],
            "statistics": ["statistical", "stats", "analysis", "regression"],
            "proteomics": ["protein", "peptide", "mass spec", "proteom"],
            "metagenomics": ["metagen", "microbiome", "16s", "amplicon"],
            "data_management": ["data", "dataset", "table", "file", "import", "export"]
        }

        for cat, keywords in category_keywords.items():
            if any(kw in text for kw in keywords):
                categories.append(cat)

        return categories if categories else ["general"]

    def search_tools(self, query: str, data_types: List[str] = None,
                    category: str = None, limit: int = 15,
                    include_datasets: bool = False) -> List[Dict]:
        """
        Search for tools using FTS5 full-text search and filters.

        Args:
            query: Search query
            data_types: Filter by data types (e.g., ['fastq', 'bam'])
            category: Filter by category
            limit: Maximum results
            include_datasets: Whether to include datasets in results
        """
        results = []

        try:
            with sqlite3.connect(self.db_path) as conn:
                conn.row_factory = sqlite3.Row
                cursor = conn.cursor()

                # Build FTS query
                fts_query = query.replace("'", "''")  # Escape quotes

                # Build SQL with filters
                sql_parts = ["""
                    SELECT t.tool_id, t.name, t.category, t.is_dataset,
                           t.rawText, t.version, t.dataset_metadata,
                           bm25(tools_fts) as relevance_score
                    FROM tools t
                    JOIN tools_fts ON t.tool_id = tools_fts.tool_id
                    WHERE tools_fts MATCH ?
                """]
                params = [fts_query]

                # Filter by dataset flag
                if not include_datasets:
                    sql_parts.append("AND (t.is_dataset IS NULL OR t.is_dataset = 0)")

                # Filter by category if specified
                if category:
                    sql_parts.append("AND t.category LIKE ?")
                    params.append(f"%{category}%")

                sql_parts.append("ORDER BY relevance_score DESC LIMIT ?")
                params.append(limit)

                sql = " ".join(sql_parts)
                cursor.execute(sql, params)

                for row in cursor.fetchall():
                    tool_id = row['tool_id']
                    is_dataset = row['is_dataset'] == 1

                    if is_dataset:
                        metadata = json.loads(row['dataset_metadata']) if row['dataset_metadata'] else {}
                        result = {
                            "id": tool_id,
                            "name": row['name'],
                            "category": row['category'],
                            "description": (row['rawText'] or '')[:200],
                            "type": "dataset",
                            "metadata": metadata,
                            "relevance_score": row['relevance_score']
                        }
                    else:
                        result = {
                            "id": tool_id,
                            "name": row['name'],
                            "category": row['category'],
                            "description": (row['rawText'] or '')[:200],
                            "version": row['version'],
                            "type": "tool",
                            "relevance_score": row['relevance_score']
                        }

                    results.append(result)

        except Exception as e:
            log.error(f"FTS search failed: {e}")
            # Fallback to basic search
            results = self._fallback_search(query, category, limit, include_datasets)

        return results

    def _fallback_search(self, query: str, category: str, limit: int, include_datasets: bool) -> List[Dict]:
        """Fallback search using simple text matching."""
        query_lower = query.lower()
        results = []

        # Search tools
        for tool_id, tool_info in self.tool_index.items():
            if category and category.lower() not in tool_info.get("category", "").lower():
                continue

            text = f"{tool_info['name']} {tool_info.get('description', '')}".lower()
            if query_lower in text:
                results.append({
                    "id": tool_id,
                    "name": tool_info["name"],
                    "description": tool_info.get("description", "")[:200],
                    "category": tool_info.get("category", ""),
                    "type": "tool",
                    "relevance_score": 1.0
                })

        # Search datasets if requested
        if include_datasets:
            for dataset_id, dataset_info in self.dataset_index.items():
                text = f"{dataset_info['name']} {dataset_info.get('description', '')}".lower()
                if query_lower in text:
                    results.append({
                        "id": dataset_id,
                        "name": dataset_info["name"],
                        "description": dataset_info.get("description", "")[:200],
                        "category": dataset_info.get("category", ""),
                        "type": "dataset",
                        "metadata": dataset_info.get("metadata", {}),
                        "relevance_score": 1.0
                    })

        return results[:limit]

    def search_datasets(self, query: str, use_case: str = None,
                       data_format: str = None, limit: int = 10) -> List[Dict]:
        """
        Search for datasets with specific filters.

        Args:
            query: Search query
            use_case: Filter by use case (e.g., 'drug discovery')
            data_format: Filter by format (e.g., 'tsv', 'csv')
            limit: Maximum results
        """
        results = []
        query_lower = query.lower()

        for dataset_id, dataset_info in self.dataset_index.items():
            # Text matching
            text = f"{dataset_info['name']} {dataset_info.get('description', '')}".lower()
            if query_lower not in text:
                continue

            # Use case filter
            if use_case:
                use_cases = [uc.lower() for uc in dataset_info.get('use_cases', [])]
                if use_case.lower() not in use_cases:
                    continue

            # Format filter
            if data_format:
                if data_format.lower() != dataset_info.get('format', '').lower():
                    continue

            results.append({
                "id": dataset_id,
                "name": dataset_info["name"],
                "description": dataset_info.get("description", "")[:200],
                "category": dataset_info.get("category", ""),
                "format": dataset_info.get("format", ""),
                "use_cases": dataset_info.get("use_cases", []),
                "compatible_tools_count": dataset_info.get("compatible_tools_count", 0),
                "type": "dataset"
            })

        return results[:limit]

    def get_compatible_tools(self, dataset_id: str, min_confidence: float = 0.5) -> List[Dict]:
        """
        Get tools compatible with a specific dataset.

        Args:
            dataset_id: Dataset tool_id
            min_confidence: Minimum confidence threshold
        """
        compatible_tools = []

        for mapping in self.dataset_tool_mapping.get(dataset_id, []):
            if mapping['confidence'] >= min_confidence:
                tool_id = mapping['tool_id']
                tool_info = self.tool_index.get(tool_id, {})

                if tool_info:
                    compatible_tools.append({
                        "id": tool_id,
                        "name": tool_info.get("name", ""),
                        "category": tool_info.get("category", ""),
                        "parameter_name": mapping['parameter_name'],
                        "confidence": mapping['confidence'],
                        "reasoning": mapping['reasoning']
                    })

        return compatible_tools

    def recommend_dataset_for_tools(self, tool_ids: List[str]) -> List[Dict]:
        """
        Recommend datasets that work well with given tools.

        Args:
            tool_ids: List of tool IDs in workflow
        """
        dataset_scores = defaultdict(lambda: {"score": 0, "matching_tools": []})

        # Score each dataset based on how many tools it's compatible with
        for dataset_id, mappings in self.dataset_tool_mapping.items():
            for mapping in mappings:
                if mapping['tool_id'] in tool_ids:
                    dataset_scores[dataset_id]["score"] += mapping['confidence']
                    dataset_scores[dataset_id]["matching_tools"].append(mapping['tool_id'])

        # Build recommendations
        recommendations = []
        for dataset_id, score_info in sorted(dataset_scores.items(),
                                            key=lambda x: x[1]["score"],
                                            reverse=True)[:10]:
            dataset_info = self.dataset_index.get(dataset_id, {})
            if dataset_info:
                recommendations.append({
                    "id": dataset_id,
                    "name": dataset_info.get("name", ""),
                    "description": dataset_info.get("description", "")[:200],
                    "format": dataset_info.get("format", ""),
                    "compatibility_score": score_info["score"],
                    "matching_tools": score_info["matching_tools"],
                    "use_cases": dataset_info.get("use_cases", [])
                })

        return recommendations

    def get_tool_info(self, tool_id: str) -> Optional[Dict]:
        """Get detailed information about a specific tool."""
        return self.tool_index.get(tool_id) or self.dataset_index.get(tool_id)

    def get_stats(self) -> Dict[str, Any]:
        """Get statistics about the tool index."""
        return {
            "total_tools": len(self.tool_index),
            "total_datasets": len(self.dataset_index),
            "total_items": len(self.tool_index) + len(self.dataset_index),
            "categories": len(self.category_index),
            "dataset_tool_mappings": sum(len(v) for v in self.dataset_tool_mapping.values()),
            "datasets_with_mappings": len([d for d in self.dataset_tool_mapping if self.dataset_tool_mapping[d]])
        }
