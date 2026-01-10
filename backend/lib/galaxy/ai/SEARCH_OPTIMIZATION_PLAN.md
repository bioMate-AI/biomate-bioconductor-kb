# Unified Tool Search Optimization Plan

## Executive Summary

This document outlines a comprehensive optimization strategy for the Galaxy tool search system that combines:
1. **LLM-based query understanding** for category inference and synonym expansion
2. **Vector embeddings** for semantic similarity search
3. **Multi-stage retrieval pipeline** with graceful fallbacks
4. **Enhanced FTS5 index** with additional searchable fields

The goal is to ensure queries like "Query UniProt protein database" correctly match tools like "Query Uniprot" without relying on hardcoded keyword mappings.

---

## Current State Analysis

### Database Schema
- **tools table**: 8,095 tools with 40+ columns
- **tools_fts**: FTS5 index with only 6 columns (tool_id, name, description, category, parameters, help_text)

### Current Search Flow (`search_index.py:56-107`)
```
User Intent → Sanitize (replace hyphens) → Raw FTS5 MATCH → Results
```

### Problem
- No semantic understanding of queries
- FTS5 requires exact/partial text matches
- LLM query transformation in `galaxy_workflow_generator.py` generates generic terms that don't match tool names

---

## Proposed Architecture

### Multi-Stage Retrieval Pipeline

```
┌─────────────────────────────────────────────────────────────────────┐
│                         User Query                                   │
│              "I want to query UniProt for protein info"             │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│                   Stage 0: Query Analysis (LLM)                      │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │ Extract:                                                       │  │
│  │   - explicit_entities: ["UniProt", "protein"]                 │  │
│  │   - inferred_category: "Data Source"                          │  │
│  │   - task_type: "database_query"                               │  │
│  │   - expanded_terms: ["uniprot", "uniprotkb", "protein db"]    │  │
│  └───────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
                                  │
          ┌───────────────────────┼───────────────────────┐
          ▼                       ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│  Stage 1:       │    │  Stage 2:       │    │  Stage 3:       │
│  Direct Match   │    │  Vector Search  │    │  FTS5 Search    │
│  (SQL LIKE)     │    │  (Embeddings)   │    │  (Full-text)    │
│                 │    │                 │    │                 │
│  Match entities │    │  Semantic sim   │    │  Category-      │
│  against names  │    │  on embeddings  │    │  filtered FTS5  │
└────────┬────────┘    └────────┬────────┘    └────────┬────────┘
         │                      │                      │
         └──────────────────────┼──────────────────────┘
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    Stage 4: Result Fusion                            │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │ Reciprocal Rank Fusion (RRF):                                  │  │
│  │   score(d) = Σ 1/(k + rank_i(d))  for each retrieval stage    │  │
│  │                                                                │  │
│  │ Deduplicate and return top-N tools                            │  │
│  └───────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
                         Final Tool Results
```

---

## Component Details

### Stage 0: LLM-Based Query Analysis

**Purpose**: Understand user intent without hardcoded rules

**Prompt Template**:
```python
QUERY_ANALYSIS_PROMPT = """Analyze this bioinformatics tool search query.

Query: "{user_query}"

Extract the following in JSON format:
{{
    "explicit_entities": [
        // Database names, tool names, file formats mentioned
        // e.g., "UniProt", "FASTA", "BLAST", "PDB"
    ],
    "inferred_category":
        // One of: Data Source, Proteomics, Genomics, Transcriptomics,
        // Metabolomics, Imaging, Functional Analysis, Assembly,
        // Alignment, Variant Calling, Phylogenetics, Metagenomics,
        // or null if unclear
    ,
    "task_type":
        // e.g., "database_query", "format_conversion", "analysis",
        // "visualization", "quality_control", "alignment"
    ,
    "expanded_terms": [
        // Synonyms and related terms for search
        // e.g., for "UniProt" → ["uniprotkb", "swiss-prot", "protein sequence database"]
    ],
    "data_types": [
        // Input/output data types expected
        // e.g., "protein sequences", "FASTA", "gene list"
    ]
}}

Only return valid JSON, no explanation."""
```

**Implementation** (`query_analyzer.py`):
```python
class LLMQueryAnalyzer:
    """Use LLM to understand search queries without hardcoded rules."""

    def __init__(self, llm_client):
        self.llm = llm_client
        self.cache = {}  # Cache analysis results

    def analyze(self, query: str) -> QueryAnalysis:
        """Analyze query using LLM."""
        if query in self.cache:
            return self.cache[query]

        prompt = QUERY_ANALYSIS_PROMPT.format(user_query=query)
        response = self.llm.generate(prompt, max_tokens=500)

        try:
            analysis = json.loads(response)
            result = QueryAnalysis(
                explicit_entities=analysis.get('explicit_entities', []),
                inferred_category=analysis.get('inferred_category'),
                task_type=analysis.get('task_type'),
                expanded_terms=analysis.get('expanded_terms', []),
                data_types=analysis.get('data_types', [])
            )
            self.cache[query] = result
            return result
        except json.JSONDecodeError:
            # Fallback: simple word extraction
            return QueryAnalysis(
                explicit_entities=[],
                inferred_category=None,
                task_type=None,
                expanded_terms=query.lower().split(),
                data_types=[]
            )
```

---

### Stage 1: Direct Entity Matching

**Purpose**: Fast exact/fuzzy match for explicitly mentioned tools/databases

**Implementation**:
```python
def direct_entity_match(self, entities: List[str], limit: int = 10) -> List[Dict]:
    """
    Match explicit entities against tool names using SQL LIKE.
    No hardcoded lists - uses entities extracted by LLM.
    """
    results = []

    with self._get_cursor() as cursor:
        for entity in entities:
            # Case-insensitive LIKE match
            pattern = f"%{entity}%"
            cursor.execute('''
                SELECT *,
                       CASE
                           WHEN LOWER(name) = LOWER(?) THEN 100
                           WHEN LOWER(name) LIKE LOWER(?) THEN 80
                           WHEN LOWER(tool_id) LIKE LOWER(?) THEN 70
                           WHEN LOWER(description) LIKE LOWER(?) THEN 50
                       END as match_score
                FROM tools
                WHERE name LIKE ? COLLATE NOCASE
                   OR tool_id LIKE ? COLLATE NOCASE
                   OR description LIKE ? COLLATE NOCASE
                ORDER BY match_score DESC
                LIMIT ?
            ''', (entity, pattern, pattern, pattern,
                  pattern, pattern, pattern, limit))

            for row in cursor.fetchall():
                if row not in results:
                    results.append(dict(row))

    return results[:limit]
```

---

### Stage 2: Vector Embedding Search

**Purpose**: Semantic similarity search using embeddings

**Embedding Strategy**:
- Use sentence-transformers model: `all-MiniLM-L6-v2` (fast, 384 dims)
- Pre-compute embeddings for all tools (name + description + category)
- Store in SQLite with `sqlite-vss` extension OR numpy file

**Implementation** (`vector_search.py`):
```python
from sentence_transformers import SentenceTransformer
import numpy as np

class VectorToolSearch:
    """Semantic search using vector embeddings."""

    def __init__(self, db_path: str, embedding_path: str = None):
        self.model = SentenceTransformer('all-MiniLM-L6-v2')
        self.db_path = db_path
        self.embedding_path = embedding_path or db_path.replace('.db', '_embeddings.npy')

        self._load_or_create_embeddings()

    def _load_or_create_embeddings(self):
        """Load existing embeddings or create new ones."""
        if Path(self.embedding_path).exists():
            data = np.load(self.embedding_path, allow_pickle=True).item()
            self.tool_ids = data['tool_ids']
            self.embeddings = data['embeddings']
        else:
            self._create_embeddings()

    def _create_embeddings(self):
        """Create embeddings for all tools."""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        cursor.execute('''
            SELECT tool_id, name, description, category
            FROM tools
        ''')

        self.tool_ids = []
        texts = []

        for row in cursor.fetchall():
            tool_id, name, desc, category = row
            self.tool_ids.append(tool_id)
            # Combine fields for embedding
            text = f"{name}. {desc or ''}. Category: {category or ''}"
            texts.append(text)

        # Batch encode
        self.embeddings = self.model.encode(texts, show_progress_bar=True)

        # Save for reuse
        np.save(self.embedding_path, {
            'tool_ids': self.tool_ids,
            'embeddings': self.embeddings
        })

        conn.close()

    def search(self, query: str, expanded_terms: List[str] = None,
               limit: int = 20) -> List[Dict]:
        """
        Search tools by semantic similarity.

        Args:
            query: Original user query
            expanded_terms: LLM-generated synonyms to include
            limit: Max results
        """
        # Combine query with expanded terms
        if expanded_terms:
            search_text = f"{query}. {' '.join(expanded_terms)}"
        else:
            search_text = query

        # Encode query
        query_embedding = self.model.encode([search_text])[0]

        # Compute cosine similarity
        similarities = np.dot(self.embeddings, query_embedding) / (
            np.linalg.norm(self.embeddings, axis=1) * np.linalg.norm(query_embedding)
        )

        # Get top-k indices
        top_indices = np.argsort(similarities)[::-1][:limit]

        # Fetch tool details
        results = []
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()

        for idx in top_indices:
            tool_id = self.tool_ids[idx]
            similarity = similarities[idx]

            cursor.execute('SELECT * FROM tools WHERE tool_id = ?', (tool_id,))
            row = cursor.fetchone()
            if row:
                tool = dict(row)
                tool['similarity_score'] = float(similarity)
                results.append(tool)

        conn.close()
        return results
```

---

### Stage 3: Enhanced FTS5 Search

**Index Enhancement**:
```sql
-- Drop and recreate FTS5 with more columns
DROP TABLE IF EXISTS tools_fts;

CREATE VIRTUAL TABLE tools_fts USING fts5(
    tool_id,
    name,
    description,
    category,
    parameters,
    help_text,
    keywords,           -- NEW: from existing column
    tags,               -- NEW: from existing column
    edam_operations,    -- NEW: ontology terms
    edam_topics,        -- NEW: ontology topics
    tokenize='porter unicode61'  -- Stemming for better matching
);

-- Populate FTS5
INSERT INTO tools_fts
SELECT tool_id, name, description, category, parameters, help_text,
       keywords, tags, edam_operations, edam_topics
FROM tools;
```

**Search with Category Filter**:
```python
def fts5_search(self, query: str, category: str = None,
                expanded_terms: List[str] = None,
                limit: int = 30) -> List[Dict]:
    """
    FTS5 full-text search with optional category filter.

    Uses LLM-provided expanded_terms for broader matching.
    """
    # Build search query with OR for expanded terms
    search_terms = [query]
    if expanded_terms:
        search_terms.extend(expanded_terms)

    # Sanitize and join with OR
    sanitized_terms = [self._sanitize_fts5(t) for t in search_terms]
    fts_query = ' OR '.join(sanitized_terms)

    with self._get_cursor() as cursor:
        if category:
            sql = '''
                SELECT t.*, bm25(tools_fts) as rank
                FROM tools t
                JOIN tools_fts fts ON t.id = fts.rowid
                WHERE tools_fts MATCH ? AND t.category = ?
                ORDER BY rank
                LIMIT ?
            '''
            cursor.execute(sql, (fts_query, category, limit))
        else:
            sql = '''
                SELECT t.*, bm25(tools_fts) as rank
                FROM tools t
                JOIN tools_fts fts ON t.id = fts.rowid
                WHERE tools_fts MATCH ?
                ORDER BY rank
                LIMIT ?
            '''
            cursor.execute(sql, (fts_query, limit))

        return [dict(row) for row in cursor.fetchall()]
```

---

### Stage 4: Result Fusion

**Reciprocal Rank Fusion (RRF)**:
```python
def reciprocal_rank_fusion(self, result_lists: List[List[Dict]],
                           k: int = 60) -> List[Dict]:
    """
    Combine results from multiple retrieval stages using RRF.

    RRF score = Σ 1/(k + rank_i) for each list where doc appears

    This is more robust than simple score averaging because:
    - It handles different score scales across methods
    - It rewards documents that appear in multiple result sets
    """
    scores = {}
    tool_data = {}

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

    # Sort by combined RRF score
    sorted_tools = sorted(scores.items(), key=lambda x: -x[1])

    results = []
    for tool_id, score in sorted_tools:
        tool = tool_data[tool_id]
        tool['rrf_score'] = score
        results.append(tool)

    return results
```

---

## Unified Search Implementation

**Main Entry Point** (`unified_tool_search.py`):
```python
class UnifiedToolSearch:
    """
    Multi-stage tool search combining LLM, vectors, and FTS5.
    """

    def __init__(self, db_path: str, llm_client, embedding_model: str = 'all-MiniLM-L6-v2'):
        self.db_path = db_path
        self.query_analyzer = LLMQueryAnalyzer(llm_client)
        self.vector_search = VectorToolSearch(db_path, embedding_model)
        self.fts_index = ToolSearchIndex(db_path)

    def search(self, query: str, limit: int = 30) -> List[Dict]:
        """
        Search for tools using multi-stage retrieval.

        Pipeline:
        1. LLM analyzes query → entities, category, expanded terms
        2. Direct match on entities
        3. Vector similarity search
        4. FTS5 with category filter
        5. RRF fusion of all results
        """
        # Stage 0: Query analysis
        analysis = self.query_analyzer.analyze(query)
        log.info(f"Query analysis: entities={analysis.explicit_entities}, "
                 f"category={analysis.inferred_category}")

        result_sets = []

        # Stage 1: Direct entity matching
        if analysis.explicit_entities:
            direct_results = self.fts_index.direct_entity_match(
                analysis.explicit_entities, limit=10
            )
            if direct_results:
                result_sets.append(direct_results)
                log.info(f"Direct match: {len(direct_results)} results")

        # Stage 2: Vector similarity search
        vector_results = self.vector_search.search(
            query,
            expanded_terms=analysis.expanded_terms,
            limit=20
        )
        if vector_results:
            result_sets.append(vector_results)
            log.info(f"Vector search: {len(vector_results)} results")

        # Stage 3: FTS5 search with category filter
        fts_results = self.fts_index.fts5_search(
            query,
            category=analysis.inferred_category,
            expanded_terms=analysis.expanded_terms,
            limit=20
        )
        if fts_results:
            result_sets.append(fts_results)
            log.info(f"FTS5 search: {len(fts_results)} results")

        # Stage 4: Fusion
        if not result_sets:
            log.warning(f"No results found for query: {query}")
            return []

        fused_results = self.reciprocal_rank_fusion(result_sets)
        log.info(f"Final fused results: {len(fused_results)}")

        return fused_results[:limit]
```

---

## Database Migration

**Script** (`migrate_tool_search.py`):
```python
#!/usr/bin/env python3
"""
Migrate tool search index for enhanced search capabilities.

1. Add stemmed FTS5 with additional columns
2. Generate vector embeddings for all tools
"""

import sqlite3
from pathlib import Path
from sentence_transformers import SentenceTransformer
import numpy as np

def migrate_fts5(db_path: str):
    """Recreate FTS5 index with more columns and stemming."""
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # Drop existing FTS5
    cursor.execute('DROP TABLE IF EXISTS tools_fts')

    # Create enhanced FTS5 with porter stemming
    cursor.execute('''
        CREATE VIRTUAL TABLE tools_fts USING fts5(
            tool_id,
            name,
            description,
            category,
            parameters,
            help_text,
            keywords,
            tags,
            edam_operations,
            edam_topics,
            tokenize='porter unicode61'
        )
    ''')

    # Populate from tools table
    cursor.execute('''
        INSERT INTO tools_fts
        SELECT tool_id, name, description, category, parameters, help_text,
               COALESCE(keywords, ''), COALESCE(tags, ''),
               COALESCE(edam_operations, ''), COALESCE(edam_topics, '')
        FROM tools
    ''')

    conn.commit()
    conn.close()
    print(f"FTS5 index migrated: {db_path}")

def generate_embeddings(db_path: str, model_name: str = 'all-MiniLM-L6-v2'):
    """Generate and save vector embeddings for all tools."""
    model = SentenceTransformer(model_name)

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute('''
        SELECT tool_id, name, description, category, keywords
        FROM tools
    ''')

    tool_ids = []
    texts = []

    for row in cursor.fetchall():
        tool_id, name, desc, category, keywords = row
        tool_ids.append(tool_id)
        # Rich text representation for embedding
        text = f"{name}. {desc or ''}. Category: {category or ''}. Keywords: {keywords or ''}"
        texts.append(text)

    print(f"Generating embeddings for {len(texts)} tools...")
    embeddings = model.encode(texts, show_progress_bar=True, batch_size=64)

    # Save embeddings
    embedding_path = db_path.replace('.db', '_embeddings.npz')
    np.savez_compressed(
        embedding_path,
        tool_ids=np.array(tool_ids),
        embeddings=embeddings
    )

    conn.close()
    print(f"Embeddings saved: {embedding_path}")

if __name__ == '__main__':
    db_path = '/home/yzhang/biomate/backend/galaxy_ai_tools.db'
    migrate_fts5(db_path)
    generate_embeddings(db_path)
```

---

## Integration with Workflow Generator

**Update** `galaxy_workflow_generator.py`:
```python
# Replace current _retrieve_tools_from_index method

def _retrieve_tools_from_index(
    self,
    user_intent: str,
    limit: int = 30
) -> List[Dict[str, Any]]:
    """
    Retrieve available tools using unified multi-stage search.

    Uses:
    - LLM for query understanding (no hardcoded rules)
    - Vector embeddings for semantic similarity
    - FTS5 for keyword matching
    - RRF for result fusion
    """
    try:
        # Use unified search instead of simple FTS5
        results = self.unified_search.search(user_intent, limit=limit)

        # Format tools for LLM context
        formatted_tools = []
        for tool in results:
            formatted_tools.append({
                'tool_id': tool['tool_id'],
                'name': tool['name'],
                'description': tool.get('description', ''),
                'version': tool.get('version', ''),
                'category': tool.get('category', ''),
                'keywords': tool.get('keywords', ''),
                'repo_owner': tool.get('repo_owner', ''),
                'repo_name': tool.get('repo_name', ''),
                'relevance_score': tool.get('rrf_score', 0)
            })

        return formatted_tools

    except Exception as e:
        log.error(f"Unified tool search failed: {e}")
        # Fallback to basic FTS5
        return self._fallback_fts5_search(user_intent, limit)
```

---

## Expected Performance

| Query | Current | With Optimization |
|-------|---------|-------------------|
| "Query UniProt database for protein" | 0 results | Query Uniprot (direct + vector) |
| "Perform GO enrichment analysis" | 0 results | GOEnrichment, gProfiler (vector + FTS5) |
| "Segment cells in microscopy images" | 0 results | cellpose, CellProfiler (vector similarity) |
| "Analyze CRISPR screen results" | 0 results | MAGeCK, BAGEL (LLM expansion + vector) |
| "Differential expression RNA-seq" | 0 results | DESeq2, edgeR, limma (FTS5 + vector) |

---

## Implementation Checklist

- [ ] Create `query_analyzer.py` with LLM-based analysis
- [ ] Create `vector_search.py` with embedding-based search
- [ ] Create `unified_tool_search.py` combining all stages
- [ ] Run `migrate_tool_search.py` to enhance FTS5 and generate embeddings
- [ ] Update `galaxy_workflow_generator.py` to use unified search
- [ ] Add unit tests for each search stage
- [ ] Benchmark search latency (target: <500ms)

---

## Dependencies

```
sentence-transformers>=2.2.0  # For vector embeddings
numpy>=1.20.0                 # For embedding storage
```

---

## Alternative: Use Existing RAG Infrastructure

If `sentence-transformers` adds too much overhead, consider:
1. **Use LLM for everything**: Let LLM generate multiple search queries from user intent
2. **API-based embeddings**: Use OpenAI/Anthropic embeddings API instead of local model
3. **Hybrid with existing EnhancedToolSearch**: Leverage `enhanced_tool_search.py` scoring

The key insight is: **Let LLM do the semantic work, not hardcoded keyword lists**.
