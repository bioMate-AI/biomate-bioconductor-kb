# Phase 1A: Cryo-EM AI Intelligence Plan
**Date:** 2026-04-02  
**Author:** BioMate Engineering  
**Status:** Draft — for review before implementation

---

## 1. Current State Diagnosis

### Why CryoSPARC Documentation Is Not Leveraged

The short answer: **BioMate has no retrieval system. All AI knowledge is hardcoded static strings.**

The full picture from code audit:

```
galaxy-assistant.ts (3,006 lines)
│
├── DOMAIN_SPECIALIST_GUIDANCE['cryo_em']   ← LINE 392
│   Single paragraph, ~120 words:
│   "SPA vs cryo-ET distinction is critical. For SPA: MotionCor2 → CTFFIND4
│    → Topaz/crYOLO → CryoSPARC 2D/3D → non-uniform refinement. Key QC gates:
│    B-factor < 80 Å²/frame; CTF ≤ 4 Å; 2D class fraction ≥ 60%..."
│
│   Contains: pipeline order, 3 QC thresholds, FSC = 0.143
│   Missing: pixel size rules, box size calculation, sample type protocols,
│            reconstitution guidance, drug difference maps, nanodisc types,
│            GPCR complex assembly, any of the 8 skill document content
│
├── BioMNIDatasetRAG (backend/lib/galaxy/ai/biomni_dataset_rag.py)
│   41 lines — STUB ONLY
│   find_relevant_datasets() returns [] unconditionally
│   No embedding model, no vector DB, no document ingestion pipeline
│
└── CryoSPARC official docs (guide.cryosparc.com)
    NOT ingested. Zero entries. Zero retrieval.
    The 23-step pipeline code exists but docs = absent.
```

**The knowledge gap in numbers:**

| Knowledge source | Words available | Words in AI | Utilization |
|-----------------|----------------|-------------|-------------|
| Our 8 skill docs | ~45,000 | 0 | 0% |
| General framework doc | ~8,000 | 0 | 0% |
| CryoSPARC official docs | ~200,000+ | 0 | 0% |
| Current cryo_em guidance | ~120 | 120 | 100% |

Everything we built in the skill documents is invisible to the AI today.

---

## 2. Root Cause: Architecture

BioMate's AI system uses **static prompt injection**, not retrieval:

```
User query
    │
    ▼
Intent classifier (Haiku)
    │ detects domain = 'cryo_em'
    ▼
buildDomainSpecialistBlock('cryo_em')
    │ returns hardcoded ~120-word paragraph
    ▼
generateResponse(systemPrompt + domainBlock)
    │ Claude Sonnet with no external knowledge
    ▼
Response
```

Static injection has a hard ceiling. You can expand the hardcoded string to ~2,000 words before:
- System prompt token costs become prohibitive (every query pays the full cost)
- Context window fills before user message + workflow catalog
- Maintenance becomes impossible (update one file, rebuild, redeploy)

The correct architecture for professional-grade domain knowledge is **retrieval-augmented generation (RAG)**:

```
User query
    │
    ├──► Intent classifier (Haiku)  →  domain = 'cryo_em'
    │
    ├──► Query vector embedding
    │        │
    │        ▼
    │    Vector search over:
    │    ├── Our 8 skill documents (indexed)
    │    ├── General framework document (indexed)
    │    ├── CryoSPARC official docs (indexed)
    │    └── RELION wiki (indexed)
    │        │
    │        ▼
    │    Top-K relevant chunks (K=5, ~1,500 words)
    │
    ▼
generateResponse(systemPrompt + retrieved_chunks + user_query)
    │ Claude Sonnet with targeted, query-specific knowledge
    ▼
Response: accurate protocol, correct parameters, right reconstitution
```

This is the right architecture. But it requires building the RAG pipeline from scratch (BioMNIDatasetRAG is a stub).

---

## 3. Two-Phase Implementation Plan

### Phase 1A-Quick (1 week): Expand static knowledge, no new infrastructure

Expand `DOMAIN_SPECIALIST_GUIDANCE['cryo_em']` from 120 words to a structured ~2,000-word block covering the decision tree and parameter tables. This is deployable immediately, zero new infrastructure.

**What goes in:**
```
1. Sample type decision tree (6 branches: nanodisc, GPCR complex, pore,
   RNA-protein, symmetric, soluble)
2. MW → parameter table (pixel size, box size, defocus, dose)
3. The 14 QC gates with pass/fail criteria
4. Drug binding study dataset design rules
5. Model building decision tree (known PDB vs AF2)
6. 5 universal invariant principles
```

**What does NOT go in (too long, needs RAG):**
- Full reconstitution protocols (saposin, MSP, liposome)
- Step-by-step GPCR complex assembly
- Full CryoSPARC parameter documentation
- Specific paper-derived workflow details

**Result:** BioMate can answer "what pixel size for a 55 kDa membrane protein?" or "do I need saposin or MSP?" — but cannot give a full step-by-step reconstitution protocol.

**File to edit:** `frontend/server/galaxy-assistant.ts` line 392 — replace the single paragraph with structured block.

**Estimated cost:** +$0.001–0.002/query (extra tokens in system prompt). Acceptable.

---

### Phase 1A-Full (3–4 weeks): Implement RAG pipeline

This is the architecture that can leverage CryoSPARC official docs, our skill documents, RELION wiki, and future documents without touching the system prompt.

#### Step 1: Document Ingestion Pipeline

Build `backend/lib/galaxy/ai/cryo_em_rag/`:

```
cryo_em_rag/
├── ingest.py           — chunk + embed documents
├── retriever.py        — query-time vector search
├── sources/
│   ├── skill_docs.py   — ingest docs/cryo_em_skills/*.md
│   ├── cryosparc.py    — scrape guide.cryosparc.com
│   ├── relion.py       — scrape relion wiki
│   └── phenix.py       — ingest phenix documentation
└── vector_store.py     — ChromaDB or FAISS wrapper
```

**CryoSPARC official docs to ingest:**

| Source | URL / Location | Content |
|--------|---------------|---------|
| CryoSPARC Guide | guide.cryosparc.com | Full pipeline documentation, all job types, all parameters |
| CryoSPARC tutorials | guide.cryosparc.com/tutorials | Step-by-step workflows |
| CryoSPARC discuss | discuss.cryosparc.com | Q&A, troubleshooting |
| Our skill docs | docs/cryo_em_skills/*.md | Master-lab derived protocols |
| General framework | docs/cryo_em_skills/00_GENERAL_FRAMEWORK.md | Decision tree |
| RELION wiki | relion.biochem.lu.se/doku.php | RELION-specific parameters |
| PHENIX docs | phenix-online.org/documentation | Model building |

**Chunking strategy:**
- Chunk size: 512 tokens (fits within reasonable context)
- Overlap: 64 tokens (preserve context across chunk boundaries)
- Metadata: source, section, tool_name, parameter_names mentioned
- Special handling: parameter tables → each row = one chunk (preserve structure)

#### Step 2: Embedding + Vector Store

```python
# vector_store.py
from chromadb import Client
import anthropic

client = anthropic.Anthropic()

def embed(text: str) -> list[float]:
    # Use voyage-3-lite for domain-specific embedding
    # Anthropic recommends voyage-3 for technical content
    resp = client.embeddings.create(
        model="voyage-3-lite",
        input=text
    )
    return resp.embeddings[0]

def index_documents(chunks: list[dict]):
    # chunks: [{text, metadata}]
    collection = chroma_client.get_or_create_collection("cryo_em_knowledge")
    collection.add(
        documents=[c['text'] for c in chunks],
        metadatas=[c['metadata'] for c in chunks],
        ids=[str(i) for i in range(len(chunks))]
    )

def retrieve(query: str, n_results: int = 5) -> list[dict]:
    query_embedding = embed(query)
    results = collection.query(
        query_embeddings=[query_embedding],
        n_results=n_results,
        include=['documents', 'metadatas', 'distances']
    )
    return results
```

#### Step 3: Activate BioMNIDatasetRAG

`backend/lib/galaxy/ai/biomni_dataset_rag.py` is currently a 41-line stub. Replace with:

```python
class BioMNIDatasetRAG:
    def __init__(self):
        self.cryo_em_retriever = CryoEMRetriever()  # new class

    def find_relevant_datasets(self, user_intent: str, domain: str) -> list[dict]:
        if domain == 'cryo_em':
            chunks = self.cryo_em_retriever.retrieve(user_intent, n_results=5)
            return [{'content': c['text'], 'source': c['metadata']['source']} 
                    for c in chunks]
        return []
```

#### Step 4: Inject Retrieved Chunks into System Prompt

In `galaxy-assistant.ts`, the `generateResponse()` function at line ~2666:

```typescript
// Add retrieval call before system prompt assembly
const retrievedKnowledge = await fetchRelevantKnowledge(
    userMessage, 
    intentDecomposition.preferredDomains
);

// Inject retrieved chunks into system prompt
const systemPrompt = [
    CORE_SYSTEM_PROMPT,
    buildDomainSpecialistBlock(preferredDomains),   // keep existing
    buildRetrievedKnowledgeBlock(retrievedKnowledge), // NEW
    buildDomainCatalogBlock(preferredDomains),
].join('\n\n');
```

`buildRetrievedKnowledgeBlock()` formats retrieved chunks as:

```
## Retrieved Protocol Knowledge

The following was retrieved from authoritative sources relevant to this query:

[SOURCE: CryoSPARC Guide — Particle Picking]
For nanodisc samples, use a combination of blob picker (initial), template picker 
(after 2D classification), and TOPAZ (trained on project-specific particles)...

[SOURCE: BioMate Skill Doc — MFSD2B preprint]
For < 60 kDa membrane proteins: pixel size 0.649 Å/pix mandatory. Box size 256 px...

[SOURCE: BioMate General Framework]
Saposin nanodisc preferred over MSP for proteins < 60 kDa. γ-cyclodextrin 
lipid delivery method. POPC:POPE:POPG = 3:1:1 typical lipid ratio...
```

---

## 4. CryoSPARC Official Docs — What to Ingest

CryoSPARC's documentation covers everything we need but don't currently have. Key sections:

| Doc section | URL path | Relevance | Priority |
|-------------|----------|-----------|----------|
| Patch Motion Correction | /processing-data/patch-motion-correction | Parameters: patch size, B-factor, dose | P0 |
| Patch CTF Estimation | /processing-data/patch-ctf-estimation | Parameters: defocus range, resolution | P0 |
| Blob Picker | /processing-data/blob-picker | Parameters: min/max diameter, threshold | P0 |
| Template Picker | /processing-data/template-picker | Template source, angular sampling | P0 |
| TOPAZ Picker | /processing-data/topaz-picking | Training workflow, expected input | P0 |
| 2D Classification | /processing-data/2d-classification | Class count, resolution, iterations | P0 |
| Ab initio | /processing-data/ab-initio-reconstruction | Class count, resolution, symmetry | P0 |
| Homogeneous Refinement | /processing-data/homogeneous-refinement | Symmetry, resolution, masking | P0 |
| Non-uniform Refinement | /processing-data/non-uniform-refinement-v3 | Dynamic masking, filter order | P0 |
| Local CTF Refinement | /processing-data/local-ctf-refinement | Beam tilt, trefoil, spherical | P1 |
| Local Refinement | /processing-data/local-refinement | Focus mask, reference | P1 |
| 3D Variability | /processing-data/3d-variability-analysis | Components, filter, cluster | P1 |
| Multi-body Refinement | /processing-data/multi-body-refinement | Body definitions, mask | P1 |
| Local Resolution | /processing-data/local-resolution-estimation | Window size, FSC threshold | P1 |
| DeepEMhancer | /processing-data/deepemhancer | Model selection, normalization | P2 |
| Nanodisc tutorial | /tutorials/tutorial-nanodisc | Full end-to-end for nanodiscs | P0 |

**Why these aren't ingested today:**
1. No web scraper exists in the codebase for guide.cryosparc.com
2. No ChromaDB/FAISS instance deployed
3. BioMNIDatasetRAG stub never built out

---

## 5. Decision: Quick vs Full

| Dimension | 1A-Quick (static expansion) | 1A-Full (RAG) |
|-----------|---------------------------|---------------|
| Time to deploy | 2–3 days | 3–4 weeks |
| CryoSPARC docs leveraged | ❌ No | ✅ Yes (full ingestion) |
| Skill docs leveraged | Partially (distilled) | ✅ Yes (full text) |
| Query-specific retrieval | ❌ No (same block for all queries) | ✅ Yes (targeted per query) |
| Maintainability | Poor (edit .ts file to update) | Good (re-index documents) |
| Token cost per query | +~500 tokens always | +~750 tokens when retrieved |
| Infrastructure change | None | ChromaDB + embedding pipeline |
| Risk | Low | Medium |

**Recommendation:** Do both in sequence.
- **1A-Quick now** (2 days): Expand static block with decision tree + parameter tables. Gets BioMate to "competent" for common cryo-EM questions immediately.
- **1A-Full next sprint** (3 weeks): RAG pipeline with CryoSPARC docs + skill docs. Gets BioMate to "expert" that can cite specific CryoSPARC job parameters.

These are independent — 1A-Quick doesn't block 1A-Full, and 1A-Full supersedes 1A-Quick once deployed.

---

## 6. What 1A-Quick Would Enable vs Not

**Would enable (static expansion):**
- "What pixel size for a 55 kDa protein?" → 0.83 Å/pix, standard range
- "Do I need saposin or MSP nanodisc?" → < 60 kDa use saposin, > 60 kDa use MSP
- "How many particles do I need for 3 Å?" → > 200K for < 3 Å
- "What's the FSC criterion?" → 0.143 gold-standard
- "What box size for my 400 kDa complex?" → formula: 1.5× diameter / pixel size
- "What defocus range for a large complex?" → −1.0 to −2.5 μm
- "What QC gate should I apply to CTF?" → FOM > 0.1, resolution < 4.5 Å

**Would NOT enable (needs RAG):**
- "What are the exact CryoSPARC Patch Motion Correction parameters for K3 detector?" → needs CryoSPARC docs
- "How do I train TOPAZ on my specific dataset?" → needs detailed TOPAZ workflow from CryoSPARC guide
- "Walk me through the saposin nanodisc reconstitution step by step" → needs full skill doc text
- "What went wrong in my 3DVA analysis?" → needs CryoSPARC 3DVA troubleshooting docs
- "What are the differences between homogeneous and non-uniform refinement?" → needs CryoSPARC docs

---

## 7. Files to Change

### 1A-Quick (static expansion)
```
frontend/server/galaxy-assistant.ts
  Line 392: Replace DOMAIN_SPECIALIST_GUIDANCE['cryo_em'] 
  (~120 words → ~2,000 words structured block)
  
  Add to clarification fork points (currently only SPA vs cryo-ET):
  - sample_type: membrane / soluble / GPCR-complex / pore-forming / RNP / symmetric
  - reconstitution: saposin / MSP / detergent / liposome / none
  - scientific_question: static_structure / drug_binding / conformational / atlas
```

### 1A-Full (RAG pipeline)
```
New files:
  backend/lib/galaxy/ai/cryo_em_rag/
  ├── __init__.py
  ├── ingest.py           — scrape + chunk + embed
  ├── retriever.py        — query-time vector search
  ├── vector_store.py     — ChromaDB wrapper
  └── sources/
      ├── skill_docs.py   — ingest docs/cryo_em_skills/*.md
      ├── cryosparc.py    — scrape guide.cryosparc.com
      └── relion.py       — scrape relion wiki

Modified files:
  backend/lib/galaxy/ai/biomni_dataset_rag.py
    Replace stub with real retriever (41 lines → ~150 lines)
    
  frontend/server/galaxy-assistant.ts
    generateResponse() at line ~2666:
    Add fetchRelevantKnowledge() call + buildRetrievedKnowledgeBlock()
    Add /api/cryo_em/retrieve proxy endpoint to routes.ts
```

---

## 8. Open Questions for Review

Before implementing, please review:

1. **ChromaDB vs FAISS:** ChromaDB is persistent (survives restarts), FAISS is faster but in-memory. For a shared server with multiple users, ChromaDB is preferred. OK?

2. **CryoSPARC docs scraping:** guide.cryosparc.com is publicly accessible. Is there a terms-of-service concern with scraping? Alternative: manually download + convert to markdown.

3. **Embedding model:** Voyage-3-lite (Anthropic-recommended) vs OpenAI text-embedding-3-small vs local sentence-transformers. Voyage-3-lite is best for domain-specific technical text; costs ~$0.0001/1K tokens for ingestion.

4. **Retrieval frequency:** Retrieve on every cryo-EM query (adds ~200ms latency) or only when the query mentions specific tool names/parameters? Recommend always-on for cryo_em domain.

5. **Knowledge freshness:** CryoSPARC updates docs frequently. Plan for re-indexing: weekly cron job? Manual trigger? Recommend weekly cron + manual trigger button.

6. **Scope of 1A-Quick static expansion:** Should the static block cover GPCR complex assembly steps (long) or stay at decision-tree level only? Recommend decision-tree level only — full protocols go in RAG.
