# Cryo-EM RAG & Knowledge Enrichment — 2026-04-14

## Summary

This session enriched BioMate's cryo-EM structural biology capabilities across three layers:
1. **Expert knowledge JSON** — publication-derived parameters injected into `knowledge_highlights`
2. **RAG index** — 150 chunks from 9 skill documents, rebuilt with BGE embeddings
3. **Embedding model** — upgraded from `all-MiniLM-L6-v2` → `BAAI/bge-small-en-v1.5` across all embedding subsystems

---

## Layer 1 — Publication-Derived Expert Knowledge (`expert_knowledge_bioimaging.json`)

### What changed
`backend/scripts/domain_knowledge/expert_knowledge_bioimaging.json` — cryo-EM section
completely replaced with 11 publication-specific topics (was: generic training-knowledge entries).

### Topics added (all values from actual skill documents)

| Topic key | Source | Key parameters |
|---|---|---|
| `cryo_em_single_particle_analysis` | `00_GENERAL_FRAMEWORK.md` | 14-gate QC hierarchy; MW-based pixel size table (<50 kDa→0.649 Å, 100-300 kDa→0.83 Å, 600-1500 kDa→1.06 Å) |
| `cryo_em_saposin_nanodisc_reconstitution` | `01_MFSD2B`, `02_VMAT2` | 1:10:200 molar ratio; POPC:POPE:POPG 3:1:1; UltrAuFoil 1.5s 10°C; three-picker strategy |
| `cryo_em_gpcr_complex_assembly` | `05_muOR`, `06_D1_PAM` | MSP1D1ΔH5; apyrase 0.02 U/mL; scFv16 mandatory; two-mask local refinement |
| `cryo_em_drug_difference_map` | `03_CaV1_2_cell2023` | ±3σ threshold; occupancy ≥0.7; CC >0.8; eLBOW CIF |
| `cryo_em_liposome_pore_forming` | `04_BAX_pore_science2025` | DOPC:DOPE:CL 4:3:1; ANTS/DPX >50% gate; two-EM approach |
| `cryo_em_symmetric_assembly` | `08_symmetric_assembly_capsid` | C1 first; symmetry expansion; preferred orientation fix |
| `cryo_em_3d_refinement` | General framework | Non-uniform refinement; local refinement; CTF refinement order |
| `cryo_em_heterogeneity_3dva` | General framework | 3DVA; cryoDRGN; 3D classification |
| `cryo_em_map_validation` | General framework | MolProbity <2.0; FSC gold-standard 0.143; DeepEMhancer |
| `cryo_et_subtomogram_averaging` | General framework | AreTomo2; IsoNet missing wedge; Dynamo |
| `helical_cryo_em` | General framework | RELION helical; rise/twist parameters |

### `_kw_expansions` additions (`ai_assistant.py`)
Added keyword expansion entries for all cryo-EM tool names so `_build_knowledge_highlights()`
correctly scores workflows against topics:

```python
'cryosparc', 'relion', 'ctffind4', 'gctf', 'motioncor2', 'topaz',
'eman2', 'aretomo2', 'isonet', 'dynamo', 'deepemhancer', 'spa', 'cryodrgn'
```

Removed bare `aretomo` (only `aretomo2` appears in DB) and bare `ctffind`/`motioncor`.

### Result
All 12 cryo-EM workflows in DB now surface relevant domain-specific topics in `knowledge_highlights`.
`generate_workflow` for a CryoSPARC SPA query returns:
- `best_practices=3`, `qc=5`, `literature_guidance=3`, `citations=1`

---

## Layer 2 — RAG Index (150 chunks from 9 publications)

### Documents indexed
| File | Sample class | Chunks |
|---|---|---|
| `00_GENERAL_FRAMEWORK.md` | general | 19 |
| `01_MFSD2B_preprint.md` | saposin_nanodisc | 15 |
| `02_VMAT2_nature2023.md` | saposin_nanodisc | 19 |
| `03_CaV1_2_cell2023.md` | detergent_ion_channel | 20 |
| `04_BAX_pore_science2025.md` | liposome_pore_forming | 19 |
| `05_muOR_cell2022.md` | msp_nanodisc_gpcr | 21 |
| `06_D1_PAM_preprint2025.md` | msp_nanodisc_gpcr | 19 |
| `07_spliceosome_multistate.md` | rna_protein_endogenous | 8 |
| `08_symmetric_assembly_capsid.md` | symmetric_assembly | 10 |
| **Total** | | **150** |

### Storage
- `cryo_em_chunks` table in `galaxy_ai_tools.db` — text + metadata + `embedding_blob BLOB`
- `cryo_em_chunks_vec` virtual table (sqlite-vec vec0) — 150 vectors, dim=384
- Both storage paths populated; brute-force cosine fallback reads `embedding_blob` directly
  (used by gunicorn workers where sqlite-vec extension is unavailable)

---

## Layer 3 — Embedding Model Upgrade

### Problem
The RAG system had an embedding space mismatch in production:
- Stored chunk blobs: `all-MiniLM-L6-v2` vectors
- Query embedding in gunicorn: TF-IDF hash (sentence-transformers failed silently due to
  `import torch` gating + CUDA driver incompatibility on NVIDIA GB10 sm_121)
- Result: cosine scores of **0.127** (near-random) instead of expected 0.6–0.8

### Fix — `cryo_em_knowledge/rag_index.py`

1. **Model**: `all-MiniLM-L6-v2` → `BAAI/bge-small-en-v1.5`
   - MTEB 62.17 vs 56.3 (+9% recall), same 384 dims, already benchmarked as "new biomate model"
   - Model cached at `~/.cache/huggingface/hub/models--BAAI--bge-small-en-v1.5`

2. **Module-level singleton**: Model loaded once per gunicorn worker, reused on every query.
   Previously re-instantiated on each `get_embeddings()` call.

3. **Offline mode**: `local_files_only=True` + `TRANSFORMERS_OFFLINE=1` env var
   (server has no outbound internet; prevents HuggingFace HEAD check timeout on every load)

4. **Removed `import torch` gate**: Was causing the silent fallback to TF-IDF

```python
# Before
try:
    import torch
    from sentence_transformers import SentenceTransformer
    _st_model = SentenceTransformer("all-MiniLM-L6-v2", device="cpu")
    ...
except Exception as e:
    # silently fell through to TF-IDF

# After
_BGE_MODEL_NAME = "BAAI/bge-small-en-v1.5"
_bge_model = None  # module-level singleton

def _get_bge_model():
    global _bge_model
    if _bge_model is None:
        os.environ.setdefault("TRANSFORMERS_OFFLINE", "1")
        os.environ.setdefault("HF_DATASETS_OFFLINE", "1")
        from sentence_transformers import SentenceTransformer
        _bge_model = SentenceTransformer(_BGE_MODEL_NAME, device="cpu",
                                         local_files_only=True)
    return _bge_model
```

### Fix — `vector_search.py`
- `DEFAULT_MODEL`: `all-MiniLM-L6-v2` → `BAAI/bge-small-en-v1.5`
- `SentenceTransformer(...)` call: added `local_files_only=True`

### Fix — `unified_workflow_search.py`
- Chain embedding model load: added `local_files_only=True`

### Score comparison

| Query | Before | After | Method |
|---|---|---|---|
| Saposin nanodisc reconstitution | 0.127 | 0.61–0.64 | vec_ann |
| GPCR MSP nanodisc apyrase | 0.127 | 0.62–0.70 | brute_cosine_blob |
| Tilt series subtomogram | 0.127 | 0.80 | vec_ann |
| Drug difference map CaV1.2 | 0.127 | 0.54–0.59 | vec_ann |

### Index rebuild
```bash
python lib/galaxy/ai/cryo_em_knowledge/rag_index.py build \
    --docs /home/yzhang/biomate/docs/cryo_em_skills \
    --db   /home/yzhang/biomate/backend/galaxy_ai_tools.db \
    --force
# Output: RAG index built: 150 chunks, dim=384, vec=True
```

---

## Live API Verification

### `/api/cryo_em/context` (direct backend port 8081)
```json
{
  "has_rag": true,
  "token_estimate": 1207,
  "sample_class_detected": null
}
```
Context includes: MW-based pixel size table, gold-standard FSC rule, capsid preferred
orientation guidance, μOR GPCR structure methodology.

### `/api/ai_assistant/generate_workflow` (CryoSPARC SPA query)
```
best_practices=3, qc=5, literature_guidance=3, citations=1
QC[0]: {'metric': 'universal_qc_gates',
         'threshold': '<50 Å total drift per micrograph',
         'context': 'After MotionCor2 motion correction; inspect trajectory output.',
         'source': 'docs/cryo_em_skills/00_GENERAL_FRAMEWORK.md'}
```

---

## Files Modified

| File | Change |
|---|---|
| `backend/scripts/domain_knowledge/expert_knowledge_bioimaging.json` | 11 publication-derived cryo-EM topics replacing generic entries |
| `backend/lib/galaxy/ai/ai_assistant.py` | `_kw_expansions` — 13 cryo-EM tool entries added |
| `backend/lib/galaxy/ai/cryo_em_knowledge/rag_index.py` | BGE model; singleton cache; offline mode; removed torch gate |
| `backend/lib/galaxy/ai/vector_search.py` | `DEFAULT_MODEL` upgraded; `local_files_only=True` |
| `backend/lib/galaxy/ai/unified_workflow_search.py` | `local_files_only=True` for chain embedding load |
| `galaxy_ai_tools.db` | 150 BGE-embedded cryo-EM chunks (rebuilt) |
