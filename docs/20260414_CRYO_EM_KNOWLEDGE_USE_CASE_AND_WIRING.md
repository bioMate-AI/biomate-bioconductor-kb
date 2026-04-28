 # Cryo-EM Knowledge System — Use Case & E2E Wiring

**Date:** 2026-04-14  
**Context:** Documents how the two cryo-EM knowledge layers (expert JSON + RAG) are wired into BioMate from user query to rendered response.

---

## Architecture Overview

BioMate has **two independent but complementary** cryo-EM knowledge paths that activate on every cryo-EM workflow request. They serve different consumers and travel different routes:

| | Knowledge Highlights | RAG Context |
|---|---|---|
| **Source** | `expert_knowledge_bioimaging.json` | `cryo_em_chunks` table (150 BGE-embedded chunks) |
| **Consumer** | User (rendered in UI panel) | LLM (injected into system prompt) |
| **Trigger** | Workflow template match + domain=`cryo_em` | Domain detected as cryo-EM by frontend server |
| **Timing** | Synchronous, inside workflow generation | Parallel fetch, non-blocking |
| **Format** | Structured JSON (best_practices, qc_thresholds, literature_guidance) | Free-text XML blocks in system prompt |

---

## Use Case: User Requests CryoSPARC SPA Workflow

**User message:** "CryoSPARC single particle analysis for cryo-EM structure determination of a GPCR"

### Step 1 — HTTP Entry Point

```
POST /api/ai_assistant/generate_workflow
x-api-key: <user_key>
{"request_text": "CryoSPARC single particle analysis..."}
```

Handler: `backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py:1501`  
Delegates to `AIAssistant.generate_workflow_unified()` in `ai_assistant.py`.

---

### Step 2 — Workflow Template Search

`ai_assistant.py:2669` — `generate_workflow_unified()`

1. `UnifiedWorkflowSearch` runs keyword + semantic search across 951+ cached templates
2. Finds `cryosparc_standard_spa` (id=12820 in DB)
3. Extracts `match.domain = 'cryo_em'`, `match.tools = ['cryosparc', 'ctffind4', 'motioncor2', 'topaz']`
4. Calls `_return_nextflow_match(match, ...)` to assemble response

---

### Step 3 — Knowledge Highlights Assembly (User-Facing)

`ai_assistant.py:4091` — `_build_knowledge_highlights(domain, workflow_name, tools)`

#### 3a. Load expert JSON
```python
fname = self._DOMAIN_KNOWLEDGE_FILES['cryo_em']
# → 'expert_knowledge_bioimaging.json'
# → backend/scripts/domain_knowledge/expert_knowledge_bioimaging.json
```

The JSON contains 11 cryo-EM topics, each with `best_practice_notes`, `key_parameters`, `key_references`.

#### 3b. Score topics by keyword overlap
All topic keys and descriptions are scored against the union of:
- Workflow name tokens: `{cryosparc, standard, spa}`
- Tool expansion via `_kw_expansions`:
  ```python
  'cryosparc' → {'single','particle','analysis','cryo','em','reconstruction','ctf','refinement'}
  'ctffind4'  → {'ctf','contrast','transfer','function','defocus','estimation'}
  'topaz'     → {'particle','picking','neural','network','detection','deep','learning'}
  ```

Top-scoring topics for this query:
1. `cryo_em_single_particle_analysis` (score≈18 — direct keyword match)
2. `cryo_em_3d_refinement` (score≈12 — refinement keywords)
3. `cryo_em_gpcr_complex_assembly` (score≈9 — GPCR in user message)

#### 3c. Extract structured knowledge from top 3 topics

```python
knowledge_highlights = {
    "best_practices": [
        "Follow the 14-gate QC hierarchy in strict order: G6 motion (<50 Å) → G7 CTF ...",
        "Use gold-standard FSC at 0.143 — never report 0.5 as primary resolution criterion",
        "Pixel size selection by MW: <50 kDa→0.649 Å, 100-300 kDa→0.83 Å, >600 kDa→1.06 Å"
    ],
    "qc_thresholds": [
        {"metric": "universal_qc_gates",
         "threshold": "<50 Å total drift per micrograph",
         "context": "After MotionCor2 motion correction",
         "source": "docs/cryo_em_skills/00_GENERAL_FRAMEWORK.md"},
        {"metric": "ctf_fom",
         "threshold": ">0.1",
         "context": "CTF fit quality; discard micrographs below"},
        # ... up to 5 thresholds
    ],
    "literature_guidance": [
        {"url": "https://doi.org/10.1038/s41586-023-06573-3",
         "context": "cryo_em_gpcr_complex_assembly"},
        # ... up to 3 papers
    ]
}
```

This dict is included verbatim in the API response.

---

### Step 4 — RAG Context Assembly (LLM-Facing, Parallel)

This path runs **in the frontend server** (`galaxy-assistant.ts`), concurrently with Step 3.

#### 4a. Domain detection in frontend server

`galaxy-assistant.ts` detects `isCryoEmDomain = true` based on:
- `preferred_domains` includes `cryo_em` or `bioimaging`
- OR matched workflow name contains `cryo`, `spa`, `relion`, `aretomo`

#### 4b. Fetch RAG context

```typescript
const cryoEmContext = await this._fetchCryoEmContext(message);
// → POST /api/cryo_em/context
//   {"query": "CryoSPARC single particle analysis..."}
```

#### 4c. Backend retriever assembles context block

`cryo_em_knowledge/retriever.py:427` — `get_full_context()`

```
Part 1 — Parameter table (always included):
<cryo_em_parameters>
| MW          | pixel_size (Å) | box_size (px) | defocus_min (μm) | total_dose (e⁻/Ų) |
|-------------|----------------|---------------|------------------|---------------------|
| <50 kDa     | 0.649          | 256           | -0.8             | 60                  |
| 100-300 kDa | 0.83           | 256           | -0.8             | 50                  |
| 600-1500 kDa| 1.06           | 400           | -1.5             | 50                  |
</cryo_em_parameters>

Part 2 — Semantic RAG chunks (BGE cosine search, top 5):
<cryo_em_knowledge>
[00_GENERAL_FRAMEWORK.md / Key Invariant Principles]
Gold-standard FSC at 0.143: Always report. MolProbity < 2.0 required for deposition...

[05_muOR_cell2022.md / 6. Key BioMate Learnable Principles]
GPCR-G protein complex requires stepwise assembly: MSP1D1ΔH5 + apyrase 0.02 U/mL
+ scFv16 must be added at the end...
</cryo_em_knowledge>
```

Total: ~600–1200 tokens. Retrieval scores: 0.60–0.80 (BGE cosine similarity).

#### 4d. Inject into system prompt

```typescript
const systemPrompt = `
${sessionMemoryBlock}
You are BioMate, a bioinformatics AI assistant...

${cryoEmContext}   ← inserted here

Available workflows: ...
`;
```

The LLM (Claude Sonnet 4.6) uses this context to:
- Confirm parameter choices (pixel size, defocus range)
- Surface protocol warnings (e.g., "scFv16 mandatory for GPCR complexes")
- Ground its scientific explanations in the actual publication data

---

### Step 5 — API Response to Frontend

The backend returns to the frontend:

```json
{
  "success": true,
  "workflow_type": "nextflow",
  "workflow_name": "cryosparc_standard_spa",
  "nextflow_path": "subworkflows/cryo_em/cryosparc_standard_spa/main.nf",
  "knowledge_highlights": {
    "best_practices": ["...14-gate QC hierarchy...", "...gold standard FSC...", "...pixel size by MW..."],
    "qc_thresholds": [
      {"metric": "universal_qc_gates", "threshold": "<50 Å drift", "context": "...", "source": "..."},
      {"metric": "ctf_fom", "threshold": ">0.1", "context": "...", "source": "..."}
    ],
    "literature_guidance": [{"url": "https://doi.org/...", "context": "cryo_em_single_particle_analysis"}]
  },
  "citations": [{"title": "CryoSPARC...", "url": "...", "year": 2017}],
  "required_params": [...],
  "optional_params": [...],
  "scientific_rationale": "..."
}
```

---

### Step 6 — Frontend Rendering

The `nextflow-workflow-viewer.tsx` viewer receives this response and:
1. Renders the workflow parameter form from `required_params` / `optional_params`
2. Passes `knowledge_highlights` to the right-panel component for display
3. The right panel (60/40 split, auto-opens) shows:
   - **Best Practices** — bulleted list from `knowledge_highlights.best_practices`
   - **QC Thresholds** — table: metric | threshold | context | source
   - **Literature** — clickable DOI links from `knowledge_highlights.literature_guidance`
   - **Citations** — formatted references from `citations`

---

## Complete Data Flow Diagram

```
User: "CryoSPARC SPA for GPCR cryo-EM"
           │
           ▼
  ┌─────────────────────────────────────┐
  │  POST /api/ai_assistant/            │
  │  generate_workflow                  │
  └──────────────┬──────────────────────┘
                 │
        ┌────────▼────────┐
        │ UnifiedWorkflow │
        │ Search → match  │ domain=cryo_em
        │ cryosparc_spa   │ tools=[cryosparc,
        └────────┬────────┘ ctffind4,topaz]
                 │
    ┌────────────▼────────────────────────────┐
    │  _build_knowledge_highlights()          │
    │  ┌──────────────────────────────────┐   │
    │  │ expert_knowledge_bioimaging.json │   │
    │  │  11 cryo-EM topics               │   │
    │  │  Score by keyword overlap        │   │
    │  │  Extract top 3 → structured dict │   │
    │  └──────────────────────────────────┘   │
    └────────────┬────────────────────────────┘
                 │
                 ▼
    {knowledge_highlights, citations, params, ...}
                 │
                 ▼
          HTTP Response ────────────────────┐
                                            │
  ┌─────────────────────┐                   │
  │ Frontend Server     │    (parallel)     │
  │ galaxy-assistant.ts │                   │
  │                     │                   │
  │  detect cryo-EM     │                   │
  │  fetch /api/cryo_em │                   │
  │       /context      │                   │
  │            │        │                   │
  │  ┌─────────▼──────┐ │                   │
  │  │  retriever.py  │ │                   │
  │  │  ┌──────────┐  │ │                   │
  │  │  │ param    │  │ │                   │
  │  │  │ table    │  │ │                   │
  │  │  ├──────────┤  │ │                   │
  │  │  │ BGE RAG  │  │ │                   │
  │  │  │ semantic │  │ │                   │
  │  │  │ search   │  │ │                   │
  │  │  │ 150 chunks│ │ │                   │
  │  │  └──────────┘  │ │                   │
  │  └─────────┬──────┘ │                   │
  │            │        │                   │
  │  inject into        │                   │
  │  system prompt      │                   │
  │  → LLM reasoning    │                   │
  └─────────────────────┘                   │
                                            ▼
                               ┌────────────────────────┐
                               │  nextflow-workflow-    │
                               │  viewer.tsx            │
                               │                        │
                               │  ┌──────────────────┐  │
                               │  │ Param form       │  │
                               │  ├──────────────────┤  │
                               │  │ Right panel 60/40│  │
                               │  │ ┌──────────────┐ │  │
                               │  │ │ Best         │ │  │
                               │  │ │ Practices    │ │  │
                               │  │ ├──────────────┤ │  │
                               │  │ │ QC Thresholds│ │  │
                               │  │ ├──────────────┤ │  │
                               │  │ │ Literature   │ │  │
                               │  │ └──────────────┘ │  │
                               │  └──────────────────┘  │
                               └────────────────────────┘
```

---

## Key Design Decisions

### Why two separate knowledge paths?

- **knowledge_highlights** is deterministic and fast. It uses keyword scoring over a curated JSON file, no LLM call needed. Gives the user trustworthy, citation-backed facts immediately.
- **RAG context** is semantic and query-adaptive. It uses BGE embeddings to find the most relevant publication chunks for the *specific* query, then injects them into the LLM prompt so the model can reason with them. The user doesn't see raw chunks — they see the LLM's response shaped by them.

### Why BGE for RAG and not TF-IDF?

TF-IDF hash embeddings gave cosine scores of 0.127 (near-random) because they can't capture semantic similarity ("saposin nanodisc" ≠ "lipid bilayer scaffold" by character n-gram). BGE-small-en-v1.5 (MTEB 62.17, 384-dim) gives 0.60–0.80 scores for semantically relevant chunks.

### Why `local_files_only=True`?

The production server has no outbound internet. Sentence-transformers by default pings HuggingFace to check for model updates on every load — timing out and falling back to TF-IDF hash. `local_files_only=True` skips the network check entirely; the model loads from `~/.cache/huggingface` in <2s.

### Why store vectors in `embedding_blob` AND `cryo_em_chunks_vec`?

- `cryo_em_chunks_vec` (sqlite-vec) provides fast ANN search when the sqlite-vec extension is loadable (direct Python calls, CLI)
- `embedding_blob` in the regular table is a fallback for gunicorn workers, which cannot `enable_load_extension()` due to security restrictions. Brute-force cosine over 150 chunks is fast enough (<10ms).

---

## Known Gaps

### Gap 1: knowledge_highlights and RAG don't cross-pollinate

RAG chunks surface dynamic, query-specific context to the LLM but don't appear in `knowledge_highlights`. A user asking about a niche protocol (e.g., "ANTS/DPX liposome pore assay") will get a good LLM response (RAG-informed) but the knowledge panel may show generic SPA best practices. 

**Future fix**: Feed top RAG chunk entities back into `knowledge_highlights.literature_guidance`.

### Gap 2: Sample class detection is keyword-only

`retriever.detect_sample_class()` matches on surface keywords (`saposin`, `gpcr`, `liposome`, etc.). Indirect descriptions ("my protein is in a lipid bilayer scaffold with saposin A") may not match.

**Future fix**: Use BGE embedding to classify sample class from query (cosine against each class centroid).

### Gap 3: knowledge_highlights only fires for template matches

If no workflow template matches and the system falls to free-form generation, `knowledge_highlights` is still populated (called at `ai_assistant.py:2755`) but only if `domain` can be inferred. Queries that are too vague may get an empty `{}`.

### Gap 4: No feedback loop from RAG to workflow parameters

RAG chunks contain specific parameter recommendations (e.g., "UltrAuFoil 1.5s blot time for saposin nanodiscs") but these are not automatically extracted and pre-filled into the workflow parameter form.

**Future fix**: Add a RAG-to-param extraction step that parses retrieved chunks for parameter hints and injects them via `_apply_parameter_hints()`.

---

## Testing the Full Path

### Quick manual check (direct backend)
```bash
# Test knowledge_highlights for cryo-EM query
curl -s http://localhost:8081/api/ai_assistant/generate_workflow \
  -H "x-api-key: 7341822cd19cddaa49139f6cccae8c76" \
  -H "Content-Type: application/json" \
  -d '{"request_text": "CryoSPARC SPA cryo-EM structure determination"}' \
  | python -c "
import sys,json; d=json.load(sys.stdin); kh=d.get('knowledge_highlights',{})
print(f'bp={len(kh.get(\"best_practices\",[]))}, qc={len(kh.get(\"qc_thresholds\",[]))}, lit={len(kh.get(\"literature_guidance\",[]))}, cits={len(d.get(\"citations\",[]))}')"
# Expected: bp=3, qc=5, lit=3, cits=1

# Test RAG context endpoint
curl -s http://localhost:8081/api/cryo_em/context \
  -H "x-api-key: 7341822cd19cddaa49139f6cccae8c76" \
  -H "Content-Type: application/json" \
  -d '{"query": "saposin nanodisc membrane protein reconstitution"}' \
  | python -m json.tool | grep has_rag
# Expected: "has_rag": true
```

### Rebuild RAG index (after adding new skill documents)
```bash
cd /home/yzhang/biomate/backend
python lib/galaxy/ai/cryo_em_knowledge/rag_index.py build \
    --docs /home/yzhang/biomate/docs/cryo_em_skills \
    --db   /home/yzhang/biomate/backend/galaxy_ai_tools.db \
    --force
# Output: RAG index built: N chunks, dim=384, vec=True
```

### Add a new skill document
1. Place `.md` file in `/home/yzhang/biomate/docs/cryo_em_skills/`
2. Add filename stem → sample_class mapping to `_FILE_TO_SAMPLE_CLASS` in `rag_index.py`
3. Rebuild index (command above)
4. Add corresponding topic to `expert_knowledge_bioimaging.json` with best_practice_notes, key_parameters, key_references
5. Add tool names to `_kw_expansions` in `ai_assistant.py`

---

## Files Reference

| File | Role in this system |
|---|---|
| `backend/scripts/domain_knowledge/expert_knowledge_bioimaging.json` | Static expert knowledge source for knowledge_highlights |
| `backend/lib/galaxy/ai/ai_assistant.py:4091` | `_build_knowledge_highlights()` — scores JSON topics by keyword overlap |
| `backend/lib/galaxy/ai/ai_assistant.py:2576` | `_return_nextflow_match()` — packages knowledge_highlights into API response |
| `backend/lib/galaxy/ai/cryo_em_knowledge/rag_index.py` | Build + query the BGE-embedded chunk index |
| `backend/lib/galaxy/ai/cryo_em_knowledge/retriever.py` | `get_full_context()` — assembles system prompt block (param table + RAG) |
| `backend/lib/galaxy/webapps/galaxy/api/cryo_em_knowledge.py` | REST endpoint `POST /api/cryo_em/context` |
| `backend/lib/galaxy/ai/vector_search.py` | BGE model for tool search (DEFAULT_MODEL=BAAI/bge-small-en-v1.5) |
| `frontend/server/galaxy-assistant.ts` | Fetches RAG context, injects into system prompt |
| `frontend/client/src/components/nextflow-workflow-viewer.tsx` | Renders knowledge_highlights in right panel |
