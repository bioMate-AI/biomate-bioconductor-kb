# CryoSPARC Pipeline Parallelism — Part A & B — 2026-04-27

## Summary

This session implements two complementary improvements to the BioMate CryoSPARC pipeline:

- **Part A**: Fix the movie preprocessing batching bug; add per-batch import support for true parallel motion correction on multi-GPU instances.
- **Part B**: Import-particles mode (skip movie preprocessing); demonstrate 2D classification and ab-initio parallelism with 26K pre-extracted particles.

Both changes are committed to `integration/next-phase`. Part B is actively running on EC2 54.159.243.71 (g6.2xlarge, 1× NVIDIA L4).

---

## Part A — Per-Batch Movie Import Fix

### The Bug (Before)

The original `PATCH_MOTION_CORRECTION_BATCH` connected ALL batches to the same `init["import_job_uid"]`:
```python
connections={"movies": (init["import_job_uid"], "imported_movies")}
```
Result: with 4 batches, CryoSPARC created 4 identical motion correction jobs each processing ALL movies — 4× duplicate work, not parallel.

### The Fix

1. **Backend (`nextflow_executor.py`)**: Added `_create_movie_batch_dirs()` — SSHes to CryoSPARC instance before launching Nextflow, creates per-batch symlink directories (`/home/ubuntu/biomate_batches/<run_tag>/batch_0000/` etc.), one per GPU worker.

2. **Main pipeline (`main.nf`)**:
   - New param `params.movie_batch_dirs = ""` — JSON list of `{batch_id, dir, num_movies}` dicts.
   - `INIT_CRYOSPARC_PROJECT` (movies mode): if `movie_batch_dirs` is provided, creates one workspace + import_movies job per batch dir. Each batch imports only its N movies.
   - `SPLIT_INTO_BATCHES`: new CSV format — `batch_id, workspace_uid, import_job_uid, num_movies` (vs old `batch_id, start, end`).
   - `PATCH_MOTION_CORRECTION_BATCH`: new input `tuple val(batch_id), val(batch_ws_uid), val(batch_import_uid), val(batch_num_movies)`. Each batch uses its OWN workspace and import job → processes only its N movies.
   - Downstream batch processes (CTF, blob picker): read `workspace_uid` from `prev["workspace_uid"]` (propagated from the per-batch motion correction output).

### Expected Speedup on g6.12xlarge (4× NVIDIA L4)

| Config | Motion correction | Speedup |
|--------|-------------------|---------|
| 1 GPU, 20 movies (P36 benchmark) | ~2 min (sequential) | 1× |
| 4 GPU, 4 batches × 5 movies (Part A) | ~2 min (parallel, each batch 5 movies) | ~4× |
| 4 GPU, `compute_num_gpus=4`, 1 job | ~1 min (all GPUs on 1 job) | ~2-4× |

Note: Actual speedup depends on CryoSPARC's internal GPU parallelism vs overhead per job.

---

## Part B — Import-Particles Mode + 2D Classification

### Design

Start from pre-extracted polished particle stacks (EMPIAR-10028 shiny particles):
- `star_file = /home/ubuntu/particles/shiny_quarter.star` — 26,312 particles (every 4th of 105,247)
- Skips movie import / motion correction / CTF estimation / picking / extraction
- Routes directly to 2D classification → ab-initio → homo-refine → NU-refine → FSC

### Key Fixes Applied in This Session

1. **`_IO_ALIASES` for `import_particles` output**: CryoSPARC v5 `import_particles` outputs `imported_particles` (not `particles`). Added `"particles": ["imported_particles"]` alias so `class_2D.particles <- J1.imported_particles` connects correctly.

2. **`compute_use_ssd = False`**: 26K particles (27 GB stacks) exceed the g6.2xlarge SSD cache (46.57 GiB). Added `"compute_use_ssd": False` to class_2D, homo_abinit, homo_refine_new, and nonuniform_refine_new params. CryoSPARC reads directly from NVMe disk (slower but no OOM).

3. **SSD cache cleared**: Removed 179 stale cache entries from `/tmp/cryosparc_ssd` to reclaim 47 GB.

### Current State (2026-04-27 ~22:45 UTC)

| Run | Project | Status |
|-----|---------|--------|
| ca43b17e | P47 | J1 import_particles ✓, J2 class_2D FAILED (missing alias) |
| ab519b6f | P48 | J1 ✓, J2 class_2D FAILED (SSD cache OOM) |
| 1dbba1bc | P49 | RUNNING — INIT on Batch, class_2D pending |

The third attempt has both fixes and should proceed past 2D classification.

### Expected Timeline on g6.2xlarge (1× NVIDIA L4)

| Step | Particles | Expected duration |
|------|-----------|-------------------|
| import_particles | 26,312 | ~5 min |
| class_2D × 3 batches (10K each) | 26,312 total | ~30–40 min each (serialized on 1 GPU) |
| ab-initio × 3 | 26,312 | ~20–30 min each |
| homo-refine × 3 | 26,312 | ~5–10 min each |
| NU-refine + CTF-refine + FSC | — | ~15–20 min |
| **Total** | — | **~3–5 hours** |

---

## Bugs Fixed in main.nf This Session

| Bug | Symptom | Fix |
|-----|---------|-----|
| `particles` alias missing | `J2.particles <- J1.particles` connection failed | Added `"particles": ["imported_particles"]` to `_IO_ALIASES` |
| SSD cache OOM for large datasets | `class_2D` crashed with RuntimeError: SSD cache 50.8 GiB > 46.6 GiB | Added `"compute_use_ssd": False` to all GPU job params |
| Motion correction batching bug | All batches processed ALL movies (4× duplicate work) | Per-batch dirs via SSH + per-batch workspace/import |
| CSV format `(batch_id, start, end)` → unused `start/end` | No actual movie subsetting possible | New CSV `(batch_id, ws_uid, import_uid, num_movies)` with real per-batch targets |

---

## Files Changed

| File | Change |
|------|--------|
| `backend/biomni_workflows/.../cryosparc_standard_spa/main.nf` | Part A batch fix + Part B alias + SSD fix |
| `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py` | `_create_movie_batch_dirs()` + `movie_batch_dirs` param + `_NON_PATH_KEYS` update |

---

## Next Steps

1. **Monitor Part B** (run `1dbba1bc`): check CryoSPARC P49 for J2 class_2D completion (~3h).
2. **Collect Part B timings**: record per-job start/end from P49 CryoSPARC UI.
3. **Merge A+B**: The pipeline now handles both starting points (movies vs particles). No further merge needed — they already share the same Phase C (2D classification) onward.
4. **Test Part A** on multi-GPU: requires downloading movies back to EC2, or using a different dataset. g6.12xlarge needed to demonstrate 4× parallel motion correction.
5. **Update Paper A** (BioMate-Cryo) with Part B timing results once complete.
