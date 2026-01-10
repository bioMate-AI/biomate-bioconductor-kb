"""
Tool Knowledge Provider

Provides citations, best practices, and parameter recommendations for bioinformatics tools.
Integrates with the tool_knowledge table in galaxy_ai_tools.db.
"""

import sqlite3
import json
import logging
from typing import Dict, List, Any, Optional
from dataclasses import dataclass, field, asdict
from functools import lru_cache
from pathlib import Path

log = logging.getLogger(__name__)


@dataclass
class Citation:
    """Structured citation data."""
    doi: Optional[str] = None
    pmid: Optional[str] = None
    title: Optional[str] = None
    authors: List[str] = field(default_factory=list)
    journal: Optional[str] = None
    year: Optional[int] = None
    url: Optional[str] = None

    def format_apa(self) -> str:
        """Format citation in APA style."""
        if not self.authors:
            author_str = "Unknown"
        elif len(self.authors) == 1:
            author_str = self.authors[0]
        elif len(self.authors) == 2:
            author_str = f"{self.authors[0]} & {self.authors[1]}"
        else:
            author_str = f"{self.authors[0]} et al."

        year_str = f"({self.year})" if self.year else "(n.d.)"
        title_str = self.title or "Untitled"
        journal_str = f" {self.journal}." if self.journal else ""

        return f"{author_str} {year_str}. {title_str}.{journal_str}"

    def format_short(self) -> str:
        """Format as short citation (Author et al., Year)."""
        if not self.authors:
            author_str = "Unknown"
        else:
            # Extract last name from first author
            # Authors are typically "Lastname Initials" or "Firstname Lastname"
            first_author = self.authors[0]
            if first_author:
                parts = first_author.split()
                # If last part is short (initials), use first part as last name
                if len(parts) > 1 and len(parts[-1]) <= 2:
                    last_name = parts[0]  # "Dobin A" -> "Dobin"
                else:
                    last_name = parts[-1]  # "John Smith" -> "Smith"
            else:
                last_name = "Unknown"
            author_str = f"{last_name} et al." if len(self.authors) > 1 else last_name

        year_str = str(self.year) if self.year else "n.d."
        return f"{author_str}, {year_str}"

    def format_bibtex(self, key: str = "tool") -> str:
        """Format citation in BibTeX format."""
        authors_bibtex = " and ".join(self.authors) if self.authors else "Unknown"
        return f"""@article{{{key},
    author = {{{authors_bibtex}}},
    title = {{{self.title or 'Untitled'}}},
    journal = {{{self.journal or 'Unknown'}}},
    year = {{{self.year or 'n.d.'}}},
    doi = {{{self.doi or ''}}}
}}"""

    def to_dict(self) -> Dict[str, Any]:
        """Return dict with all fields including formatted versions for API."""
        base = asdict(self)
        # Add formatted versions for frontend consumption
        base['formatted_apa'] = self.format_apa()
        base['formatted_short'] = self.format_short()
        base['formatted_bibtex'] = self.format_bibtex()
        return base

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "Citation":
        if not data:
            return None
        return cls(
            doi=data.get("doi"),
            pmid=data.get("pmid"),
            title=data.get("title"),
            authors=data.get("authors", []),
            journal=data.get("journal"),
            year=data.get("year"),
            url=data.get("url")
        )


@dataclass
class ParameterRecommendation:
    """Parameter recommendation with context."""
    name: str
    recommended_value: Any
    description: str
    confidence: float = 0.8  # 0-1 confidence score
    source: str = "best_practice"  # 'benchmark', 'protocol', 'manual', 'best_practice'
    context: Optional[str] = None  # When this recommendation applies

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


@dataclass
class ToolKnowledge:
    """Complete knowledge about a tool."""
    tool_name: str
    tool_id: Optional[str] = None
    category: Optional[str] = None

    # Citation
    citation: Optional[Citation] = None
    benchmark_papers: List[Citation] = field(default_factory=list)
    review_papers: List[Citation] = field(default_factory=list)

    # Best practices
    recommended_parameters: Dict[str, ParameterRecommendation] = field(default_factory=dict)
    use_cases: List[str] = field(default_factory=list)
    limitations: List[str] = field(default_factory=list)
    alternatives: List[str] = field(default_factory=list)

    # Confidence scoring
    citation_quality_score: float = 0.5  # 0-1, higher = more authoritative
    knowledge_completeness: float = 0.5  # 0-1, how complete is our knowledge

    def to_dict(self) -> Dict[str, Any]:
        return {
            "tool_name": self.tool_name,
            "tool_id": self.tool_id,
            "category": self.category,
            "citation": self.citation.to_dict() if self.citation else None,
            "benchmark_papers": [c.to_dict() for c in self.benchmark_papers],
            "review_papers": [c.to_dict() for c in self.review_papers],
            "recommended_parameters": {k: v.to_dict() for k, v in self.recommended_parameters.items()},
            "use_cases": self.use_cases,
            "limitations": self.limitations,
            "alternatives": self.alternatives,
            "citation_quality_score": self.citation_quality_score,
            "knowledge_completeness": self.knowledge_completeness
        }


class ToolKnowledgeProvider:
    """
    Provides citations and best practices for bioinformatics tools.

    Integrates with the tool_knowledge table to provide:
    - Primary citations (DOI, PMID, formatted references)
    - Recommended parameters with confidence scores
    - Use cases, limitations, and alternatives
    - Auto-generated methods section text
    """

    def __init__(self, db_path: str = None):
        """
        Initialize the provider.

        Args:
            db_path: Path to galaxy_ai_tools.db. If None, uses default location.
        """
        if db_path is None:
            # Default path relative to Galaxy root
            db_path = Path(__file__).parent.parent.parent.parent / "database" / "galaxy_ai_tools.db"

        self.db_path = str(db_path)
        self._cache: Dict[str, ToolKnowledge] = {}
        self._cache_size = 500

        log.info(f"ToolKnowledgeProvider initialized with db: {self.db_path}")

    def _get_connection(self) -> sqlite3.Connection:
        """Get database connection."""
        return sqlite3.connect(self.db_path)

    def _normalize_tool_name(self, tool_id_or_name: str) -> str:
        """Normalize tool identifier for lookup."""
        # Handle various formats: toolshed.g2.bx.psu.edu/repos/iuc/star/rna_star/2.7.10
        name = tool_id_or_name.lower().strip()

        # Extract tool name from full Galaxy tool ID
        if "/" in name:
            parts = name.split("/")
            # Try to find the actual tool name (usually after 'repos/owner/')
            for i, part in enumerate(parts):
                if part == "repos" and i + 2 < len(parts):
                    name = parts[i + 2]  # Skip owner, get tool name
                    break
            else:
                name = parts[-1]  # Fall back to last part

        # Remove version numbers
        if "_" in name and name.split("_")[-1].replace(".", "").isdigit():
            name = "_".join(name.split("_")[:-1])

        return name

    @lru_cache(maxsize=500)
    def get_tool_knowledge(self, tool_id_or_name: str) -> Optional[ToolKnowledge]:
        """
        Retrieve complete knowledge about a tool.

        Args:
            tool_id_or_name: Tool identifier or name

        Returns:
            ToolKnowledge object or None if not found
        """
        normalized_name = self._normalize_tool_name(tool_id_or_name)

        try:
            conn = self._get_connection()
            cursor = conn.cursor()

            # Try exact match first, then fuzzy match
            cursor.execute("""
                SELECT tool_name, tool_id, category, primary_citation,
                       benchmark_papers, review_papers, recommended_parameters,
                       use_cases, limitations, alternatives
                FROM tool_knowledge
                WHERE LOWER(tool_name) = ? OR LOWER(tool_id) LIKE ?
                LIMIT 1
            """, (normalized_name, f"%{normalized_name}%"))

            row = cursor.fetchone()
            conn.close()

            if not row:
                log.debug(f"No knowledge found for tool: {tool_id_or_name}")
                return None

            # Parse JSON fields
            primary_citation = self._parse_json(row[3])
            benchmark_papers = self._parse_json(row[4]) or []
            review_papers = self._parse_json(row[5]) or []
            recommended_params = self._parse_json(row[6]) or {}
            use_cases = self._parse_json(row[7]) or []
            limitations = self._parse_json(row[8]) or []
            alternatives = self._parse_json(row[9]) or []

            # Build ToolKnowledge object
            knowledge = ToolKnowledge(
                tool_name=row[0],
                tool_id=row[1],
                category=row[2],
                citation=Citation.from_dict(primary_citation) if primary_citation else None,
                benchmark_papers=[Citation.from_dict(p) for p in benchmark_papers if p],
                review_papers=[Citation.from_dict(p) for p in review_papers if p],
                use_cases=use_cases,
                limitations=limitations,
                alternatives=alternatives
            )

            # Parse recommended parameters
            for param_name, param_info in recommended_params.items():
                if isinstance(param_info, dict):
                    knowledge.recommended_parameters[param_name] = ParameterRecommendation(
                        name=param_name,
                        recommended_value=param_info.get("value", param_info),
                        description=str(param_info) if isinstance(param_info, str) else param_info.get("description", ""),
                        confidence=param_info.get("confidence", 0.8),
                        source=param_info.get("source", "best_practice")
                    )
                else:
                    # Simple key-value parameter
                    knowledge.recommended_parameters[param_name] = ParameterRecommendation(
                        name=param_name,
                        recommended_value=param_info,
                        description=str(param_info),
                        confidence=0.7
                    )

            # Calculate knowledge completeness
            completeness_factors = [
                1.0 if knowledge.citation else 0.0,
                0.2 if knowledge.use_cases else 0.0,
                0.2 if knowledge.limitations else 0.0,
                0.2 if knowledge.recommended_parameters else 0.0,
                0.1 if knowledge.alternatives else 0.0
            ]
            knowledge.knowledge_completeness = sum(completeness_factors) / 1.7

            # Calculate citation quality score
            if knowledge.citation:
                quality = 0.5
                if knowledge.citation.doi:
                    quality += 0.2
                if knowledge.citation.pmid:
                    quality += 0.2
                if knowledge.citation.year and knowledge.citation.year >= 2015:
                    quality += 0.1
                knowledge.citation_quality_score = min(1.0, quality)

            return knowledge

        except Exception as e:
            log.error(f"Error fetching tool knowledge for {tool_id_or_name}: {e}")
            return None

    def _parse_json(self, value: str) -> Any:
        """Safely parse JSON string."""
        if not value:
            return None
        try:
            return json.loads(value)
        except (json.JSONDecodeError, TypeError):
            return None

    def get_citation(self, tool_id_or_name: str) -> Optional[Citation]:
        """Get just the citation for a tool."""
        knowledge = self.get_tool_knowledge(tool_id_or_name)
        return knowledge.citation if knowledge else None

    def format_citation(self, tool_id_or_name: str, style: str = "short") -> Optional[str]:
        """
        Format citation in specified style.

        Args:
            tool_id_or_name: Tool identifier
            style: 'short', 'apa', or 'bibtex'

        Returns:
            Formatted citation string or None
        """
        citation = self.get_citation(tool_id_or_name)
        if not citation:
            return None

        if style == "apa":
            return citation.format_apa()
        elif style == "bibtex":
            return citation.format_bibtex(self._normalize_tool_name(tool_id_or_name))
        else:  # short
            return citation.format_short()

    def get_recommended_parameters(
        self,
        tool_id_or_name: str,
        context: Optional[Dict[str, Any]] = None
    ) -> Dict[str, ParameterRecommendation]:
        """
        Get recommended parameters for a tool.

        Args:
            tool_id_or_name: Tool identifier
            context: Optional context for context-aware recommendations
                     e.g., {"organism": "human", "data_type": "rna-seq"}

        Returns:
            Dictionary of parameter recommendations
        """
        knowledge = self.get_tool_knowledge(tool_id_or_name)
        if not knowledge:
            return {}

        params = knowledge.recommended_parameters.copy()

        # Apply context-aware adjustments
        if context:
            params = self._apply_context(params, context, knowledge)

        return params

    def _apply_context(
        self,
        params: Dict[str, ParameterRecommendation],
        context: Dict[str, Any],
        knowledge: ToolKnowledge
    ) -> Dict[str, ParameterRecommendation]:
        """Apply context-aware adjustments to parameters."""
        # Example: Adjust thread count based on available resources
        if "available_threads" in context and "threads" in params:
            available = context["available_threads"]
            params["threads"].recommended_value = min(
                int(params["threads"].recommended_value or 8),
                available
            )
            params["threads"].context = f"Adjusted for {available} available threads"

        # Example: Adjust memory for organism
        if "organism" in context and context["organism"] == "human":
            if "memory" in params:
                params["memory"].context = "Human genome requires higher memory"

        return params

    def get_limitations(self, tool_id_or_name: str) -> List[str]:
        """Get tool limitations."""
        knowledge = self.get_tool_knowledge(tool_id_or_name)
        return knowledge.limitations if knowledge else []

    def get_alternatives(self, tool_id_or_name: str) -> List[str]:
        """Get alternative tools."""
        knowledge = self.get_tool_knowledge(tool_id_or_name)
        return knowledge.alternatives if knowledge else []

    def get_use_cases(self, tool_id_or_name: str) -> List[str]:
        """Get tool use cases."""
        knowledge = self.get_tool_knowledge(tool_id_or_name)
        return knowledge.use_cases if knowledge else []

    def get_parameter_recommendation(
        self,
        tool_id_or_name: str,
        parameter_name: str
    ) -> Optional[ParameterRecommendation]:
        """
        Get recommendation for a specific parameter.

        Args:
            tool_id_or_name: Tool identifier
            parameter_name: Name of the parameter

        Returns:
            ParameterRecommendation or None
        """
        knowledge = self.get_tool_knowledge(tool_id_or_name)
        if not knowledge:
            return None
        return knowledge.recommended_parameters.get(parameter_name)

    def get_confidence_score(self, tool_id_or_name: str) -> float:
        """
        Get overall confidence score for tool knowledge.

        Returns:
            Float 0-1, higher = more confident in our knowledge
        """
        knowledge = self.get_tool_knowledge(tool_id_or_name)
        if not knowledge:
            return 0.0

        # Weighted average of citation quality and knowledge completeness
        return (knowledge.citation_quality_score * 0.6 +
                knowledge.knowledge_completeness * 0.4)

    def build_step_annotation(self, tool_id_or_name: str, tool_name: str = None) -> str:
        """
        Build workflow step annotation with citation and best practices.

        Args:
            tool_id_or_name: Tool identifier
            tool_name: Display name for the tool

        Returns:
            Formatted annotation string
        """
        knowledge = self.get_tool_knowledge(tool_id_or_name)
        display_name = tool_name or tool_id_or_name

        annotation = f"Tool: {display_name}\n"

        if not knowledge:
            return annotation

        # Add citation
        if knowledge.citation:
            annotation += f"\nCitation: {knowledge.citation.format_short()}"
            if knowledge.citation.doi:
                annotation += f"\nDOI: https://doi.org/{knowledge.citation.doi}"
            if knowledge.citation.pmid:
                annotation += f"\nPMID: {knowledge.citation.pmid}"

        # Add limitations as warnings
        if knowledge.limitations:
            annotation += "\n\nLimitations:"
            for limit in knowledge.limitations[:3]:  # Top 3 limitations
                annotation += f"\n  - {limit}"

        # Add recommended parameters summary
        if knowledge.recommended_parameters:
            annotation += "\n\nRecommended settings:"
            for name, rec in list(knowledge.recommended_parameters.items())[:5]:
                annotation += f"\n  - {name}: {rec.recommended_value}"

        return annotation

    def get_tools_by_category(self, category: str) -> List[str]:
        """Get all tools in a category."""
        try:
            conn = self._get_connection()
            cursor = conn.cursor()
            cursor.execute(
                "SELECT tool_name FROM tool_knowledge WHERE LOWER(category) = ?",
                (category.lower(),)
            )
            tools = [row[0] for row in cursor.fetchall()]
            conn.close()
            return tools
        except Exception as e:
            log.error(f"Error fetching tools by category: {e}")
            return []

    def get_all_citations(self, tool_ids: List[str]) -> Dict[str, Citation]:
        """
        Get citations for multiple tools at once.

        Args:
            tool_ids: List of tool identifiers

        Returns:
            Dictionary mapping tool_id to Citation
        """
        citations = {}
        for tool_id in tool_ids:
            citation = self.get_citation(tool_id)
            if citation:
                citations[tool_id] = citation
        return citations

    def get_stats(self) -> Dict[str, int]:
        """Get statistics about the knowledge base."""
        try:
            conn = self._get_connection()
            cursor = conn.cursor()

            stats = {}

            cursor.execute("SELECT COUNT(*) FROM tool_knowledge")
            stats["total_tools"] = cursor.fetchone()[0]

            cursor.execute("""
                SELECT COUNT(*) FROM tool_knowledge
                WHERE primary_citation IS NOT NULL AND length(primary_citation) > 10
            """)
            stats["with_citations"] = cursor.fetchone()[0]

            cursor.execute("""
                SELECT COUNT(*) FROM tool_knowledge
                WHERE recommended_parameters IS NOT NULL AND recommended_parameters != '{}'
            """)
            stats["with_parameters"] = cursor.fetchone()[0]

            cursor.execute("""
                SELECT COUNT(*) FROM tool_knowledge
                WHERE use_cases IS NOT NULL AND use_cases != '[]'
            """)
            stats["with_use_cases"] = cursor.fetchone()[0]

            conn.close()
            return stats

        except Exception as e:
            log.error(f"Error getting stats: {e}")
            return {}


# Singleton instance for easy access
_provider_instance: Optional[ToolKnowledgeProvider] = None


def get_tool_knowledge_provider(db_path: str = None) -> ToolKnowledgeProvider:
    """Get or create the singleton ToolKnowledgeProvider instance."""
    global _provider_instance
    if _provider_instance is None:
        _provider_instance = ToolKnowledgeProvider(db_path)
    return _provider_instance
