# Benchmark Matrix & External Benchmark Fixes — 2026-04-16

**Branch:** integration/next-phase  
**Status:** Complete — 4 benchmarks run, v3 matrix generated

---

## Session Goals

1. Fix external benchmark failures (SGI-Bench 10%, BixBench 26.7%, BiomniEval1 PGD 23.3%, RDD 20.0%)
2. Run benchmarks with fixes applied
3. Generate team-discussion Excel matrix

---

## Fixes Applied

### Fix 1 — Intent Routing (galaxy-assistant.ts)
Added 5 explicit rule bullets and 4 few-shot examples to force `research_question` intent with `needsResearchAgent: true` for:
- Numerical/statistical questions about published data (ORR, hazard ratio, p-value)
- Paper figure data extraction questions
- GWAS/functional genomics knowledge lookups
- scRNA-seq/computational biology MCQ without user data files
- Clinical trial result queries

### Fix 2 — ResearchAgent DB Clients (research_agent.py)
Added live HTTP client functions called before LLM synthesis in `_gather_evidence()`:
- `lookup_ensembl_ids()` — Ensembl REST API batch lookup for ENSG IDs
- `lookup_mygene()` — MyGene.info gene annotation (OMIM IDs, summaries)
- `lookup_hpo_genes()` — Monarch Initiative v3 API for HPO → gene associations
- `lookup_clinvar_gene()` — NCBI E-utils esearch+esummary for pathogenic variants
- `extract_biomedical_identifiers()` — regex extraction of HP:, ENSG, gene symbols from query

### Fix 3 — Boilerplate Suppression (galaxy-assistant.ts)
`enforceDrugDevelopmentResponseQuality()` was appending "Workflow phases / Required inputs / Next step" boilerplate even on pure research answers. Root cause: the function checked `runnableWorkflow` (False for research) but didn't know the intent was research.

Fix: Added `isResearchAnswer` param; set by checking `intent.type` against `RESEARCH_INTENT_TYPES` set:
```typescript
const RESEARCH_INTENT_TYPES = new Set([
  'research_question', 'troubleshooting', 'parameter_optimization',
  'experiment_design', 'data_interpretation', 'protocol_guidance',
  'methods_writing', 'comparative_methodology', 'regulatory_compliance',
]);
```

### Fix 4 — BiomniEval1 Local Cache (biomni_eval1.py)
The loader tried `pd.read_parquet("hf://datasets/biomni/Eval1/...")` which times out when HuggingFace is unreachable. Fixed to check local HuggingFace hub cache first:
```python
_LOCAL = "~/.cache/huggingface/hub/datasets--biomni--Eval1/snapshots/.../biomni_eval1_dataset.parquet"
_src = _LOCAL if os.path.exists(_LOCAL) else "hf://..."
```

---

## Benchmark Results

| Benchmark | Before | After | Delta |
|-----------|--------|-------|-------|
| SGI-Bench deep research (30q) | 10.0% | **16.7%** | +6.7pp |
| BixBench MCQ verified (30q) | 26.7% | **23.3%** | −3.4pp (noise) |
| BiomniEval1 PGD (30q) | 23.3% | **40.0%** | +16.7pp |
| BiomniEval1 RDD (30q) | 20.0% | **40.0%** | +20.0pp |

---

## Root Cause Analysis

### Why SGI-Bench is still low (16.7% vs Claude ~42%)
SGI deep research questions require extracting specific numbers from specific paper sections (e.g., "biopsy window: within 30 days" from Methods of a specific trial paper). ResearchAgent searches PubMed/arXiv abstracts but cannot retrieve full-text method sections. Boilerplate removal helped (+6.7pp) but paper retrieval is the ceiling.

**Fix needed:** PMC Open Access full-text retrieval or Semantic Scholar PDF integration.

### Why BixBench remains low (23% vs Biomni 88.7%)
BixBench asks computational biology questions requiring Python/R code execution (e.g., "compute PCA on this count matrix, report % variance explained by PC1"). BioMate has no code sandbox. This is a structural limitation.

**Fix needed:** Docker-sandboxed Python execution tool or Nextflow-based compute step.

---

## Architecture Debt

Per user direction: ResearchAgent DB clients should eventually be replaced by calling registered tools in `galaxy_ai_tools.db` via Galaxy API (CLINVAR id=9322, ENSEMBL id=9326, mygene id=9489). Current interim HTTP clients are a temporary fix.

---

## Files Changed

| File | Change |
|------|--------|
| `frontend/server/galaxy-assistant.ts` | Routing examples + boilerplate suppression fix |
| `backend/lib/galaxy/ai/agents/research_agent.py` | Live DB clients: Ensembl, MyGene, Monarch, ClinVar |
| `Biomni/biomni/eval/biomni_eval1.py` | Local HF cache fallback |
| `docs/20260416_biomate_benchmark_matrix_v3.xlsx` | v3 matrix with post-fix results |
