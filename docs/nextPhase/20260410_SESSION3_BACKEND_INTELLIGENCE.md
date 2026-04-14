# Session 3 — Backend Intelligence & Knowledge
**Date:** 2026-04-10  
**Branch:** integration/next-phase  
**Status:** Tracks 3A, 3B, 3C, 3D-i, 3D-ii, 3D-iii COMPLETE

---

## Track 3A — Database Access: Comprehensive Tool Routing

### Problem
The AI only had 10 hardcoded databases in the `query_database` tool schema, but 75+ database/reference tools are indexed in `galaxy_ai_tools.db`.

### Solution
Implemented a comprehensive `/api/databases/query` POST endpoint in the Python backend that routes to **all major public biological REST APIs**:

**File:** `backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py`  
**Method:** `query_biological_database()` at `@router.post("/api/databases/query")`

**File:** `backend/lib/galaxy/ai/ai_assistant.py`  
**Methods added:**
- `query_database(database, query)` — main dispatcher
- `_detect_database_from_query(query)` — auto entity-type detection
- `_http_get_json(url, headers)` — shared HTTP helper
- `_query_uniprot(query)` — UniProt REST v2
- `_query_pdb(query)` — RCSB PDB / PDB direct entry
- `_query_alphafold(query)` — AlphaFold EBI prediction
- `_query_ncbi_gene(query)` — NCBI Gene via E-utilities
- `_query_ncbi_entrez(query, db)` — generic NCBI Entrez (dbSNP, ClinVar, PubMed)
- `_query_gnomad(query)` — gnomAD GraphQL v4
- `_query_kegg(query)` — KEGG REST (compound, pathway, gene)
- `_query_reactome(query)` — Reactome content service
- `_query_go(query)` — QuickGO (ID lookup + text search)
- `_query_hpo(query)` — HPO JAX API
- `_query_chebi(query)` — ChEBI EBI REST
- `_query_chembl(query)` — ChEMBL EBI REST
- `_query_interpro(query)` — InterPro EBI REST
- `_query_string(query)` — STRING DB protein interactions
- `_query_ensembl(query)` — Ensembl REST (symbol + ID lookup)

**Auto-detection logic (`database="auto"`):**
| Pattern | Detected DB |
|---------|-------------|
| `rs\d+` or "variant" | dbsnp or clinvar |
| UniProt accession format | uniprot |
| 4-char alphanumeric PDB ID | pdb |
| "compound", "smiles", "drug" | chembl |
| "pathway", "kegg" | kegg |
| `GO:\d+` | go |
| "disease", "phenotype", "hp:" | hpo |
| "domain", "pfam" | interpro |
| "gene", "mrna" | ncbi_gene |
| "protein", "enzyme" | uniprot |
| Default | ncbi_gene |

**Verified live:**
- ✅ ncbi_gene(TP53) → 12,016 results, gene_id=7157
- ✅ uniprot(BRCA1) → reviewed results, accession P38398
- ✅ kegg(apoptosis) → pathway entries
- ✅ reactome(apoptosis) → 5 pathway results
- ⚠️ chembl(ibuprofen) → timeout from server (works in direct Python, network issue)

---

## Track 3B — Domain Knowledge Leverage

### Problem
6 expert knowledge JSON files (~540KB, 59 topics) existed but were only used for parameter defaults (`_apply_parameter_hints()`). Rich protocol guidance, QC thresholds, and literature references were never surfaced in the chat response.

### Solution
Added `_build_knowledge_highlights()` method in `ai_assistant.py` that:
1. Detects the domain from the workflow name
2. Loads the relevant expert knowledge JSON file
3. Finds topics relevant to this specific workflow by keyword matching
4. Extracts:
   - `best_practices`: best_practice_notes strings (≤3)
   - `qc_thresholds`: `{metric, threshold, context, source}` from `situations.value_or_range` (≤5)
   - `literature_guidance`: `{url, context}` from `key_references` (≤3)

Domain → file mapping:
| Domain | File |
|--------|------|
| genomics | expert_knowledge_genomics.json |
| drug_discovery, pharmacology, structural_biology | expert_knowledge_pharmacology.json |
| bioimaging | expert_knowledge_bioimaging.json |
| proteomics, molecular_biology | expert_knowledge_molecular_biology.json |
| single_cell, cell_biology, immunology | expert_knowledge_cellbio_immuno.json |
| microbiology, systems_biology | expert_knowledge_microbio_sysbio.json |

**Wired into** `_return_nextflow_match()`:
```python
knowledge_highlights = self._build_knowledge_highlights(match.domain, match.name, match.tools)
# Added to response dict as 'knowledge_highlights' key
```

---

## Track 3C — AI Container Tools (COMPLETED IN PREVIOUS SESSION)

All 8 AI tool containers registered as Nextflow workflows:

| Tool | Workflow ID | Domain |
|------|-------------|--------|
| Boltz-2 | 12853 | structural_biology |
| Chai-1 | 12854 | structural_biology |
| DrugCLIP | 12855 | drug_discovery |
| scFv-pMPNN | 12856 | drug_discovery |
| SynCraft | 12857 | drug_discovery |
| ProTrek | 12858 | proteomics |
| ProFAM-1 | 12859 | proteomics |
| STATE | 12860 | single_cell |

- All `main.nf` + `nextflow.config` files created under `backend/biomni_workflows/nextflow_nfcore/subworkflows/`
- Registered in `galaxy_ai_tools.db` workflows table (IDs 12853–12860)
- Routing clauses added in `galaxy-assistant.ts` system prompt
- ECR URIs: `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/{tool}:latest`

---

## Track 3D-i — Reference/Citation Consistency

### Problem
Workflow chat responses had no consistent citation format. `ToolKnowledgeProvider` had `format_apa()` but it was never called in the workflow generation path.

### Solution
Added `_build_workflow_citations()` in `ai_assistant.py`:

1. **Source 1 — tool_knowledge DB**: For each workflow tool, calls `ToolKnowledgeProvider.get_citation(tool_name)` → `citation.format_apa()` → APA string
2. **Source 2 — domain landmark papers**: Hardcoded dict of 1 key paper per major domain (genomics: nf-core 2020; drug_discovery: AlphaFold 2021; proteomics: Röst 2016; single_cell: Seurat/Hao 2024; structural_biology: PDB 2000)
3. **Format**: `{index, authors, year, title, journal, doi, pmid, formatted_apa}`

**Consistent APA format:**
```
[1] Ewels PA et al. (2020). The nf-core framework for community-curated bioinformatics pipelines. Nature Biotechnology. DOI: 10.1038/s41587-020-0439-x
```

**Wired into** `_return_nextflow_match()`:
```python
citations = self._build_workflow_citations(match.tools, match.domain, match.tags)
# Added to response dict as 'citations' key (only when non-empty)
```

---

## Track 3D-ii — Autofix Comprehensive E2E Test

**File:** `frontend/e2e/autofix-comprehensive.e2e.ts`

10 test groups:
| Group | Tests | What it covers |
|-------|-------|----------------|
| AF-1 | 12 | /databases/query returns structured results for all major DBs |
| AF-8 | 7 | Auto-detection routes to correct DB for each entity type |
| AF-3 | 5 | Error classification (missing_param, docker_pull, data_format, resource_limit, unknown) |
| AF-4 | 1 | UI: Run button disabled during active autofix |
| AF-5 | 1 | UI: Autofix banner shows attempt count |
| AF-6 | 1 | UI: Resolved autofix shows success/failure clearly |
| AF-7 | 5 | Routing determinism — same query ×5 returns same workflow ≥4/5 times |
| AF-9 | 3 | knowledge_highlights + citations in workflow response |
| AF-10 | 5 | Autofix framework error class coverage via /explain_error |

---

## Track 3D-iii — LLM Output Determinism

### Audit Results
| File | Line | Method | Old temp | Fix |
|------|------|--------|----------|-----|
| `galaxy-assistant.ts` | 1232 | `_generateClarificationQuestion()` | unset | `0.0` |
| `galaxy-assistant.ts` | 4131 | Session summary generation | unset | `0.1` |
| `routes.ts` | 8727 | Yes/No binary classifier | unset | `0.0` |
| `ai_assistant.py` | 2771 | Parameter inference (Haiku) | (already fixed) | `0.0` ✓ |
| `ai_assistant.py` | 669 | Fast LLM classify | (already 0) | `0.0` ✓ |

All 3 new fixes applied. The consistency benchmark (`evaluation/runners/run_consistency_benchmark.py`) can now be run — all routing/classification call sites have explicit `temperature=0.0`.

---

## Summary: Files Changed

| File | Change |
|------|--------|
| `backend/lib/galaxy/ai/ai_assistant.py` | +520 lines: `query_database()`, 13 DB query methods, `_build_workflow_citations()`, `_build_knowledge_highlights()`, `_return_nextflow_match()` wired to citations+knowledge |
| `backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py` | +45 lines: `/api/databases/query` POST endpoint |
| `frontend/server/galaxy-assistant.ts` | 2 temperature fixes (lines 1232, 4131) |
| `frontend/server/routes.ts` | 1 temperature fix (line 8727) |
| `frontend/e2e/autofix-comprehensive.e2e.ts` | New: 10 test groups, ~280 lines |

---

## What's Next

### Immediate (this session)
1. **Consistency benchmark** (`evaluation/runners/run_consistency_benchmark.py`) — can now run after temperature fixes; baseline measurement needed
2. **Track 1D** — Wire `user_domain_profile` into `generate_workflow_unified()` search to activate the `+2` domain bonus
3. **Track 3A** — Wire `database_lookup` intent to the new endpoint in `galaxy-assistant.ts` (currently `needsDatasetAccess=true` but no dedicated handler calls `/api/databases/query`)

### Session 4 (Docker images)
- Track 4D-ii: Docker image size analysis — Session 4 needs finalized ECR image names to wire container directives
- The 8 AI tools already have ECR URIs in their `nextflow.config` files
- Session 4's Docker split work should reference: `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/{tool}:latest`

### Session 5 (Consistency)
- Run consistency benchmark to measure `temperature=0.0` impact (Track 5A)
- Expected: same-result rate should increase from ~70% to ≥90%
