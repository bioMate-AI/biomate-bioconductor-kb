# Benchmark Knowledge Integration into BioMate AI Scientist

**Date:** 2025-12-30
**Status:** ✅ IMPLEMENTED (Core Integration Complete)
**Dependencies:** `20251223_AI_SCIENTIST_INTEGRATION_PLAN.md`

---

## Implementation Summary (2025-12-30)

### Completed Components

| Component | Status | Notes |
|-----------|--------|-------|
| Semantic Query Interface | ✅ Done | `query_semantic()` with keyword fallback |
| Tool Mapping Table | ✅ Done | 34 mappings (benchmark ↔ Galaxy IDs) |
| AIAssistant Integration | ✅ Done | 4 public methods added |
| Database Population | ✅ Done | 5 studies, 22 tools, 64 results |

### Key Methods Added to AIAssistant

```python
# For ResearchAgent - answering "what's the best tool for X?"
ai.query_benchmark("best RNA-seq aligner")
# Returns: {'best_tool': 'STAR', 'evidence': 'Based on Baruzzo et al...'}

# For showing evidence to users
ai.get_benchmark_evidence_for_tool("STAR")
# Returns: {'rank': 1, 'doi': '10.1038/nmeth.4106', ...}

# For workflow generation - context-aware tool selection
ai.get_benchmark_informed_tool_selection(
    "align RNA-seq reads",
    context={'memory_limited': True}
)
# Returns: {'recommended_tool': 'HISAT2', 'galaxy_tool_id': 'hisat2', ...}

# For tool comparison
ai.compare_tools_for_task("STAR", "HISAT2")
# Returns: {'winner': 'STAR', 'evidence_text': '...'}
```

### Files Modified

| File | Changes |
|------|---------|
| `lib/galaxy/ai/benchmark_knowledge.py` | +300 lines: semantic search, tool mapping |
| `lib/galaxy/ai/ai_assistant.py` | +200 lines: benchmark integration methods |
| `database/benchmark_knowledge.db` | Populated with 5 benchmarks + 34 tool mappings |

---

## Executive Summary

This plan integrates the **Benchmark Knowledge System** into the AI Scientist architecture to provide:

1. **Evidence-backed tool recommendations** with benchmark rankings
2. **Benchmark citations** alongside literature citations
3. **Condition-aware tool selection** (data size, compute, sequence length)
4. **Tool comparison evidence** for user decision-making

**Key Insight:** The Benchmark Knowledge System complements literature search (PubMed/Scholar) by providing **structured, pre-curated performance data** rather than requiring LLM to extract rankings from paper text.

---

## Part 1: Technical Review Summary

### Current State (Updated After Implementation)

| Metric | Before | After | Target |
|--------|--------|-------|--------|
| Studies | 5 | 5 | 20+ |
| Tools | 22 | 22 | 100+ |
| Results | 64 | 64 | 500+ |
| Decision Rules | 28 | 50 | 100+ |
| Tool Mappings | 0 | **34** | 100+ |
| Integration | None | **AIAssistant** | Full |

### Critical Gaps Identified → Status

1. **~~No semantic query interface~~** ✅ RESOLVED - `query_semantic()` with keyword fallback
2. **~~No tool mapping~~** ✅ RESOLVED - 34 mappings (benchmark ↔ Galaxy IDs)
3. **~~No production integration~~** ✅ RESOLVED - Integrated into AIAssistant
4. **Limited coverage** ⏳ TODO - Missing ChIP-seq, metagenomics, proteomics

### Strengths to Leverage

1. **Structured rankings** - Pre-computed, no LLM extraction needed
2. **Decision rules** - Actionable condition→tool mappings
3. **Evidence generation** - Ready-to-use citation text
4. **Multi-condition support** - Handles tradeoffs

---

## Part 2: Integration Architecture

### 2.1 Where Benchmark Knowledge Fits

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           AIAssistant                                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   User Query                                                                 │
│       │                                                                      │
│       ▼                                                                      │
│   ┌────────────────────────────────────────────────────────────────────────┐│
│   │              UNIFIED INTENT ROUTER                                      ││
│   │                                                                         ││
│   │   Intent Types:                                                         ││
│   │   • workflow_generation → AgentOrchestrator + BenchmarkKnowledge        ││
│   │   • research_question → ResearchAgent + BenchmarkKnowledge              ││
│   │   • tool_recommendation → BenchmarkKnowledge (direct)    [NEW]          ││
│   │   • result_comparison → ResearchAgent + BenchmarkKnowledge              ││
│   └────────────────────────┬───────────────────────────────────────────────┘│
│                            │                                                 │
│         ┌──────────────────┼──────────────────────────────────────┐         │
│         ▼                  ▼                                      ▼         │
│   ┌───────────────┐  ┌───────────────┐                   ┌───────────────┐  │
│   │ AgentOrch.    │  │ ResearchAgent │                   │ BenchmarkKB   │  │
│   │               │  │               │◄──────────────────│ (NEW)         │  │
│   │ • DomainRouter│  │ • LitSearch   │ Benchmark data    │               │  │
│   │ • Specialists │  │ • Synthesizer │ for evidence      │ • Rankings    │  │
│   │ • Assembler   │  │ • Citations   │                   │ • Rules       │  │
│   │       │       │  │       │       │                   │ • Evidence    │  │
│   │       │       │  │       │       │                   └───────────────┘  │
│   │       ▼       │  │       ▼       │                          ▲           │
│   │ ┌───────────┐ │  │ Uses benchmark│                          │           │
│   │ │Tool Select│◄├──┤ rankings for  │                          │           │
│   │ │with bench │ │  │ tool evidence │                          │           │
│   │ │rankings   │ │  └───────────────┘                          │           │
│   │ └───────────┘ │                                              │           │
│   └───────┬───────┘                                              │           │
│           │                                                      │           │
│           └──────────────────────────────────────────────────────┘           │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### 2.2 Integration Points

| Component | Integration | Purpose |
|-----------|-------------|---------|
| **UnifiedIntentRouter** | Add `TOOL_RECOMMENDATION` intent | Route "what's the best X?" queries |
| **ResearchAgent** | Inject benchmark rankings into synthesis | Structured evidence for answers |
| **AgentOrchestrator** | Query benchmarks during tool selection | Evidence-backed workflow tools |
| **WorkflowAssembler** | Add benchmark citations to validation | Explain tool choices |
| **API** | New endpoint `/api/ai_assistant/benchmark_evidence` | Direct benchmark queries |

---

## Part 3: Implementation Plan

### Phase 1: Core Integration (Week 1-2)

#### 3.1.1 Add Semantic Query Interface

**File:** `backend/lib/galaxy/ai/benchmark_knowledge.py`

```python
from sentence_transformers import SentenceTransformer
from sklearn.metrics.pairwise import cosine_similarity

class BenchmarkKnowledgeDB:
    def __init__(self, db_path: str = None, enable_semantic: bool = True):
        # ... existing init ...

        # ADD: Semantic search capability
        self._embedding_model = None
        self._embeddings_cache = {}
        self._enable_semantic = enable_semantic

    @property
    def embedding_model(self):
        """Lazy-load embedding model."""
        if self._embedding_model is None and self._enable_semantic:
            self._embedding_model = SentenceTransformer('all-MiniLM-L6-v2')
            self._build_embeddings_index()
        return self._embedding_model

    def _build_embeddings_index(self):
        """Pre-compute embeddings for all tasks and decision rules."""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()

        # Index tasks
        cursor.execute("""
            SELECT task_id, task_name, biological_question
            FROM benchmark_tasks
        """)
        for task_id, task_name, bio_q in cursor.fetchall():
            text = f"{task_name}. {bio_q or ''}"
            self._embeddings_cache[f"task:{task_id}"] = {
                'embedding': self._embedding_model.encode(text),
                'type': 'task',
                'id': task_id,
                'text': text
            }

        # Index decision rules
        cursor.execute("""
            SELECT id, rule_type, condition, recommendation, reason
            FROM benchmark_decision_rules
        """)
        for rule_id, rule_type, condition, rec, reason in cursor.fetchall():
            text = f"{rule_type} {condition}: {rec}. {reason or ''}"
            self._embeddings_cache[f"rule:{rule_id}"] = {
                'embedding': self._embedding_model.encode(text),
                'type': 'rule',
                'id': rule_id,
                'text': text
            }

        conn.close()

    def query_semantic(
        self,
        user_query: str,
        top_k: int = 5,
        min_similarity: float = 0.5,
        include_rankings: bool = True
    ) -> List[Dict[str, Any]]:
        """
        Query benchmarks using natural language.

        Args:
            user_query: Natural language query (e.g., "best tool for RNA-seq alignment")
            top_k: Number of results
            min_similarity: Minimum cosine similarity threshold
            include_rankings: Whether to include full rankings for matched tasks

        Returns:
            List of relevant benchmark data with similarity scores
        """
        if not self._enable_semantic:
            return self._fallback_keyword_search(user_query, top_k)

        query_embedding = self.embedding_model.encode(user_query)

        # Score all cached embeddings
        scored_results = []
        for key, data in self._embeddings_cache.items():
            similarity = cosine_similarity(
                [query_embedding],
                [data['embedding']]
            )[0][0]

            if similarity >= min_similarity:
                scored_results.append({
                    'key': key,
                    'similarity': float(similarity),
                    **data
                })

        # Sort by similarity
        scored_results.sort(key=lambda x: x['similarity'], reverse=True)
        top_results = scored_results[:top_k]

        # Enrich with benchmark data
        enriched = []
        for result in top_results:
            if result['type'] == 'task' and include_rankings:
                # Add rankings for this task
                rankings = self.get_rankings_for_task(result['id'], limit=5)
                result['rankings'] = rankings
                result['evidence'] = self.generate_evidence_text(
                    rankings[0]['tool_name'] if rankings else None,
                    result['id']
                )
            elif result['type'] == 'rule':
                # Get full rule details
                conn = sqlite3.connect(self.db_path)
                cursor = conn.cursor()
                cursor.execute("""
                    SELECT dr.*, bs.title, bs.doi
                    FROM benchmark_decision_rules dr
                    JOIN benchmark_studies bs ON dr.benchmark_id = bs.benchmark_id
                    WHERE dr.id = ?
                """, (result['id'],))
                row = cursor.fetchone()
                if row:
                    result['recommendation'] = row[3]
                    result['recommended_tools'] = json.loads(row[4]) if row[4] else []
                    result['reason'] = row[5]
                    result['evidence'] = row[6]
                    result['benchmark_paper'] = row[7]
                    result['doi'] = row[8]
                conn.close()

            enriched.append(result)

        return enriched

    def _fallback_keyword_search(self, query: str, top_k: int) -> List[Dict]:
        """Keyword-based fallback when semantic search is disabled."""
        # Simple keyword matching against task names and rules
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()

        results = []
        keywords = query.lower().split()

        # Search tasks
        cursor.execute("SELECT task_id, task_name, biological_question FROM benchmark_tasks")
        for task_id, name, question in cursor.fetchall():
            text = f"{name} {question or ''}".lower()
            matches = sum(1 for kw in keywords if kw in text)
            if matches > 0:
                results.append({
                    'type': 'task',
                    'id': task_id,
                    'similarity': matches / len(keywords),
                    'rankings': self.get_rankings_for_task(task_id, limit=3)
                })

        conn.close()
        results.sort(key=lambda x: x['similarity'], reverse=True)
        return results[:top_k]
```

#### 3.1.2 Add Tool Mapping Table

**File:** `backend/lib/galaxy/ai/benchmark_knowledge.py`

```python
def _init_schema(self):
    # ... existing tables ...

    # ADD: Tool mapping table
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS benchmark_tool_galaxy_mapping (
            id INTEGER PRIMARY KEY,
            benchmark_tool_name TEXT NOT NULL,
            galaxy_tool_id TEXT NOT NULL,
            mapping_confidence REAL DEFAULT 1.0,
            mapping_method TEXT DEFAULT 'manual',
            notes TEXT,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP,
            UNIQUE(benchmark_tool_name, galaxy_tool_id)
        )
    """)

    cursor.execute("""
        CREATE INDEX IF NOT EXISTS idx_mapping_benchmark_name
        ON benchmark_tool_galaxy_mapping(benchmark_tool_name)
    """)

def add_tool_mapping(
    self,
    benchmark_tool_name: str,
    galaxy_tool_id: str,
    confidence: float = 1.0,
    method: str = "manual"
) -> int:
    """Add a mapping between benchmark tool name and Galaxy tool ID."""
    conn = sqlite3.connect(self.db_path)
    cursor = conn.cursor()

    cursor.execute("""
        INSERT OR REPLACE INTO benchmark_tool_galaxy_mapping
        (benchmark_tool_name, galaxy_tool_id, mapping_confidence, mapping_method)
        VALUES (?, ?, ?, ?)
    """, (benchmark_tool_name, galaxy_tool_id, confidence, method))

    mapping_id = cursor.lastrowid
    conn.commit()
    conn.close()
    return mapping_id

def resolve_to_galaxy_id(
    self,
    benchmark_tool_name: str,
    galaxy_app=None
) -> Optional[str]:
    """
    Resolve benchmark tool name to Galaxy tool ID.

    Strategy:
    1. Check explicit mapping table
    2. Fuzzy match against Galaxy toolbox
    3. Return None if no match
    """
    conn = sqlite3.connect(self.db_path)
    cursor = conn.cursor()

    # 1. Check mapping table
    cursor.execute("""
        SELECT galaxy_tool_id, mapping_confidence
        FROM benchmark_tool_galaxy_mapping
        WHERE LOWER(benchmark_tool_name) = LOWER(?)
        ORDER BY mapping_confidence DESC
        LIMIT 1
    """, (benchmark_tool_name,))

    result = cursor.fetchone()
    conn.close()

    if result and result[1] >= 0.8:
        return result[0]

    # 2. Fuzzy match against Galaxy toolbox
    if galaxy_app:
        from difflib import get_close_matches

        tool_names = {
            t.name.lower(): t.id
            for t in galaxy_app.toolbox.tools_by_id.values()
        }

        matches = get_close_matches(
            benchmark_tool_name.lower(),
            tool_names.keys(),
            n=1,
            cutoff=0.7
        )

        if matches:
            galaxy_id = tool_names[matches[0]]
            # Cache this mapping
            self.add_tool_mapping(
                benchmark_tool_name,
                galaxy_id,
                confidence=0.85,
                method="fuzzy"
            )
            return galaxy_id

    return None
```

#### 3.1.3 Populate Initial Tool Mappings

**File:** `backend/lib/galaxy/ai/benchmark_knowledge.py`

```python
def populate_tool_mappings(db: BenchmarkKnowledgeDB):
    """Populate initial benchmark-to-Galaxy tool mappings."""

    mappings = [
        # RNA-seq alignment
        ("STAR", "rna_star", 1.0, "manual"),
        ("HISAT2", "hisat2", 1.0, "manual"),
        ("TopHat2", "tophat2", 0.9, "manual"),
        ("Subread", "subread_align", 0.9, "manual"),

        # Variant calling
        ("DeepVariant", "deepvariant", 1.0, "manual"),
        ("GATK HaplotypeCaller", "gatk4_haplotypecaller", 1.0, "manual"),
        ("FreeBayes", "freebayes", 1.0, "manual"),
        ("Strelka2", "strelka_germline", 0.9, "manual"),

        # Single-cell
        ("scVI", "biomni/genomics/create_scvi_embeddings_scRNA", 1.0, "manual"),
        ("Harmony", "biomni/genomics/create_harmony_embeddings_scRNA", 1.0, "manual"),
        ("Scanorama", "scanorama", 0.9, "manual"),

        # Differential expression
        ("DESeq2", "deseq2", 1.0, "manual"),
        ("edgeR", "edger", 1.0, "manual"),
        ("limma-voom", "limma_voom", 0.9, "manual"),

        # RNA gLM tools (biomni)
        ("SpliceBERT", "biomni/genomics/generate_gene_embeddings_with_ESM_models", 0.8, "inferred"),
        ("RNA-FM", "biomni/genomics/generate_gene_embeddings_with_ESM_models", 0.8, "inferred"),
    ]

    for tool_name, galaxy_id, confidence, method in mappings:
        db.add_tool_mapping(tool_name, galaxy_id, confidence, method)

    return len(mappings)
```

### Phase 2: ResearchAgent Integration (Week 2-3)

#### 3.2.1 Add Benchmark Source to ResearchAgent

**File:** `backend/lib/galaxy/ai/agents/research_agent.py`

```python
from ..benchmark_knowledge import BenchmarkKnowledgeDB

class ResearchAgent:
    def __init__(
        self,
        llm_client: LLMClient,
        pubmed_client=None,
        semantic_scholar_client=None,
        benchmark_db: BenchmarkKnowledgeDB = None,  # ADD
        cache_enabled: bool = True
    ):
        self.llm = llm_client
        self.pubmed = pubmed_client
        self.semantic_scholar = semantic_scholar_client
        self.benchmark_db = benchmark_db or BenchmarkKnowledgeDB()  # ADD
        self._cache = {} if cache_enabled else None

    async def answer(
        self,
        query: str,
        context: Optional[Dict[str, Any]] = None,
        workflow_results: Optional[Dict] = None,
        max_citations: int = 5
    ) -> ResearchResponse:
        """Answer with literature + benchmark evidence."""

        # 1. Classify query type
        query_type = await self._classify_query(query, workflow_results)

        # 2. Search literature (existing)
        papers = await self._search_literature(query, query_type, max_citations * 2)

        # 3. NEW: Query benchmark knowledge
        benchmark_evidence = self._query_benchmarks(query, query_type)

        # 4. Synthesize with both sources
        synthesis = await self._synthesize_with_benchmarks(
            papers,
            benchmark_evidence,
            query,
            query_type
        )

        # 5. Generate response (modified to include benchmarks)
        if query_type == QueryType.RESULT_COMPARISON and workflow_results:
            answer = await self._compare_with_literature(
                workflow_results, synthesis, query
            )
        elif query_type == QueryType.CONCLUSION_DRAWING and workflow_results:
            answer = await self._draw_conclusions(
                workflow_results, synthesis, query
            )
        else:
            answer = await self._answer_question_with_benchmarks(
                query, synthesis, benchmark_evidence
            )

        # 6. Extract citations (literature + benchmarks)
        citations = self._extract_all_citations(answer, papers, benchmark_evidence)

        return ResearchResponse(
            answer=answer,
            citations=citations[:max_citations],
            confidence=self._calculate_confidence(citations, synthesis),
            query_type=query_type,
            follow_up_suggestions=await self._suggest_followups(query, answer),
            benchmark_evidence=benchmark_evidence  # ADD
        )

    def _query_benchmarks(
        self,
        query: str,
        query_type: QueryType
    ) -> Dict[str, Any]:
        """Query benchmark knowledge for relevant evidence."""

        # Semantic search for relevant benchmarks
        results = self.benchmark_db.query_semantic(
            query,
            top_k=5,
            min_similarity=0.4
        )

        if not results:
            return {'has_benchmarks': False}

        # Structure the evidence
        benchmark_evidence = {
            'has_benchmarks': True,
            'task_matches': [],
            'decision_rules': [],
            'tool_rankings': []
        }

        for result in results:
            if result['type'] == 'task':
                benchmark_evidence['task_matches'].append({
                    'task': result['text'],
                    'similarity': result['similarity'],
                    'rankings': result.get('rankings', []),
                    'evidence': result.get('evidence', '')
                })

                # Add tool rankings
                for ranking in result.get('rankings', []):
                    benchmark_evidence['tool_rankings'].append({
                        'tool': ranking['tool_name'],
                        'rank': ranking['rank'],
                        'metric': ranking['metric'],
                        'score': ranking['score'],
                        'benchmark': ranking['benchmark_paper'],
                        'doi': ranking['doi']
                    })

            elif result['type'] == 'rule':
                benchmark_evidence['decision_rules'].append({
                    'condition': result.get('text', ''),
                    'recommendation': result.get('recommendation', ''),
                    'tools': result.get('recommended_tools', []),
                    'reason': result.get('reason', ''),
                    'evidence': result.get('evidence', ''),
                    'doi': result.get('doi', '')
                })

        return benchmark_evidence

    async def _answer_question_with_benchmarks(
        self,
        query: str,
        synthesis: Dict,
        benchmark_evidence: Dict
    ) -> str:
        """Answer question using both literature and benchmark evidence."""

        # Format benchmark evidence for prompt
        benchmark_section = ""
        if benchmark_evidence.get('has_benchmarks'):
            benchmark_section = "\n\nBenchmark Evidence:\n"

            for ranking in benchmark_evidence.get('tool_rankings', [])[:5]:
                benchmark_section += f"- {ranking['tool']} ranked #{ranking['rank']} "
                benchmark_section += f"({ranking['metric']}={ranking['score']}) "
                benchmark_section += f"[Benchmark: {ranking['benchmark']}]\n"

            for rule in benchmark_evidence.get('decision_rules', [])[:3]:
                benchmark_section += f"- Recommendation: {rule['recommendation']}\n"
                benchmark_section += f"  Reason: {rule['reason']}\n"

        prompt = f"""Answer this research question using literature AND benchmark evidence:

Question: {query}

Literature Synthesis:
{synthesis.get('summary', 'No literature found')}

{benchmark_section}

Provide an answer that:
1. Directly addresses the question
2. Uses inline citations [1], [2], etc. for literature
3. Cites benchmark studies for tool recommendations
4. Notes any uncertainty or trade-offs

IMPORTANT: When recommending tools, cite benchmark evidence (e.g., "STAR ranked #1 for alignment accuracy [Baruzzo et al. 2017]")
"""

        return await self.llm.generate(prompt, max_tokens=1500)

    def _extract_all_citations(
        self,
        answer: str,
        papers: List[Dict],
        benchmark_evidence: Dict
    ) -> List[Citation]:
        """Extract citations from both literature and benchmarks."""

        citations = []

        # Literature citations
        for i, paper in enumerate(papers):
            marker = f"[{i+1}]"
            if marker in answer:
                citations.append(Citation(
                    type="paper",
                    title=paper.get('title', 'Unknown'),
                    url=paper.get('url', ''),
                    doi=paper.get('doi'),
                    authors=paper.get('authors', []),
                    year=paper.get('year'),
                    relevance=1.0 - (i * 0.1)
                ))

        # Benchmark citations
        if benchmark_evidence.get('has_benchmarks'):
            seen_dois = set()
            for ranking in benchmark_evidence.get('tool_rankings', []):
                doi = ranking.get('doi')
                if doi and doi not in seen_dois:
                    seen_dois.add(doi)
                    citations.append(Citation(
                        type="benchmark",
                        title=ranking.get('benchmark', 'Benchmark Study'),
                        doi=doi,
                        relevance=0.9,
                        metadata={
                            'tool': ranking['tool'],
                            'rank': ranking['rank'],
                            'metric': ranking['metric'],
                            'score': ranking['score']
                        }
                    ))

        return citations
```

### Phase 3: Workflow Generation Integration (Week 3-4)

#### 3.3.1 Add Benchmark-Informed Tool Selection

**File:** `backend/lib/galaxy/ai/agents/domain_specialist.py`

```python
class DomainSpecialist:
    def __init__(
        self,
        domain: str,
        llm_client,
        tool_recommender,
        benchmark_db: BenchmarkKnowledgeDB = None  # ADD
    ):
        self.domain = domain
        self.llm = llm_client
        self.tools = tool_recommender
        self.benchmark_db = benchmark_db or BenchmarkKnowledgeDB()

    def recommend_tools_with_evidence(
        self,
        task_description: str,
        constraints: Dict[str, str] = None
    ) -> List[Dict[str, Any]]:
        """
        Recommend tools with benchmark evidence.

        Args:
            task_description: What the user wants to do
            constraints: Optional constraints (data_size, compute, etc.)

        Returns:
            List of tool recommendations with benchmark evidence
        """
        recommendations = []

        # 1. Query benchmarks for this task
        benchmark_results = self.benchmark_db.query_semantic(
            task_description,
            top_k=5
        )

        # 2. Get decision rules for constraints
        if constraints:
            for constraint_type, constraint_value in constraints.items():
                rules = self.benchmark_db.get_recommendation_for_condition(
                    constraint_type, constraint_value
                )
                for rule in rules:
                    recommendations.append({
                        'source': 'benchmark_rule',
                        'tools': rule['recommended_tools'],
                        'reason': rule['reason'],
                        'evidence': rule['evidence'],
                        'constraint': f"{constraint_type}={constraint_value}",
                        'doi': rule['doi']
                    })

        # 3. Add task-specific rankings
        for result in benchmark_results:
            if result['type'] == 'task':
                for ranking in result.get('rankings', [])[:3]:
                    recommendations.append({
                        'source': 'benchmark_ranking',
                        'tool': ranking['tool_name'],
                        'rank': ranking['rank'],
                        'metric': ranking['metric'],
                        'score': ranking['score'],
                        'evidence': result.get('evidence', ''),
                        'benchmark': ranking['benchmark_paper'],
                        'doi': ranking['doi']
                    })

        # 4. Resolve to Galaxy tool IDs
        for rec in recommendations:
            tools = rec.get('tools') or [rec.get('tool')]
            rec['galaxy_tool_ids'] = []
            for tool in tools:
                if tool:
                    galaxy_id = self.benchmark_db.resolve_to_galaxy_id(tool)
                    if galaxy_id:
                        rec['galaxy_tool_ids'].append(galaxy_id)

        return recommendations
```

#### 3.3.2 Add Evidence to Workflow Responses

**File:** `backend/lib/galaxy/ai/agents/workflow_assembler.py`

```python
class WorkflowAssembler:
    def __init__(
        self,
        llm_client,
        workflow_validator,
        benchmark_db: BenchmarkKnowledgeDB = None
    ):
        self.llm = llm_client
        self.validator = workflow_validator
        self.benchmark_db = benchmark_db or BenchmarkKnowledgeDB()

    def assemble_with_evidence(
        self,
        domain_recommendations: List[Dict],
        benchmark_recommendations: List[Dict]
    ) -> Dict[str, Any]:
        """
        Assemble workflow with benchmark evidence.

        Returns workflow with:
        - Tool selections with evidence
        - Citations for each tool choice
        - Alternative tools with trade-offs
        """
        workflow = {
            'steps': [],
            'tool_evidence': {},
            'benchmark_citations': []
        }

        # Build evidence for each step
        for step in domain_recommendations:
            tool_id = step.get('tool_id')

            # Find benchmark evidence for this tool
            evidence = self._get_tool_evidence(tool_id)

            workflow['steps'].append({
                **step,
                'has_benchmark_evidence': bool(evidence),
                'benchmark_evidence': evidence
            })

            if evidence:
                workflow['tool_evidence'][tool_id] = evidence

                # Collect citations
                if evidence.get('doi'):
                    workflow['benchmark_citations'].append({
                        'tool': tool_id,
                        'benchmark': evidence.get('benchmark_paper'),
                        'doi': evidence['doi'],
                        'rank': evidence.get('rank'),
                        'metric': evidence.get('metric'),
                        'score': evidence.get('score')
                    })

        return workflow

    def _get_tool_evidence(self, tool_id: str) -> Optional[Dict]:
        """Get benchmark evidence for a tool."""
        # Try to find tool in benchmarks
        results = self.benchmark_db.get_tool_performance(tool_id)

        if not results:
            # Try common name variations
            tool_name = tool_id.split('/')[-1].replace('_', ' ').title()
            results = self.benchmark_db.get_tool_performance(tool_name)

        if results:
            best = min(results, key=lambda x: x.get('rank', 999))
            return {
                'task': best['task_name'],
                'rank': best['rank'],
                'metric': best['metric'],
                'score': best['score'],
                'benchmark_paper': best['benchmark_paper'],
                'doi': best['doi'],
                'notes': best.get('notes', '')
            }

        return None

    def generate_evidence_summary(self, workflow: Dict) -> str:
        """Generate human-readable evidence summary for workflow."""
        if not workflow.get('benchmark_citations'):
            return "No benchmark evidence available for tool selections."

        lines = ["**Tool Selection Evidence:**\n"]

        for citation in workflow['benchmark_citations']:
            lines.append(
                f"- **{citation['tool']}**: Ranked #{citation['rank']} "
                f"({citation['metric']}={citation['score']}) "
                f"in {citation['benchmark']} (DOI: {citation['doi']})"
            )

        return "\n".join(lines)
```

### Phase 4: API Endpoints (Week 4)

#### 3.4.1 Add Benchmark Query Endpoint

**File:** `backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py`

```python
@router.post("/api/ai_assistant/benchmark_query")
async def query_benchmarks(
    request: BenchmarkQueryRequest,
    ai_assistant: AIAssistant = Depends(get_ai_assistant)
) -> BenchmarkQueryResponse:
    """
    Query benchmark knowledge for tool recommendations.

    Args:
        query: Natural language query
        constraints: Optional constraints (data_size, compute, etc.)

    Returns:
        Tool recommendations with benchmark evidence
    """
    results = ai_assistant.benchmark_db.query_semantic(
        request.query,
        top_k=request.top_k or 10
    )

    # Apply constraint-based rules if provided
    if request.constraints:
        for constraint_type, constraint_value in request.constraints.items():
            rules = ai_assistant.benchmark_db.get_recommendation_for_condition(
                constraint_type, constraint_value
            )
            for rule in rules:
                results.append({
                    'type': 'decision_rule',
                    'recommendation': rule['recommendation'],
                    'tools': rule['recommended_tools'],
                    'reason': rule['reason'],
                    'evidence': rule['evidence'],
                    'constraint': f"{constraint_type}={constraint_value}"
                })

    return BenchmarkQueryResponse(
        query=request.query,
        results=results,
        has_evidence=bool(results)
    )


@router.post("/api/ai_assistant/tool_comparison")
async def compare_tools(
    request: ToolComparisonRequest,
    ai_assistant: AIAssistant = Depends(get_ai_assistant)
) -> ToolComparisonResponse:
    """
    Compare tools based on benchmark data.

    Args:
        tool_a: First tool name
        tool_b: Second tool name
        task: Optional specific task to compare on

    Returns:
        Detailed comparison with evidence
    """
    comparison = ai_assistant.benchmark_db.compare_tools(
        request.tool_a,
        request.tool_b,
        task_id=request.task
    )

    evidence_text = ai_assistant.benchmark_db.generate_comparison_evidence(
        request.tool_a,
        request.tool_b,
        task_id=request.task
    )

    return ToolComparisonResponse(
        tool_a=request.tool_a,
        tool_b=request.tool_b,
        comparison=comparison,
        evidence=evidence_text
    )
```

### Phase 5: Benchmark Expansion (Week 5-6)

#### 3.5.1 Priority Benchmarks to Add

| Priority | Domain | Paper | Tools | Impact |
|----------|--------|-------|-------|--------|
| P0 | ChIP-seq | ENCODE 2020 | MACS2, HOMER, SPP | 15% of workflows |
| P0 | Genome assembly | Phillippy 2023 | HiFiasm, Flye, Canu | Foundation |
| P1 | Metagenomics | CAMI | Kraken2, MetaPhlAn | 10% workflows |
| P1 | Protein structure | AlphaFold | AlphaFold, ESMFold | High impact |
| P2 | Pathway enrichment | Wijesooriya 2022 | GSEA, Enrichr | Common downstream |

#### 3.5.2 Semi-Automated Population

```python
async def populate_benchmark_from_doi(
    db: BenchmarkKnowledgeDB,
    doi: str,
    llm_client
) -> Dict[str, Any]:
    """
    Semi-automated benchmark extraction from paper.

    Uses LLM to extract structured benchmark data.
    """
    # 1. Fetch paper content
    paper = await fetch_paper_content(doi)

    # 2. Extract with LLM
    extraction_prompt = f"""
    Extract benchmark data from this paper:

    {paper['abstract'][:2000]}
    {paper.get('methods', '')[:3000]}

    Return JSON with:
    {{
        "benchmark_id": "short_id",
        "title": "paper title",
        "tools": [{{"name": "", "strengths": [], "weaknesses": []}}],
        "tasks": [{{"task_id": "", "task_name": "", "metrics": []}}],
        "results": [{{"tool": "", "task": "", "metric": "", "score": 0.0, "rank": 0}}],
        "decision_rules": [{{"condition": "", "recommendation": "", "reason": ""}}]
    }}
    """

    extracted = await llm_client.generate(extraction_prompt, max_tokens=2000)
    data = json.loads(extracted)

    # 3. Validate and review
    validation = validate_benchmark_data(data)

    if validation['confidence'] < 0.7:
        return {
            'status': 'needs_review',
            'data': data,
            'issues': validation['issues']
        }

    # 4. Populate database
    populate_benchmark_from_extracted(db, data, doi)

    return {'status': 'success', 'data': data}
```

---

## Part 4: Integration with Existing AI Scientist Plan

### 4.1 Modified UnifiedIntentRouter

Add new intent type for benchmark queries:

```python
class UserIntent(Enum):
    WORKFLOW_GENERATION = "workflow_generation"
    RESEARCH_QUESTION = "research_question"
    RESULT_COMPARISON = "result_comparison"
    CONCLUSION_DRAWING = "conclusion_drawing"
    TOOL_RECOMMENDATION = "tool_recommendation"  # NEW - routes to benchmarks
    TOOL_SEARCH = "tool_search"
    GENERAL_CHAT = "general_chat"

# Add patterns
INTENT_PATTERNS[UserIntent.TOOL_RECOMMENDATION] = [
    r'\b(best|optimal|recommended)\b.*(tool|method|algorithm)',
    r'\bwhich\s+(tool|method)\s+should\s+i\s+use',
    r'\bcompare\b.*(tools|methods)',
    r'\b(rank|ranking)\b.*(tools|methods)',
]
```

### 4.2 Modified AIAssistant.process_query

```python
elif intent_decision.intent == UserIntent.TOOL_RECOMMENDATION:
    # Use benchmark knowledge directly
    benchmark_results = self.benchmark_db.query_semantic(
        query,
        top_k=10
    )

    # Format response with evidence
    response = await self._format_benchmark_response(query, benchmark_results)

    return {
        'type': 'tool_recommendation',
        'answer': response['answer'],
        'recommendations': response['recommendations'],
        'citations': response['citations'],
        'has_benchmark_evidence': True
    }
```

### 4.3 Modified ResearchAgent Skills Mapping

```python
# In SkillLoader
INTENT_TO_SKILLS = {
    UserIntent.RESEARCH_QUESTION: [
        "scientific-thinking/hypothesis-generation",
        "scientific-databases/pubmed-database"
    ],
    UserIntent.RESULT_COMPARISON: [
        "scientific-thinking/peer-review",
        "scientific-databases/pubmed-database"
    ],
    UserIntent.CONCLUSION_DRAWING: [
        "scientific-thinking/exploratory-data-analysis",
        "scientific-thinking/scientific-critical-thinking"
    ],
    UserIntent.TOOL_RECOMMENDATION: [  # NEW
        "scientific-databases/pubmed-database",
        # Benchmark knowledge injected separately (not a skill file)
    ]
}
```

---

## Part 5: Implementation Timeline

| Week | Phase | Deliverables |
|------|-------|--------------|
| 1 | Core Integration | Semantic query, tool mapping, basic integration |
| 2 | ResearchAgent | Benchmark evidence in answers, combined citations |
| 3 | Workflow Gen | Benchmark-informed tool selection, evidence in workflows |
| 4 | API + Testing | New endpoints, integration tests |
| 5-6 | Expansion | Add 10+ priority benchmarks |

---

## Part 6: Success Metrics

| Metric | Current | Target |
|--------|---------|--------|
| Tool recommendations with evidence | 0% | >60% |
| Benchmark-backed workflow steps | 0% | >40% |
| User queries with benchmark citations | 0% | >30% |
| Benchmark coverage (domains) | 5 | 15+ |

---

## Part 7: Files to Create/Modify

### New Files
```
backend/lib/galaxy/ai/
├── benchmark_knowledge.py          # Existing - add semantic search
├── agents/
│   ├── benchmark_evidence_agent.py # NEW - standalone benchmark queries
│   └── ...
```

### Modified Files
| File | Changes |
|------|---------|
| `agents/unified_intent_router.py` | Add TOOL_RECOMMENDATION intent |
| `agents/research_agent.py` | Add benchmark source, combined citations |
| `agents/domain_specialist.py` | Add benchmark-informed recommendations |
| `agents/workflow_assembler.py` | Add evidence to workflow responses |
| `ai_assistant.py` | Initialize benchmark_db, route new intent |
| `webapps/galaxy/api/ai_assistant.py` | Add benchmark endpoints |

---

## Conclusion

The Benchmark Knowledge System provides **structured, pre-curated evidence** that complements the AI Scientist's literature synthesis capabilities. By integrating benchmarks into:

1. **ResearchAgent** - Provides tool rankings alongside literature
2. **Workflow Generation** - Evidence-backed tool selection
3. **Direct Queries** - Benchmark comparisons and recommendations

Users receive **evidence-based recommendations** with clear citations, improving trust and reproducibility.
