# Multi-GPU CryoSPARC Pipeline — Code Analysis & Study Findings

**Date:** 2026-04-28  
**Status:** Complete — documented from benchmark results, source code review, and session history

---

## 1. Background

Over several sessions (2026-04-20 through 2026-04-28), BioMate's CryoSPARC SPA pipeline
was extended to support multi-GPU execution on AWS Batch. This document consolidates:

- What the completed benchmark (P52) showed
- How multi-GPU is architecturally wired (executor → workflow → CryoSPARC)
- The exact code path that presets GPU numbers before launch
- The INIT process worker registration block: what it does, what was changed, and why

---

## 2. Benchmark Results (P52 — Completed)

Source: `docs/20260428_CRYOSPARC_MULTIMODE_BENCHMARK_RESULTS.md`

| Run | Dataset | Instance | GPUs | Workers | FSC 0.143 | Cost |
|-----|---------|----------|------|---------|-----------|------|
| P36 | 20 raw movies → 24,879 particles | g6.2xlarge | 1× L4 | 1 | 3.98 Å | $6.29 |
| P49 | 26,312 polished particles | g6.2xlarge | 1× L4 | 1 | (aborted, baseline timing) | ~$1.28 |
| **P52** | **26,312 polished particles** | **g6.12xlarge** | **4× L4** | **4** | **1.78 Å** | **$0.75** |

P52 is **Nyquist-limited** at 1.78 Å (Nyquist = 1.77 Å at 0.885 Å/px), meaning BioMate's
automated pipeline recovered every bit of resolution the data could provide with no
manual tuning.

### Parallel Stage Speedup (P52 vs P49 baseline)

| Stage | P52 (4 GPUs, parallel) | P49 (1 GPU, sequential) | Speedup |
|-------|------------------------|-------------------------|---------|
| class_2D × 3 batches | **5m 46s** (simultaneous) | 6 + 11 + 16 = 34 min | **5.7×** |
| ab-initio × 3 | **12m 48s** (simultaneous) | 11 + 12 + 13 = 36 min | **2.8×** |
| homo-refine × 3 | **8m 49s** (simultaneous) | 7 + 9 + 6 = 22 min | **2.5×** |
| **GPU-bound total** | **~27 min** | **~92 min** | **3.4×** |

---

## 3. How Multi-GPU Is Architecturally Wired

### 3.1 Fleet Selection (nextflow_executor.py, lines 4571–4651)

The executor auto-selects the instance type and GPU count based on dataset size:

```python
_CRYOSPARC_FLEET = [
    {"max_movies": 20,   "instance_type": "g6.2xlarge",  "num_gpu": 1, "label": "CI/test (1× L4, ≤20 movies)"},
    {"max_movies": 500,  "instance_type": "g6.12xlarge", "num_gpu": 4, "label": "standard (4× L4)"},
    {"max_movies": 2000, "instance_type": "g6.48xlarge", "num_gpu": 8, "label": "large campaign (8× L4)"},
    {"max_movies": 9999, "instance_type": "p3.16xlarge",  "num_gpu": 8, "label": "bandwidth-bound (8× V100 HBM2)"},
]
```

### 3.2 num_cs_workers Is Always Preset (lines 4647–4654)

**This is the key code that presets GPU numbers before the workflow starts:**

```python
_selected_num_gpu = int(params.get("num_gpu", 0)) or _fleet_entry["num_gpu"]

# Auto-set num_cs_workers to match the GPU count unless caller overrides.
if "num_cs_workers" not in params:
    params["num_cs_workers"] = _selected_num_gpu
```

For a 21–500 movie dataset on g6.12xlarge: `_selected_num_gpu = 4`, so
`params["num_cs_workers"] = 4` is written into the NF params dict before Nextflow launches.
**The workflow always receives a concrete integer (e.g., 4), never 0.**

### 3.3 Worker Pre-Registration via SSH (lines 4741–4762)

For multi-worker movies mode, the executor SSHes to the CryoSPARC instance **before**
launching Nextflow to create per-batch movie directories and register workers:

```python
if num_cs_workers > 1 and input_mode != "import_particles" and movies_path_raw:
    _batch_dirs = _create_movie_batch_dirs(
        movies_path=movies_path_raw,
        instance_ip=_inst_ip_mb,
        ssh_key=_ssh_key_mb,
        num_workers=num_cs_workers,
        batch_size=batch_size,
    )
```

CryoSPARC worker lanes are registered using (from benchmark doc, item 4 in "Key Technical Fixes"):
```bash
cryosparcm worker connect \
  --path /home/ubuntu/cryosparc_worker \
  --worker worker_N \
  --lane worker_N \
  --sshstr ubuntu@localhost \
  --gpus N \
  --ssdpath /tmp/cryosparc_ssd
```
This is `v5` syntax. The `v4` equivalent (`cryosparcm addworker`) is not used.

### 3.4 Lane Routing in Downstream Processes (_lane_for_batch)

Every downstream Nextflow process calls `_lane_for_batch()` to route its batch to the
correct GPU worker lane:

```python
def _lane_for_batch(batch_id: str, num_workers: int, base_lane: str = "default") -> str:
    if num_workers <= 1:
        return base_lane          # single-GPU: always "default"
    try:
        idx = int(batch_id.split("_")[-1])
    except ValueError:
        idx = hash(batch_id) % num_workers
    return f"worker_{idx % num_workers}"
```

With `num_cs_workers=4`:
- `batch_0000` → `worker_0` (GPU 0)
- `batch_0001` → `worker_1` (GPU 1)
- `batch_0002` → `worker_2` (GPU 2)
- `ab_initio_k1..k3` → `worker_0..worker_2`

---

## 4. INIT Process Worker Block — What Was There, What Changed, and Why

### 4.1 Original Code (before this session)

Lines 568–600 of `main.nf` contained a worker registration block:

```python
# ── Multi-lane worker registration (only when num_cs_workers > 1) ──
import subprocess as _sp, shutil as _sh
_num_workers = ${params.num_cs_workers}   # e.g. 4 for g6.12xlarge
if _num_workers > 1:
    _cryosparcm = _sh.which("cryosparcm") or "/home/ubuntu/cryosparc_master/bin/cryosparcm"
    for _i in range(_num_workers):
        _wname = f"worker_{_i}"
        try:
            # Check if lane already exists
            _r = _sp.run([_cryosparcm, "cli", f"list(db.workers.find(...))"], ...)
            if f"worker_{_i}" in (_r.stdout or ""):
                continue  # already registered
            # Register via v4 addworker command
            _reg = _sp.run([_cryosparcm, "addworker", "--name", _wname, ...], ...)
        except Exception as _e:
            print(f"[CS] Warning: worker registration {_wname} failed: {_e}", flush=True)
```

### 4.2 Why It Silently Failed (and Why That Was OK)

**Three problems with the original code:**

1. **Wrong binary path**: The Nextflow INIT process runs inside an AWS Batch container
   (`biomni-tools` or similar), not on the CryoSPARC EC2 instance itself. `_sh.which("cryosparcm")`
   returns `None` in the container, and `/home/ubuntu/cryosparc_master/bin/cryosparcm` does not
   exist in the container filesystem. `subprocess.run()` raises `FileNotFoundError`.

2. **Wrong v4 command**: Even if `cryosparcm` were accessible, `addworker` is the CryoSPARC v4
   command. BioMate runs CryoSPARC v5, where the equivalent is `cryosparcm worker connect`.

3. **Workers already registered**: `nextflow_executor.py` pre-registers workers via SSH to the
   CryoSPARC EC2 instance **before** Nextflow launches. By the time INIT runs, `worker_0..worker_3`
   are already registered and ready.

**Why the pipeline still worked (P52 ran successfully):** Each `_sp.run()` call was wrapped in
`try/except Exception` with a warning print. The `FileNotFoundError` was caught and printed as
`[CS] Warning: worker registration worker_N failed: [Errno 2] No such file or directory`.
Execution continued normally. Since workers were already registered by the executor, the
CryoSPARC API calls in subsequent steps found the lanes and used them correctly.

### 4.3 Replacement Code (this session)

The broken subprocess block was replaced with a clean API-based detection approach:

```python
# ── Multi-lane worker detection (auto when num_cs_workers == 0) ─────────────
# Workers are pre-registered by nextflow_executor.py via SSH BEFORE this
# workflow starts. This block DETECTS available worker lanes via the CryoSPARC API only.

def _detect_worker_lanes(cs):
    """Return set of 'worker_N' lane names visible to the CryoSPARC API."""
    found = set()
    try:
        targets = cs.get_targets() if hasattr(cs, "get_targets") else []
        for t in (targets or []):
            for attr in ("lane", "name"):
                val = getattr(t, attr, None)
                if val is None and isinstance(t, dict):
                    val = t.get(attr)
                if isinstance(val, str) and val.startswith("worker_"):
                    found.add(val)
                    break
    except Exception as _e:
        print(f"[CS] Warning: get_targets() failed ({_e})", flush=True)
    return found

_num_workers_param = ${params.num_cs_workers}  # always a concrete int from executor
if _num_workers_param == 0:
    # Safety net: auto-detect if executor somehow didn't preset
    _worker_lanes = _detect_worker_lanes(cs)
    _num_workers = len(_worker_lanes) if len(_worker_lanes) >= 2 else 1
else:
    _num_workers = _num_workers_param
    if _num_workers > 1:
        # Verify (not register): confirm executor pre-registration succeeded
        _worker_lanes = _detect_worker_lanes(cs)
        _missing = [f"worker_{i}" for i in range(_num_workers) if f"worker_{i}" not in _worker_lanes]
        if _missing:
            print(f"[CS] Warning: expected lanes {_missing} not in targets — jobs will fall back to 'default'")
        else:
            print(f"[CS] Verified {_num_workers} worker lanes pre-registered")
```

**What changed and what didn't:**
- Removed: broken `cryosparcm addworker` subprocess calls
- Added: API-based lane verification using `cs.get_targets()` (already used in `_get_lane_gpu_count()`)
- Added: auto-detect safety net when `num_cs_workers=0` (executor always passes a concrete value; this handles edge cases)
- Unchanged: `_num_workers` written into `cs_init.json` for downstream processes — same as before
- Unchanged: `params.num_cs_workers` default restored to `1` (safe single-GPU default if run directly without executor)

### 4.4 Was the Change Necessary?

**Strictly necessary?** No — P52 succeeded with the old code because the silent failures were harmless.

**Still correct to make?** Yes — dead code that silently fails is a maintenance hazard. The replacement:
- Eliminates a subprocess that will never succeed in the container environment
- Adds verification that confirms executor pre-registration worked
- Uses the existing `cs.get_targets()` API that's already proven to work in the pipeline

---

## 5. The `compute_use_ssd=False` Pattern

A critical fix from Part B (2026-04-27) that must be present on all GPU jobs for large datasets:

```python
# 26K polished stacks = ~27 GB. SSD cache on g6.2xlarge = 46.57 GiB.
# Setting compute_use_ssd=True would fill the cache and crash with:
#   RuntimeError: SSD cache 50.8 GiB > 46.6 GiB
job.set_param("compute_use_ssd", False)
```

Applied to: `class_2D`, `homo_abinit`, `homo_refine_new`, `ctf_refine_local`,
`nonuniform_refine_new` in `main.nf`.

---

## 6. Per-Batch Movie Directory Setup (Part A)

For movies mode with `num_cs_workers > 1`, the executor calls `_create_movie_batch_dirs()`
before Nextflow launches. This SSHes to the CryoSPARC EC2 instance and creates:

```
/home/ubuntu/biomate_batches/<run_tag>/
    batch_0000/  →  symlinks to movies 0..N-1
    batch_0001/  →  symlinks to movies N..2N-1
    batch_0002/  →  symlinks to movies 2N..3N-1
    batch_0003/  →  symlinks to movies 3N..end
```

The INIT process receives these as `params.movie_batch_dirs` (JSON string) and creates one
CryoSPARC workspace + `import_movies` job per batch. This is what enables true parallel
motion correction: each GPU worker processes its own independent batch of movies, not a
copy of all movies.

**Previous bug (before Part A):** All batches connected to `init["import_job_uid"]` —
meaning 4 batches created 4 motion correction jobs each processing ALL movies (4× duplicate
work, not parallelism).

---

## 7. Current State of main.nf params Section

```groovy
params.num_gpu_workers = 1    // ThreadPoolExecutor threads; executor sets to match num_gpu
params.max_parallel_jobs = 20 // Nextflow queueSize cap
// Multi-GPU parallelism: executor auto-sets num_cs_workers = num_gpu before launch.
// Workers pre-registered via SSH by nextflow_executor.py (cryosparcm worker connect v5)
// Benchmark: g6.12xlarge (4× NVIDIA L4), num_cs_workers=4 → 3.4× speedup, FSC 1.78 Å
params.num_cs_workers = 1     // executor overrides to num_gpu (e.g. 4 for g6.12xlarge)
```

---

## 8. Summary of All Files Modified for Multi-GPU Support

| File | Change | Session |
|------|--------|---------|
| `nextflow_executor.py` | Fleet table (4 tiers); `_select_cryosparc_instance()`; auto `num_cs_workers=num_gpu`; `_create_movie_batch_dirs()` SSH pre-setup | 2026-04-28 |
| `nextflow_executor.py` | Worker registration via `cryosparcm worker connect` (v5 SSH path) | 2026-04-28 |
| `main.nf` | `compute_use_ssd=False` on all 6 GPU job types | 2026-04-27 |
| `main.nf` | Per-batch workspace propagation (Part A); `_IO_ALIASES` particles alias (Part B) | 2026-04-27 |
| `main.nf` | INIT: replaced broken `cryosparcm addworker` subprocess with API-based lane detection | 2026-04-28 |
| `backend/.env` | `CRYOSPARC_HOST=3.89.36.242`, `CRYOSPARC_INSTANCE_TYPE=g6.12xlarge` | 2026-04-28 |

---

## 9. Key Lessons for Future Sessions

1. **The executor always presets GPU numbers.** `num_cs_workers` in `main.nf` defaults
   don't matter in production — `nextflow_executor.py` line 4650 overwrites them.

2. **Worker registration happens outside Nextflow.** The CryoSPARC instance must have
   `worker_0..worker_{N-1}` lanes registered before the Nextflow workflow is submitted.
   This is done by the executor via SSH, using `cryosparcm worker connect` (v5 syntax).
   Never attempt worker registration from inside a Nextflow process or container.

3. **`compute_use_ssd=False` is mandatory for >~20 GB datasets.** The SSD cache on all
   tested instances (g6.2xlarge through g6.12xlarge) fills up with real cryo-EM particle
   stacks. All GPU job types must have this parameter set to False.

4. **P52 is the reference benchmark.** g6.12xlarge, 4× L4, 4 workers, 26K particles,
   FSC 1.78 Å, $0.75, 3.4× speedup over single-GPU. These numbers go into Paper A,
   Table 3.2 (Performance Benchmarks).
