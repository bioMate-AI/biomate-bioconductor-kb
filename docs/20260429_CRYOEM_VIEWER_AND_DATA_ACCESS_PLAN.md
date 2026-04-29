# CryoEM Viewer & Data Access — Implementation Plan
**Date:** 2026-04-29  
**Status:** In progress  
**Scope:** Make every CryoEM pipeline step output viewable through BioMate UX

---

## Background

The CryoEM Standard SPA pipeline (23 steps) produces outputs at every step. All outputs
are stored in S3 (`biomate-nextflow-work`) and listed in `task_files` per phase card.
The full viewer stack exists:

- **JSON viewer** — renders formatted JSON for all `.json` report files ✓
- **CSV/table viewer** — renders `.csv` manifests ✓
- **DensityMapViewer** — 3-axis slice viewer for `.mrc` 3D volumes ✓ (built)
- **MontageViewer** — 2D class average grid for `.mrc` image stacks ✓ (just built)
- **Binary download** — for `.cs` (CryoSPARC dataset) files ✓

The chain: `task_files` (Galaxy API) → phase card file list → click → `StepOutputPreview`
→ viewer routed by extension → `step-file` endpoint → S3 proxy → browser.

---

## Step-by-Step Viewer Map

| Step | Key output files | Viewer | Status |
|------|-----------------|--------|--------|
| 00 batch_split | `batch_manifest.csv` | Table | ✓ works |
| 00 cs_init | `cs_init.json` | JSON | ✓ works |
| 02 motion_correction | `motion_report_batch_*.json` | JSON + **Motion chart** | JSON ✓ · Chart ✗ |
| 03 ctf_estimation | `ctf_report_batch_*.json` | JSON + **CTF histogram** | JSON ✓ · Chart ✗ |
| 03b merge_micrographs | `all_micrographs_ctf.cs` | Binary download | ✓ |
| 04 denoiser | `denoise_report.json` | JSON | ✓ |
| 05 blob_picker | `picking_report_batch_*.json` | JSON | ✓ |
| 06 junk_detector | `junk_report.json` | JSON | ✓ |
| 07 inspect_picks_r1 | `inspect_report.json` | JSON | ✓ |
| 08 extract_r1 | `extract_report_batch_*.json` | JSON | ✓ |
| **09 classify_2d_r1** | `cs_out_J6_020_class_averages.mrc` | **Montage grid** | ✓ just built |
| 10 select_2d_r1 | `selection_report.json` | JSON | ✓ |
| 11 template_picker | `template_pick_report.json` | JSON | ✓ |
| 12 inspect_picks_r2 | `inspect_report.json` | JSON | ✓ |
| 13 extract_r2 | `extract_report.json` | JSON | ✓ |
| **14 classify_2d_r2** | `cs_out_J*_class_averages.mrc` × 4 batches | **Montage grid** | ✓ just built |
| 15 select_2d_r2 | `selection_report.json` | JSON | ✓ |
| 16 ab_initio | `ab_initio_report_k*.json` × 3 | JSON | ✓ |
| 17 homo_refinement | `cs_out_J*_volume_precision.mrc` × 3 | **3D volume slicer** | ✓ DensityMapViewer |
| 18 volume_tools | `volume_tools_report.json` | JSON | ✓ |
| **19 validation_fsc** | `fsc_validation.json` | JSON + **FSC curve chart** | JSON ✓ · Chart ✗ |
| 20 local_ctf_refinement | `ctf_refinement_report.json` | JSON | ✓ |
| **21 nu_refinement** | `volume_nu_refined.mrc` (13.6 MB) | **3D volume slicer** | ✓ DensityMapViewer |
| **23 sharpening** | `volume_sharpened.mrc` (27 MB) | **3D volume slicer** | ✓ DensityMapViewer |

---

## What the Pipeline Already Exports (confirmed from code audit)

### Motion report (`motion_report_batch_*.json`)
The pipeline exports these fields when CryoSPARC provides them:
```json
{
  "num_micrographs": 20,
  "avg_total_motion_A": <float>,
  "min_total_motion_A": <float>,
  "max_total_motion_A": <float>,
  "num_accepted": <int>,
  "motion_field_used": "total_motion_A"
}
```
**What's missing for a chart:** per-micrograph motion values (array), not just the mean/min/max.
The pipeline currently reads `nanmean` but discards the individual values.

### CTF report (`ctf_report_batch_*.json`)
```json
{
  "avg_ctf_fit_to_A":  <float>,
  "avg_defocus_A":     <float>,
  "min_defocus_A":     <float>,
  "max_defocus_A":     <float>,
  "avg_astigmatism_A": <float>
}
```
**What's missing:** per-micrograph values for a defocus histogram / scatter plot.

### FSC validation (`fsc_validation.json`)
```json
{
  "fsc_curve": [
    {"spatial_frequency": 0.05, "resolution_angstroms": 20.0, "fsc": 0.998},
    ...
  ],
  "fsc_0143_resolution": 3.8,
  "cs_job_uid": "J20"
}
```
**Status:** Data IS exported correctly. In the completed run the array was `[]` — that
means CryoSPARC's validation job (J20) ran but produced no output slots that the pipeline
could read. This is a pipeline bug (likely the output slot name changed in the CryoSPARC
version running on EC2). The chart component can be built against the schema above; the
pipeline fix is separate.

---

## Missing Data: Pipeline Fixes Needed

### Fix 1 — Export per-micrograph motion array
**File:** `main.nf` step `PATCH_MOTION_CORRECTION_BATCH`  
**Change:** Before computing `nanmean`, collect the individual values into a list:
```python
motion_values = arr.tolist()            # per-micrograph total motion (Å)
report["per_micrograph_motion_A"] = motion_values[:200]  # cap at 200
```
**Why:** Enables a histogram showing the distribution of motion across micrographs.
Micrographs with > ~30 Å total motion are typically discarded.

### Fix 2 — Export per-micrograph defocus array
**File:** `main.nf` step `PATCH_CTF_ESTIMATION_BATCH`  
**Change:**
```python
report["per_micrograph_defocus_A"] = df1_arr.tolist()[:200]
report["per_micrograph_fit_A"]     = fit_arr.tolist()[:200]
```
**Why:** Defocus histogram shows data quality. CTF fit quality per-micrograph
helps identify bad data before it enters the particle stack.

### Fix 3 — Fix FSC curve export for current CryoSPARC version
**File:** `main.nf` step `VALIDATION_FSC`  
**Issue:** The pipeline tries known slot names (`fsc_info`, `fsc`, `fsc_no_masking`, etc.)
but on the EC2 instance none matched → `fsc_curve = []`.  
**Fix:** Add a broader fallback that iterates ALL output slots and looks for any
2-column array with a `fsc` or `freq` field:
```python
for slot_name, slot_data in job.outputs.items():
    for field in slot_data.data.dtype.names:
        if 'fsc' in field.lower() or 'fourier' in field.lower():
            # use this
```

---

## Frontend: Charts to Build

### 1. FSC Curve chart (`FscCurveChart`)
**File:** `frontend/client/src/components/viewers/fsc-curve-chart.tsx`  
**When:** Rendered by `StepOutputPreview` when file is `fsc_validation.json`  
**Data shape:** `fsc_curve: [{spatial_frequency, resolution_angstroms, fsc}]`  
**Chart type:** `recharts` `<LineChart>` with dual X axis:
- Primary X: spatial frequency (1/Å)
- Secondary X: resolution (Å) — inverses of spatial_frequency
- Y: FSC (0–1)
- Reference line at FSC = 0.143 (gold-standard resolution criterion)
- Reference line at FSC = 0.5
- Annotate the `fsc_0143_resolution` value as a vertical line

### 2. Motion distribution chart (`MotionHistogramChart`)  
**File:** `frontend/client/src/components/viewers/motion-histogram-chart.tsx`  
**When:** Rendered by `StepOutputPreview` when file is `motion_report_batch_*.json`  
**Data shape:** `per_micrograph_motion_A: [float, ...]`  
**Chart type:** `recharts` `<BarChart>` histogram (bin into 10-20 buckets)  
- X: total motion (Å)
- Y: count of micrographs
- Reference line at 30 Å (typical rejection threshold)
- Show mean ± std in legend

### 3. CTF quality chart (`CtfQualityChart`)
**File:** `frontend/client/src/components/viewers/ctf-quality-chart.tsx`  
**When:** Rendered by `StepOutputPreview` when file is `ctf_report_batch_*.json`  
**Data shape:** `per_micrograph_defocus_A`, `per_micrograph_fit_A`  
**Chart type:** `recharts` `<ScatterChart>` — defocus vs CTF fit quality per micrograph
- X: defocus (Å)  
- Y: CTF fit resolution (Å) — lower = better fit
- Color: accepted (blue) / rejected (red) based on fit quality threshold

---

## StepOutputPreview Routing Changes

```typescript
// Detect special JSON reports by filename and route to dedicated chart viewers
function resolveJsonViewer(fileName: string): 'fsc-curve' | 'motion-histogram' | 'ctf-quality' | 'json' {
  if (/fsc_validation/.test(fileName))  return 'fsc-curve';
  if (/motion_report/.test(fileName))   return 'motion-histogram';
  if (/ctf_report/.test(fileName))      return 'ctf-quality';
  return 'json';
}
```

These viewers each:
1. Fetch the JSON via `step-file` endpoint (same S3 proxy)
2. Parse the known fields
3. Render the recharts chart
4. Fall back to the plain JSON viewer if the required array fields are absent (backward compat)

---

## Resume / Intermediate Access

**Both auto-loop ON and OFF expose the same phase card file list.**  
- Auto-loop ON: pipeline continues automatically; phase cards update in real-time; user
  can click any completed step's files at any point during the run
- Auto-loop OFF: pipeline completes each checkpoint, presents outputs, and shows
  a "Resume" button that calls `POST /api/workflows/resume/:id`; user reviews class
  averages or FSC curve and decides when to continue

The resume mechanism uses Nextflow `-resume` which replays from the S3 work directory
cache — completed tasks are skipped, only new downstream tasks run.

---

## Implementation Order

1. **[Done]** MontageViewer for 2D class averages
2. **[Done]** Binary download for `.cs` files
3. **[Done]** S3 credentials fix in step-file endpoint
4. **Next** FscCurveChart component (recharts)
5. **Next** MotionHistogramChart component (recharts)
6. **Next** CtfQualityChart component (recharts)
7. **Next** StepOutputPreview routing for special JSON filenames
8. **Next** Pipeline: export `per_micrograph_motion_A` array
9. **Next** Pipeline: export `per_micrograph_defocus_A` + `per_micrograph_fit_A`
10. **Next** Pipeline: fix FSC curve slot discovery for current CryoSPARC version

---

## Open Questions

- CTF power spectrum images (Thon rings): CryoSPARC generates these per-micrograph but
  does not export them as standalone files via the API. Options: (a) skip — the JSON
  stats are sufficient; (b) export via `cryosparc.download_file()` in the pipeline (adds
  significant storage and processing time)
- Particle picking overlay: requires both the micrograph image and the .cs picks file;
  not feasible in the browser without a server-side renderer
- 3D volume WebGL: DensityMapViewer uses canvas 2D (orthogonal slices). A proper 3D
  isosurface renderer (e.g., NGL Viewer or Mol* integrated as an iframe) would be more
  useful for the final map. This is a larger effort.
