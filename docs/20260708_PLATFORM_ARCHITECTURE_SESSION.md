# BioMate Platform Architecture Session — 2026-07-08

## What Was Built

### 1. Federated Query Layer (`backend/lib/galaxy/ai/federated_query.py`)

Replaced the single-dispatch `query_database()` pattern with a parallel fan-out engine.

**Before:** `query_database("auto", "BRCA1")` → picks ONE database based on keyword heuristics → single synchronous HTTP call → result.

**After:** `federated_query("BRCA1")` → detects entity type (gene) → fires 9 sources in parallel (NCBI Gene + Ensembl + UniProt + STRING + KEGG + GO + gnomAD + PubMed + Semantic Scholar) → deduplicates and merges results in priority order → Redis-cached for 24h.

**Entity types auto-detected:** gene, protein, compound, variant, pathway, structure, disease, literature.
Detection is regex-first (UniProt accession pattern, PDB 4-char, rsID, GO term, SMILES structural chars), keyword fallback.

**New sources added (beyond existing 16):**
- `europepmc` — EBI Europe PMC, 4M open-access full-text papers with abstracts
- `semantic_scholar` — Semantic Scholar API, citation graph + open-access PDFs
- `openalex` — 250M works, concept tagging, institution filtering

**Caching:**
- Stable data (UniProt, PDB, AlphaFold, ChEMBL): 24h Redis TTL
- Literature (PubMed, EuropePMC, Semantic Scholar): 1h Redis TTL
- Chemical name→SMILES: 7 day Redis TTL
- Graceful degradation: if Redis unavailable, all queries run live

**Backward compatible:** existing single-source calls (`database="pubmed"`) unchanged.

### 2. Iterative Literature Search (`federated_query.iterative_literature_search`)

Open Deep Research-style depth loop over all 4 literature sources.
- Fans out PubMed + EuropePMC + Semantic Scholar + OpenAlex in parallel per iteration
- Deduplicates across iterations by PMID / Semantic Scholar paper ID
- Gap detection: if < 3 new results returned, refines query (appends "mechanism review") and deepens
- Stops at `min_results` (default 10) or `max_depth` (default 3, max 5)
- Returns full result set + search trace (depth, query used, sources hit, new_results count)

### 3. Chemical Name → SMILES Resolution

**Problem identified:** When a user types "run ADMET for imatinib", the LLM parameter extractor would set `smiles="imatinib"` — a name, not a valid SMILES string. The ADMET workflow receives this and silently fails or produces garbage.

**Fix:**
- `_looks_like_chemical_name(value)` — detects name vs. SMILES. Rule: no structural chars (`=`, `#`, `(`, `[`, `@`), word-like pattern. InChI strings and real SMILES pass through unchanged.
- `resolve_chemical_name(name)` — PubChem PUG REST lookup. Returns isomeric SMILES. `aspirin → CC(=O)OC1=CC=CC=C1C(=O)O`. Redis-cached 7 days.
- `resolve_smiles_params(params)` — post-processes extracted param list, only acts on SMILES-named fields (`smiles`, `ligand_smiles`, `compound`, `molecule`, etc.).
- **Hooked into** `_suggest_parameters_with_llm()` in `ai_assistant.py` — runs automatically on every workflow parameter extraction.

### 4. Backend API endpoints

New Galaxy Python routes in `backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py`:
```
POST /api/databases/query     { database="federated", query, entity_type?, sources? }
POST /api/literature/search   { query, max_depth=3, min_results=10 }
```

New Node.js routes in `frontend/server/routes.ts`:
```
POST /api/databases/query     (default now federates instead of single-source)
POST /api/databases/federated (explicit federated endpoint)
POST /api/literature/search   (iterative depth-loop)
```

### 5. Architecture Comparison Document (Artifact)

Compared BioMate vs OpenWork (Tauri desktop) vs Open Deep Research (iterative research loop).
Published as interactive HTML artifact.

Key findings:
- BioMate has unique domain capabilities neither reference project has (2,455 workflows, regulatory output, auto-loop QC)
- Gap: no desktop delivery, no local file access, no local compute, no iterative literature research
- OpenWork → adopt Tauri shell strategy (Phase 1: client mode wrapping existing web app)
- Open Deep Research → adopt iterative depth-loop for literature research (now partially implemented)

---

## Files Changed

| File | Change |
|------|--------|
| `backend/lib/galaxy/ai/federated_query.py` | **New** — federated query engine, 3 new literature sources, chemical name resolver |
| `backend/lib/galaxy/ai/ai_assistant.py` | `query_database()`: added `federated`/`europepmc`/`semantic_scholar`/`openalex` dispatch; `_suggest_parameters_with_llm()`: SMILES resolution hook |
| `backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py` | `DatabaseQueryRequest`: added `entity_type`, `sources` fields; `query_biological_database()`: direct federated path; new `LiteratureSearchRequest` + `literature_search()` endpoint |
| `frontend/server/routes.ts` | `POST /api/databases/query` default changed to `federated`; added `POST /api/databases/federated` and `POST /api/literature/search` |

---

## Open Issues / Known Gaps

- **Iterative query refinement is naive** — gap detection refines by appending "mechanism review". Should use LLM to generate a semantically targeted refinement query based on what's missing.
- **`resolve_chemical_name` PubChem field handling** — PubChem returns `SMILES` not `IsomericSMILES` in name-lookup responses; handled with multi-key fallback, but should be confirmed for edge cases (large polymers, mixtures).
- **No SMILES validation after resolution** — after PubChem returns a SMILES, we don't run RDKit or similar to validate it's parseable. A malformed SMILES from PubChem would still pass through.
- **Fan-out timeout is wall-clock 15s** — sources that consistently time out (e.g. gnomAD GraphQL under load) will be in `sources_failed` rather than blocking. This is correct behavior, but callers should check `sources_failed` in responses.
- **No streaming for federated results** — results arrive as a single JSON blob after all parallel calls complete. For the UI, consider streaming each source result as it arrives via SSE.

---

## Next Steps (Platform Roadmap)

### Immediate (this session)
- [ ] **Desktop Phase 1**: Tauri shell wrapping existing React app, client mode (connects to cloud), local file picker, token in OS keychain. macOS + Windows builds via GitHub Actions matrix.

### Short term
- [ ] **Desktop Phase 2**: BioMate Agent sidecar (Node.js), local Nextflow executor, SLURM connector as MCP server, Ollama local model support
- [ ] **LLM-guided query refinement**: replace naive "append mechanism review" with a fast LLM call that analyzes the gaps and generates a targeted follow-up query
- [ ] **Streaming federated results**: SSE endpoint that pushes each source result as it arrives
- [ ] **SMILES validation**: run OpenBabel or RDKit (via subprocess) to validate resolved SMILES before passing to workflow

### Medium term
- [ ] **Architecture consolidation**: collapse Galaxy into pure execution engine; Node.js owns all user-facing API surface; Redis as single run-state store
- [ ] **TanStack Query adoption**: replace scattered useState(loading) patterns in React
- [ ] **Instrument connectors as local MCP servers** (Desktop Phase 2 prerequisite)
