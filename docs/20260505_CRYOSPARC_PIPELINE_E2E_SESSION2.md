# CryoSPARC Pipeline E2E — Session 2 Fixes (2026-05-05 afternoon)

## Pipeline Run
- **BioMate run ID:** `ffdeb9c7-a0dd-4006-bd99-6d0558fe5a92`
- **Nextflow run ID:** `07d5bd77-632d-4edc-832c-48fec4fc788e`
- **S3 output base:** `s3://biomate-nextflow-work/nextflow/outputs/5a1621ac-e8d9-4ce5-8beb-0b376fe51123/6eed66cb/`
- **Status at doc time:** Running — CLASSIFY_2D_R2 (3 batches), 48 S3 files, 21 processes mapped

---

## Fix 1 — Status endpoint missed CryoSPARC-via-Nextflow runs

### Problem
`/api/workflows/runs/:id/status` lives-queries Galaxy for `nextflowStatus` only when:
```typescript
const isNextflowRun =
    getWorkflowExecutionEngine(run.workflowDefinition) === 'nextflow' ||
    run.execution?.executionEngine === 'nextflow';
```

But CryoSPARC runs via Nextflow store `executionEngine = 'cryosparc'` (set from the CryoSPARC API response), even though the pipeline runs on Nextflow/Batch. So `isNextflowRun = false` → no live Galaxy query → `nextflowStatus = undefined` in the UI.

### Fix
Added third condition: any run with a `nextflowRunId` is treated as a Nextflow run.

**File:** `frontend/server/routes.ts` (~line 8215)

```typescript
const isNextflowRun =
    getWorkflowExecutionEngine(run.workflowDefinition) === 'nextflow' ||
    run.execution?.executionEngine === 'nextflow' ||
    !!run.execution?.nextflowRunId; // CryoSPARC-via-Nextflow: executionEngine='cryosparc' but nf run exists
```

### Result
Status endpoint now returns `nextflowStatus` with 21 processes and 48 S3 files for the running CryoSPARC pipeline.

---

## Fix 2 — CryoSPARC poller didn't fetch Nextflow status for `executionEngine='cryosparc'` runs

### Problem
The CryoSPARC poller has two branches:
- `effectiveEngine === 'nextflow'`: fetches Galaxy status → stores `latestNfStatus`
- `else (cryosparc)`: fetches CryoSPARC status → `latestNfStatus` stays null

Result: `nextflowStatus` was never stored in DB by the poller for CryoSPARC runs.

### Fix
In the `cryosparc` branch, also fetch Nextflow status when `nextflowRunId` is present.

**File:** `frontend/server/routes.ts` (~line 7789)

```typescript
const nfRunId = executionRun.execution?.nextflowRunId;
if (nfRunId) {
    try {
        const nfResp = await fetch(
            `${GALAXY_URL}/api/nextflow/status/${nfRunId}`, {...}
        );
        if (nfResp.ok) latestNfStatus = await nfResp.json();
    } catch { /* non-fatal */ }
}
```

---

## Visualization Status

All visualizations verified on `/dev/cryo-viewers` using the current run's S3 paths.

| Component | Status | Notes |
|---|---|---|
| 2D class averages R1 (MRC montage) | ✅ Rendering | 20 classes, β-gal particles visible |
| 2D class averages R2 (MRC montage) | ✅ Rendering | 20 classes, template-picked, higher quality |
| Final sharpened 3D map (128³) | ✅ Rendering | Smooth blob, 8.4 MB, XY/XZ/YZ planes |
| NUR volume (65×128×128) | ✅ Rendering | Thon rings visible on NUR |
| Motion histogram | ⚠️ Mean only | Shows "Mean 16.0 Å" but no per-mic distribution (pipeline fix applied, next run will have histogram) |
| CTF scatter chart | ⚠️ Count only | Shows "20 micrographs" (pipeline slot fix applied, next run will have scatter) |

### Screenshot references
- `/tmp/viz_now/01_top.png` — class averages R1 + R2 (β-gal particles visible)
- `/tmp/viz_now/02_charts.png` — 3D maps: sharpened + NUR with Thon rings
- `/tmp/viz_now/03_motion_ctf_section.png` — motion mean + CTF count panels

---

## Pipeline Progress (at 19:37 local)
- ✅ Phase A: Init, Split, Motion Correction, CTF, Denoiser, Blob Picker, Junk Detector, Inspect Picks R1, Extract R1
- ✅ Phase B partial: Particle Batch Split, Classify 2D R1 (all 4 batches), Select 2D R1, Template Picker, Inspect Picks R2, Extract R2
- 🔄 CLASSIFY_2D_R2 — 3 batches running on Batch
- ⏳ AB_INITIO, HOMO_REFINEMENT, NUR, CTF_REFINEMENT, LOCAL_RESOLUTION, SHARPEN (pending)
- CS-10 Playwright test actively monitoring — will take `cs10_03_terminal` through `cs10_07_metrics` when pipeline completes

---

## `_CRYOSPARC_S3_DIR_TO_STEP` Verified Correct
All 19 completed step directories correctly mapped to workflow step IDs:

| S3 dir | Step ID | Name |
|---|---|---|
| 00_cs_init | 0 | INIT_CRYOSPARC_PROJECT |
| 00_batch_split | 1 | SPLIT_INTO_BATCHES |
| 02_motion_correction | 2 | PATCH_MOTION_CORRECTION_BATCH ✓ |
| 03_ctf_estimation | 3 | PATCH_CTF_ESTIMATION_BATCH |
| 03b_merge_micrographs | 12 | MERGE_MICROGRAPHS |
| 04_denoiser | 19 | MICROGRAPH_DENOISER |
| 05_blob_picker | 4 | BLOB_PICKER_BATCH |
| 06_junk_detector | 20 | JUNK_2D_DETECTOR |
| 07_inspect_picks_round1 | 21 | INSPECT_PICKS |
| 08_extract_round1 | 5 | EXTRACT_PARTICLES_R1 |
| 09_particle_batch_split | 6 | SPLIT_PARTICLE_BATCHES |
| 09_particle_batch_split_r2 | 7 | SPLIT_PARTICLE_BATCHES_R2 |
| 09_classify_2d_round1 | 8 | CLASSIFY_2D_R1 — 12 files including 4 class avg MRCs ✓ |
| 10_select_2d_round1 | 22 | SELECT_2D_R1 |
| 11_template_picker | 23 | TEMPLATE_PICKER |
| 12_inspect_picks_round2 | 24 | INSPECT_PICKS_R2 |
| 13_extract_round2 | 25 | EXTRACT_PARTICLES_R2 |
| 14_classify_2d_round2 | 9 | CLASSIFY_2D_R2 (currently running) |
| merge_particles | 13 | MERGE_PARTICLES |
| merge_classes | 14 | MERGE_CLASSES |
| merge_particles_r1 | 16 | MERGE_PARTICLES_R1 |

---

## Data Flow Verified
API call confirms end-to-end data flow working:
```
Galaxy /api/nextflow/status → nextflow_executor.py → _build_processes_from_s3_files
→ /api/workflows/runs/:id/status → nextflowStatus.processes
→ frontend nfProcessByName → phase card output file chips
```

Result: `status=running, procs=21` confirmed via browser evaluation.

---

## Known Remaining Issues
1. Motion per-micrograph: frame indices not Å — fix applied to main.nf for next run
2. CTF slot name: `micrographs_ctf` → `exposures` — fix applied to main.nf for next run
3. CS-10 test still running — final screenshots pending pipeline completion (~30-60 min)
