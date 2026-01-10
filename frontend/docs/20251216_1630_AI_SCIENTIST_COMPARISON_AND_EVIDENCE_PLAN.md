# AI Scientist Frameworks Comparison & BioMate Evidence System Plan

**Date**: 2025-12-16 16:30
**Branch**: `new_framework_platform`
**Status**: Planning

---

## Part 1: AI Scientist Frameworks Comparison

### Overview of Reviewed Frameworks

| Framework | Organization | Focus | Key Innovation |
|-----------|--------------|-------|----------------|
| **OmniScientist** | Tsinghua FIB-LAB | Full research lifecycle | Co-evolving AI-human ecosystem |
| **AI-Scientist** | Sakana AI | ML paper generation | End-to-end autonomous paper writing |
| **Kosmos** | Open Source | General scientific research | Multi-agent with Docker sandbox |
| **OmniCellAgent** | WashU | Precision medicine | Single-cell omics integration |
| **BioMate** | Ours | Bioinformatics workflows | Practical tool orchestration |

---

### Detailed Framework Analysis

#### 1. OmniScientist (Tsinghua)
**Repository**: https://github.com/tsinghua-fib-lab/OmniScientist

**Architecture Components:**
- **Deep Ideation**: Scientific concept networks for novel research connections
- **AgentExpt**: Automated experiment design with codebase/dataset retrieval
- **MirrorMind**: Human expert knowledge integration
- **HybridQuestion**: Human-AI collaborative question identification

**Strengths:**
- Emphasizes human-AI collaboration (not fully autonomous)
- Institutional backing with published papers
- Focus on encoding research methodologies

**Limitations:**
- Early stage, methodology-focused
- Less focus on practical execution

**Relevance to BioMate**:
- **Deep Ideation** approach could enhance our workflow design rationale
- **AgentExpt** similar to our tool/workflow retrieval

---

#### 2. AI-Scientist (Sakana AI)
**Repository**: https://github.com/SakanaAI/AI-Scientist

**Architecture Components:**
- Idea generation with Semantic Scholar novelty checking
- Autonomous code implementation and execution
- LaTeX paper generation with citations
- LLM-based peer review simulation

**Built-in Templates:**
1. NanoGPT (transformer tasks)
2. 2D Diffusion (generative models)
3. Grokking (deep learning generalization)

**Strengths:**
- Most mature end-to-end system
- Publication-ready outputs
- Semantic Scholar integration for citations
- Customizable templates

**Limitations:**
- ML/AI focused, not biology
- Requires significant GPU resources
- Templates limit scope

**Relevance to BioMate**:
- **Citation system** (Semantic Scholar/OpenAlex) directly applicable
- **Template architecture** could inspire our workflow templates
- **Review simulation** interesting for workflow validation

---

#### 3. Kosmos
**Repository**: https://github.com/jimmc414/Kosmos

**Architecture Components:**
- Multi-agent system (hypothesis, experiment, analysis, literature, planning agents)
- ArXiv/PubMed/Semantic Scholar integration
- Docker sandboxed code execution
- Knowledge graph for concept tracking
- 8-dimension quality framework for validation

**Strengths:**
- Literature integration with hierarchical compression (20:1)
- Security-focused execution (sandboxed Docker)
- Multi-agent coordination
- Open source implementation

**Limitations:**
- Has not reproduced claimed results (79.4% accuracy)
- Experimental, not production-ready

**Relevance to BioMate**:
- **Literature compression** technique valuable for evidence gathering
- **Multi-agent architecture** could improve our workflow planning
- **Knowledge graph** useful for tracking tool/method relationships

---

#### 4. OmniCellAgent (WashU)
**Paper**: https://www.biorxiv.org/content/10.1101/2025.07.31.667797v1

**Focus**: Precision medicine via single-cell omics

**Key Features:**
- Designed for non-computational experts (clinicians, patients)
- Integrates scRNA-seq data analysis
- Autonomous hypothesis generation
- Precision therapy identification

**Strengths:**
- Biology/medicine specific (closest to our domain)
- Targets practical clinical applications
- Designed for non-experts

**Limitations:**
- Focused on single-cell analysis only
- Less general-purpose

**Relevance to BioMate**:
- **Most aligned** with our bioinformatics focus
- **User targeting** (non-experts) matches our goal
- **Omic data integration** approach valuable

---

### Comparison Matrix

| Capability | OmniScientist | AI-Scientist | Kosmos | OmniCellAgent | BioMate |
|------------|---------------|--------------|--------|---------------|---------|
| **Literature Search** | Planned | Semantic Scholar | PubMed/ArXiv/SS | Yes | **No** |
| **Citations** | Planned | Yes (inline) | Yes | Yes | **No** |
| **Hypothesis Gen** | Yes | Yes | Yes | Yes | Partial |
| **Experiment Design** | Yes | Templates | Yes | Yes | **Workflow Gen** |
| **Code Execution** | Planned | Yes | Docker | Yes | Galaxy Jobs |
| **Paper Writing** | Planned | Yes (LaTeX) | Partial | No | No |
| **Domain** | General | ML/AI | General | Biology | **Bioinformatics** |
| **Tool Orchestration** | No | No | No | Partial | **Yes (9k+ tools)** |
| **Workflow Building** | No | No | No | No | **Yes (951 templates)** |
| **User Level** | Expert | Expert | Expert | Non-expert | **Non-expert** |

---

## Part 2: BioMate's Unique Position

### What BioMate Does Better

1. **Practical Workflow Execution**
   - 9,103 indexed Galaxy tools
   - 951 pre-built workflow templates
   - Real tool orchestration (not just simulation)
   - Production-ready bioinformatics pipelines

2. **Tool Ecosystem Integration**
   - Galaxy ToolShed integration
   - nf-core pipeline patterns
   - BioMNI dataset compatibility
   - EDAM ontology mapping

3. **Non-Expert Accessibility**
   - Natural language to workflow conversion
   - Chat-first interface
   - Automated parameter inference
   - No coding required

### What BioMate Lacks (vs AI Scientists)

1. **Evidence & Citations** - No literature backing for recommendations
2. **Hypothesis Generation** - Focused on execution, not discovery
3. **Scientific Reasoning Chain** - No visible reasoning/justification
4. **Knowledge Graphs** - No concept relationship tracking
5. **Literature Compression** - No paper summarization

---

## Part 3: Strategic Recommendation

### Proposed Architecture: Hybrid Approach

```
┌─────────────────────────────────────────────────────────────────┐
│                      BioMate Platform                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────┐ │
│  │  RESEARCH LAYER │    │  EVIDENCE LAYER │    │ EXECUTION   │ │
│  │  (New/External) │    │  (New)          │    │ LAYER       │ │
│  │                 │    │                 │    │ (Existing)  │ │
│  │ • Literature    │───▶│ • Citations     │───▶│ • Workflows │ │
│  │   Survey        │    │ • Justification │    │ • Tools     │ │
│  │ • Hypothesis    │    │ • Best Practice │    │ • Parameters│ │
│  │   Generation    │    │ • Confidence    │    │ • Execution │ │
│  │ • Gap Analysis  │    │   Scoring       │    │             │ │
│  └─────────────────┘    └─────────────────┘    └─────────────┘ │
│         │                       │                     │        │
│         ▼                       ▼                     ▼        │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                    UNIFIED RESPONSE                       │  │
│  │  "For RNA-seq analysis, I recommend HISAT2 [1] for       │  │
│  │   alignment due to its splice-aware algorithm [2].       │  │
│  │   Using quality threshold of 20 based on best practices  │  │
│  │   from nf-core/rnaseq pipeline [3]."                     │  │
│  │                                                           │  │
│  │   Sources:                                                │  │
│  │   [1] Kim et al. 2019, Nature Methods                    │  │
│  │   [2] HISAT2 documentation, Johns Hopkins                │  │
│  │   [3] nf-core/rnaseq v3.14.0 default parameters         │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### What to BUILD vs INTEGRATE

| Capability | Approach | Source |
|------------|----------|--------|
| **Literature Search** | INTEGRATE | PubMed API, Semantic Scholar API |
| **Paper Citations** | INTEGRATE | Semantic Scholar, CrossRef |
| **Tool Citations** | BUILD | bio.tools API + our database |
| **Parameter Justification** | BUILD | nf-core docs, Galaxy best practices |
| **Hypothesis Generation** | INTEGRATE | OmniScientist/AI-Scientist concepts |
| **Workflow Rationale** | BUILD | Our RAG + LLM reasoning |
| **Knowledge Graph** | CONSIDER | Inspired by Kosmos |

---

## Part 4: Detailed Implementation Plan

### Phase 1: Evidence Foundation (Week 1-2)

#### 1.1 Citation Data Model

```typescript
interface Citation {
  id: string
  type: 'paper' | 'tool' | 'documentation' | 'pipeline' | 'database'
  title: string
  authors?: string[]
  url: string
  doi?: string
  pmid?: string
  year?: number
  relevance: number  // 0-1 score
  excerpt?: string   // relevant quote
}

interface EvidencedRecommendation {
  recommendation: string
  confidence: number
  citations: Citation[]
  reasoning: string
}

interface EvidencedWorkflowStep {
  step: WorkflowStep
  toolCitation: Citation        // Original tool paper
  parameterEvidence: Citation[] // Why these parameters
  alternativeTools: Array<{
    tool: string
    citation: Citation
    reason: string
  }>
}
```

#### 1.2 Citation Database Schema

```sql
-- Tool citations (populated from bio.tools + manual curation)
CREATE TABLE tool_citations (
  tool_id TEXT PRIMARY KEY,
  paper_doi TEXT,
  paper_pmid TEXT,
  paper_title TEXT,
  paper_authors TEXT,
  paper_year INTEGER,
  documentation_url TEXT,
  bio_tools_id TEXT
);

-- Parameter best practices
CREATE TABLE parameter_evidence (
  id INTEGER PRIMARY KEY,
  tool_id TEXT,
  parameter_name TEXT,
  recommended_value TEXT,
  source_type TEXT,  -- 'nf-core', 'paper', 'documentation'
  source_url TEXT,
  source_excerpt TEXT,
  confidence REAL
);

-- Workflow patterns
CREATE TABLE workflow_citations (
  workflow_pattern TEXT PRIMARY KEY,
  reference_pipeline TEXT,  -- e.g., 'nf-core/rnaseq'
  reference_url TEXT,
  paper_doi TEXT,
  description TEXT
);
```

### Phase 2: API Integrations (Week 2-3)

#### 2.1 PubMed/Literature Search

```python
class LiteratureSearchService:
    """Search and retrieve scientific literature."""

    async def search_pubmed(self, query: str, max_results: int = 10) -> List[Citation]:
        """Search PubMed for relevant papers."""
        # Use NCBI E-utilities API
        # https://www.ncbi.nlm.nih.gov/books/NBK25501/
        pass

    async def search_semantic_scholar(self, query: str) -> List[Citation]:
        """Search Semantic Scholar for papers with citation context."""
        # https://api.semanticscholar.org/
        pass

    async def get_tool_papers(self, tool_name: str) -> List[Citation]:
        """Find original papers for a bioinformatics tool."""
        # Search: "{tool_name} bioinformatics" OR bio.tools lookup
        pass
```

#### 2.2 bio.tools Integration

```python
class BioToolsService:
    """Integrate with ELIXIR bio.tools registry."""

    BASE_URL = "https://bio.tools/api"

    async def get_tool_info(self, tool_id: str) -> Dict:
        """Get tool metadata including citations."""
        # Returns: description, publications, EDAM operations
        pass

    async def search_tools(self, query: str) -> List[Dict]:
        """Search bio.tools registry."""
        pass
```

### Phase 3: Evidence Generation (Week 3-4)

#### 3.1 Enhanced Tool Recommender

```python
class EvidencedToolRecommender:
    """Tool recommendations with citations."""

    async def recommend_with_evidence(
        self,
        task: str,
        data_type: str
    ) -> List[EvidencedRecommendation]:

        # 1. Get tool candidates (existing logic)
        tools = await self.tool_recommender.recommend(task, data_type)

        # 2. Enrich with citations
        evidenced = []
        for tool in tools:
            citations = await self.gather_evidence(tool)
            evidenced.append(EvidencedRecommendation(
                recommendation=tool.name,
                confidence=tool.score,
                citations=citations,
                reasoning=self.generate_reasoning(tool, citations)
            ))

        return evidenced

    async def gather_evidence(self, tool: ToolMatch) -> List[Citation]:
        """Gather citations for a tool recommendation."""
        citations = []

        # 1. Tool's original paper
        paper = await self.bio_tools.get_tool_publication(tool.id)
        if paper:
            citations.append(paper)

        # 2. Best practice documentation
        docs = await self.get_best_practice_docs(tool.id)
        citations.extend(docs)

        # 3. Comparative studies (why this tool vs alternatives)
        comparisons = await self.literature.search(
            f"{tool.name} comparison benchmark bioinformatics"
        )
        citations.extend(comparisons[:2])

        return citations
```

#### 3.2 Parameter Evidence Generator

```python
class ParameterEvidenceGenerator:
    """Generate evidence for parameter choices."""

    async def justify_parameters(
        self,
        tool_id: str,
        parameters: Dict[str, Any],
        user_context: str
    ) -> Dict[str, ParameterJustification]:

        justifications = {}

        for param_name, param_value in parameters.items():
            # 1. Check curated best practices
            best_practice = await self.db.get_parameter_evidence(
                tool_id, param_name
            )

            # 2. Check nf-core defaults
            nfcore_default = await self.get_nfcore_default(
                tool_id, param_name
            )

            # 3. Generate justification
            justifications[param_name] = ParameterJustification(
                value=param_value,
                source=best_practice or nfcore_default,
                confidence=self.calculate_confidence(
                    param_value, best_practice, nfcore_default
                ),
                reasoning=self.generate_param_reasoning(
                    param_name, param_value, user_context
                )
            )

        return justifications
```

### Phase 4: UI Integration (Week 4-5)

#### 4.1 Citation Display Component

```typescript
// components/citation-badge.tsx
interface CitationBadgeProps {
  citation: Citation
  index: number
}

export function CitationBadge({ citation, index }: CitationBadgeProps) {
  return (
    <TooltipProvider>
      <Tooltip>
        <TooltipTrigger asChild>
          <a
            href={citation.url}
            target="_blank"
            className="inline-flex items-center justify-center w-5 h-5
                       text-xs font-medium text-blue-600 bg-blue-100
                       rounded hover:bg-blue-200"
          >
            [{index + 1}]
          </a>
        </TooltipTrigger>
        <TooltipContent className="max-w-sm">
          <p className="font-medium">{citation.title}</p>
          {citation.authors && (
            <p className="text-xs text-muted-foreground">
              {citation.authors.slice(0, 3).join(', ')}
              {citation.authors.length > 3 && ' et al.'}
            </p>
          )}
          {citation.year && (
            <p className="text-xs">{citation.year}</p>
          )}
        </TooltipContent>
      </Tooltip>
    </TooltipProvider>
  )
}
```

#### 4.2 Sources Panel

```typescript
// components/sources-panel.tsx
interface SourcesPanelProps {
  citations: Citation[]
}

export function SourcesPanel({ citations }: SourcesPanelProps) {
  return (
    <Card className="mt-4">
      <CardHeader className="py-3">
        <CardTitle className="text-sm flex items-center gap-2">
          <BookOpen className="h-4 w-4" />
          Sources ({citations.length})
        </CardTitle>
      </CardHeader>
      <CardContent className="py-2">
        <div className="space-y-2">
          {citations.map((citation, idx) => (
            <div key={citation.id} className="flex gap-2 text-sm">
              <span className="text-blue-600 font-medium">[{idx + 1}]</span>
              <div>
                <a href={citation.url} target="_blank"
                   className="hover:underline">
                  {citation.title}
                </a>
                {citation.type === 'paper' && citation.authors && (
                  <p className="text-xs text-muted-foreground">
                    {citation.authors[0]} et al., {citation.year}
                  </p>
                )}
              </div>
            </div>
          ))}
        </div>
      </CardContent>
    </Card>
  )
}
```

### Phase 5: Research Layer Integration (Week 5-6)

#### 5.1 Optional: Integrate AI-Scientist Concepts

For users who want research/hypothesis features (not core workflow users):

```python
class ResearchAssistant:
    """Optional research layer for hypothesis and survey."""

    async def literature_survey(self, topic: str) -> LiteratureSurvey:
        """Generate a mini literature review."""
        # 1. Search multiple sources
        papers = await self.search_all_sources(topic)

        # 2. Compress and summarize (Kosmos-style)
        summary = await self.compress_literature(papers)

        # 3. Identify gaps
        gaps = await self.identify_research_gaps(papers, topic)

        return LiteratureSurvey(
            topic=topic,
            papers=papers,
            summary=summary,
            gaps=gaps,
            suggested_workflows=await self.suggest_workflows(gaps)
        )

    async def generate_hypothesis(
        self,
        observation: str,
        data_context: str
    ) -> List[Hypothesis]:
        """Generate testable hypotheses."""
        # Inspired by OmniScientist's Deep Ideation
        pass
```

---

## Part 5: Integration with External Frameworks

### Recommended Integrations

#### From AI-Scientist:
- **Semantic Scholar API** for citation search
- **Novelty checking** approach for workflow suggestions
- **Template architecture** for domain-specific workflows

#### From Kosmos:
- **Literature compression** (20:1 ratio) for survey generation
- **Multi-agent coordination** for complex workflow planning
- **Knowledge graph** for tracking tool relationships

#### From OmniCellAgent:
- **Non-expert user targeting** philosophy
- **Omic data integration** patterns
- **Clinical relevance** framing

### What NOT to Integrate

- **Full paper generation** (not our focus)
- **Heavy compute experiments** (Galaxy handles this)
- **Peer review simulation** (not needed for workflows)

---

## Part 6: Success Metrics

### Evidence Quality Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Citation coverage | 80% of recommendations | % with at least 1 citation |
| Citation relevance | >0.7 avg | User feedback + automated scoring |
| Parameter justification | 90% of non-default | % parameters with evidence |
| Source diversity | 3+ types | Papers, docs, pipelines per workflow |

### User Experience Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Trust increase | +30% | Survey: "I trust this recommendation" |
| Decision confidence | +25% | Time to accept recommendation |
| Support reduction | -20% | Questions about "why this tool?" |

---

## Part 7: Timeline Summary

| Phase | Duration | Deliverables |
|-------|----------|--------------|
| **Phase 1**: Data Model | Week 1-2 | Citation schema, database, types |
| **Phase 2**: APIs | Week 2-3 | PubMed, Semantic Scholar, bio.tools |
| **Phase 3**: Evidence Gen | Week 3-4 | Tool citations, parameter evidence |
| **Phase 4**: UI | Week 4-5 | Citation badges, sources panel |
| **Phase 5**: Research Layer | Week 5-6 | Optional survey/hypothesis features |

---

## Appendix: API References

### PubMed E-utilities
- Base URL: `https://eutils.ncbi.nlm.nih.gov/entrez/eutils/`
- Rate limit: 3 requests/second (with API key: 10/sec)
- Documentation: https://www.ncbi.nlm.nih.gov/books/NBK25501/

### Semantic Scholar
- Base URL: `https://api.semanticscholar.org/graph/v1/`
- Rate limit: 100 requests/5 minutes (free tier)
- Documentation: https://api.semanticscholar.org/api-docs/

### bio.tools
- Base URL: `https://bio.tools/api/`
- No rate limit documented
- Documentation: https://biotools.readthedocs.io/

### CrossRef (for DOI resolution)
- Base URL: `https://api.crossref.org/works/`
- Rate limit: 50 requests/second
- Documentation: https://api.crossref.org/swagger-ui/index.html
