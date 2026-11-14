# In-product IGV.js BAM/VCF preview slots (Wave 2 only)

**Date:** 2026-11-14  
**Scope:** Genomics viewers in existing AfterRun / step-output / Files preview slots.  
**Explicitly out of scope:** Wave 0 residuals, admin cost, converters, landings, purge, notifications, `.ga` honesty — wait for permission. **Do not** flip `OPEN_IN_AVAILABLE` or enable Interactive Tools.

## What shipped

- Dependency: `igv` (lazy `import()` only)
- [`inline-igv-viewer.tsx`](../frontend/client/src/components/viewers/inline-igv-viewer.tsx) — BAM+BAI / VCF.gz+TBI|CSI; missing index → honest message + download
- Registry: `resolveViewer` / `resolveViewerFromName` → `igv` for `.bam` and `.vcf.gz` (plain `.vcf` stays table)
- [`step-output-preview.tsx`](../frontend/client/src/components/step-output-preview.tsx) — `IgvPreview` path (SELF_FETCHING; no full-file text fetch)
- [`dataset-file-preview.tsx`](../frontend/client/src/components/datasets/dataset-file-preview.tsx) — mode `igv`; alignment content renderer = `viewer`
- [`routes.ts`](../frontend/server/routes.ts) `step-file` — `Accept-Ranges` + S3/local **206** Range support for IGV byte fetches
- `OPEN_IN_AVAILABLE` remains **`false`**

## Accept

- Unit: `genomics-index.test.ts`, view-model BAM → `viewer`
- Live: open a run output `.bam` with sibling `.bai` → IGV host; DevTools shows Range/206 on BAM
