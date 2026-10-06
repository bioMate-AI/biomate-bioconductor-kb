# BioMate — Accession → Dataset → Workflow Intelligence (capability list + tutorial spec)

**Date:** 2026-10-05 · Owner: video/tutorial session (biomate-review-14)
Grounded in code at `/Users/kky/biomate-review` (inventory 2026-10-05) + live dev-stack demos captured 2026-10-05. Honesty contract: every claim below is backed by a file/function or a live tool result; known gaps are listed explicitly and must NOT be overstated in buyer-facing material.

---

## The one-sentence story

Give BioMate a database accession (e.g. a GEO `GSE…` or an SRA `SRR…`) instead of a file, and it (1) recognizes the archive and ID type, (2) fetches the data, and (3) — for GEO — reads the study's own metadata to infer the data modality and route your stated goal to the right analysis workflow with the modality parameters pre-filled. **You paste an ID; BioMate turns it into a running, correctly-parameterized pipeline.**

It is a **two-stage** system, and the tutorial teaches it as two stages (conflating them would overstate):

- **Stage 1 — ID → fetch** (deterministic, by archive/ID type).
- **Stage 2 — context → analysis** (modality-aware + intent-aware routing; GEO-centric).

---

## What we can do (capability list — grounded)

### A. Identify the accession / ID type
- `resolve_accession` (MCP tool `backend/lib/mcp/tools_manifest.py`; endpoint `/api/accession/resolve`, `frontend/server/routes.ts:8673`). Pure-regex ID-type detection (no network), recognizes:
  - **GEO** series/dataset/sample: `GSE…`, `GDS…`, `GSM…` → **Geo Data Connector** (#10672), param `accession`.
  - **SRA / ENA / DDBJ / ArrayExpress-style sequencing**: `SRR/SRX/SRS/SRP`, `ERR/ERX/ERP`, `DRR/DRP`, `PRJNA/PRJEB/PRJDB`, `E-…-…` → **nf-core/fetchngs** (#12704), param `input`.
  - Unrecognized → honest HTTP 422 "Unrecognised accession format".
- Returns `prefilled_params`, `ready_to_run`, and a `next_step` — ready to hand straight to `run_workflow`.

### B. Automatically fetch the data (two mechanisms)
1. **Prefilled fetcher workflow** (from `resolve_accession`): GEO → GEOquery connector; sequencing → fetchngs (raw FASTQ + samplesheet).
2. **Run-time auto-fetch chain** inside the executor (`backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py`, `_ACCESSION_REGISTRY`): when a *workflow parameter value* is a public accession, it is resolved and **downloaded before the run**. Broad, and these actually download:
   - **sequencing** (SRR/ERR/DRR, SRP/ERP, PRJNA/PRJEB, GSE/GSM, E-…) → fetchngs prefetch → FASTQ + samplesheet.
   - **structure**: PDB, EMDB → HTTP download.
   - **protein sequence**: UniProt, RefSeq NP, Ensembl ENSP → FASTA.
   - **genomic reference**: RefSeq NC, Ensembl ENSG/ENST.
   - **chemical**: ChEMBL, PubChem CID.

### C. Infer data modality from the study itself (GEO) — the strongest differentiator
- `_detect_geo_platform()` (`backend/lib/galaxy/ai/ai_assistant.py:3856`): a **data-first** lookup — one HTTP GET to GEO's SOFT record, reads the authoritative `!Series_type` (array vs sequencing) plus title/design keywords (`single cell`, `10x`, `chromium`, …) → returns `microarray | bulk_rnaseq | scrna | None`. Cached; never guesses single-cell without explicit scRNA signals.

### D. Route the same accession to different workflows by context
- Fast-path routing in `ai_assistant.py` combines (C) modality with the user's intent keywords, so one `GSE…` diverges:
  - microarray / bulk → `geo_data_connector` retrieval card (DE deferred until counts + contrast are verified).
  - scRNA + pseudobulk intent → `geo_scrna_pseudobulk`.
  - scRNA + clustering/Seurat/UMAP intent → defers so the router picks nf-core/scrnaseq / Seurat (not collapsed to pseudobulk DE).
- Accession → param prefill via `_extract_sra_accession` / `_inject_sra_into_params`.
- General routing/composer: `backend/lib/galaxy/ai/unified_workflow_search.py` (ChainIndex) + `bioc_chain_templates.py`.

### E. Know its own data sources
- Unified data-source registry `backend/lib/galaxy/ai/data_sources.py` (`/api/data_sources`): **~54 live sources** across federation / single-source / MCP / Galaxy surfaces, each tagged `live | planned | key_required`. Doc: `docs/20260728_UNIFIED_DATA_SOURCE_REGISTRY.md`.

---

## Live GEO demonstration (real results, captured 2026-10-05)

**Stage 1 — ID → fetch** (`resolve_accession`):

| Accession | Recognized as | Routes to |
|---|---|---|
| GSE52778 / GSE2034 / GSE132044 | GEO series | Geo Data Connector (#10672) |
| SRR1039508 | SRA run | nf-core/fetchngs (#12704) |
| SRP033351 | SRA project | nf-core/fetchngs (#12704) |

**Stage 2 — context → analysis** (same GEO archive, different stated goal → different pipeline, modality params auto-filled):

| Stated goal | Routed workflow | Auto-filled |
|---|---|---|
| "GSE2034 **microarray** breast cancer, DE good vs poor prognosis" | Affymetrix microarray DE (`peca_microarray_affy` / differentialabundance) | `study_type=affy` |
| "GSE52778 **bulk RNA-seq** DE, dex vs untreated" | chain: nf-core/rnaseq → differentialabundance (DESeq2) → GSEA | `genome=GRCh38` |
| "GSE52778 … **pathway enrichment / GSEA**" | Gene Set Enrichment Analysis (fgsea + clusterProfiler; GO/KEGG/Reactome) | `species=Homo sapiens`, `organism=hsa` |

Headline for the video: **one GEO ID, three intents, three correct pipelines with the right modality parameters filled in automatically.**

---

## Honest gaps (do NOT overstate in the tutorial)

- `resolve_accession` resolves **only** GEO + SRA/ENA sequencing accessions. It does **not** resolve PDB/EMDB/UniProt/ChEMBL/dbGaP at this endpoint (a richer handler exists at `routes.ts:16953` but is **dead/unreachable**). PDB/UniProt/ChEMBL downloading happens only in the run-time executor chain (B.2), not via `resolve_accession`.
- **No recount3 / supplementary-file fallback** to obtain counts for an **RNA-seq GEO series**: the GEO connector uses GEOquery `getGEO()` → series matrix, which has no expression values for sequencing series, so it errors (`stop("No expression matrix found…")`). Counts for an RNA-seq GEO study come from fetchngs→rnaseq (raw FASTQ) or a user-supplied matrix. (The `recount3` module only *transforms a local counts file*; it is not an auto-fetcher.) The m2 DESeq2 demo used a pre-staged airway count matrix, not an auto-GEO-fetch.
- The bulk GEO end-to-end auto-DE chain (`geo_bulk_deg_v2`, `docs/20260911_P0_BULK_GEO_AUTOFETCH_CHAIN_SPEC.md`) is spec / partially-landed (routing works; full Batch run unconfirmed).
- scRNA **clustering** from a bare GEO accession (raw-FASTQ→scrnaseq) is an open gap; only pseudobulk-DE is covered.
- Proteomics (PRIDE PXD / MassIVE) and annotation (dbSNP / ClinVar) accessions are *recognized* but **not auto-downloaded**.
- GEO connector is **GEO-only**; Chinese archives (NGDC/CNCB `HRA…`) unsupported.
- Modality inference is **GEO-only**; SRA/ENA accessions go to fetchngs regardless of intent.

---

## Tutorial plan — `m3-accession-to-workflow` (HTML + EN/ZH narration + video)

Audience: the biologist who has a published accession and wants the analysis, GTM-facing. ~9–10 scenes, same auto-play contract as m2/qPCR.

1. **Title** — "You have an accession number. BioMate turns it into a running pipeline."
2. **The problem** — finding the dataset, guessing its modality, picking the right pipeline, wiring params is slow and error-prone.
3. **The ideas** — accession / archive / modality / workflow routing (four plain words).
4. **Stage 1 — ID → fetch** — paste `GSE…` or `SRR…`; BioMate recognizes the archive and picks the fetcher (GEO connector vs fetchngs). *(live resolve_accession table)*
5. **Stage 2 — it reads the study** — data-first modality inference from GEO's own metadata (array vs RNA-seq vs single-cell).
6. **Same ID, different goal → different pipeline** — the GSE2034/GSE52778 three-way routing table; modality params auto-filled. *(the headline demo)*
7. **It fetches and runs** — connector/fetchngs → the analysis workflow, on cloud compute.
8. **Honest limits** — what it does and does not auto-fetch (RNA-seq GEO counts need FASTQ or a matrix; sequencing archives skip modality inference). Builds trust.
9. **Closing** — paste an ID, state your goal, get a correctly-routed run with a record.

Assets: live `resolve_accession` + routing JSON (captured); a rendered "two-stage routing" table image (same technique as `de-results.png`). No fabricated screenshots.

## Change log
- 2026-10-05 — created: grounded capability list + live GEO demo results + m3 tutorial spec. Corrects the earlier (wrong) "recount3 fallback" note in `docs/20261005_REALBIO_CAPABILITY_DEMO_SERIES.md` gap list.
