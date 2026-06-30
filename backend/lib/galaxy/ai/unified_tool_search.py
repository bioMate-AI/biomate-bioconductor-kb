"""
Unified Tool Search

Multi-stage retrieval pipeline combining:
1. LLM-based query analysis (extract entities, infer category, expand terms)
2. Direct entity matching (SQL LIKE on extracted entities)
3. Vector similarity search (semantic embeddings)
4. Enhanced FTS5 search (full-text with category filter)
5. Reciprocal Rank Fusion (combine all results)

This provides robust tool discovery without hardcoded keyword lists.
"""

import sqlite3
import logging
from typing import List, Dict, Any, Optional, Tuple
from pathlib import Path
from contextlib import contextmanager
import threading

from .query_analyzer import LLMQueryAnalyzer, QueryAnalysis, SimpleQueryAnalyzer
from .vector_search import get_vector_search, VectorToolSearch

log = logging.getLogger(__name__)


class UnifiedToolSearch:
    """
    Multi-stage tool search combining LLM, vectors, and FTS5.

    Pipeline:
    1. LLM analyzes query → entities, category, expanded terms
    2. Direct match on entities (SQL LIKE)
    3. Vector similarity search
    4. FTS5 with category filter
    5. RRF fusion of all results
    """

    def __init__(
        self,
        db_path: str,
        llm_client=None,
        use_vector_search: bool = True,
        use_llm_analysis: bool = True,
        include_toolshed: bool = True
    ):
        """
        Initialize unified search.

        Args:
            db_path: Path to galaxy_ai_tools.db
            llm_client: LLM client with generate() method
            use_vector_search: Enable vector similarity search
            use_llm_analysis: Use LLM for query analysis (vs simple pattern matching)
            include_toolshed: Include ToolShed tools in search results (default True).
                              When True, all tools are searchable. Tool installation
                              will be handled by the workflow generator via ToolAutoInstaller.
        """
        self.db_path = db_path
        self._local = threading.local()
        self.include_toolshed = include_toolshed

        # Initialize query analyzer
        if use_llm_analysis and llm_client:
            self.query_analyzer = LLMQueryAnalyzer(llm_client)
            log.info("Using LLM-based query analyzer")
        else:
            self.query_analyzer = SimpleQueryAnalyzer()
            log.info("Using simple pattern-based query analyzer")

        # Initialize vector search
        if use_vector_search:
            self.vector_search = get_vector_search(db_path)
            log.info(f"Vector search available: {self.vector_search.is_available()}")
        else:
            self.vector_search = None

    def _get_connection(self) -> sqlite3.Connection:
        """Get thread-local database connection."""
        if not hasattr(self._local, 'conn') or self._local.conn is None:
            self._local.conn = sqlite3.connect(self.db_path)
            self._local.conn.row_factory = sqlite3.Row
        return self._local.conn

    @contextmanager
    def _get_cursor(self):
        """Context manager for cursor."""
        conn = self._get_connection()
        cursor = conn.cursor()
        try:
            yield cursor
        finally:
            cursor.close()

    def search(
        self,
        query: str,
        limit: int = 30,
        include_debug: bool = False
    ) -> List[Dict[str, Any]]:
        """
        Search for tools using multi-stage retrieval.

        Args:
            query: User's search query
            limit: Maximum number of results
            include_debug: Include debug info in results

        Returns:
            List of tool dicts sorted by relevance
        """
        if not query or not query.strip():
            return []

        query = query.strip()
        result_sets = []
        debug_info = {'stages': []}

        # Stage 0: Query analysis
        log.info(f"Analyzing query: {query[:100]}...")
        analysis = self.query_analyzer.analyze(query)
        log.info(f"Analysis: entities={analysis.explicit_entities}, "
                f"category={analysis.inferred_category}")

        if include_debug:
            debug_info['analysis'] = analysis.to_dict()

        # Stage 1: Direct entity matching
        if analysis.explicit_entities:
            direct_results = self._direct_entity_match(
                analysis.explicit_entities,
                limit=15
            )
            if direct_results:
                result_sets.append(('direct', direct_results))
                log.info(f"Stage 1 (direct match): {len(direct_results)} results")
                if include_debug:
                    debug_info['stages'].append({
                        'name': 'direct_match',
                        'count': len(direct_results)
                    })

        # Stage 2: Vector similarity search
        if self.vector_search and self.vector_search.is_available():
            vector_results = self.vector_search.search(
                query,
                expanded_terms=analysis.expanded_terms,
                limit=20
            )
            if vector_results:
                result_sets.append(('vector', vector_results))
                log.info(f"Stage 2 (vector): {len(vector_results)} results")
                if include_debug:
                    debug_info['stages'].append({
                        'name': 'vector_search',
                        'count': len(vector_results)
                    })

        # Stage 3: FTS5 search with category filter
        fts_results = self._fts5_search(
            query,
            category=analysis.inferred_category,
            expanded_terms=analysis.expanded_terms,
            limit=25
        )
        if fts_results:
            result_sets.append(('fts5', fts_results))
            log.info(f"Stage 3 (FTS5): {len(fts_results)} results")
            if include_debug:
                debug_info['stages'].append({
                    'name': 'fts5_search',
                    'count': len(fts_results)
                })

        # Stage 4: Fallback - broader FTS5 without category filter
        if not result_sets or sum(len(rs[1]) for rs in result_sets) < 5:
            fallback_results = self._fts5_search(
                query,
                category=None,
                expanded_terms=analysis.expanded_terms,
                limit=20
            )
            if fallback_results:
                result_sets.append(('fallback', fallback_results))
                log.info(f"Stage 4 (fallback): {len(fallback_results)} results")

        # Stage 5: Result fusion
        if not result_sets:
            log.warning(f"No results found for query: {query}")
            return []

        fused_results = self._reciprocal_rank_fusion(
            [rs[1] for rs in result_sets],
            k=60
        )

        log.info(f"Final fused results: {len(fused_results)}")

        # Add debug info if requested
        if include_debug:
            for result in fused_results[:10]:
                result['_debug'] = debug_info

        return fused_results[:limit]

    def _direct_entity_match(
        self,
        entities: List[str],
        limit: int = 15
    ) -> List[Dict[str, Any]]:
        """
        Match explicit entities against tool names using SQL LIKE.
        No hardcoded lists - uses entities extracted by LLM.
        """
        results = []
        seen_ids = set()

        with self._get_cursor() as cursor:
            for entity in entities:
                if not entity or len(entity) < 2:
                    continue

                pattern = f"%{entity}%"

                # Search in name, tool_id, and description
                # Prioritize Biomni tools but include ToolShed tools for installation
                # ToolShed filter is configurable via include_toolshed parameter
                toolshed_filter = "" if self.include_toolshed else "AND tool_id NOT LIKE 'toolshed.%'"

                # Two-stage ranking: relevance first, then availability as tie-breaker
                # This ensures semantic match quality comes before tool availability
                cursor.execute(f'''
                    SELECT *,
                           CASE
                               WHEN LOWER(name) = LOWER(?) THEN 100
                               WHEN LOWER(name) LIKE LOWER(?) THEN 80
                               WHEN LOWER(tool_id) LIKE LOWER(?) THEN 70
                               WHEN LOWER(description) LIKE LOWER(?) THEN 50
                               ELSE 30
                           END as relevance_score,
                           COALESCE(priority_score, 0) as availability_score
                    FROM tools
                    WHERE (name LIKE ? COLLATE NOCASE
                       OR tool_id LIKE ? COLLATE NOCASE
                       OR (description IS NOT NULL AND description LIKE ? COLLATE NOCASE))
                      {toolshed_filter}
                    ORDER BY relevance_score DESC, availability_score DESC
                    LIMIT ?
                ''', (entity, pattern, pattern, pattern,
                      pattern, pattern, pattern, limit))

                for row in cursor.fetchall():
                    tool = dict(row)
                    tool_id = tool['tool_id']

                    if tool_id not in seen_ids:
                        seen_ids.add(tool_id)
                        tool['search_method'] = 'direct'
                        tool['matched_entity'] = entity
                        results.append(tool)

        return results[:limit]

    def _fts5_search(
        self,
        query: str,
        category: Optional[str] = None,
        expanded_terms: List[str] = None,
        limit: int = 25
    ) -> List[Dict[str, Any]]:
        """
        FTS5 full-text search with optional category filter.
        Uses expanded terms from LLM for broader matching.
        """
        # Build search query with OR for expanded terms
        search_terms = [query]
        if expanded_terms:
            search_terms.extend(expanded_terms[:10])  # Limit expansion

        # Sanitize and join with OR
        sanitized_terms = []
        for term in search_terms:
            sanitized = self._sanitize_fts5(term)
            if sanitized:
                sanitized_terms.append(sanitized)

        if not sanitized_terms:
            return []

        fts_query = ' OR '.join(sanitized_terms)

        results = []
        # ToolShed filter is configurable via include_toolshed parameter
        toolshed_filter = "" if self.include_toolshed else "AND t.tool_id NOT LIKE 'toolshed.%'"

        with self._get_cursor() as cursor:
            try:
                # Use tool_id for JOIN (not rowid) since FTS5 rowids don't match tools.id
                # Prioritize Biomni tools but include ToolShed tools for installation
                # Two-stage ranking: BM25 relevance first, then availability as tie-breaker
                # BM25 returns negative scores (lower = better match)
                if category:
                    sql = f'''
                        SELECT t.*, bm25(tools_fts) as rank,
                               COALESCE(t.priority_score, 0) as availability_score
                        FROM tools t
                        JOIN tools_fts fts ON t.tool_id = fts.tool_id
                        WHERE tools_fts MATCH ? AND t.category = ?
                          {toolshed_filter}
                        ORDER BY rank, availability_score DESC
                        LIMIT ?
                    '''
                    cursor.execute(sql, (fts_query, category, limit))
                else:
                    sql = f'''
                        SELECT t.*, bm25(tools_fts) as rank,
                               COALESCE(t.priority_score, 0) as availability_score
                        FROM tools t
                        JOIN tools_fts fts ON t.tool_id = fts.tool_id
                        WHERE tools_fts MATCH ?
                          {toolshed_filter}
                        ORDER BY rank, availability_score DESC
                        LIMIT ?
                    '''
                    cursor.execute(sql, (fts_query, limit))

                for row in cursor.fetchall():
                    tool = dict(row)
                    tool['search_method'] = 'fts5'
                    tool['fts5_rank'] = tool.get('rank', 0)
                    results.append(tool)

            except sqlite3.OperationalError as e:
                log.warning(f"FTS5 search failed: {e}")
                # Try simpler query
                results = self._simple_like_search(query, category, limit)

        return results

    def _simple_like_search(
        self,
        query: str,
        category: Optional[str] = None,
        limit: int = 25
    ) -> List[Dict[str, Any]]:
        """Fallback LIKE search when FTS5 fails."""
        results = []
        pattern = f"%{query}%"
        # ToolShed filter is configurable via include_toolshed parameter
        toolshed_filter = "" if self.include_toolshed else "AND tool_id NOT LIKE 'toolshed.%'"

        with self._get_cursor() as cursor:
            # Simple LIKE fallback - order by name match quality, then availability
            if category:
                cursor.execute(f'''
                    SELECT *,
                           CASE WHEN name LIKE ? THEN 1 ELSE 0 END as name_match,
                           COALESCE(priority_score, 0) as availability_score
                    FROM tools
                    WHERE (name LIKE ? OR description LIKE ?)
                      AND category = ?
                      {toolshed_filter}
                    ORDER BY name_match DESC, availability_score DESC
                    LIMIT ?
                ''', (pattern, pattern, pattern, category, limit))
            else:
                cursor.execute(f'''
                    SELECT *,
                           CASE WHEN name LIKE ? THEN 1 ELSE 0 END as name_match,
                           COALESCE(priority_score, 0) as availability_score
                    FROM tools
                    WHERE (name LIKE ? OR description LIKE ?)
                      {toolshed_filter}
                    ORDER BY name_match DESC, availability_score DESC
                    LIMIT ?
                ''', (pattern, pattern, pattern, limit))

            for row in cursor.fetchall():
                tool = dict(row)
                tool['search_method'] = 'like_fallback'
                results.append(tool)

        return results

    def _sanitize_fts5(self, query: str) -> str:
        """Sanitize query for FTS5 to prevent syntax errors."""
        if not query:
            return ""

        # Replace special characters
        replacements = {
            '-': ' ',
            '/': ' ',
            '(': ' ',
            ')': ' ',
            '"': '',
            "'": '',
            ':': ' ',
            ';': ' ',
            '.': ' ',
            ',': ' ',
            '!': ' ',
            '?': ' ',
            '*': '',
            '+': '',
        }

        sanitized = query
        for old, new in replacements.items():
            sanitized = sanitized.replace(old, new)

        # Remove multiple spaces
        sanitized = ' '.join(sanitized.split())

        # Remove FTS5 reserved words if used alone
        reserved = ['NOT', 'AND', 'OR', 'NEAR']
        words = sanitized.split()
        words = [w for w in words if w.upper() not in reserved or len(w) > 4]

        return ' '.join(words)

    def _reciprocal_rank_fusion(
        self,
        result_lists: List[List[Dict]],
        k: int = 60,
        relevance_tolerance: float = 0.1
    ) -> List[Dict[str, Any]]:
        """
        Combine results from multiple retrieval stages using RRF.

        RRF score = sum(1/(k + rank_i)) for each list where doc appears

        Two-stage ranking:
        1. Group tools by relevance (RRF score within tolerance are considered equivalent)
        2. Within each relevance group, sort by availability (priority_score)

        Args:
            result_lists: Lists of results from different search methods
            k: RRF constant (default 60)
            relevance_tolerance: Tools within this relative difference are considered
                                 equally relevant (default 0.1 = 10%)
        """
        scores: Dict[str, float] = {}
        tool_data: Dict[str, Dict] = {}

        for result_list in result_lists:
            for rank, tool in enumerate(result_list):
                tool_id = tool['tool_id']

                # RRF score contribution
                rrf_score = 1.0 / (k + rank + 1)

                if tool_id in scores:
                    scores[tool_id] += rrf_score
                else:
                    scores[tool_id] = rrf_score
                    tool_data[tool_id] = tool

        # Two-stage sorting with relevance tolerance:
        # 1. Quantize RRF scores into buckets (tools within tolerance are in same bucket)
        # 2. Sort by bucket (relevance) first, then by availability within bucket

        if not scores:
            return []

        max_score = max(scores.values())

        def get_sort_key(item):
            tool_id, rrf_score = item
            # Quantize to buckets based on relative tolerance
            # Higher bucket number = more relevant (we negate for descending sort)
            bucket = int(rrf_score / (max_score * relevance_tolerance)) if max_score > 0 else 0
            priority = tool_data[tool_id].get('priority_score', 0)
            # Sort by: bucket DESC, priority DESC
            return (-bucket, -priority)

        sorted_tools = sorted(scores.items(), key=get_sort_key)

        results = []
        for tool_id, score in sorted_tools:
            tool = tool_data[tool_id]
            tool['rrf_score'] = score
            results.append(tool)

        return results

    def get_categories(self) -> List[str]:
        """Get list of all categories."""
        with self._get_cursor() as cursor:
            cursor.execute('SELECT DISTINCT category FROM tools ORDER BY category')
            return [row[0] for row in cursor.fetchall() if row[0]]

    def get_stats(self) -> Dict[str, Any]:
        """Get search system statistics."""
        with self._get_cursor() as cursor:
            cursor.execute('SELECT COUNT(*) FROM tools')
            tool_count = cursor.fetchone()[0]

        return {
            'tool_count': tool_count,
            'vector_search_available': (
                self.vector_search.is_available()
                if self.vector_search else False
            ),
            'query_analyzer': type(self.query_analyzer).__name__,
            'db_path': self.db_path
        }

    def close(self):
        """Close database connection."""
        if hasattr(self._local, 'conn') and self._local.conn:
            self._local.conn.close()
            self._local.conn = None


def create_unified_search(
    db_path: str = None,
    llm_client=None,
    include_toolshed: bool = True
) -> UnifiedToolSearch:
    """
    Factory function to create UnifiedToolSearch.

    Args:
        db_path: Path to database (auto-detected if None)
        llm_client: LLM client for query analysis
        include_toolshed: Include ToolShed tools (default True).
                          ToolShed tools can be auto-installed via Galaxy API.

    Returns:
        Configured UnifiedToolSearch instance
    """
    if db_path is None:
        # Auto-detect database path
        possible_paths = [
            Path(__file__).parent.parent.parent.parent / "database" / "galaxy_ai_tools.db",
        ]
        for path in possible_paths:
            if path.exists():
                db_path = str(path)
                break

    if not db_path or not Path(db_path).exists():
        raise FileNotFoundError(f"Tool database not found: {db_path}")

    return UnifiedToolSearch(
        db_path=db_path,
        llm_client=llm_client,
        use_vector_search=True,
        use_llm_analysis=(llm_client is not None),
        include_toolshed=include_toolshed
    )
