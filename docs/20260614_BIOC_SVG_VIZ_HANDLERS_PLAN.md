# Bioconductor SVG Viz Handlers — Plan (closed as redundant)

Date: 2026-06-14
Branch: `bioc/v2-qc-audit-panel`
Status: **CLOSED — not needed in dev.** Audit (2026-06-14 follow-up) found:

| viz type | Dev rendering today | Need a custom component? |
|---|---|---|
| volcano / dmp_volcano / pb_volcano | real PNG → existing `case 'image'` in `step-output-preview.tsx` | No |
| umap | real PNG | No |
| dmr_tracks / manhattan | real PNG | No |
| gsea_bar / go_bar / bar | structured data via Wave 2-2 `findings_data.json` `figures[]` adapter → existing `FigBars` in `v2/AfterRunReport.tsx` | No |
| qc_violin / probe_retention | same `figures[]` path → existing `FigQc` | No |
| composition-style | same `figures[]` path → existing `FigComposition` | No |
| marker_heatmap / celltype heatmap | real PNG (no dedicated heatmap component in dev — image fallback works) | Future enhancement, not blocking |

The bioc handoff *prototype* needs synthetic SVG previews because the prototype has no real files. The *dev product* doesn't — real bioc runs emit real PNGs that the existing image renderer handles, and structured numbers route through F's `figures[]` adapter into existing `FigBars / FigComposition / FigQc` (shipped task #40).

The dispatch-path gap (the `viz` token from the prototype's `data.js` never reaches dev's `step-output-preview.tsx`) is also moot — dev routes by file extension, not by viz token.

If future tutorial recordings need fresh synthetic previews, the work belongs in the prototype `Modals.jsx`, not in dev.

---

## Original plan (kept for reference)

## Problem

The bioc handoff prototype (`reference/claude_design/bioconductor-handoff/src/Modals.jsx`) renders inline SVG previews driven by a `viz:` token attached to each output in `data.js` (e.g. `viz:'volcano'`, `viz:'umap'`, `viz:'dmp_volcano'`). An `OutputViz` picker maps the token → an SVG component (`VizMotion`, `VizClass2D`, `VizFsc`, …).

The 19 bioc-specific viz tokens in `data.js` BIOC_KB / BIOC_SC / BIOC_METHYL are:

- volcano-family (scatter): `volcano`, `dmp_volcano`, `pb_volcano`, `ma`
- heatmap-family (grid): `marker_heatmap`, `celltype`, `clusters`
- bar-family: `gsea_bar`, `go_bar`, `beta_density`, `probe_retention`, `size_factors`
- track-family (chrom stripe): `dmr_tracks`, `manhattan`
- embedding (2D point cloud): `umap`
- composite QC: `qc_violin`, `mean_var`, `sce_overview`, `mset_overview`

## Why I'm not wiring this yet

The v2 production component `frontend/client/src/components/step-output-preview.tsx` is **extension-driven**, not viz-token-driven:

```ts
function resolveViewer(ext: string): ViewerKind { ... }   // ext → renderer
```

It dispatches on file extension (png / csv / json / mrc / pdb / …). The only "smart" hook is a narrow JSON-filename match for three cryo reports:

```ts
function resolveCryoChartViewer(fileName: string): … {
  if (n.includes('fsc_validation'))  return 'fsc-curve';
  if (n.includes('motion_report'))   return 'motion-histogram';
  if (n.includes('ctf_report'))      return 'ctf-quality';
}
```

There is no plumbing from the workflow KB's `output.viz` token to the preview component. Real Nextflow runs deliver a file path and extension; the `viz` token only exists in the React prototype's `data.js`.

If I author 6 SVG components now and add them to a dispatcher, **nothing in production will pick them** because:

1. `step-output-preview.tsx` never sees a `viz` token.
2. Bioc workflows don't currently emit filename conventions like `volcano_plot.json` that we could heuristically detect.
3. The only filename-detection path requires real backend files with stable, agreed names.

Per CLAUDE.md "Resolve root causes — never workaround," shipping unreachable components would be code rot.

## What needs to happen first (root-cause work)

1. **Decide the viz contract.** Two options:
   - **A. Filename convention** — bioc workflows write canonical JSON sidecars (`volcano.json`, `umap.json`, `marker_heatmap.json`, …). `step-output-preview.tsx` extends `resolveCryoChartViewer` to a generic `resolveVizChartViewer` covering bioc names. Pro: no schema change. Con: bioc workflows must agree on names.
   - **B. KB-driven viz token** — workflow KB `step_metadata` already carries per-output `viz` hints (see MEMORY: "Bioc step_metadata viz/QC enrichment"). Surface `output.viz` through `/api/nextflow/steps`, propagate it to the file-row component, and pass it as a prop to `StepOutputPreview`. Then dispatch on (ext, viz). Pro: one source of truth. Con: needs API + viewer prop wiring.
2. **Inventory real filenames per bioc step** (`backend/lib/galaxy/ai_assistant/step_metadata` or DB `step_metadata` table). Without this, any wiring is speculation.
3. **Then** author the 6 SVG primitive components (`VizScatter`, `VizHeatmap`, `VizBars`, `VizTracks`, `VizEmbedding`, `VizComposite`) using the seeded PRNG pattern from `Modals.jsx:89`, with captions like "Synthetic preview — open in RStudio for live values."

## Recommended next step

Pick option B (KB-driven). It matches the work already done in the v2-qc-audit-panel branch which pulls step_metadata through the same channel for QC. Concretely:

1. Extend `/api/nextflow/steps` response with each output's `viz` token from DB step_metadata.
2. Add `viz?: string` to the `file` prop of `StepOutputPreview`.
3. Add a `VizPreview` early-return in `StepOutputPreview` before the extension dispatcher.
4. Then land the 6 SVG components in `frontend/client/src/components/viewers/viz-svg/*.tsx`.

## Files audited

- `/home/yzhang/biomate/frontend/client/src/components/step-output-preview.tsx`
- `/home/yzhang/biomate/reference/claude_design/bioconductor-handoff/src/Modals.jsx`
- `/home/yzhang/biomate/reference/claude_design/bioconductor-handoff/src/data.js`

No source files were modified.
