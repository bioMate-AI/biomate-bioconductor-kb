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

## 2. The solution — one resolver (data_type × intent × context)

The routing decision is **not data-type-only**. The right ingest + downstream + parameters depend on
**three axes together**:
- **data_type** — microarray / bulk RNA-seq / scRNA / (per ID: SRA library strategy, structure, etc.)
- **intent** — what the user is trying to DO: differential expression vs clustering/trajectory/cell-typing
  vs enrichment/GSEA vs variant calling vs docking… The SAME data routes differently by intent (scRNA + DE
  → pseudobulk→DE; scRNA + clustering → Scanpy/Seurat, NOT pseudobulk — pseudobulk destroys per-cell
  resolution; bulk + DE → DESeq2; microarray + DE → limma; bulk + GSEA → enrichment pipeline).
- **context** — the project's prior data, the conversation, the stated comparison. Context fills the
  parameters/contrast (e.g. "tumor vs normal"), not just the workflow choice.

A single **`resolve_id_to_plan(id, intent, context)`** returns the full plan:
```
{ id_type, data_type, intent, ingest_workflow, downstream_workflow (or 'review'),
  method (e.g. limma|deseq2|edger), contrast/params from context, chain_connections, residency, warnings }
```
**Crucially, this logic ALREADY EXISTS in the chat path** — `generate_workflow_unified` + the GeoFastPath
already combine `_detect_geo_platform` (data_type) with the user's intent (DE vs single-cell clustering,
guarded at ai_assistant.py:4204) and context (method + contrast extraction; the dev log
`Run DEG on the gse22055 microarray with limma, tumor vs normal` shows all three). So the resolver is
**not new code to invent — it's the existing intent/context/data-type routing, lifted into one function
and reused** by all three surfaces (chat, execute-gate, chain). The execute-gate must DELEGATE to it, not
reimplement a shallow data-type map. This fixes GEO correctness, removes the dual-classifier conflict,
and generalizes to every ID with one code path — while respecting intent and context, not just the type.

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
1. **GEO intent-and-context-aware chain.** The execute-gate guard **delegates to the existing
   intent/context/data-type routing** (`resolve_id_to_plan` = the lifted GeoFastPath +
   `generate_workflow_unified` logic) rather than a shallow data-type map. It combines data_type
   (micro/bulk/scRNA) × **intent** (DE vs clustering/trajectory vs GSEA) × **context** (method +
   contrast, e.g. limma + tumor-vs-normal): scRNA+DE→pseudobulk→DE; scRNA+clustering→Scanpy/Seurat
   (NOT pseudobulk); bulk+DE→DESeq2; microarray+DE→**limma**; unknown→review. Replaces the
   hard-coded `geo_data_connector → differentialabundance` chain.
2. **SRA → fetchngs → (rnaseq|sarek|chipseq|atacseq)** by library strategy, as explicit chains.
3. **PDB/EMDB → docking** (receptor-path workflows) via a structure-fetch pre-step chain to S3.
4. **UniProt/ChEMBL cross-workflow chains** (seq→structure→dock; chem→ADMET).
5. **PXD/MassIVE**: build the ingest workflow, then chain to proteomics.

**Testing discipline (per step):** unit-prove the plan/chain emission + `pick_artifact_file` mapping;
then ONE real Batch run per ID type (predict the outcome first; the fetcher must be green standalone
before chaining). Real fixture (lifeifei163361@163.com), live dev, no mocks.

## 5. Status

- **Step 0 (dual-classifier) — DONE + verified live.** `_workflow_fetches_geo_natively` skip
  (executor commit `a94dffaec`); GSE22055 chain re-run shows `geo_data_connector` SUCCEEDED
  (count_matrix + sample_metadata).
- **Step 1 (GEO intent-and-context-aware chain) — IMPLEMENTED 2026-11-03.** The execute-gate no longer
  hard-codes `geo_data_connector → differentialabundance(DESeq2)`. It now:
  1. **Delegates** data-modality detection to the backend — new `GET /api/ai_assistant/geo_platform`
     (`webapps/.../ai_assistant.py`) reusing the module-level `detect_geo_platform()` lifted from
     `AIAssistant._detect_geo_platform` (ONE source of truth with the chat path,
     `lib/galaxy/ai/ai_assistant.py`).
  2. **Builds the plan by modality** (`frontend/server/routes.ts` execute-gate):
     - `microarray` → geo_data_connector → `differentialabundance(study_type=affy, normalisation_method=limma)`
       (differentialabundance supports affy/limma natively — `nextflow_schema.json` enums; avoids the
       DESeq2 integer-coercion that zeroed GSE22055).
     - `bulk_rnaseq` → geo_data_connector → `differentialabundance(rnaseq, deseq2)`.
     - `scrna` → **geo_scrna_pseudobulk** (not geo_data_connector) → `differentialabundance(rnaseq, deseq2)`;
       connections use that workflow's emit names (`matrix|metadata|contrasts`, vs the connector's
       `count_matrix|sample_metadata`).
     - `unknown` → bulk default (deseq2) + a warning surfaced in the response.
  3. **Intent/context:** intent (DE) is implied by the DE workflow the user is executing; context —
     user-supplied `study_type`/`normalisation_method` WIN over the modality defaults.
- **Steps 2–5 (other public IDs) — not started.** SRA→fetchngs→(rnaseq|sarek|chipseq|atacseq);
  PDB/EMDB→docking; UniProt/ChEMBL cross-workflow; PXD/MassIVE needs an ingest built first.
- Landscape evidence + line refs: the 2026-11-02 landscape audit (ID-type table, self-fetching list,
  coverage matrix); `docs/20261102_ACCESSION_LAUNCH_INFO_FLOW_ISSUE_AND_FIX.md`;
  config-bug audit `docs/20261102_WORKFLOW_CONFIG_ERROR_AUDIT.md`.
