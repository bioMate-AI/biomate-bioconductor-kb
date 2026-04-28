# CryoSPARC Engineering Decisions, Hardware Model, and Robustness Plan

**Date:** 2026-04-20 / 2026-04-21  
**Branch:** integration/next-phase

---

## 1. GPU Auto-Detect → Static Job Type Classification

### What Was Wrong
`submit_and_wait()` previously called `cs.get_targets()` on every job submission (even CPU jobs like `import_movies`, `blob_picker`, `extract_micrographs_cpu_parallel`) to determine GPU count. This caused:
- A redundant API round-trip per Batch task
- `set_param(compute_num_gpus=1)` returning HTTP 404 on CPU-only job types
- 404 errors caught silently but then `job.queue()` returning 422 ("Invalid path")

### The Fix
Replaced auto-detect with a static `_GPU_JOB_TYPES` frozenset:

```python
_GPU_JOB_TYPES = frozenset({
    "class_2D", "class_3D",
    "homo_abinit", "hetero_abinit",
    "homo_refine", "homo_refine_new",
    "heterogeneous_refinement",
    "non_uniform_refinement", "non_uniform_refinement_new",
    "local_refinement", "local_ctf_refinement",
    "flex_refine", "refine_3D", "refine_3D_new",
})
```

`submit_and_wait()` only sets `compute_num_gpus` when `job_type in _GPU_JOB_TYPES`. CPU jobs never receive this parameter. No API call needed.

### What Code Needs Changing for Multiple GPUs

**Nothing in the Nextflow pipeline.** CryoSPARC handles GPU parallelism internally:
1. `submit_and_wait(..., num_gpu=N)` — set N=4 for g6.12xlarge (4× L4)
2. CryoSPARC assigns all N GPUs to that job automatically
3. The Nextflow Batch job definition must request GPU resources:
   ```
   resourceRequirements: [{type: GPU, value: N}]
   ```
4. The Batch CE must have multi-GPU instances in its fleet

**No pipeline logic changes.** GPU count is a resource parameter, not a compute topology change. CryoSPARC's internal scheduler handles splitting work across GPUs within a single job.

For multi-node GPU (multiple EC2 instances):
- Not supported by CryoSPARC — each CryoSPARC job runs on a single worker node
- Parallelism across nodes is at the **Nextflow level** (multiple parallel Batch tasks)
- e.g. 4 micrograph batches × 1 GPU each = 4 concurrent single-GPU jobs (current design)

---

## 2. Hardware Follows Data — Corrected GPU Hierarchy

**Previous (wrong) model:** V100 > L4 for cryo-EM  
**Correct model:** L4 (Ada Lovelace, 2023) is faster than V100 (Volta, 2017) for compute-bound workloads.

| GPU | FP32 TFLOPS | VRAM | Bandwidth | Architecture |
|-----|-------------|------|-----------|--------------|
| NVIDIA L4 | 31.2 | 24GB GDDR6 | 300 GB/s | Ada Lovelace (2023) |
| NVIDIA V100 | 14.1 | 16–32GB HBM2 | 900 GB/s | Volta (2017) |

L4 wins 2:1 on raw compute. V100 wins on memory bandwidth — relevant only for massive datasets where loading particle stacks becomes the bottleneck.

### Dataset → Instance Decision

The right signal is **particle_count × box_size² × batch_size** — if compute-bound, use L4; if bandwidth-bound (huge stacks), HBM2 matters.

| Dataset size | AWS Instance | GPUs | Total VRAM | When to use |
|---|---|---|---|---|
| <100 movies, test | g6.2xlarge | 1× L4 | 24 GB | Dev/test only |
| 100–500 movies | g6.12xlarge | 4× L4 | 96 GB | Standard datasets |
| 500–2000 movies | g6.48xlarge | 8× L4 | 192 GB | Large campaigns |
| >1M particles, box>512px | p3.16xlarge | 8× V100 | 128–256 GB HBM2 | Memory bandwidth bottleneck |

**This selection should be automatic**, driven by:
1. Count files in the movies path before launch (`len(glob(movies_path))`)
2. Estimate particle count: `num_movies × picks_per_mic × pick_rate`
3. Select instance type from a fleet before submitting Nextflow

This pre-launch sizing is **not yet implemented** — tracked as P1 below.

---

## 3. Intermediate Outputs — Visibility in BioMate

### What CryoSPARC Stores

Every CryoSPARC job writes outputs to `/home/ubuntu/cryosparc_projects/<project>/<job>/`:

| Job | Interesting output | Format |
|-----|-------------------|--------|
| import_movies | imported_movies.cs | particle metadata |
| patch_motion_correction | thumbnails/*.png | micrograph JPEGs |
| patch_ctf_estimation | thumbnails/*.png | CTF diagnostic plots |
| blob_picker / template_picker | thumbnails/*.png | picks overlaid on mics |
| extract_micrographs | extracted_particles.cs | particle stack |
| class_2D | `*_class_averages.cs` + thumbnails/ | 2D class images |
| homo_abinit | volume output (.mrc) | 3D density map |
| homo_refine_new | volume output (.mrc) | Refined 3D map |
| local_resolution | local_resolution.mrc | Local resolution map |

### Current State in BioMate

- **Workflow viewer**: shows phase card status, elapsed time, particle counts from JSON metadata
- **Findings endpoint** (`/api/workflows/runs/:id/findings`): Claude Haiku text analysis of outputs — no images
- **Download endpoint**: lists output files from S3 — downloadable but not rendered
- **CryoSPARC UI** (3.88.225.107:30000): full visualization — but separate from BioMate

### What's Missing (P2 — Next Feature)

To make intermediate outputs visible inside BioMate:

1. **Phase card data panel** — already shows JSON metadata; extend to show:
   - `num_particles`, `resolution_angstroms` from job JSON
   - CTF quality histogram
   - 2D class count and best-resolution class

2. **Thumbnail relay** — SSH from BioMate backend to CryoSPARC instance and serve `thumbnails/*.png` as base64-encoded images through the findings endpoint. Findings would include:
   - CTF diagnostic image (per-micrograph)
   - 2D class gallery (from class_2D job)
   - Micrograph motion traces

3. **3D volume viewer** — when refinement completes, download `.mrc` file and render via:
   - NGL viewer (already in BioMate for protein structures) — supports volumetric `.mrc`
   - Or Mol* with electron density mode

4. **FSC curve** — `fsc_validation` job output is JSON; plot inline in findings panel

**Implementation approach**: extend `_build_cryosparc_findings()` in `nextflow_executor.py` to:
- Call CryoSPARC API to list job outputs
- Fetch thumbnails via SCP/SFTP and base64-encode
- Return structured findings with image data

---

## 4. Root Causes of Recent Run Failures

| Run | Failure | Root cause | Fix |
|-----|---------|-----------|-----|
| `013bebcb` | INIT 422: invalid path | Wrong movies path (`/data/cryosparc/movies`) | Updated env + restarted gunicorn |
| `469ecf85` | INIT 422: invalid path | `.env` not reloaded by SIGHUP (`override=False`) | Full gunicorn restart |
| `752a3889` | INIT 422: invalid path | Same — SIGHUP doesn't overcome `override=False` | Full gunicorn restart |
| `4dee63c9` | INIT fail: blob_paths=None | Same env issue + empty movies_path → blob_paths="" → None | Full gunicorn restart |
| `f5392ef6` | (in progress) | Should work — gunicorn fully restarted with new env | Monitoring |

### `load_dotenv(override=False)` Is a Fragility — Fix Applied

**Problem:** `nextflow_executor.py` line 38 uses `override=False`, meaning once an env var is set in the process environment, `.env` changes are silently ignored. SIGHUP restarts workers but they inherit the parent's (stale) environment.

**Fix applied to `nextflow_executor.py`:** changed to `override=True` so `.env` always wins, even on reloaded workers. SIGHUP now propagates `.env` changes correctly.

### Wrong Default Movie Directory in `.env`

`CRYOSPARC_DEFAULT_MOVIE_DIR` was `/home/ubuntu/empiar-10028/Micrographs` (non-existent). Corrected to `/home/ubuntu/biomate_movies/2b97383e3f` (20 `.mrcs` movies confirmed present).

---

## 5. Implementation Plan (Priority Order)

### P0 — In Progress: Full R2 Chain Validation
Run `f5392ef6` — verify TEMPLATE_PICKER → EXTRACT_PARTICLES_R2 → CLASSIFY_2D_R2 all complete with real CryoSPARC job UIDs.

### P1 — Post-Processing: Real Jobs for Final Steps
These processes are still mock Python (no real CryoSPARC calls):
- `NON_UNIFORM_REFINEMENT` — should submit `non_uniform_refinement_new`
- `LOCAL_CTF_REFINEMENT` — should submit `local_ctf_refinement`
- `LOCAL_RESOLUTION` — should submit `local_resolution_estimation`
- `SHARPEN` — should submit `sharpening_tools`
- `VALIDATION_FSC` — should submit `fsc_validation`

Priority: `non_uniform_refinement_new` + `local_ctf_refinement` first (biggest impact on final resolution).

### P2 — Intermediate Output Visualization in BioMate
Extend findings endpoint to serve CryoSPARC thumbnails (CTF plots, 2D class gallery, micrograph picks) and wire 3D volume into NGL viewer.

### P3 — Pre-Launch Dataset Sizing + Instance Selection
Before launching Nextflow: count movies in path → estimate particle count → select instance type from fleet automatically.

### P4 — Full Scientific Validation
Run full EMPIAR-10028 (150 movies) on `g6.12xlarge` (4× L4). Verify 2D class averages show interpretable TRPV1 projections. Target: produce a density map that resolves the transmembrane domain (≤6Å).
