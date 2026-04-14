# Per-Step Output Visualization & Parameter Adjustment — Design Plan

**Date**: 2026-04-03  
**Branch**: integration/next-phase  
**Priority**: P0 — critical for cryo-EM iterative loop; benefits all workflows

---

## Problem Statement

BioMate currently shows per-step *status* (pending/running/completed/failed) but not per-step *outputs*. After a step completes, the user sees a filename list at best — no inline preview. Parameter adjustment exists only in error recovery. This is a fundamental gap for iterative workflows like cryo-EM, where every step requires visual inspection and parameter tuning before proceeding.

---

## Three Capabilities to Build

### Capability 1 — Per-Step Output Preview

When a step completes, clicking its output file opens an inline preview using the same 8 viewers already in `chat-output-attachments.tsx` (table, image, density map, structure, sequence, VCF, annotation, interactive HTML).

**Data flow:**
```
Nextflow trace → backend parses work_dir → per-process task_files[] in status JSON
→ PhaseCard shows clickable file list
→ click → StepOutputPreview fetches file via /api/workflows/runs/:id/step-file?path=
→ renders via existing viewers
```

**Files to create/modify:**
- `frontend/client/src/components/step-output-preview.tsx` — NEW, inline preview panel
- `frontend/client/src/components/phase-card.tsx` — add onPreviewFile callback, richer file list UI
- `frontend/server/routes.ts` — NEW endpoint `GET /api/workflows/runs/:id/step-file`
- `frontend/client/src/components/nextflow-workflow-viewer.tsx` — pass outputFiles into PhaseCard, handle preview state

---

### Capability 2 — Per-Step Parameter Override & Selective Rerun

Each completed step gets an "Adjust & Rerun from here" button. Opens a modal with that step's current parameter values. User edits values → clicks "Rerun from step N" → backend resumes the Nextflow run with `-resume` and the overridden params injected via `--param value` flags.

**Data flow:**
```
PhaseCard "Adjust" button click
→ StepAdjustModal opens (shows step params, editable)
→ user edits + submits
→ POST /api/workflows/runs/:id/rerun-from-step {step_name, param_overrides}
→ backend: build nextflow command with -resume -w <prev_work_dir> + param flags
→ new run starts, viewer tracks it
```

**Files to create/modify:**
- `frontend/client/src/components/step-adjust-modal.tsx` — NEW, param editor + rerun trigger
- `frontend/client/src/components/phase-card.tsx` — add onAdjustAndRerun callback + Adjust button
- `frontend/server/routes.ts` — NEW endpoint `POST /api/workflows/runs/:id/rerun-from-step`
- `frontend/client/src/components/nextflow-workflow-viewer.tsx` — wire StepAdjustModal, handle rerun response

---

### Capability 3 — Chat-Driven Parameter Suggestion

After viewing a step output (e.g. 2D classes, CTF power spectrum), the user types in chat: "keep classes 3, 5, 8" or "reduce pixel size to 0.8" or "picking threshold looks too low". The assistant parses this, identifies the relevant step parameters, and pre-fills the StepAdjustModal (or directly calls rerun-from-step).

**Data flow:**
```
User chat message → galaxy-assistant.ts detects param-adjustment intent
→ generates param_overrides JSON
→ frontend routes to StepAdjustModal pre-filled with suggestions
→ user confirms → rerun-from-step
```

**Integration points:**
- `onAdjustViaChat` prop already exists in `nextflow-workflow-viewer.tsx` — extend it to accept structured `{step_name, param_overrides}` payload
- `generateResponse()` in `galaxy-assistant.ts` — add rule to emit structured adjustment intent
- `chat-message.tsx` — detect adjustment intent response and trigger viewer modal

---

## Detailed Component Specs

### `StepOutputPreview` component

```typescript
interface StepOutputPreviewProps {
  runId: string;
  file: { name: string; path: string; extension: string };
  onClose: () => void;
}
```

- Fetches `/api/workflows/runs/:runId/step-file?path=<encoded>&name=<name>` 
- For text/table: feeds into `CsvTableViewer`
- For image (png/jpg/svg/pdf): `<img>` with max-height constraint
- For MRC/MAP: `DensityMapViewer`
- For PDB/mmCIF: `StructureViewer`
- For HTML: sandboxed `<iframe>`
- For FASTA/FASTQ: `SequenceViewer`
- For VCF: `VCFViewer`
- Fallback: download link
- Rendered as a slide-over panel (right side) or expandable section below the PhaseCard

### `StepAdjustModal` component

```typescript
interface StepAdjustModalProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  runId: string;
  step: { id: string; name: string; processName?: string; parameters?: Record<string, any> };
  workflowDefinition?: any;
  onRerunSubmitted: (newRunId: string) => void;
}
```

- Shows step name + current parameter values
- Editable fields (text/number/boolean, same as existing `buildViewerParameters()`)
- "Rerun from this step" button → POST `/api/workflows/runs/:runId/rerun-from-step`
- Response: `{new_run_id: string, message: string}` → viewer switches to tracking new run

### Backend endpoint: `GET /api/workflows/runs/:id/step-file`

Query params: `path` (encoded file path), `name` (filename for Content-Disposition)

Security: validate that the resolved path is within the run's work_dir or outdir. Reject any path with `..` traversal.

Returns: raw file content with inferred Content-Type. For binary files (MRC, PDF), returns as `application/octet-stream`.

### Backend endpoint: `POST /api/workflows/runs/:id/rerun-from-step`

Body:
```json
{
  "step_name": "MOTION_CORRECTION",
  "param_overrides": {
    "patch_x": 7,
    "patch_y": 5
  }
}
```

Response:
```json
{
  "new_run_id": "abc123",
  "message": "Rerunning from MOTION_CORRECTION with 2 overridden parameters"
}
```

Implementation: get previous run's `work_dir` and `nextflow_path`, build overrides as `--patch_x 7 --patch_y 5`, call `execute_nextflow()` with `-resume -w <prev_work_dir>`.

---

## PhaseCard Changes

```typescript
interface PhaseCardProps {
  phase: {
    // existing fields...
    outputFiles?: Array<{ name: string; path: string; extension: string }>; // NEW
  };
  onPreviewFile?: (file: { name: string; path: string; extension: string }) => void; // NEW
  onAdjustAndRerun?: () => void; // NEW
  // existing callbacks...
}
```

New UI in expanded state:
- File rows: `[icon] filename.ext  [Preview ▶]`
- Preview button visible only for visualizable extensions
- Adjust button: `[⚙ Adjust & Rerun]` shown for completed steps with parameters

---

## nextflow-workflow-viewer.tsx Changes

1. Map `nextflowStatus.processes[]` → `updatedPhases` including `outputFiles` (already have `taskFiles`, need to normalize)
2. State: `previewFile: {runId, file} | null` → renders `StepOutputPreview` as overlay
3. State: `adjustStep: ViewerPhase | null` → renders `StepAdjustModal`
4. Pass `onPreviewFile` and `onAdjustAndRerun` into each `PhaseCard`
5. When rerun-from-step completes, call the existing run-start flow with new `runId`

---

## Implementation Order

The three capabilities are mostly independent. They can be implemented in parallel:

| Agent | Scope |
|---|---|
| **A** | `step-output-preview.tsx` (new) + `phase-card.tsx` (preview UI) + `routes.ts` (step-file endpoint) |
| **B** | `step-adjust-modal.tsx` (new) + `phase-card.tsx` (adjust button) + `routes.ts` (rerun-from-step endpoint) |
| **C** | `nextflow-workflow-viewer.tsx` wiring — connect both new components, map outputFiles, handle state |

Note: A and B both touch `phase-card.tsx`. A adds the preview button/callback. B adds the adjust button/callback. These are additive and non-conflicting — both can be done carefully with no overlap.

---

## File Extension → Viewer Mapping

```
png, jpg, jpeg, gif, svg, pdf → image (<img> or iframe)
csv, tsv, json, tabular        → CsvTableViewer
fasta, fa, fastq, fq           → SequenceViewer
vcf, bcf                       → VCFViewer
bed, gff, gtf, gff3            → AnnotationViewer
pdb, mmcif, cif                → StructureViewer
mrc, map, mrcs, rec            → DensityMapViewer
html, htm                      → iframe (sandboxed)
log, txt, sh, py               → plain text <pre>
star (RELION STAR format)      → CsvTableViewer (tab-separated)
```

---

## What This Enables for Cryo-EM

| Cryo-EM Step | Output Visualized | Adjust & Rerun |
|---|---|---|
| Motion correction | Micrograph JPEG thumbnails | patch_x, patch_y, max_shift |
| CTF estimation | CTF power spectrum PNG | min_resolution, max_resolution |
| Particle picking | Overlay PNG + coords CSV | threshold, diameter, model |
| 2D classification | Class average PNGs | num_classes, iterations |
| Ab-initio reconstruction | FSC curve PNG + map MRC | symmetry, num_classes |
| Homogeneous refinement | Map MRC, FSC curve | mask, resolution limit |
| Local resolution | Resolution heat map MRC | FSC threshold |
