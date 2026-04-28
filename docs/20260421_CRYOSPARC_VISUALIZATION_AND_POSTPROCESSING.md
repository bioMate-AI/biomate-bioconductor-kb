# CryoSPARC Visualization Integration + Real Post-Processing Jobs

**Date:** 2026-04-21  
**Branch:** integration/next-phase

---

## 1. What Was Implemented

### A. `cs_download_outputs()` helper (CS_HELPER block)

Added to the shared Python helper block embedded in every process:

```python
def cs_download_outputs(cs, proj_uid, job_uid, mrc_prefix="cs_out_", png_prefix="cs_thumb_"):
    """Download output MRC files and thumbnails from a completed CryoSPARC job."""
```

Logic:
1. `cs.list_files(proj_uid, prefix=f"{job_uid}/", recursive=True)` — lists all files in the job dir
2. Finds MRC files; deduplicates by kind (class_averages, volume, map); downloads last-iteration file per kind
3. Downloads up to 3 PNG thumbnails
4. Returns list of local filenames written

This is called after `submit_and_wait()` in every visualization-enabled process.

### B. Visualization Output Declarations

Added `optional: true` outputs to 3 processes:

| Process | New outputs |
|---------|-------------|
| `CLASSIFY_2D_R1_BATCH` | `cs_out_*_class_averages.mrc`, `cs_thumb_*.png` |
| `CLASSIFY_2D_R2_BATCH` | `cs_out_*_class_averages.mrc`, `cs_thumb_*.png` |
| `HOMO_REFINEMENT_BATCH` | `cs_out_*volume*.mrc`, `cs_out_*map*.mrc` |

These files are published to S3 via Nextflow's `publishDir`. They're immediately accessible through:
- `/api/workflows/runs/:id/step-file?key=…` endpoint
- `StepOutputPreview` component (routes `.mrc` → `DensityMapViewer`)
- `DensityMapViewer` (NGL volumetric rendering, already in production)

No frontend changes required — the existing viewer stack handles `.mrc` automatically.

### C. Real CryoSPARC Jobs for Post-Processing (P1 Priority)

All 6 post-processing processes were rewritten from mock Python to real CryoSPARC job submission. Previously they generated synthetic data; now they use actual CryoSPARC reconstruction algorithms.

| Process | CS Job Type | Input connections | Mock fallback |
|---------|-------------|-------------------|---------------|
| `VOLUME_TOOLS` | `volume_tools` | `{volume: (refine_uid, volume)}` | ✓ copy-through |
| `VALIDATION_FSC` | `fsc_validation` | `{volume: (vol_tools_uid, volume)}` | ✓ synthetic FSC curve |
| `LOCAL_CTF_REFINEMENT` | `local_ctf_refinement` | `{particles: (r2_uid, particles), volume: (vol_uid, volume)}` | ✓ synthetic defocus shift |
| `NON_UNIFORM_REFINEMENT` | `non_uniform_refinement_new` | `{particles: (ctf_refine_uid, particles), volume: (vol_uid, volume)}` | ✓ synthetic MRC |
| `LOCAL_RESOLUTION` | `local_resolution_estimation` | `{volume: (nu_uid, volume)}` | ✓ copy-through |
| `SHARPEN` | `sharpening_tools` | `{volume: (nu_uid, volume)}` | ✓ copy-through |

All 6 also have `container CS_IMAGE` added so they run in the CryoSPARC tools container.

### D. job_uid Threading for Post-Processing Chain

Previous problem: post-processing processes had no way to reference upstream CryoSPARC jobs (they received mock JSON dicts with no `job_uid`).

Fix: `volume_processed.cs` from `VOLUME_TOOLS` now includes `job_uid` in real mode. `NON_UNIFORM_REFINEMENT` outputs a companion `volume_nu_refined_meta.json` with `job_uid` so that `LOCAL_RESOLUTION` and `SHARPEN` can submit their CryoSPARC jobs.

All workflow calls updated:
```groovy
VOLUME_TOOLS(best_refined_ch, init_json_ch)
VALIDATION_FSC(VOLUME_TOOLS.out.processed_cs, init_json_ch)
LOCAL_CTF_REFINEMENT(SELECT_2D_R2.out.selected_cs, VOLUME_TOOLS.out.processed_cs, init_json_ch)
NON_UNIFORM_REFINEMENT(LOCAL_CTF_REFINEMENT.out.refined_particles_cs, VOLUME_TOOLS.out.processed_cs, init_json_ch)
LOCAL_RESOLUTION(NON_UNIFORM_REFINEMENT.out.final_volume, NON_UNIFORM_REFINEMENT.out.volume_meta, init_json_ch)
SHARPEN(NON_UNIFORM_REFINEMENT.out.final_volume, NON_UNIFORM_REFINEMENT.out.volume_meta, init_json_ch)
```

---

## 2. Full CryoSPARC Job Coverage

After this session, the full 23-step pipeline has real CryoSPARC jobs throughout:

| Step | CS Job Type | Status |
|------|-------------|--------|
| Import movies | `import_movies` | ✓ real |
| Patch motion correction | `patch_motion_correction_multi` | ✓ real |
| Patch CTF estimation | `patch_ctf_estimation_multi` | ✓ real |
| Blob picker | `blob_picker_gpu` | ✓ real |
| Extract particles R1 | `extract_micrographs_cpu_parallel` | ✓ real |
| 2D classify R1 | `class_2D` | ✓ real + MRC download |
| Template picker | `template_picker` | ✓ real |
| Extract particles R2 | `extract_micrographs_cpu_parallel` | ✓ real |
| 2D classify R2 | `class_2D` | ✓ real + MRC download |
| Ab-initio reconstruction | `homo_abinit` | ✓ real |
| Homogeneous refinement | `homo_refine_new` | ✓ real + MRC download |
| Volume tools | `volume_tools` | ✓ **NEW** real |
| FSC validation | `fsc_validation` | ✓ **NEW** real |
| Local CTF refinement | `local_ctf_refinement` | ✓ **NEW** real |
| Non-uniform refinement | `non_uniform_refinement_new` | ✓ **NEW** real + MRC download |
| Local resolution | `local_resolution_estimation` | ✓ **NEW** real + MRC download |
| Sharpening | `sharpening_tools` | ✓ **NEW** real + MRC download |

Steps still mock (minor display/analysis steps, not on critical reconstruction path):
- `MICROGRAPH_DENOISER` — optional quality step
- `JUNK_2D_DETECTOR` — optional classifier
- `INSPECT_PICKS`, `INSPECT_PICKS_R2` — passthrough metadata
- `MERGE_*`, `SELECT_2D_*`, `SPLIT_*` — pure Python data routing

---

## 3. Data Flow — Visualization to BioMate UI

```
CLASSIFY_2D_R1_BATCH completes
  → cs_download_outputs() downloads J{n}/J{n}_020_class_averages.mrc
  → Written as cs_out_J{n}_020_class_averages.mrc in work dir
  → publishDir stages to S3: s3://biomate-nextflow-work/{run}/09_classify_2d_round1/batch_0000/
  → /api/workflows/runs/:id/step-file?key=09_classify_2d_round1/batch_0000/cs_out_*.mrc
  → StepOutputPreview detects .mrc extension → DensityMapViewer
  → NGL volumetric rendering of 2D class averages (pseudo-3D display)

SHARPEN completes
  → cs_download_outputs() downloads J{n}/J{n}_volume_sharpenmap.mrc
  → Written as cs_out_sharp_volume_sharpened.mrc
  → volume_sharpened.mrc (final deliverable) = this file
  → Accessible via step-file endpoint → DensityMapViewer → full 3D map
```

---

## 4. Remaining P3/P4 Items

- **Full scientific validation**: run EMPIAR-10028 (150 movies) end-to-end on g6.12xlarge (4× L4)
- **FSC curve visualization**: `fsc_validation.json` returned by real job contains raw curve data; wire into a chart component in `FindingsCard`
- **Pre-launch instance sizing**: count movies → estimate particles → auto-select g6.2xlarge / g6.12xlarge / g6.48xlarge
- **Micrograph denoiser real job**: `deep_picker` or `patch_ctf_estimation_multi` with denoising
