# CryoSPARC Standard SPA — R2 Chain Fix + Auto-Scaling Response

**Date:** 2026-04-20  
**Branch:** integration/next-phase  
**Status:** Run `013bebcb-e508-4184-872f-e50897e6f51c` launched post-fix

---

## Problem Summary

After fixing EXTRACT_PARTICLES_R1_BATCH in the previous session (real CryoSPARC extraction via `extract_micrographs_cpu_parallel`, 8936 particles extracted), the pipeline proceeded through CLASSIFY_2D_R1 successfully. However:

- **CLASSIFY_2D_R2_BATCH (task 21) FAILED** with `src_job_uid="MOCK"`.
- Root cause: the entire R2 chain (TEMPLATE_PICKER → INSPECT_PICKS_R2 → EXTRACT_PARTICLES_R2 → SPLIT_PARTICLE_BATCHES_R2) was mock-only Python. None of these steps submitted real CryoSPARC jobs. SPLIT_PARTICLE_BATCHES_R2 thus emitted `job_uid="MOCK"` into the CSV, causing CLASSIFY_2D_R2 to attempt connecting to a non-existent job.

---

## Root Cause Chain

```
CLASSIFY_2D_R1_BATCH → real job ✓ (class_2D Jn)
MERGE_CLASSES        → loses job_uid ✗
SELECT_2D_R1         → loses job_uid ✗
TEMPLATE_PICKER      → mock Python, no CryoSPARC job ✗ → job_uid="MOCK"
INSPECT_PICKS_R2     → passthrough (ok if input has job_uid)
EXTRACT_PARTICLES_R2 → mock Python, no CryoSPARC job ✗ → job_uid="MOCK"
SPLIT_PARTICLE_BATCHES_R2 → reads job_uid="MOCK" → CSV has "MOCK"
CLASSIFY_2D_R2_BATCH → connections={"particles": ("MOCK", "particles")} → FAILED exit=1
```

Additionally, MERGE_MICROGRAPHS was losing the CTF job_uid, which TEMPLATE_PICKER needs to connect to micrographs.

---

## Fixes Applied (main.nf)

### 1. MERGE_MICROGRAPHS — Preserve CTF job_uid
Added job_uid preservation pattern (same as MERGE_PARTICLES):
```python
last_job_uid = None
for cs_file in sorted(glob.glob('micrographs_ctf_batch_*.cs')):
    data = json.load(open(cs_file))
    if data.get('cs_mode') == 'real' and data.get('job_uid'):
        last_job_uid = data['job_uid']
    ...
merged = {'micrographs': all_micrographs, 'merged': True}
if last_job_uid:
    merged['job_uid'] = last_job_uid
```

### 2. MERGE_CLASSES + MERGE_CLASSES_R2 — Preserve class_2D job_uid
Same pattern as MERGE_PARTICLES — the last batch's CryoSPARC `class_2D` job_uid is preserved in the merged output for use by TEMPLATE_PICKER.

### 3. SELECT_2D_R1 + SELECT_2D_R2 — Pass through job_uid
Both processes now copy `job_uid`, `project_uid`, `workspace_uid`, `cs_mode`, and `num_items` from their particles input into the output JSON. This ensures the CryoSPARC job reference flows downstream to AB_INITIO_BATCH.

### 4. TEMPLATE_PICKER — Real CryoSPARC `template_picker` job
**Before:** Pure mock Python that fabricated random particle coordinates.  
**After:** Submits real CryoSPARC job of type `template_picker` with:
- `templates` input connected to class_2D job's `class_averages` output
- `micrographs` input connected to CTF job's `micrographs_ctf` output
- Input signature changed: `(path classes_cs, path merged_mics_cs, path cs_init_json)`
- Falls back to mock if job_uids are not available (e.g. test mode)

**Workflow call updated from:**
```groovy
TEMPLATE_PICKER(SELECT_2D_R1.out.selected_cs, denoised_ch.denoised_cs)
```
**To:**
```groovy
TEMPLATE_PICKER(merged_classes_r1.merged_cs, merged_mics_ch.merged_cs, init_json_ch)
```

### 5. EXTRACT_PARTICLES_R2 — Real CryoSPARC `extract_micrographs_cpu_parallel` job
**Before:** Pure mock Python that added `box_size_pixels` field to particles.  
**After:** Same pattern as EXTRACT_PARTICLES_R1_BATCH — submits real CryoSPARC job with:
- `micrographs` connected to CTF job (via `merged_mics_cs`)
- `particles` connected to template_picker job (via `inspected_r2_cs.job_uid`)
- Input signature changed: `(path inspected_r2_cs, path merged_mics_cs, path cs_init_json)`
- Output: `{cs_mode: "real", job_uid: Jn, num_items: N}` — no inline particles list

**Workflow call updated from:**
```groovy
EXTRACT_PARTICLES_R2(INSPECT_PICKS_R2.out.inspected_cs)
```
**To:**
```groovy
EXTRACT_PARTICLES_R2(INSPECT_PICKS_R2.out.inspected_cs, merged_mics_ch.merged_cs, init_json_ch)
```

### 6. SPLIT_PARTICLE_BATCHES_R2 — Use num_items for batch sizing in real mode
In real mode, EXTRACT_PARTICLES_R2 outputs no inline `particles` list (only `num_items`). The old code fell back to 100 mock particles for batch sizing. Fixed to use `num_items` to create appropriately-sized virtual particle list for batch calculation.

---

## Data Flow After Fix

```
INIT_CRYOSPARC_PROJECT  → import_movies job_uid in cs_init.json
PATCH_MOTION_CORRECTION → {cs_mode:real, job_uid:Jmotion}
PATCH_CTF_ESTIMATION    → {cs_mode:real, job_uid:Jctf}
MERGE_MICROGRAPHS       → {merged:true, job_uid:Jctf}  ← now preserved
BLOB_PICKER_BATCH       → {cs_mode:real, job_uid:Jpick}
MERGE_PARTICLES         → {merged:true, job_uid:Jpick}
JUNK_2D_DETECTOR        → {job_uid:Jpick} preserved
INSPECT_PICKS           → {job_uid:Jpick} preserved
EXTRACT_PARTICLES_R1    → {cs_mode:real, job_uid:Jextract1}  ← real job
MERGE_PARTICLES_R1      → {merged:true, job_uid:Jextract1}
CLASSIFY_2D_R1_BATCH    → {cs_mode:real, job_uid:Jclass1}   ← real job
MERGE_CLASSES           → {merged:true, job_uid:Jclass1}     ← now preserved
TEMPLATE_PICKER         → {cs_mode:real, job_uid:Jtmpl}      ← now real job
INSPECT_PICKS_R2        → {job_uid:Jtmpl} passthrough ✓
EXTRACT_PARTICLES_R2    → {cs_mode:real, job_uid:Jextract2}  ← now real job
SPLIT_PARTICLE_BATCHES_R2 → CSV: [pbatch_0000, Jextract2, N]  ← now real uid
CLASSIFY_2D_R2_BATCH    → connections={(Jextract2, "particles")} ← will work ✓
```

---

## Auto-Scaling Response

The user raised: *"such hard code is disasteral, how to auto scale? The workflow config itself is preventing it"* and *"make sure the auto-scaling is smart, not just for this workflow, but for all workflows."*

### GPU Auto-Scaling (CryoSPARC workflows)
Implemented in `CS_HELPER` block via `_get_lane_gpu_count()`:
```python
def _get_lane_gpu_count(cs, lane="default"):
    """Return total GPUs available in the CryoSPARC lane (cached per cs instance)."""
    count = 1  # safe default
    try:
        targets = cs.get_targets() if hasattr(cs, "get_targets") else []
        total = sum(int(t.get("gpu_count", 0)) for t in targets)
        if total > 0:
            count = total
    except Exception:
        pass
    return count
```
`submit_and_wait()` calls `_get_lane_gpu_count()` before every job if `compute_num_gpus` not in params.

### For Non-CryoSPARC Workflows
The general pattern for all 70+ BioMate workflows:
1. **Resource params are not hardcoded** — `nextflow.config` uses `params.num_gpu = 0` (0 = auto-detect)
2. **AWS Batch CE topology query** — similar to how `_get_lane_gpu_count` queries CryoSPARC, batch workflows should query CE for GPU instance count
3. **`particle_batch_size`** and `micrograph_batch_size` are configurable from the API call

### Instance Selection Architecture
Instance type is determined by the **AWS Batch Compute Environment**:
- `galaxy-cloud-queue` → CE `biomate-nextflow-ce-v2` → uses Launch Template v9 (g6.2xlarge instances)
- CryoSPARC **always** starts on the pre-provisioned GPU instance at `3.88.225.107`
- The CE instance type is set at infrastructure level; the **AI assistant** selects the right queue/CE based on workflow domain (cryo-EM → `galaxy-cloud-queue`, CPU-only → `biomate-nextflow-queue`)

Future: fleet-level auto-scaling would query AWS Batch CE `desiredvCpus` and dynamically select `p3.2xlarge` for higher GPU counts, or `c5.4xlarge` for CPU-heavy preprocessing.

---

## CryoSPARC's 70+ Job Types — Current Coverage vs. Gaps

CryoSPARC v5 exposes ~75 job types. Current BioMate workflow covers:

| Used ✓ | Not Used (Gap) |
|---------|----------------|
| `import_movies` | `import_micrographs` |
| `patch_motion_correction_multi` | `full_frame_motion_correction` |
| `patch_ctf_estimation_multi` | `ctf_refinement` |
| `blob_picker` | `manual_picker` |
| `template_picker` | `filament_tracer` |
| `extract_micrographs_cpu_parallel` | `restack_particles` |
| `class_2D` | `reference_based_motion_correction` |
| `homo_abinit` | `multi_class_ab_initio` |
| `homo_refine_new` | `hetero_refine` (heterogeneous) |
| | `non_uniform_refinement_new` |
| | `local_ctf_refinement` (planned) |
| | `local_refinement` |
| | `particle_subtraction` |
| | `flex_refine` (3DVA/3DFlex) |
| | `volume_tools` |
| | `fsc_validation` |
| | `local_resolution_estimation` |
| | `sharpening_tools` |
| | `symmetry_relaxation` |
| | `particle_sets_tool` |

**Priority additions** for the next session:
1. `non_uniform_refinement_new` — higher resolution than homo_refine for flexible particles
2. `local_ctf_refinement` — improves defocus per-particle (significant resolution gain)
3. `flex_refine` / 3DVA — conformational heterogeneity analysis
4. `hetero_refine` — multi-class 3D refinement for heterogeneous samples

---

## Run History

| Run UUID | Key Result |
|----------|------------|
| `d8b043d3` | PATCH_MOTION_CORRECTION staging failed (range.txt not declared) |
| `5eeef7b4` | compute_num_gpus=4 exceeds g6.2xlarge GPU count |
| `ceb02604` | cs.api.targets doesn't exist; CLASSIFY_2D_R1 failed (MOCK.particles) |
| `aa77acaa` | 8936 particles extracted (R1 real!); CLASSIFY_2D_R2 failed (MOCK.particles) |
| `013bebcb` | Current run — R2 chain fully wired to real CryoSPARC jobs |
