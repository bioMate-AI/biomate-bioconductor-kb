# Domain Inference & Sample Class Detection — BGE Semantic Upgrade

**Date:** 2026-04-14

---

## Problem

Two subsystems used keyword lists for classification:

1. `retriever.detect_sample_class()` — matched cryo-EM sample class from user query using a flat keyword list. Indirect phrasing ("my protein is in a lipid bilayer scaffold with saposin A") would return `None` because none of the literal keywords matched.

2. `ai_assistant._infer_domain_from_intent()` — a newly added method that used an ordered keyword list to classify which knowledge domain a query belongs to. The ordering was fragile: "single cell RNA-seq" matched `transcriptomics` before `single_cell` because `rna-seq` appeared earlier in the list. The fix of moving array entries up was immediately rejected as ad hoc.

Both were the same root cause: keyword matching can't handle paraphrase, indirect description, or terminology variation.

---

## Fix

Both methods now use **BGE cosine similarity against pre-computed description centroids**. No keyword lists. The model makes its own decision.

### How it works

Each domain/class is represented by a rich description string that combines:
- A natural-language summary of what the domain covers
- Representative tool names and method terms
- Common user phrasings and synonyms (formerly "keywords")

These descriptions are encoded once at startup into 384-dim BGE vectors (centroids). On each query, the user intent is encoded and cosine-compared against all centroids. The closest match wins — if score ≥ threshold and margin over second-best ≥ minimum gap; otherwise returns empty (no domain / no class).

The description strings are **reference material for the model, not rules**. BGE reads the full text semantically and is not bound by any individual term. Ambiguous queries score low on all domains and return nothing — which is the correct behavior.

---

## Implementation

### Gap 1 — `retriever.detect_sample_class()` (`cryo_em_knowledge/retriever.py`)

Added at module top:
- `_BGE_MODEL_NAME`, `_bge_model` singleton (same pattern as `rag_index.py`)
- `_get_bge_model()` — loads once per process, `local_files_only=True`
- `_CLASS_DESCRIPTIONS` — one rich description string per sample class
- `_get_class_centroids()` — encodes all class descriptions once, caches result
- `_cosine()` helper

`detect_sample_class()` now has two passes:
1. **Keyword fast path** — retained for the handful of unambiguous surface signals (exact tool names, acronyms). Zero cost.
2. **BGE semantic fallback** — if keywords produce no match, embeds the query and cosines against centroids. Requires score ≥ 0.55, margin ≥ 0.05. Handles indirect phrasing.

Sample class descriptions:

| Class | Description anchors |
|---|---|
| `saposin_nanodisc` | saposin, MFSD2B, VMAT2, lipid bilayer scaffold, POPC:POPE:POPG, gamma-cyclodextrin |
| `msp_nanodisc_gpcr` | GPCR, G protein, MSP, apyrase, scFv16, Gi, Gs, biased agonism |
| `detergent_ion_channel` | DDM, digitonin, GDN, ion channel, CaV, detergent exchange |
| `liposome_pore_forming` | liposome, BAX, bcl-2, ANTS/DPX, proteoliposome, apoptosis |
| `rna_protein_endogenous` | spliceosome, ribosome, glycerol gradient, 3DVA, multistate |
| `symmetric_assembly` | capsid, icosahedral, T=4, HBV, AAV, symmetry expansion |
| `cryo_et` | cryo-ET, tilt series, subtomogram, FIB milling, lamella, AreTomo2 |

### Gap 2 — `_infer_domain_from_intent()` (`ai_assistant.py`)

Replaces the entire keyword-ordered list with BGE centroids.

Added to `AIAssistant`:
- `_DOMAIN_DESCRIPTIONS` — 18 domain description strings, each blending summary + tool names + method terms + common phrasings. Marked with docstring: *"reference material only — BGE makes its own decision"*
- `_domain_centroids` — class-level dict, populated once per process
- `_get_domain_centroids()` — encodes `_DOMAIN_DESCRIPTIONS` via shared `_get_bge_model()` from `rag_index.py` (no second model load)
- `_infer_domain_from_intent()` — embeds query, cosines against centroids, returns best domain if score ≥ 0.40 and margin ≥ 0.03

Threshold rationale:
- 0.40 minimum score: below this the query is too vague to classify confidently
- 0.03 margin: prevents returning a domain when two domains are nearly tied (genuinely ambiguous query)
- Unrelated queries (e.g. "weather and climate") score ~0.51 on best domain with Δ=0.02 → correctly return `''`

Domains covered (18):
`cryo_em`, `cryo_et`, `genomics`, `transcriptomics`, `epigenomics`, `single_cell`, `proteomics`, `metabolomics`, `drug_discovery`, `structural_biology`, `metagenomics`, `microbiology`, `systems_biology`, `synthetic_biology`, `immunology`, `cell_biology`, `cancer_biology`, `bioengineering`

### Shared BGE singleton

Both `retriever.py` and `ai_assistant.py` import `_get_bge_model` from `rag_index.py`. The model loads once per gunicorn worker and is reused for:
1. Cryo-EM chunk embedding (RAG index build)
2. Cryo-EM RAG query embedding (semantic search)
3. Sample class centroid build
4. Sample class query embedding
5. Domain centroid build
6. Domain query embedding

---

## Test Results

### Sample class detection — 7/7

| Query | Expected | Got | Method |
|---|---|---|---|
| "my protein is in a lipid bilayer scaffold with saposin A" | saposin_nanodisc | ✓ | BGE |
| "studying opioid-receptor complex in a membrane mimetic environment" | msp_nanodisc_gpcr | ✓ | BGE |
| "BAX pore formation assay in artificial membranes" | liposome_pore_forming | ✓ | BGE |
| "RNA spliceosome structural studies with multiple conformational states" | rna_protein_endogenous | ✓ | BGE |
| "virus-like particle symmetry determination from cryo-EM" | symmetric_assembly | ✓ | BGE |
| "saposin nanodisc reconstitution" | saposin_nanodisc | ✓ | keyword |
| "cryo-ET tilt series of a lamella" | cryo_et | ✓ | keyword |

### Domain inference — 13/13

| Query | Expected | Score | Δ |
|---|---|---|---|
| "single cell RNA-seq analysis with Seurat clustering" | single_cell | 0.812 | 0.134 |
| "cryo-EM micrographs with RELION structure determination" | cryo_em | 0.833 | 0.067 |
| "GATK HaplotypeCaller germline variant calling WGS" | genomics | 0.822 | 0.140 |
| "differential expression from bulk RNA-seq using DESeq2" | transcriptomics | 0.835 | 0.112 |
| "protein reconstituted in lipid bilayer for cryo-EM SPA" | cryo_em | 0.696 | 0.035 |
| "LC-MS/MS label-free proteomics FDR filtering" | proteomics | 0.803 | 0.121 |
| "ADMET prediction for small molecule drug candidate" | drug_discovery | 0.793 | 0.137 |
| "subtomogram averaging cryo-ET tilt series lamella" | cryo_et | 0.832 | 0.126 |
| "ChIP-seq H3K27ac peak calling MACS2" | epigenomics | 0.818 | 0.171 |
| "microbiome 16S amplicon sequencing MetaPhlAn" | metagenomics | 0.824 | 0.126 |
| "T cell exhaustion antibody staining flow cytometry" | immunology | 0.747 | 0.081 |
| "cancer somatic mutation calling tumor mutational burden" | cancer_biology | 0.794 | 0.125 |
| "weather and climate" (unrelated) | None | 0.537 | 0.022 → rejected |

---

## RAG Index Scope — Current Limitation

`rag_index.py` is currently cryo-EM only:
- Reads from `docs/cryo_em_skills/` (9 documents, 150 chunks)
- Stores in `cryo_em_chunks` / `cryo_em_chunks_vec`
- Called only when frontend detects cryo-EM domain → `POST /api/cryo_em/context`

This is not an architectural constraint — it is a content gap. The indexer is generic; it takes `--docs` and `--db` as arguments. Every other domain runs without RAG because no skill documents exist yet for them. As domain skill document sets are authored (equivalent to `docs/cryo_em_skills/` for genomics, proteomics, etc.), the same pipeline applies:

```bash
python lib/galaxy/ai/cryo_em_knowledge/rag_index.py build \
    --docs docs/{domain}_skills/ \
    --db   galaxy_ai_tools.db
```

The right generalization is a `domain_rag_index.py` that takes `--domain` and writes to `{domain}_chunks` — making the cryo-EM implementation the reference, not the exception.

---

## Files Modified

| File | Change |
|---|---|
| `backend/lib/galaxy/ai/cryo_em_knowledge/retriever.py` | BGE singleton + class centroids + hybrid `detect_sample_class()` |
| `backend/lib/galaxy/ai/ai_assistant.py` | `_DOMAIN_DESCRIPTIONS` (18 domains) + `_get_domain_centroids()` + BGE `_infer_domain_from_intent()` |
