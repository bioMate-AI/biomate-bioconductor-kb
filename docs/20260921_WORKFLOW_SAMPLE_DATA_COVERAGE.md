# Workflow Default Sample Data — Coverage, Mechanism & Plan

**Date:** 2026-09-21
**Goal (product owner):** every relevant workflow should ship **default sample data** so a hospital user / BD demo / reviewer can try the platform in one click, without uploading their own instrument files. This also backs the per-instrument E2E tests (they can dispatch with bundled data).

## The standard mechanism (adopt this everywhere)

BioMate already has a proven, reusable pattern — the **Nextflow demo-data fallback**: when no input is provided, the `.nf` process generates (or copies) realistic sample data so the workflow is one-click runnable.

- **Best form (real bundled example):** copy the analysis package's own example dataset — e.g. qPCR now copies `system.file("exData","example.txt", package="NormqPCR")`. Honest, correct, zero-fabrication.
- **Synthetic form:** generate a realistic synthetic table inline (the B8 QC parsers + HTS plate do this) — fine for tabular QC data.

Surfaced to users two ways: (1) the workflow just runs when clicked with no upload; (2) the **cold-start dashboard** `sampleDataset` field (`cold-start-dashboard.tsx:70`) shows a "▶ sample: …" chip for curated public accessions — set **only when the dataset genuinely exists (no fabricated demo data)**.

## Coverage — hospital-instrument workflows

| Workflow | Sample data | Runs end-to-end? | Action |
|---|---|---|---|
| **qPCR ΔΔCq** | ✅ **added** (NormqPCR bundled example) | ✅ yes | Done this session |
| **HTS plate QC / dose-response** | ✅ has (synthetic 96-well) | ✅ yes | Already covered |
| **RIN / Bioanalyzer QC** | ✅ has (synthetic 6 samples) | ✅ (B8, pending DB reg) | Already covered |
| **NanoDrop QC** | ✅ has (synthetic 5 samples) | ✅ (B8, pending DB reg) | Already covered |
| **Cell-counter viability QC** | ✅ has (synthetic 5 samples) | ✅ (B8, pending DB reg) | Already covered |
| **RNA-seq (DESeq2)** | ✅ has (cold-start `GSE52778` airway) | ✅ yes | Already covered |
| **ADMET screening** | ✅ has (inline SMILES) | ✅ yes | Already covered |
| **Flow cytometry immunophenotyping** | ❌ none | 🟡 unverified | **Follow-up:** bundle a real small public `.fcs` fixture + set as default (biomni-tool wrapper — do NOT fabricate a synthetic `.fcs` blind) |
| **WGS germline** | ❌ none | ❌ dispatch blocked (fetchngs S3 bug) | **Blocked first** — sample data is premature until execution works |
| **Proteomics (DIA/DDA)** | ❌ none | ❌ blocked (B3 raw→mzML) | **Blocked first** |
| **Metabolomics (LC-MS)** | ❌ none | ❌ blocked (B3 raw→mzML) | **Blocked first** |
| **Imaging (WSI / confocal)** | ❌ none | ❌ blocked (B1 format readers) | **Blocked first** |

## The honest principle

**Do not attach sample data to a workflow whose pipeline is execution-blocked** — a "Try it" that dead-ends is worse than none. For WGS / proteomics / metabolomics / imaging the blocker is *execution* (B1 imaging readers, B3 MS raw→mzML, the fetchngs S3 work-dir bug), not sample data. Unblock execution first, then the same demo-fallback mechanism applies.

## Recommended next steps

1. **Flow cytometry** — add a real small public `.fcs` fixture (e.g. a flowCore/Cytobank sample) under a known path and default `params.fcs_file_path` to it; verify the biomni tool parses it. (Small, needs a real file — not a blind synthetic.)
2. **UI affordance** — a **"Try with sample data"** chip in the pre-run workflow panel that runs the demo fallback (or stages the cold-start accession) with one click. Makes the capability discoverable.
3. **Standardize** the `.nf` demo-fallback across all *runnable* workflows; keep `galaxy-assistant.ts`'s "workflows with demo data" list in sync.
4. **Unblock then cover** — after B1/B3/fetchngs land, add demo data to WGS/proteomics/metabolomics/imaging using the same pattern.

## What shipped this session
- qPCR ΔΔCq default sample data (commit on the working branch).
- This coverage map + the standard mechanism (this doc).
