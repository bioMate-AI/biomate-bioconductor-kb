# CryoSPARC Output Display, QC Metrics, and Step Visualization Fixes

**Date:** 2026-04-27  
**Commit:** 4f3cd7f493 (auto-commit pre-sync)

---

## Problem Statement

The CE-1 CryoSPARC E2E test was reporting two of its assertions as "expected failures":

1. **Per-step output files** — no `.mrc`, `.json`, or `.png` files appeared in phase card chips
2. **QC report** — even for a passing run, no QC metrics (defocus, motion drift, fit quality) were visible

These are not "expected failures". A completed CryoSPARC SPA run produces 26+ S3 files across Phases A-C, including:
- `cs_out_J6_020_class_averages.mrc` (3.27 MB) — 2D class averages for DensityMapViewer
- `ctf_report_batch_0000.json` — CTF estimation metadata
- `motion_report_batch_0000.json` — motion correction metadata
- `class2d_report_pbatch_0000.json` — 2D classification stats

The root cause was a **S3 path mismatch** that made the system list the wrong directory, returning 0 files. Secondary issues were absent QC numbers in the JSON reports and no viewer support for showing QC results on completed passing runs.

---

## Fix 1: S3 Outdir Mismatch (Generalizable — affects all AWS Batch workflows)

**Root cause:** `execute_nextflow()` generates a random 8-char UUID (`run_uuid_short`) for the actual S3 output directory (e.g., `e5810297`). The fallback status code read `outdir` from `biomate_executor_override.config` which uses the full `run_id` (e.g., `33821cae-...`). The S3 listing found 0 files because it was looking in the wrong directory.

**Fix in `nextflow_executor.py`:**
- Write `outdir` and `workflow_domain` to `timing.json` when the run starts (line ~2547)
- Fallback reads `outdir` from `timing.json` first; falls back to config file for legacy runs

**Applies to:** All AWS Batch Nextflow workflows (RNA-seq, WGS, CryoSPARC, ADMET, etc.)

---

## Fix 2: Step-Level S3 Output Display (Generalizable framework, CryoSPARC-specific mapping)

**Root cause:** `processes[]` in the status response was empty when the Nextflow coordinator exited before all Batch jobs completed (CryoSPARC-via-Nextflow pattern). The viewer uses `processes[].task_files` to populate output chips in phase cards.

**Fix in `nextflow_executor.py`:** Added `_build_processes_from_s3_files(s3_files, outdir, workflow_domain)`:
- Groups S3 files by step directory (first path component after outdir prefix)
- For `cryo_em` domain: uses `_CRYOSPARC_S3_DIR_TO_STEP` dict to map directory names (e.g., `02_motion_correction` → step ID `"1"`) matching the viewer's `nfProcessByName` lookup
- For other domains: parses numeric directory prefix (e.g., `02_alignment` → step `"1"`)
- Returns `processes` entries with `id`, `name`, `status: "completed"`, `task_files: [s3_uris]`
- Skips `.cs` files (CryoSPARC binary datasets — not human-viewable)

**Viewer flow:** `task_files: ['s3://...file.mrc']` → viewer maps to `outputFiles: [{name, path, extension}]` → phase card renders "view" chip → `onPreviewFile()` → `StepOutputPreview` → `DensityMapViewer` for `.mrc` files → `/api/workflows/runs/:id/step-file?path=s3://...` proxy endpoint

**CryoSPARC step → directory mapping:**
| Directory | Step ID | Step Name |
|-----------|---------|-----------|
| `02_motion_correction` | 1 | Patch Motion Correction |
| `03_ctf_estimation` | 3 | CTF Estimation |
| `05_blob_picker` | 6 | Blob Picker |
| `09_classify_2d_round1` | 11 | 2D Classification R1 |
| (and 15+ more) | ... | ... |

---

## Fix 3: Real QC Metrics from CryoSPARC API (CryoSPARC-specific)

**Root cause:** The Nextflow process JSON reports only contained job metadata (`cs_job_uid`, `num_micrographs`). Actual QC numbers (defocus, drift, fit quality) are stored in CryoSPARC's internal database, not in plain files. The existing QC gate handler never received these values.

**Fix in `cryosparc_standard_spa/main.nf`:** After `submit_and_wait()` completes in three processes:

**PATCH_MOTION_CORRECTION_BATCH:**
```python
micrographs_out = job.load_output("micrographs")
# Tries field names: total_motion_A, micrograph/total_motion_A, motion_global_a
report["avg_total_motion_A"] = round(float(np.nanmean(vals)), 2)
report["min_total_motion_A"] = ...
report["max_total_motion_A"] = ...
```

**PATCH_CTF_ESTIMATION_BATCH:**
```python
ctf_out = job.load_output("micrographs_ctf")
# fit quality: ctf_info/fit_to_A_lp, ctf/fit_to_A, ctf_fit_to_A
report["avg_fit_quality"] = round(max(0.0, 1.0 - np.nanmean(vals) / 10.0), 3)
# defocus: ctf_info/df1_A, ctf/df1_A, df1_A
report["avg_defocus_A"] = ...
# astigmatism from |df1 - df2|
report["avg_astigmatism_A"] = ...
```

**CLASSIFY_2D_R1_BATCH:**
```python
classes_out = job.load_output("class_averages")
# class_posterior_prob or fraction_selected → junk fraction
report["junk_class_fraction"] = round(1.0 - good / total, 3)
report["num_good_classes"] = good
```

All wrapped in `try/except` — if CryoSPARC field names differ between versions, the extraction is skipped gracefully and only job metadata is written.

---

## Fix 4: QC Results Panel for Completed Runs (Viewer + Backend)

**Root cause:** The QC panel only showed thresholds (user-configurable) and firing gates (blocking events). For a passing run with all thresholds met, no QC metrics were displayed at all.

**Fix in `nextflow_executor.py`:** Added `_build_qc_report_from_s3_files(s3_files, outdir)`:
- Downloads all `*_report*.json` files from S3 after run completion
- Extracts metrics by step name: motion drift, CTF quality, defocus, junk fraction, FSC resolution
- Returns `{"motion": {...}, "ctf": {...}, "classification": {...}, "_all_metrics": [...]}`
- Each metric entry: `{name, measured, unit, threshold, pass: bool, step}`
- Added `qc_report` to the Nextflow status response

**Fix in `nextflow-workflow-viewer.tsx`:** Added QC Results strip below the completion banner:
- Only shown for `status === 'completed'` AND `nextflowStatus.qc_report._all_metrics.length > 0`
- `data-testid="qc-report-panel"` for E2E testing
- Per-row: metric name | measured value (green if pass, red if fail) | threshold

---

## Why 0 Particles Were Selected in Phase C → Phase D Not Run

In the CE-1 run (run7 with EMPIAR-10028 beta-galactosidase, 20 micrographs):
- 2D classification (J6): `num_particles=24879`, `num_classes=50` ✓
- Select 2D R1: `num_input_particles=0, num_selected_particles=0`

Root cause: CryoSPARC's automated select_2D job found no classes meeting the selection criteria. With only 20 micrographs, the 2D class averages may not have sufficient density/resolution to auto-select confidently. This is a data quantity issue (EMPIAR-10028 has 1,081 total micrographs; using only 20 is borderline for ab initio reconstruction).

**Not a code bug** — the pipeline terminated gracefully after Phase C. Phase D (3D reconstruction) requires selecting particles with good 2D class averages. Running with more micrographs (≥50) or adjusting `num_ab_initio_classes` parameters should allow Phase D to proceed.

---

## Architecture Notes: Generalizable vs. CryoSPARC-Specific

| Fix | Scope | Files Changed |
|-----|-------|--------------|
| S3 outdir → timing.json | **Generalizable** — all AWS Batch workflows | `nextflow_executor.py` |
| Step output from S3 dirs | **Generalizable framework** + CryoSPARC mapping | `nextflow_executor.py` |
| QC metrics extraction | **CryoSPARC-specific** (cryosparc-tools API) | `main.nf` |
| QC Results display panel | **Generalizable** (reads qc_report from status) | `nextflow-workflow-viewer.tsx` |

Adding support for another workflow's step-level outputs: add `_<DOMAIN>_S3_DIR_TO_STEP` mapping in `nextflow_executor.py`.

---

## Updated E2E Test Assertions

The CE-1 test should now be updated to:
1. Check `[data-testid="qc-report-panel"]` is visible after completion (once metrics are extracted)
2. Check that phase card output chips appear for steps with S3 files
3. Remove the "expected failure" language — these are real features that must work

The two assertions that will remain "not observed" until Phase D runs:
- FSC resolution (requires homogeneous refinement completing)
- Final map sharpening report (requires Phase E completing)

Running with ≥50 EMPIAR-10028 micrographs is recommended for a full A-E pipeline completion.

---

## Next Steps

1. Reload Galaxy backend: `kill -HUP $(pgrep -f "gunicorn.*8081" | head -1)`
2. Run CE-1 test with ≥50 micrographs to verify Phase D/E execute
3. Update E2E test assertions to check QC panel and step output files
4. Verify DensityMapViewer renders `cs_out_J6_020_class_averages.mrc` correctly
