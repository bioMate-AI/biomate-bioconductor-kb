# ToolUniverse Integration Architecture

**Document Created:** 2025-10-28
**Priority:** P1 - Core Enhancement
**Status:** Architecture Specification
**Estimated Implementation:** 6-8 weeks

---

## Executive Summary

This document defines the architecture for integrating **ToolUniverse** into BioMate platform. ToolUniverse will serve as a comprehensive knowledge aggregation service that discovers, indexes, and maintains an up-to-date catalog of bioinformatics tools from multiple sources (Galaxy, nf-core, Bioconductor, GitHub, social media, literature).

**Key Goals:**
- Automated tool discovery from 10+ sources
- Semantic search via embeddings (find tools by intent, not just keywords)
- Real-time updates (daily/weekly sync from sources)
- Integration with Chatboard Knowledge Panel (P1)
- MCP (Model Context Protocol) service generation for Claude

**Value Proposition:** Users can discover the right tool for their analysis without knowing specific tool names, and BioMate AI can recommend tools based on scientific context.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Data Sources](#data-sources)
3. [Tool Discovery Pipeline](#tool-discovery-pipeline)
4. [Semantic Search System](#semantic-search-system)
5. [MCP Service Generation](#mcp-service-generation)
6. [API Design](#api-design)
7. [Storage Schema](#storage-schema)
8. [Update Scheduling](#update-scheduling)
9. [Implementation Plan](#implementation-plan)
10. [Performance Requirements](#performance-requirements)

---

## Architecture Overview

### System Components

```
┌─────────────────────────────────────────────────────────────────┐
│                     ToolUniverse Architecture                    │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                      External Data Sources                       │
├─────────────────────────────────────────────────────────────────┤
│  • Galaxy ToolShed (5000+ tools)                                │
│  • nf-core (60+ pipelines, 1000+ modules)                       │
│  • Bioconductor (2000+ packages)                                │
│  • GitHub (bioinformatics repos)                                │
│  • Hugging Face (genomics models)                               │
│  • PubMed (literature, citations)                               │
│  • Twitter/X (tool announcements)                               │
│  • bioRxiv (preprints)                                          │
│  • Reddit (r/bioinformatics)                                    │
│  • SeqAnswers, Biostars (community forums)                      │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│                   Tool Discovery Pipeline                        │
├─────────────────────────────────────────────────────────────────┤
│  ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐   │
│  │ Scrapers │──▶│ Parsers  │──▶│Enrichers │──▶│ Indexers │   │
│  └──────────┘   └──────────┘   └──────────┘   └──────────┘   │
│       │              │               │               │          │
│       ▼              ▼               ▼               ▼          │
│  Fetch data    Extract info   Add metadata    Store in DB     │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│                    Tool Database (PostgreSQL)                    │
├─────────────────────────────────────────────────────────────────┤
│  • Tools table (metadata, parameters, citations)                │
│  • Embeddings table (vector search)                             │
│  • Usage statistics (popularity, success rate)                  │
│  • Update history (changelog, versions)                         │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│                    Semantic Search Engine                        │
├─────────────────────────────────────────────────────────────────┤
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐       │
│  │  Embedding   │──▶│   Vector DB  │──▶│   Ranking    │       │
│  │  Generator   │   │  (pgvector)  │   │   Engine     │       │
│  └──────────────┘   └──────────────┘   └──────────────┘       │
│         │                   │                   │               │
│         ▼                   ▼                   ▼               │
│    Encode query    Similarity search    Re-rank by context     │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│                      API & MCP Services                          │
├─────────────────────────────────────────────────────────────────┤
│  • REST API (tool search, metadata retrieval)                   │
│  • MCP Service (Claude integration)                             │
│  • WebSocket (real-time updates)                                │
│  • GraphQL (flexible queries)                                   │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│                      BioMate Consumers                           │
├─────────────────────────────────────────────────────────────────┤
│  • Chatboard Knowledge Panel                                    │
│  • AI Workflow Generator                                        │
│  • Tool Browser UI                                              │
│  • Claude Skills (via MCP)                                      │
└─────────────────────────────────────────────────────────────────┘
```

---

## Data Sources

### Primary Sources (Phase 1 - Month 1-2)

#### 1. Galaxy ToolShed

**URL:** https://toolshed.g2.bx.psu.edu/
**Content:** 5000+ tools with XML definitions

**Data to Extract:**
- Tool name, ID, version
- Description, help text
- Input/output formats
- Parameters (type, default, description)
- Categories (genomics, proteomics, etc.)
- Author, repository URL
- Installation count (popularity metric)

**API:** REST API available
**Update Frequency:** Daily
**Estimated Storage:** ~500MB (metadata only)

**Sample Tool Entry:**

```json
{
  "id": "toolshed.g2.bx.psu.edu/repos/devteam/fastqc/fastqc/0.73",
  "name": "FastQC",
  "version": "0.73",
  "description": "Read Quality reports",
  "category": "FASTQ Quality Control",
  "inputs": [
    {"name": "input_file", "type": "fastq", "description": "FASTQ file to analyze"}
  ],
  "outputs": [
    {"name": "html_file", "type": "html", "description": "Quality report"}
  ],
  "parameters": [...],
  "repository": "https://github.com/s-andrews/FastQC",
  "citations": ["doi:10.1093/bioinformatics/btq281"],
  "installations": 15000
}
```

---

#### 2. nf-core

**URL:** https://nf-co.re/
**Content:** 60+ pipelines, 1000+ modules

**Data to Extract:**
- Pipeline name, description, version
- Modules (individual tools)
- Input schemas (required files, parameters)
- Output files
- Resource requirements (CPU, memory)
- Containerization (Docker, Singularity)
- Citations, publications

**API:** GitHub API + nf-core API
**Update Frequency:** Weekly
**Estimated Storage:** ~200MB

**Sample Pipeline Entry:**

```json
{
  "id": "nf-core/rnaseq",
  "name": "RNA-seq Pipeline",
  "version": "3.12.0",
  "description": "RNA sequencing analysis pipeline",
  "modules": [
    "fastqc", "trimgalore", "star", "rsem", "deseq2"
  ],
  "inputs": {
    "reads": {"type": "fastq", "required": true},
    "genome": {"type": "fasta", "required": true}
  },
  "citations": ["doi:10.1038/nbt.4314"],
  "downloads": 5000
}
```

---

#### 3. Bioconductor

**URL:** https://bioconductor.org/
**Content:** 2000+ R packages

**Data to Extract:**
- Package name, version
- Description, vignette
- Functions (exported functions)
- Dependencies
- Use cases (from vignettes)
- Citations, papers

**API:** Bioconductor API
**Update Frequency:** Bi-weekly (releases twice a year, updates between releases)
**Estimated Storage:** ~300MB

---

#### 4. GitHub

**Search Queries:**
- `topic:bioinformatics language:python stars:>100`
- `topic:genomics language:r stars:>50`
- `bioinformatics in:description stars:>100`

**Data to Extract:**
- Repository name, description
- Stars, forks (popularity)
- Last commit date (maintenance)
- README (parse for tool description)
- Documentation link

**API:** GitHub REST API (5000 requests/hour)
**Update Frequency:** Weekly
**Estimated Storage:** ~1GB

---

### Secondary Sources (Phase 2 - Month 3-4)

#### 5. Hugging Face (Genomics Models)

**URL:** https://huggingface.co/models?pipeline_tag=genomics
**Content:** 100+ pre-trained models for genomics

**Examples:**
- DNA language models (DNABERT, Nucleotide Transformer)
- Protein structure prediction (ESM, AlphaFold variants)
- Variant effect prediction

---

#### 6. PubMed (Literature)

**Search Queries:**
- Tool announcements: "new tool" AND "bioinformatics"
- Method papers: "method" AND "genomics"

**Data to Extract:**
- Paper title, abstract
- Tool name (extract from title/abstract)
- Citation count
- Publication date

**API:** NCBI E-utilities (10 requests/second)
**Update Frequency:** Daily

---

#### 7. Social Media & Forums

**Twitter/X:**
- Search hashtags: #bioinformatics, #genomics, #scRNAseq
- Track announcements from key accounts (@bioconductor, @nextflowio, etc.)

**Reddit:**
- r/bioinformatics (tool discussions, recommendations)

**Biostars, SeqAnswers:**
- Parse forum threads for tool recommendations

**Update Frequency:** Daily
**Challenge:** Noise filtering (many irrelevant posts)

---

## Tool Discovery Pipeline

### 1. Scrapers (Data Collection)

**Architecture:**

```python
# Base scraper class
class ToolScraper:
    def __init__(self, source_name: str):
        self.source = source_name
        self.cache_dir = f"/cache/{source_name}"

    async def fetch(self) -> List[RawTool]:
        """Fetch raw data from source"""
        pass

    async def parse(self, raw: RawTool) -> Tool:
        """Parse raw data into structured format"""
        pass

    async def run(self) -> List[Tool]:
        """Full scraping pipeline"""
        raw_tools = await self.fetch()
        return [await self.parse(t) for t in raw_tools]

# Example: Galaxy scraper
class GalaxyScraper(ToolScraper):
    async def fetch(self):
        # Fetch from Galaxy ToolShed API
        response = await self.client.get("https://toolshed.g2.bx.psu.edu/api/repositories")
        return response.json()

    async def parse(self, raw):
        return Tool(
            id=raw['id'],
            name=raw['name'],
            description=raw['description'],
            source='galaxy',
            # ... more fields
        )
```

**Rate Limiting:**
- Respect API rate limits (exponential backoff)
- Cache responses locally (avoid redundant fetches)
- Incremental updates (fetch only new/changed tools)

---

### 2. Enrichers (Metadata Enhancement)

**Enrichment Steps:**

```python
class ToolEnricher:
    async def enrich(self, tool: Tool) -> Tool:
        """Add additional metadata"""
        # 1. Extract citations
        tool.citations = await self.extract_citations(tool)

        # 2. Fetch usage statistics
        tool.usage_stats = await self.fetch_usage_stats(tool)

        # 3. Generate embeddings
        tool.embedding = await self.generate_embedding(tool)

        # 4. Extract parameters from documentation
        tool.parameters = await self.parse_parameters(tool)

        # 5. Categorize tool
        tool.categories = await self.categorize(tool)

        return tool
```

**Citation Extraction:**
- Parse help text, README for DOIs
- Cross-reference with PubMed
- Extract citation count (Google Scholar API)

**Usage Statistics:**
- Galaxy: Installation count
- GitHub: Stars, forks, clones
- nf-core: Pipeline runs (if available)
- Bioconductor: Download count

---

### 3. Indexers (Database Storage)

**Indexing Strategy:**

```sql
-- Store tool metadata
INSERT INTO tools (
    id, name, version, description, source,
    category, parameters, citations, usage_stats,
    created_at, updated_at
) VALUES (...);

-- Store embeddings for vector search
INSERT INTO tool_embeddings (
    tool_id, embedding_model, embedding_vector
) VALUES (
    'tool_123',
    'all-MiniLM-L6-v2',
    '[0.123, -0.456, ...]'::vector(384)
);

-- Store version history
INSERT INTO tool_versions (
    tool_id, version, changelog, released_at
) VALUES (...);
```

---

## Semantic Search System

### Embedding Model

**Model Choice:** `all-MiniLM-L6-v2` (sentence-transformers)

**Why:**
- Fast inference (100ms on CPU)
- Good quality (384-dimensional embeddings)
- Pre-trained on diverse text (generalizes well)
- Small model size (80MB)

**Alternatives Considered:**
- `all-mpnet-base-v2` (better quality, slower, 768-dim)
- `bio-bert` (biology-specific, but outdated)
- OpenAI embeddings (expensive, requires API calls)

**Embedding Generation:**

```python
from sentence_transformers import SentenceTransformer

model = SentenceTransformer('all-MiniLM-L6-v2')

def generate_tool_embedding(tool: Tool) -> List[float]:
    # Combine relevant fields
    text = f"{tool.name}. {tool.description}. {tool.category}. {' '.join(tool.parameters)}"

    # Generate embedding
    embedding = model.encode(text)
    return embedding.tolist()
```

---

### Vector Database (pgvector)

**Setup:**

```sql
-- Enable pgvector extension
CREATE EXTENSION vector;

-- Create embeddings table
CREATE TABLE tool_embeddings (
    id SERIAL PRIMARY KEY,
    tool_id VARCHAR(255) REFERENCES tools(id),
    embedding_model VARCHAR(100),
    embedding_vector vector(384),  -- 384 dimensions for MiniLM
    created_at TIMESTAMP DEFAULT NOW()
);

-- Create HNSW index for fast similarity search
CREATE INDEX ON tool_embeddings USING hnsw (embedding_vector vector_cosine_ops);
```

**Vector Search Query:**

```python
async def search_tools(query: str, limit: int = 10) -> List[Tool]:
    # 1. Generate query embedding
    query_embedding = model.encode(query)

    # 2. Cosine similarity search
    results = await db.execute("""
        SELECT t.*,
               1 - (te.embedding_vector <=> $1::vector) AS similarity
        FROM tools t
        JOIN tool_embeddings te ON t.id = te.tool_id
        WHERE te.embedding_model = 'all-MiniLM-L6-v2'
        ORDER BY te.embedding_vector <=> $1::vector
        LIMIT $2
    """, query_embedding, limit)

    return [Tool(**row) for row in results]
```

**Example Queries:**

| User Query | Expected Results |
|------------|------------------|
| "quality control for sequencing reads" | FastQC, MultiQC, Trimmomatic |
| "align RNA-seq reads to genome" | STAR, HISAT2, Bowtie2 |
| "find differentially expressed genes" | DESeq2, edgeR, limma |
| "variant calling from WGS" | GATK, FreeBayes, DeepVariant |

---

### Re-Ranking (Hybrid Search)

**Combine:**
1. **Vector similarity** (semantic relevance)
2. **Keyword matching** (exact matches)
3. **Popularity** (usage statistics)
4. **Recency** (last updated)

**Scoring Formula:**

```python
def compute_score(tool: Tool, query: str, embedding_sim: float) -> float:
    # Weights (tunable)
    w_semantic = 0.5
    w_keyword = 0.2
    w_popularity = 0.2
    w_recency = 0.1

    # Keyword matching (BM25)
    keyword_score = bm25_score(tool.description, query)

    # Popularity (normalized)
    pop_score = normalize(tool.usage_stats.get('stars', 0))

    # Recency (decay factor)
    days_since_update = (now() - tool.updated_at).days
    recency_score = exp(-days_since_update / 365)

    # Combined score
    total_score = (
        w_semantic * embedding_sim +
        w_keyword * keyword_score +
        w_popularity * pop_score +
        w_recency * recency_score
    )

    return total_score
```

---

## MCP Service Generation

### Model Context Protocol (MCP)

**What is MCP:**
- Protocol for connecting Claude to external tools/data
- Allows Claude to call functions, retrieve context
- Similar to OpenAI function calling

**ToolUniverse MCP Service:**

```typescript
// MCP Server for ToolUniverse
import { MCPServer } from '@anthropic-ai/mcp-sdk';

const server = new MCPServer({
  name: 'tooluniverse',
  version: '1.0.0',
  description: 'Search and discover bioinformatics tools',
});

// Tool: search_tools
server.addTool({
  name: 'search_tools',
  description: 'Search for bioinformatics tools by natural language query',
  parameters: {
    type: 'object',
    properties: {
      query: {
        type: 'string',
        description: 'Natural language description of the analysis task',
      },
      category: {
        type: 'string',
        enum: ['genomics', 'proteomics', 'transcriptomics', 'quality_control'],
        description: 'Optional: Filter by category',
      },
      limit: {
        type: 'number',
        description: 'Maximum number of results to return',
        default: 10,
      },
    },
    required: ['query'],
  },
  handler: async (params) => {
    const results = await searchTools(params.query, params.category, params.limit);
    return results;
  },
});

// Tool: get_tool_details
server.addTool({
  name: 'get_tool_details',
  description: 'Get detailed information about a specific tool',
  parameters: {
    type: 'object',
    properties: {
      tool_id: {
        type: 'string',
        description: 'The unique identifier of the tool',
      },
    },
    required: ['tool_id'],
  },
  handler: async (params) => {
    const tool = await getToolDetails(params.tool_id);
    return tool;
  },
});

// Tool: get_tool_parameters
server.addTool({
  name: 'get_tool_parameters',
  description: 'Get parameter schema for a specific tool',
  parameters: {
    type: 'object',
    properties: {
      tool_id: {
        type: 'string',
        description: 'The unique identifier of the tool',
      },
    },
    required: ['tool_id'],
  },
  handler: async (params) => {
    const parameters = await getToolParameters(params.tool_id);
    return parameters;
  },
});

server.start();
```

**Claude Usage Example:**

```
User: I want to analyze RNA-seq data. What tools do I need?

Claude (using MCP):
1. Calls search_tools(query="RNA-seq analysis pipeline")
2. Receives: [STAR, HISAT2, featureCounts, DESeq2, ...]
3. Responds: "For RNA-seq analysis, I recommend:
   - Alignment: STAR or HISAT2
   - Quantification: featureCounts or Salmon
   - Differential expression: DESeq2 or edgeR

   Would you like me to generate a workflow using these tools?"
```

---

## API Design

### REST API

**Base URL:** `https://api.biomate.ai/tooluniverse/v1`

**Endpoints:**

```typescript
// Search tools
GET /tools/search
Query params:
  - q: string (query)
  - category?: string
  - source?: string (galaxy|nfcore|bioconductor|github)
  - limit?: number (default 10)
  - offset?: number (pagination)

Response:
{
  "results": [
    {
      "id": "galaxy/fastqc",
      "name": "FastQC",
      "description": "Quality control for sequencing data",
      "category": "quality_control",
      "source": "galaxy",
      "version": "0.73",
      "similarity": 0.92,
      "score": 0.87,
      "usage_stats": {
        "installations": 15000,
        "stars": 320
      }
    },
    // ... more results
  ],
  "total": 156,
  "page": 1,
  "pages": 16
}

// Get tool details
GET /tools/{tool_id}

Response:
{
  "id": "galaxy/fastqc",
  "name": "FastQC",
  "version": "0.73",
  "description": "...",
  "parameters": [...],
  "citations": [...],
  "repository": "https://github.com/s-andrews/FastQC",
  "documentation": "...",
  "examples": [...]
}

// Get tool parameters
GET /tools/{tool_id}/parameters

Response:
{
  "parameters": [
    {
      "name": "input_file",
      "type": "fastq",
      "required": true,
      "description": "FASTQ file to analyze"
    },
    // ... more parameters
  ]
}

// Get tool citations
GET /tools/{tool_id}/citations

// Get similar tools
GET /tools/{tool_id}/similar?limit=10

// Get tool versions
GET /tools/{tool_id}/versions

// Suggest tools for workflow
POST /tools/suggest
Body:
{
  "workflow_description": "RNA-seq differential expression analysis",
  "input_formats": ["fastq"],
  "desired_outputs": ["gene_counts", "differential_expression"]
}

Response:
{
  "suggested_pipeline": [
    {"step": 1, "tool": "fastqc", "purpose": "quality_control"},
    {"step": 2, "tool": "star", "purpose": "alignment"},
    {"step": 3, "tool": "featurecounts", "purpose": "quantification"},
    {"step": 4, "tool": "deseq2", "purpose": "differential_expression"}
  ]
}
```

---

### GraphQL API

**Schema:**

```graphql
type Tool {
  id: ID!
  name: String!
  version: String!
  description: String!
  category: String!
  source: String!
  parameters: [Parameter!]!
  citations: [Citation!]!
  usageStats: UsageStats!
  repository: String
  documentation: String
  examples: [Example!]!
  versions: [ToolVersion!]!
  similar: [Tool!]!
}

type Parameter {
  name: String!
  type: String!
  required: Boolean!
  default: String
  description: String
}

type Citation {
  doi: String
  title: String
  authors: [String!]!
  year: Int!
  journal: String
  citationCount: Int
}

type UsageStats {
  installations: Int
  stars: Int
  forks: Int
  downloads: Int
}

type Query {
  searchTools(
    query: String!
    category: String
    source: String
    limit: Int = 10
    offset: Int = 0
  ): ToolSearchResult!

  getTool(id: ID!): Tool

  suggestPipeline(
    description: String!
    inputFormats: [String!]!
    outputFormats: [String!]!
  ): [Tool!]!
}

type ToolSearchResult {
  results: [Tool!]!
  total: Int!
  page: Int!
  pages: Int!
}
```

---

## Storage Schema

### PostgreSQL Schema

```sql
-- Tools table
CREATE TABLE tools (
    id VARCHAR(255) PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    version VARCHAR(100),
    description TEXT,
    category VARCHAR(100),
    source VARCHAR(50),  -- galaxy, nfcore, bioconductor, github
    repository_url TEXT,
    documentation_url TEXT,
    help_text TEXT,
    parameters JSONB,
    inputs JSONB,
    outputs JSONB,
    citations JSONB,
    usage_stats JSONB,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    last_scraped_at TIMESTAMP
);

-- Indexes
CREATE INDEX idx_tools_name ON tools(name);
CREATE INDEX idx_tools_category ON tools(category);
CREATE INDEX idx_tools_source ON tools(source);
CREATE INDEX idx_tools_updated ON tools(updated_at);
CREATE INDEX idx_tools_parameters_gin ON tools USING GIN (parameters);

-- Full-text search
CREATE INDEX idx_tools_description_fts ON tools USING GIN (to_tsvector('english', description));

-- Tool embeddings (for vector search)
CREATE TABLE tool_embeddings (
    id SERIAL PRIMARY KEY,
    tool_id VARCHAR(255) REFERENCES tools(id) ON DELETE CASCADE,
    embedding_model VARCHAR(100),
    embedding_vector vector(384),
    created_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(tool_id, embedding_model)
);

CREATE INDEX idx_embeddings_vector ON tool_embeddings USING hnsw (embedding_vector vector_cosine_ops);

-- Tool versions
CREATE TABLE tool_versions (
    id SERIAL PRIMARY KEY,
    tool_id VARCHAR(255) REFERENCES tools(id) ON DELETE CASCADE,
    version VARCHAR(100) NOT NULL,
    changelog TEXT,
    released_at TIMESTAMP,
    deprecated BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_versions_tool ON tool_versions(tool_id);

-- Tool usage tracking (BioMate internal)
CREATE TABLE tool_usage (
    id SERIAL PRIMARY KEY,
    tool_id VARCHAR(255) REFERENCES tools(id),
    user_id VARCHAR(255),
    workflow_id VARCHAR(255),
    used_at TIMESTAMP DEFAULT NOW(),
    success BOOLEAN
);

CREATE INDEX idx_usage_tool ON tool_usage(tool_id);
CREATE INDEX idx_usage_time ON tool_usage(used_at);

-- Scraping logs
CREATE TABLE scraping_logs (
    id SERIAL PRIMARY KEY,
    source VARCHAR(50),
    status VARCHAR(50),  -- success, failed, partial
    tools_found INT,
    tools_updated INT,
    tools_added INT,
    error_message TEXT,
    started_at TIMESTAMP,
    completed_at TIMESTAMP
);
```

---

## Update Scheduling

### Cron Jobs

```yaml
# Daily updates (high-priority sources)
- name: Update Galaxy Tools
  schedule: "0 2 * * *"  # 2 AM daily
  script: ./scrapers/galaxy_scraper.py

- name: Update PubMed
  schedule: "0 3 * * *"  # 3 AM daily
  script: ./scrapers/pubmed_scraper.py

- name: Update Social Media
  schedule: "0 */6 * * *"  # Every 6 hours
  script: ./scrapers/social_scraper.py

# Weekly updates (slower-changing sources)
- name: Update nf-core
  schedule: "0 4 * * 0"  # 4 AM Sunday
  script: ./scrapers/nfcore_scraper.py

- name: Update Bioconductor
  schedule: "0 5 * * 0"  # 5 AM Sunday
  script: ./scrapers/bioconductor_scraper.py

- name: Update GitHub
  schedule: "0 6 * * 0"  # 6 AM Sunday
  script: ./scrapers/github_scraper.py

# Monthly maintenance
- name: Recompute Embeddings
  schedule: "0 7 1 * *"  # 7 AM 1st of month
  script: ./maintenance/recompute_embeddings.py

- name: Prune Old Versions
  schedule: "0 8 1 * *"  # 8 AM 1st of month
  script: ./maintenance/prune_versions.py
```

---

## Implementation Plan

### Phase 1: MVP (Weeks 1-3)

**Week 1:**
- [ ] Set up PostgreSQL with pgvector
- [ ] Implement Galaxy scraper
- [ ] Implement nf-core scraper
- [ ] Create tools table schema
- [ ] Basic API (search, get tool)

**Week 2:**
- [ ] Implement embedding generation
- [ ] Set up vector search (pgvector)
- [ ] Test semantic search quality
- [ ] Add Bioconductor scraper
- [ ] Add GitHub scraper

**Week 3:**
- [ ] Implement re-ranking algorithm
- [ ] Add REST API endpoints
- [ ] Add GraphQL API
- [ ] Write integration tests
- [ ] Deploy to staging

**Deliverable:** Functional tool search with 7000+ tools (Galaxy + nf-core + Bioconductor + GitHub)

---

### Phase 2: MCP & Advanced Features (Weeks 4-6)

**Week 4:**
- [ ] Implement MCP service
- [ ] Test Claude integration
- [ ] Add tool suggestion API
- [ ] Implement usage tracking

**Week 5:**
- [ ] Add PubMed scraper (citations)
- [ ] Implement social media scrapers
- [ ] Add Hugging Face scraper
- [ ] Enrich existing tools with citations

**Week 6:**
- [ ] Implement cron jobs for updates
- [ ] Add monitoring/alerting
- [ ] Performance optimization
- [ ] Documentation

**Deliverable:** MCP service integrated with Claude, 10,000+ tools

---

### Phase 3: Knowledge Panel Integration (Weeks 7-8)

**Week 7:**
- [ ] Integrate with Chatboard Knowledge Panel
- [ ] Add real-time search UI
- [ ] Add tool comparison feature
- [ ] Add "similar tools" feature

**Week 8:**
- [ ] User feedback collection
- [ ] A/B testing (vector vs keyword search)
- [ ] Performance tuning
- [ ] Production deployment

**Deliverable:** Full Knowledge Panel integration, production-ready

---

## Performance Requirements

### Search Performance

| Metric | Target (p95) | Notes |
|--------|--------------|-------|
| Search latency | <200ms | Vector search + re-ranking |
| Embedding generation | <100ms | Per query, CPU |
| Database query | <50ms | PostgreSQL + pgvector |
| API response time | <300ms | Total end-to-end |

### Update Performance

| Task | Target | Frequency |
|------|--------|-----------|
| Galaxy scrape | <10 minutes | Daily |
| nf-core scrape | <5 minutes | Weekly |
| Bioconductor scrape | <15 minutes | Bi-weekly |
| GitHub scrape | <30 minutes | Weekly |
| Embedding update | <1 hour | Monthly |

### Storage Estimates

| Data Type | Size | Growth Rate |
|-----------|------|-------------|
| Tool metadata | 500MB | +50MB/month |
| Embeddings | 200MB | +20MB/month |
| Version history | 100MB | +10MB/month |
| Scraping logs | 50MB | +5MB/month |
| **Total** | **850MB** | **+85MB/month** |

**1-Year Projection:** ~1.9GB

---

## Success Metrics

### Launch (Week 3)
- ✅ 7000+ tools indexed
- ✅ Search relevance >0.7 (user-rated)
- ✅ <300ms API response time
- ✅ Zero downtime during updates

### Month 2
- ✅ 10,000+ tools indexed
- ✅ MCP service operational
- ✅ Claude integration successful
- ✅ 80%+ search satisfaction

### Month 3
- ✅ Knowledge Panel integrated
- ✅ 50+ daily active searches
- ✅ 90%+ search relevance
- ✅ 100% uptime

---

**Document Version:** 1.0
**Last Updated:** 2025-10-28
**Next Review:** Before Phase 1 implementation
**Owner:** BioMate AI/Knowledge Team
