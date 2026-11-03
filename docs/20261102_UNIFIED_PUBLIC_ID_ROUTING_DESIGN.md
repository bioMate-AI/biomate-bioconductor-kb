# Unified public-ID → data-type → workflow routing (design + plan)

**Date:** 2026-11-02
**Why:** The GEO auto-chain I added (execute-gate, GEO → geo_data_connector → differentialabundance)
is too blunt — it ignores the data-type-aware GEO routing that already exists, and the same
data-type problem applies to every other public ID. This doc is the one-source-of-truth solution.

## 1. The issue

- **GEO already has data-type-aware routing, deliberately** (`backend/lib/galaxy/ai/ai_assistant.py`):
  `_detect_geo_platform` (:4075) reads GEO series metadata → `microarray | scrna | bulk_rnaseq | None`.
  Routing (:4180-4205): scRNA → `geo_scrna_pseudobulk`; microarray/bulk → `_return_geo_bulk_connector`
  (fetch + **review**, and it **intentionally does NOT auto-chain to DESeq2** — :4185-4187 — because
  microarray needs limma and the contrast needs a choice); unknown → connector for review.
- **My #2 auto-chain bypasses it** — it hard-codes `geo_data_connector → differentialabundance` (DESeq2)
  for any GEO accession (routes.ts ~:10934). Wrong for scRNA (should be pseudobulk) and microarray
  (should be limma), and it overrides the deliberate "fetch + choose method/contrast" design.
- **Two classifiers disagree** (the dual-classifier bug): the executor maps GEO (GSE) →
  `handler="sequencing"` → **fetchngs/FASTQ** (nextflow_executor.py:612-623), while Node maps GEO →
  **geo_data_connector/count matrix** (routes.ts:9124-9145). This is also the likely cause of the live
  `geo_data_connector` chain-step failure (the executor fetchngs-es the GSE a self-fetching getGEO
  workflow is already handling — the `aeff50cc` class).
- **Every other public ID has the same shape** (see the landscape audit): the right workflow depends on
  the ID's data type, and most downstream workflows can't self-fetch.

## 2. The solution — one resolver

A single **`resolve_id_to_plan(id, intent)`** function (in Python, where `_detect_geo_platform` + the
fast-path already live) that returns a data-type-aware **execution plan**:
```
{ id_type, data_type, ingest_workflow, downstream_workflow (or 'review'),
  chain_connections, residency, warnings }
```
Reused by **all three surfaces** — the chat generation path, the Node execute-gate (my #2 guard calls
it instead of hard-coding), and the chain builder. This fixes GEO data-type-awareness, removes the
dual-classifier conflict (one classifier), and generalizes to every ID with one code path.

## 3. Per-ID-type routing (what the resolver returns)

| ID type | data-type signal | ingest | downstream | notes |
|---|---|---|---|---|
| **GEO** GSE/GSM | `_detect_geo_platform` | scRNA→`geo_scrna_pseudobulk`; bulk/array→`geo_data_connector` | scRNA→pseudobulk-DE; **bulk→differentialabundance (DESeq2)**; **microarray→limma**; unknown→**review** | never auto-DESeq2 on array; single-cell clustering intent ≠ pseudobulk |
| **SRA/ENA** SRR/SRP/PRJNA/E-* | library strategy (RNA-Seq/WGS/ChIP/ATAC) from ENA metadata | `fetchngs` (FASTQ) | RNA-Seq→rnaseq; WGS/WES→sarek; ChIP→chipseq; ATAC→atacseq; 10x→scrnaseq | sarek self-fetches SRA natively (skip fetchngs); make the others explicit chains |
| **PDB/EMDB** | n/a | RCSB/EMDB fetch | docking / MD / structure-viz | self-fetching docking (vina/alphafold) already OK; **chain for workflows that take a receptor path** (Glide/MOE) — Batch-broken today |
| **UniProt / Ensembl / RefSeq** | seq vs structure intent | UniProtKB/Ensembl/NCBI fetch (FASTA) | structure-predict (ESMfold/AlphaFold) → dock; annotation | cross-workflow chain missing |
| **ChEMBL / PubChem** | n/a | ChEMBL/PubChem fetch (SDF) | ADMET / docking ligand-prep | cross-workflow chain missing |
| **PXD / MassIVE** | n/a | **NO fetcher exists** | proteomics (diaproteomics/quantms) | build a PRIDE/MassIVE ingest first, then chain |
| dbSNP / ClinVar | n/a | flag only (no file) | annotation | by design |

## 4. Implementation plan (incremental, each with its own real-run test)

0. **Unblock: reconcile the dual GEO classifier.** Make the executor NOT fetchngs a GSE that a
   self-fetching GEO ingest owns (fix/verify the `_workflow_fetches_*_natively` skip for
   geo_data_connector/geo_scrna_pseudobulk on the chain-launch path). This is what's failing the live
   `geo_data_connector` step — fix + re-run the GSE22055 chain to green first.
1. **GEO data-type-aware chain.** execute-gate guard calls `resolve_id_to_plan` → scRNA→pseudobulk,
   bulk→differentialabundance, microarray→limma, unknown→review. Replaces the hard-coded chain.
2. **SRA → fetchngs → (rnaseq|sarek|chipseq|atacseq)** by library strategy, as explicit chains.
3. **PDB/EMDB → docking** (receptor-path workflows) via a structure-fetch pre-step chain to S3.
4. **UniProt/ChEMBL cross-workflow chains** (seq→structure→dock; chem→ADMET).
5. **PXD/MassIVE**: build the ingest workflow, then chain to proteomics.

**Testing discipline (per step):** unit-prove the plan/chain emission + `pick_artifact_file` mapping;
then ONE real Batch run per ID type (predict the outcome first; the fetcher must be green standalone
before chaining). Real fixture (lifeifei163361@163.com), live dev, no mocks.

## 5. Status now
- #2 GEO auto-chain: wiring verified live, but **blunt (ignores data-type) + blocked by step-0 failure
  (dual-classifier)**. Should be reworked per step 0–1 above, not shipped as-is for non-bulk GEO.
- Landscape evidence + line refs: the 2026-11-02 landscape audit (ID-type table, self-fetching list,
  coverage matrix); `docs/20261102_ACCESSION_LAUNCH_INFO_FLOW_ISSUE_AND_FIX.md`.
