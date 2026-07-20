# Autoimmune Single-Cell Corpus — Automated Collection Plan (Phase A)

**Date:** 2026-07-19 · **Feeds:** Phase A of `20260719_AUTOIMMUNE_MODEL_TRAINING_STRATEGY_AND_DGX_EXECUTION.md`
**Code:** `research/autoimmune_corpus/`

## Can it be collected automatically? — Honest breakdown

| Layer | Automatable? | How |
|---|---|---|
| **Expression matrices + standardized metadata** (disease, cell_type, tissue, assay, donor) | **✅ Fully** | CELLxGENE Census API (`cellxgene_census`) — harmonized `h5ad`, ontology-labeled |
| **Dataset discovery** (which GEO/CELLxGENE series exist) | **✅ Fully** | NCBI E-utilities (GEO `gds` db) + Census `get_anndata`/dataset catalog |
| **Raw GEO series download** (non-Census) | **◑ Semi** | GEO E-utils → supplementary files; per-series format handling |
| **Per-patient clinical activity labels** (SLEDAI, anti-dsDNA, complement, flare, treatment) | **◑ Semi** | LLM extract-then-verify from linked paper text / supp tables; **human-review pass required** |
| **Controlled-access cohorts** (e.g., Perez GSE174188 / dbGaP) | **✗ Manual** | Requires a data-access application — cannot be automated |

**Verdict:** ~80% (expression + ontology metadata + discovery) is fully automatic; the clinical-label ~20% is semi-automatic (auto-extract + verify) with a small manual tail for dbGaP-locked cohorts. The *curation quality of the clinical labels* is the differentiator — so we automate collection and spend human effort only on label verification.

## Architecture — three layers

```
Layer 1  DISCOVERY   (runs anywhere; stdlib + requests; NO heavy deps)
  NCBI E-utils gds search per disease -> GSE accessions, titles, n_samples, PMIDs
  -> results/discovery_manifest.{json,csv}   [STARTED 2026-07-19]

Layer 2  ACQUISITION (runs on DGX Spark; needs cellxgene_census, scanpy, GEOparse)
  A. CELLxGENE Census: disease-filtered immune cells -> per-disease h5ad shards
  B. GEO: download supplementary matrices for series not in Census
  -> data/raw/<disease>/*.h5ad

Layer 3  HARMONIZE + LABEL (Spark)
  - unify to cell x gene + per-cell metadata + per-patient clinical vector
  - patient-level train/val/test split (no leakage)
  - LLM extract-then-verify clinical labels from linked papers/supp -> review queue
  -> data/curated/autoimmune_sc_corpus.{h5ad, clinical_labels.csv, splits.json}
```

## Sources & cores (see `manifest.yaml`)
- **SLE:** Nehar-Belaid 2020 (GSE135779, eval), Banchereau 2016 (GSE65391), CELLxGENE Census `systemic lupus erythematosus`.
- **RA:** CELLxGENE Census `rheumatoid arthritis`; AMP RA/SLE synovium.
- **IBD:** IBDverse (1.1M Crohn's cells, *Nat Genet* 2026); GSE134809.
- **MS (optional breadth):** Census `multiple sclerosis`.

## Target schema (Layer 3 output)
- `X`: cell × gene counts (sparse), gene IDs harmonized to Ensembl.
- `obs`: `donor_id, disease, disease_activity{low/high/healthy}, cell_type, tissue, assay, dataset, split`.
- `clinical`: per-`donor_id` vector — `SLEDAI, anti_dsDNA, C3, C4, treatment, flare, source, verified{bool}`.

## What runs where / deps
- **Here (now):** Layer 1 discovery — `python3.9` + `requests` (present). Real manifest produced today.
- **DGX Spark:** Layers 2–3 — `pip install cellxgene-census scanpy anndata GEOparse` (add to the Spark env). Downloads are GB-scale → do them on the Spark, not the laptop.

## Run steps
1. `python3 research/autoimmune_corpus/collect_discovery.py` → discovery manifest (no installs). **[run now]**
2. On Spark: `python3 research/autoimmune_corpus/collect_expression.py --manifest results/discovery_manifest.json` (Census + GEO).
3. On Spark: `python3 research/autoimmune_corpus/harmonize.py` → curated corpus + splits + label review queue.
4. Verify the clinical-label review queue (human pass) → `verified=true`.
5. Hand curated corpus to Phase B (baseline gate) then Phase C (A+B adaptation).

## Status
- **Layer 1 discovery: STARTED 2026-07-19** (this session).
- Layers 2–3: coded as runnable scripts; execute on the Spark after dep install.
