# Session 3 — Backend Intelligence & Knowledge: Final Status

**Date:** 2026-04-13  
**Branch:** integration/next-phase

---

## Track 3B: Domain Knowledge Highlights — DoD MET ✓

All 5 domain demo cases return `knowledge_highlights` with measurably different parameter defaults:

| Domain | Workflow | bp | qc | lit | citations | Source |
|--------|----------|----|----|-----|-----------|--------|
| drug_discovery | Predict Admet Properties | 3 | 5 | 3 | 2 | template_reuse |
| genomics | Wgs Germline Gatk | 3 | 5 | 3 | 3 | template_reuse |
| bioimaging | CryoSPARC Standard SPA | 3 | 5 | 3 | 1 | template_reuse |
| proteomics | nf-core/proteomicslfq | 3 | 5 | 3 | 2 | template_reuse |
| single_cell | single_cell_multimodal_analysis | 3 | 5 | 3 | — | chain_lookup |

Sample outputs (showing real domain specificity):
- **drug_discovery**: "Use multiple complementary ADMET prediction tools (SwissADME, ADMETlab, pkCSM)"; QC: `lipinski_rule_of_five=MW < 500 Da`
- **genomics**: "Always apply BQSR before HaplotypeCaller variant calling"; QC: `vqsr_tranche=99.5%`
- **bioimaging**: "Always perform motion correction before CTF estimation"; QC: `ctf_defocus_range=0.5-4.0 µm`
- **proteomics**: "Always apply protein-level FDR correction separately from peptide-level FDR"; QC: `fdr_threshold=1%`

---

## Bugs Fixed

### 1. Forward slash not stripped from workflow names
**File:** `backend/lib/galaxy/ai/ai_assistant.py` — `_build_knowledge_highlights()`  
**Problem:** `nf-core/proteomicslfq` split to `{'nf', 'core/proteomicslfq'}`, so `proteomicslfq` was not a standalone keyword and expansion never fired.  
**Fix:** `_normalize = lambda s: s.lower().replace('-',' ').replace('_',' ').replace('/',' ')`

### 2. `proteomicslfq` missing from keyword expansions
**File:** `backend/lib/galaxy/ai/ai_assistant.py` — `_kw_expansions`  
**Fix:** Added `'proteomicslfq': {'proteomics', 'lfq', 'lc', 'ms', 'label', 'free', 'quantification'}`

### 3. `rare_disease_multimodal_workup` chain false-positive on WGS-only queries
**File:** `backend/lib/galaxy/ai/unified_workflow_search.py`  
**Problem:** Query "GATK HaplotypeCaller germline variant calling on WGS" triggered the rare_disease chain (which requires BOTH WGS AND RNA-seq). The chain's description overlaps heavily with germline variant calling, causing false match in Jaccard (Tier 2) and sometimes embedding (Tier 1).  
**Fix:** Added `_CHAIN_REQUIRED_CONTEXT` class dict mapping chain names to required term groups. Implemented `_chain_multimodal_context_compatible()` classmethod that rejects a chain if the query doesn't contain any term from each required group. Applied to **both** Tier 1 (embedding path) and Tier 2 (Jaccard fallback) in `search_chains()`.

```python
_CHAIN_REQUIRED_CONTEXT = {
    'rare_disease_multimodal_workup': [
        frozenset({'rare disease', 'rare_disease', 'multimodal', 'rna-seq', 'rnaseq',
                   'rna seq', 'transcriptomic', 'outrider', 'fraser', ...})
    ]
}
```

### 4. Chain results had no `knowledge_highlights`
**Files:** `ai_assistant.py` + `api/ai_assistant.py`  
**Fix:** Added `_build_knowledge_highlights(top_chain.domain, ...)` call inside the chain return block; passthrough in the API handler's chain branch.

---

## Track 3A: Biological Database Query — Implemented

15+ REST API query methods (UniProt, NCBI Gene, KEGG, PDB, AlphaFold, Reactome, gnomAD, GO, HPO, ChEBI, ChEMBL, InterPro, STRING, Ensembl, dbSNP/ClinVar via Entrez).

Endpoint: `POST /api/databases/query` with body `{"database": "uniprot|ncbi|kegg|...", "query": "TP53"}`.

Auto-routing: `database="auto"` detects from query format (accession regex matching).

---

## Track 3D-i: Citation Consistency — Fixed

**Problems fixed:**
- `CitationModel.authors` validation error when ToolKnowledgeProvider returns `str` instead of `list`
- API passthrough `citation_info = cit_data.get('citation', cit_data)` supports both flat dict and nested `{'citation': {...}}` format
- Added `knowledge_highlights` passthrough in all result paths (Nextflow match, chain match)

---

## Knowledge JSON Files Updated

| File | Topic Added |
|------|-------------|
| `expert_knowledge_genomics.json` | `gatk_variant_calling` — VQSR tranches, BQSR known sites, hard filter fallback |
| `expert_knowledge_bioimaging.json` | `cryo_em_single_particle_analysis` — CTF defocus ranges, FSC=0.143, cryoSPARC thresholds |
| `expert_knowledge_molecular_biology.json` | `lc_ms_proteomics_data_analysis` — FDR 1%, LFQ min ratio count ≥2, CV thresholds |
| `expert_knowledge_cellbio_immuno.json` | `scrna_seq_clustering_leiden_seurat` — Leiden resolution guidance, n_neighbors, HVG count |

---

## Open Items

- **Track 3D-ii E2E test**: `frontend/e2e/autofix-comprehensive.e2e.ts` — needs verification
- **Track 3D-iii consistency benchmark**: `evaluation/runners/run_consistency_benchmark.py` — temperature fixes in place, ready to run
- **P2/P3 memory**: pgvector embeddings, cross-session injection, memory UI panel (from Session 3 original scope)
- **single_cell chain citations**: Chain results don't carry per-tool citations; would need curated citation list on the `workflow_chains` row
