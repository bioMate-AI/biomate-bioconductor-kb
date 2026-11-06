# Single-cell in-app visualization + interactive-tool honesty gate

**Date:** 2026-09-19

## Context

A review of how Jupyter/RStudio/CellxGene are used in BioMate found:

1. **Interactive tools don't launch on dev.** `GET /api/interactive/sessions` responds 200,
   but every launch (RStudio, Jupyter, both endpoints) returns **400** — the tools aren't
   registered in the dev Galaxy toolbox. The "Open in RStudio/Jupyter" buttons were dead.
2. **The data hand-off was never wired** — Jupyter/RStudio "ignore inputs", and nextflow outputs
   live in S3 (not Galaxy HDAs), so even CellxGene's dataset injection wouldn't resolve.
3. **Most output visualization already lives in in-app panels** (`StepOutputPreview`): image, pdf,
   table, sequence, VCF, annotation, structure (3D + pLDDT/PAE), density maps, cryo charts, etc.
   The only types that *punted* to an external tool were **single-cell (.h5ad/.loom)** and
   **R objects (.rds)**.

Decision (per product steer "don't over-complicate; viz should be in-app"): **don't** build the
heavy interactive-tool data-mount bridge. Instead (1) make the dead buttons honest, and (2) close
the single-cell in-app gap with a light sidecar-driven panel.

## Shipped

### 1. Interactive-tool honesty gate
- `GET /api/interactive/available` + `galaxyAPIProxy.getInteractiveToolAvailability()` (probes the
  Galaxy toolbox, cached 5 min, fails closed).
- `useInteractiveToolsAvailable()` hook (module-cached).
- `step-output-preview` (RObject/single-cell) and the shared `InteractiveLauncher` hide/disable the
  launch buttons when a tool isn't provisioned, replacing them with an honest "not enabled here —
  download to analyze locally" note. No more dead 400 clicks.

### 2. In-app single-cell panel
- **Basic viz already existed** — the scRNA end-to-end workflow emits `umap_celltypes.png` /
  `umap_clusters.png`, which render inline in the image viewer. Nothing to add there.
- **New interactive-ish panel** `SingleCellSummaryPanel` renders an in-app UMAP scatter + cluster
  composition + top markers from a small JSON sidecar, with a graceful fallback to the (gated)
  interactive tools / download when the sidecar is absent. No browser h5ad parsing; no external tool.

## Sidecar contract

The scRNA workflow emits `<h5ad path>.summary.json` next to the annotated `.h5ad`
(mirroring the `<rds>.json` convention the R-object viewer already uses). Shape:

```json
{
  "n_cells": 12345,
  "n_genes": 20000,
  "clusters": [ { "label": "CD4 T", "n": 3200 }, { "label": "B cell", "n": 1800 } ],
  "umap":     { "points": [ [x, y, "CD4 T"], [x, y, "B cell"] ] },   // subsampled ≤ 2000
  "markers":  [ { "cluster": "CD4 T", "genes": ["IL7R", "CCR7", ...] } ]
}
```

Rules: all fields optional; the panel renders only the parts present and treats an empty summary as
absent (no fabricated plot). `umap.points` is pre-subsampled by the pipeline (≤ ~2000) so the client
just scales to the viewbox.

## Pipeline emission (verify on next run)

`subworkflows/single_cell/scrnaseq_standard_endtoend/main.nf` gained **STAGE 6.5** — a **fail-soft**
Python step (wrapped in `try/except` + `|| echo`, output declared `optional: true`) that reads the
`annotated.h5ad` it already produced (UMAP in `obsm['X_umap']`, a celltype/leiden `obs` column) plus
the existing `marker_genes_per_cluster.csv`, and writes `annotated.h5ad.summary.json`. Because the
step is fail-soft and the output optional, it **cannot break an existing run** — worst case the
sidecar is absent and the UI falls back to the PNG plots / download.

**Not yet verified on a live run** (needs an scRNA Batch run to confirm the obs-key detection and
marker CSV schema match this container's scripts). Frontend is fully unit-tested and safe regardless.

## Not done (parked, by design)
- Interactive-tool container + S3 data-mount bridge — parked; the in-app panels are the viz path.
- Emitting the sidecar from other h5ad-producing workflows — extend the same STAGE 6.5 pattern if/when needed.
