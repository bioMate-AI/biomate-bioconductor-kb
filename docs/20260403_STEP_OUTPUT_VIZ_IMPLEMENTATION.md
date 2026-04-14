# Per-Step Output Visualization & Parameter Adjustment — Implementation

**Date**: 2026-04-03  
**Branch**: integration/next-phase  
**Design plan**: `docs/20260403_STEP_OUTPUT_VIZ_PLAN.md`

---

## Motivation

BioMate workflows showed per-step *status* (pending/running/completed/failed) but not per-step *outputs*. Users could see that a step completed but had to wait for the entire workflow to finish before inspecting any file. Parameter adjustment existed only in error recovery flows.

This is a critical gap for iterative scientific workflows — especially cryo-EM, where every step (motion correction, CTF estimation, particle picking, 2D classification, 3D refinement) requires visual inspection and parameter tuning before the next step is worth running.

---

## What Was Built

### Capability 1 — Per-Step Output Preview

**New component**: `frontend/client/src/components/step-output-preview.tsx`

When a workflow step completes, expanding its file list shows an eye icon next to each visualizable file. Clicking the eye opens an inline preview panel below the step card.

**Viewer modes** (by file extension):

| Extension(s) | Viewer |
|---|---|
| png, jpg, jpeg, gif, svg, pdf | `<img>` with max-height |
| csv, tsv, json, tabular, star | Custom inline table (parsed locally, 200-row limit, tab/comma auto-detect, JSON array support) |
| fasta, fa, fastq, fq | Sequence viewer (header + truncated sequence, up to 20 entries) |
| vcf, bed, gff, gtf, bed | Plain text `<pre>` (8000 char limit) |
| pdb, mmcif, cif | Plain text `<pre>` with note to use ChimeraX for 3D |
| mrc, map, mrcs, rec | Download link (binary — requires desktop viewer) |
| html, htm | Sandboxed `<iframe>` |
| log, txt, sh, py, out, err | Plain text `<pre>` |
| anything else | Download link |

**Fetch strategy**: text-based formats (table, sequence, text) fetched as text; binary formats (image, HTML, density, structure) fetched as blob → object URL. Blob URLs are revoked on component unmount.

**Error handling**: non-OK HTTP responses display the HTTP status + body text in a destructive-coloured alert.

**New backend endpoint**: `GET /api/workflows/runs/:id/step-file?path=<encoded>&name=<filename>`

- Validates the run exists (404 if not)
- Rejects path traversal: both pre- and post-`resolve()` checks for `..`
- Validates the resolved path starts with one of: `work_dir`, `outdir`, or `/tmp/` (guards against arbitrary file reads)
- Infers `Content-Type` from extension (20+ mappings; falls back to `application/octet-stream`)
- Streams file with `createReadStream().pipe(res)`
- Returns 404 if file doesn't exist on disk

---

### Capability 2 — Per-Step Parameter Override & Selective Rerun

**New component**: `frontend/client/src/components/step-adjust-modal.tsx`

Each completed step card shows a gear icon (⚙). Clicking it opens a dialog listing that step's current parameter values as editable fields:
- **Boolean** → `<Switch>`
- **Number** → `<Input type="number">`
- **String** → `<Input type="text">`

Parameters are sourced from `step.parameters`, merged with matching entries from `workflowDefinition.required_params` / `optional_params` (for richer label/description metadata).

**"Rerun from this step"** button:
- Shows `Loader2` spinner while request in-flight
- POSTs `{step_name, param_overrides}` to `/api/workflows/runs/:id/rerun-from-step`
- On success: closes the modal and updates the viewer to track the new run
- On failure: shows error message in a red alert (modal stays open)

**New backend endpoint**: `POST /api/workflows/runs/:id/rerun-from-step`

Request body:
```json
{ "step_name": "MOTION_CORRECTION", "param_overrides": { "patch_x": 7 } }
```

Response:
```json
{ "new_run_id": "abc123", "message": "Rerunning from step MOTION_CORRECTION with 1 overridden parameter(s)", "prev_run_id": "xyz" }
```

Implementation:
- Reads `prevWorkDir` from `run.execution.nextflowStatus.work_dir`
- Builds `-resume -w <prevWorkDir>` flag for Nextflow continuity
- Builds `--key value` override flags for each entry in `param_overrides`
- Forwards to Galaxy backend `/api/nextflow/execute` with merged params + resume args

---

### Capability 3 — Chat-Driven Parameter Suggestion

After rerunning from a step, the assistant receives a structured chat message:  
`"Rerunning workflow from step X. New run ID: Y"`

This message flows through the existing `onAdjustViaChat` prop, enabling the assistant to acknowledge the rerun and guide next steps (e.g., "Your CTF estimation is rerunning with the adjusted resolution range. I'll notify you when it completes.").

---

## Files Changed

### New files

| File | Description |
|---|---|
| `frontend/client/src/components/step-output-preview.tsx` | Inline file preview panel; 8 viewer modes; blob URL lifecycle management |
| `frontend/client/src/components/step-adjust-modal.tsx` | Step parameter editor dialog + rerun trigger |
| `docs/20260403_STEP_OUTPUT_VIZ_PLAN.md` | Design plan document |

### Modified files

| File | Changes |
|---|---|
| `frontend/client/src/components/phase-card.tsx` | Added `outputFiles`, `onPreviewFile`, `onAdjustAndRerun` props; file list uses `displayFiles` (prefers structured outputFiles over legacy taskFiles strings); eye button per visualizable file; gear button for completed steps |
| `frontend/client/src/components/nextflow-workflow-viewer.tsx` | Imports both new components; `ViewerPhase` type gains `outputFiles` field; `previewFile` + `adjustStep` + `rerunRunId` state; maps `nextflowStatus.processes[].task_files` to `outputFiles[]`; passes `outputFiles` and both callbacks into `PhaseCard`; renders `StepOutputPreview` and `StepAdjustModal`; uses `activeRunId = rerunRunId ?? runId` for run-tracking continuity after rerun |
| `frontend/server/routes.ts` | New `GET /api/workflows/runs/:id/step-file` endpoint; new `POST /api/workflows/runs/:id/rerun-from-step` endpoint |

---

## Audit Findings & Fixes

Two critical bugs were identified and fixed during audit:

### Bug 1: Missing `outputFiles` prop pass-through (FIXED)

**Problem**: `PhaseCard` expects `outputFiles` as an explicit prop. `nextflow-workflow-viewer.tsx` was building the `outputFiles` array and storing it inside the `phase` object, but passing `phase={phase}` without also passing `outputFiles={phase.outputFiles}` as a separate prop. Result: file lists would never render.

**Fix** (nextflow-workflow-viewer.tsx, PhaseCard call):
```tsx
// Added:
outputFiles={phase.outputFiles}
```

### Bug 2: Viewer didn't track new runId after rerun (FIXED)

**Problem**: After `onRerunSubmitted(newRunId)`, the modal closed and a chat message was sent, but the viewer continued polling the old runId. The user would see no progress for the new run.

**Fix**: Added `rerunRunId` state initialized to `null`, updated to `newRunId` when a rerun completes, and derived `activeRunId = rerunRunId ?? runId`. All post-rerun endpoint calls (StepOutputPreview, StepAdjustModal, DownloadCommandsPanel) use `activeRunId`.

```typescript
const [rerunRunId, setRerunRunId] = useState<string | null>(null);
const activeRunId = rerunRunId ?? runId;

// In onRerunSubmitted:
setRerunRunId(newRunId);
```

---

## Data Flow

```
Nextflow trace file
  → backend parses work_dir per task
  → GET /api/workflows/runs/:id/status returns processes[]{name, status, task_files[]}
  → nextflow-workflow-viewer.tsx maps task_files → outputFiles[]{name, path, extension}
  → PhaseCard receives outputFiles prop
  → user expands file list, clicks eye icon
  → StepOutputPreview mounts, fetches /api/workflows/runs/:id/step-file?path=...
  → backend validates path, streams file
  → appropriate viewer renders inline

  (separately)
  → user clicks gear icon on completed step
  → StepAdjustModal opens, shows step.parameters as editable fields
  → user edits, clicks "Rerun from this step"
  → POST /api/workflows/runs/:id/rerun-from-step {step_name, param_overrides}
  → backend: builds Nextflow -resume + --param overrides, calls Galaxy backend
  → response: {new_run_id}
  → viewer: setRerunRunId(new_run_id), sends chat message, continues polling new run
```

---

## Cryo-EM Iterative Loop Now Supported

| Step | Output type | Preview mode | Adjust & Rerun |
|---|---|---|---|
| Motion correction | JPEG micrograph thumbnails | Image viewer | patch_x, patch_y, max_shift |
| CTF estimation | PNG power spectrum | Image viewer | min_resolution, max_resolution, defocus_range |
| Particle picking | PNG overlay + CSV coordinates | Image + table | threshold, diameter, topaz model |
| 2D classification | PNG class averages | Image viewer | num_classes, iterations, mask_diameter |
| Ab-initio reconstruction | PNG FSC curve + MRC map | Image + download link | symmetry, num_classes, resolution limit |
| Homogeneous refinement | MRC map + PNG FSC | Image + download link | mask, resolution limit, box_size |
| Local resolution | MRC heat map | Download link | FSC threshold, local_averaging_window |

---

## Known Limitations

1. **MRC/MAP density files**: Preview shows a download link only. Full interactive slice viewer (like the `DensityMapViewer` component) requires a Galaxy history entry and cannot be wired to raw step files without porting the ArrayBuffer renderer. Acceptable for now — the download points the user to ChimeraX/Coot.

2. **PDB/mmCIF structure files**: Preview shows plain text (first 4000 chars). The `StructureViewer` component uses 3Dmol.js but requires `/api/outputs/:id/display` endpoint URLs. Same constraint as density.

3. **S3 step files**: The `step-file` endpoint reads from local disk only. For AWS Batch runs where `task_files` point to S3 paths (`s3://...`), the endpoint will 404. A future enhancement should proxy S3 paths through the existing `aws s3 cp` infrastructure.

4. **`rerunRunId` is not persisted**: If the user reloads the page, the viewer reverts to tracking the original `runId` prop. The parent component would need to persist and pass the new runId for full persistence.

5. **Step parameters**: `step.parameters` is populated from the viewer's `phase.parameters` field, which reflects workflow-level params at definition time, not the actual runtime params used by that specific Nextflow process. This is a Nextflow trace limitation — process-level param resolution requires parsing the `.nextflow.log`.
