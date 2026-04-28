# CryoEM Speed + Paper Gap Implementation Plan
**Date:** 2026-04-16
**Status:** IN PROGRESS — parallel implementation underway
**Goal:** Complete all gaps for paper submission and user presentation

---

## Gap Summary

| # | Gap | Priority | Effort | Status |
|---|-----|----------|--------|--------|
| G1 | Full 23-step pipeline in cryosparc_executor.py (only 3 steps now) | P0 | 1 day | ✅ Done (cryosparc_executor.py rewritten, 1220 lines, full 23 steps) |
| G2 | Parallel execution: multi-batch fan-out + multi-worker CryoSPARC | P0 | 1 day | ✅ Done (ThreadPoolExecutor parallel phases A/B/C/D) |
| G3 | FSC 0.143 gate (parse CryoSPARC JSON half-map FSC) | P0 | 0.5 day | ✅ Done — `check_fsc_gate()` + `_check_fsc_gate_from_job()` wired with correct `fsc["freq_A_inv"]`/`fsc["fsc_nomask"]` Dataset API |
| G4 | 2D junk class gate (junk fraction > 70% blocking) | P1 | 0.5 day | ✅ Done — `check_junk_class_gate()` + `_check_junk_gate()` using `class_averages["class_num_particles"]` |
| G5 | Preferred orientation detection (anisotropy ratio gate) | P1 | 0.5 day | ✅ Done — `check_orientation_gate()` + `_check_orientation_gate_from_job()` using `particles["alignments3D/pose"]` rotation vectors → theta |
| G6 | Ice thickness proxy gate | P2 | 0.25 day | ✅ Done (check_ice_gate exists in cryosparc_qc_gates.py) |
| G7 | main.nf refactor: channel-based parallel with queueSize | P0 | 0.5 day | ✅ Done (main.nf refactored with SPLIT_INTO_BATCHES + channel fan-out, 1860 lines) |
| G8 | QC audit trail: real JSONL per run (not placeholder) | P1 | 0.5 day | ✅ Done (write_audit_event implemented + wired) |
| G9 | Ab initio quality gate | P1 | 0.5 day | ✅ Done — `check_abinitio_gate()` BRONZE evidence, 3 halt + 2 advisory conditions |
| G10 | Unit + integration tests for all gates | P1 | 0.5 day | ✅ Done (181/181 passing: test_cryosparc_qc_gates.py: 46, test_cryosparc_smart_params.py: 112, test_cryoem_rationale.py: 23) |
| G12 | MolProbity / model validation gate | P1 | 0.25 day | ✅ Done — `check_model_quality_gate()` GOLD evidence (PDB standard) |
| Smart params | Intelligent parameter resolution | P0 | 0.5 day | ✅ Done — `_resolve_smart_params()` with box size, resolution→count, heterogeneity depth, CTF level, symmetry discipline |
| AI rationale | Sample-aware rationale generation in ai_assistant.py | P1 | 0.5 day | ✅ Done — `_build_cryoem_rationale()` with sample class detection + 4 bug fixes |

---

## G1 + G2: Full Pipeline + Parallel Execution

### Architecture

```
cryosparc_executor.py
├── execute_spa_pipeline_parallel()   ← new entry point
│   ├── Phase A: Preprocessing (parallelizable per-batch)
│   │   ├── IMPORT_MOVIES           — single job, all movies
│   │   ├── MOTION_CORRECTION       — N_batch parallel jobs (each: movies/N_batch micrographs)
│   │   ├── CTF_ESTIMATION          — N_batch parallel jobs (pipeline: starts as motion batches complete)
│   │   └── MICROGRAPH_CURATE       — collect + filter (single)
│   ├── Phase B: Picking (parallelizable per-batch)
│   │   ├── BLOB_PICKER             — N_batch parallel jobs
│   │   ├── JUNK_2D_DETECTOR        — single (collected particles)
│   │   ├── INSPECT_PICKS           — single
│   │   └── EXTRACT_PARTICLES_R1    — N_batch parallel jobs
│   ├── Phase C: Classification (parallelizable per-particle-batch)
│   │   ├── CLASSIFY_2D_R1          — M_batch parallel jobs (split 100k → M×10k)
│   │   ├── SELECT_2D_R1            — single (collect)
│   │   ├── TEMPLATE_PICKER         — N_batch parallel
│   │   ├── EXTRACT_PARTICLES_R2    — N_batch parallel
│   │   ├── CLASSIFY_2D_R2          — M_batch parallel
│   │   └── SELECT_2D_R2            — single (collect)
│   └── Phase D: Reconstruction (parallelizable per-model)
│       ├── AB_INITIO               — K parallel (K = num_ab_initio_classes, default 3)
│       ├── HOMO_REFINEMENT         — K parallel (one per ab initio volume)
│       ├── VOLUME_TOOLS            — single (best volume)
│       ├── VALIDATION_FSC          — single → QC gate G3
│       ├── LOCAL_CTF_REFINEMENT    — single
│       ├── NON_UNIFORM_REFINEMENT  — single
│       ├── LOCAL_RESOLUTION        — single
│       └── SHARPENING              — single
```

### Parallelism parameters
```python
N_batch = min(num_micrographs // 200, num_gpu_workers)  # ~200 micrographs per batch
M_batch = max(1, total_particles // 10000)              # ~10k particles per 2D class batch
K = params.get('num_ab_initio_classes', 3)
```

### Concurrency control
```python
# In parallel phase: use ThreadPoolExecutor
from concurrent.futures import ThreadPoolExecutor, as_completed

with ThreadPoolExecutor(max_workers=N_batch) as pool:
    futures = {pool.submit(_run_motion_batch, cs, proj, ws, batch): i
               for i, batch in enumerate(movie_batches)}
    for fut in as_completed(futures):
        micrographs = fut.result()
        # Pipeline: immediately submit CTF for this batch
        pool.submit(_run_ctf_batch, cs, proj, ws, micrographs)
```

### Expected speedup
| Config | Preprocessing | 2D Class | Ab Initio | Total | vs serial |
|--------|-------------|---------|-----------|-------|-----------|
| 1 GPU (baseline) | 500 min | 120 min | 180 min | ~39 hrs | 1x |
| 4 GPU (g6.8xlarge) | 125 min | 30 min | 60 min | ~10.8 hrs | 3.6x |
| 8 GPU (2×g6.4xlarge) | 63 min | 15 min | 30 min | ~5.8 hrs | 6.7x |
| 20 GPU (spot fleet) | 25 min | 6 min | 12 min | ~2.5 hrs | 15.6x |

---

## G3: FSC 0.143 Gate

### Implementation
Parse CryoSPARC validation_fsc job output JSON:
```python
def _check_fsc_gate(job, run, cb):
    """Parse FSC from validation_fsc job and apply GOLD gate."""
    fsc_data = job.load_output("fsc")  # CryoSPARC outputs FSC as structured array
    # fsc_data has fields: 'fsc_nomask', 'fsc_loose', 'fsc_tight', 'fsc_noisesub'
    # Resolution at FSC=0.143 (gold-standard criterion, Henderson 2012)
    resolution_A = _fsc_to_resolution(fsc_data, threshold=0.143)
    
    # Gate: resolution must be determinable (not NaN = FSC never crosses 0.143)
    if resolution_A is None or resolution_A > 20.0:
        _fire_qc_halt(run, cb, {
            "gate": "fsc_0143",
            "level": "GOLD",
            "metric": "fsc_resolution_angstroms",
            "value": resolution_A,
            "threshold": 20.0,
            "message": "FSC curve does not cross 0.143 — reconstruction did not converge",
            "suggestion": "Check: particle count (>10k needed for <6Å), symmetry assignment, preferred orientation"
        })
    
    return resolution_A

def _fsc_to_resolution(fsc_data, threshold=0.143):
    """Interpolate FSC curve to find resolution at given threshold."""
    import numpy as np
    # fsc_data is numpy structured array with 'freq_A_inv' and 'fsc_nomask' columns
    freq = fsc_data['freq_A_inv']   # spatial frequencies in 1/Å
    fsc  = fsc_data['fsc_nomask']   # FSC values
    # Find first crossing below threshold
    below = np.where(fsc < threshold)[0]
    if len(below) == 0:
        return None  # FSC never crosses — bad reconstruction
    idx = below[0]
    if idx == 0:
        return None
    # Linear interpolation
    f1, f2 = freq[idx-1], freq[idx]
    v1, v2 = fsc[idx-1], fsc[idx]
    f_cross = f1 + (threshold - v1) * (f2 - f1) / (v2 - v1)
    return round(1.0 / f_cross, 2) if f_cross > 0 else None
```

---

## G4: 2D Junk Class Gate

### Implementation
After CLASSIFY_2D jobs complete, collect all class averages and score:
```python
def _check_junk_gate(job, run, cb):
    classes = job.load_output("class_averages")
    # CryoSPARC class_averages has 'class_ess' (effective sample size) per class
    # Classes with very low ESS relative to mean are junk
    total_particles = sum(classes['class_num_particles'])
    junk_threshold = 0.05 * (total_particles / len(classes))  # <5% of expected per class
    junk_count = sum(1 for n in classes['class_num_particles'] if n < junk_threshold)
    junk_fraction = junk_count / len(classes)
    
    if junk_fraction > 0.70:  # GOLD gate: >70% junk
        _fire_qc_halt(...)
    elif junk_fraction > 0.50:  # SILVER advisory
        _fire_qc_advisory(...)
```

---

## G5: Preferred Orientation Detection

### Implementation
After HOMO_REFINEMENT, check orientation distribution:
```python
def _check_orientation_gate(job, run, cb):
    particles = job.load_output("particles")
    # Euler angles: 'alignments3D/pose' — shape (N, 3)
    poses = particles['alignments3D/pose']
    # Convert to viewing directions on unit sphere
    # Compute occupancy in equal-area bins (Fibonacci sphere)
    anisotropy_ratio = _compute_orientation_anisotropy(poses)
    
    if anisotropy_ratio > 10.0:  # GOLD gate
        _fire_qc_halt(run, cb, {
            "gate": "preferred_orientation",
            "level": "GOLD",
            "metric": "orientation_anisotropy_ratio",
            "value": anisotropy_ratio,
            "threshold": 10.0,
            "message": f"Orientation anisotropy ratio {anisotropy_ratio:.1f}× — preferred orientation detected",
            "suggestion": "Try: tilted data collection (30-40°), cryo-additive screening (0.01-0.1% fluorinated detergent), detergent titration for membrane proteins"
        })
```

---

## G7: main.nf Parallel Refactor

### Key change: per-batch channel fan-out
```nextflow
workflow CRYOSPARC_STANDARD_SPA {
    take: movies_path

    main:
    // Fan-out: one channel item per micrograph batch
    batch_size = params.micrograph_batch_size ?: 200
    movie_batches_ch = Channel.fromPath("${movies_path}/*.{tif,mrc,eer}")
        .buffer(size: batch_size, remainder: true)  // groups of 200 movies
        .map { batch -> tuple(UUID.randomUUID().toString()[0..7], batch) }

    // Phase A: parallel per-batch preprocessing
    motion_ch = PATCH_MOTION_CORRECTION_BATCH(movie_batches_ch)
    ctf_ch    = PATCH_CTF_ESTIMATION_BATCH(motion_ch)      // pipeline parallel
    
    // Collect all batches → single dataset for classification
    all_micrographs = ctf_ch.collect()
    
    // Phase B: picking (parallel per batch)
    picked_batches = BLOB_PICKER_BATCH(ctf_ch)             // still streaming
    all_picks = picked_batches.collect()
    
    // Phase C: 2D classification with particle batch fan-out
    particle_batches_ch = EXTRACT_PARTICLES_R1(all_micrographs, all_picks)
        .splitText(by: params.particle_batch_size ?: 10000)
    classes_ch = CLASSIFY_2D_R1(particle_batches_ch)
    all_classes = classes_ch.collect()
    ...
}
```

### nextflow.config change
```groovy
executor {
    name = 'awsbatch'
    queueSize = params.max_parallel_jobs ?: 20  // cap cost
}
```

---

## G8: QC Audit Trail (real JSONL)

Each QC event written to `{outdir}/qc_audit.jsonl`:
```json
{"ts":"2026-04-16T10:23:45Z","run_id":"abc123","step":"motion_correction","batch":3,"gate":"total_drift","level":"GOLD","value":47.2,"threshold":50.0,"action":"pass","evidence":"Bharat & Scheres 2016 community practice"}
{"ts":"2026-04-16T10:45:12Z","run_id":"abc123","step":"ctf_estimation","batch":7,"gate":"fit_quality","level":"GOLD","value":0.61,"threshold":0.7,"action":"halt","override":null,"suggestion":"Widen CTF search range; verify pixel size"}
```

---

## G9: Benchmark Harness

### Script: `scripts/run_empiar_benchmark.sh`
```bash
#!/bin/bash
# Download EMPIAR-10061 subset (100 micrographs), run BioMate, record metrics
EMPIAR_ID=10061
SUBSET=100

# Download
aspera -i /path/to/ascp.openssh \
  emp@fasp.ebi.ac.uk:/10061/data/Movies/*.tif \
  ./empiar_${EMPIAR_ID}/

# Stage to working directory
# Run BioMate pipeline
nextflow run main.nf \
  --movies_path ./empiar_${EMPIAR_ID}/ \
  --pixel_size 0.885 \
  --voltage 300 \
  --symmetry D2 \
  --qc_profile cryoem_spa_purified \
  --max_parallel_jobs 4 \
  -with-report benchmark_report.html \
  -with-timeline benchmark_timeline.html

# Record metrics
python3 scripts/extract_benchmark_metrics.py \
  --run_dir ./results/ \
  --expected_resolution 2.2 \
  --output benchmark_results.json
```

### Metrics extracted:
```python
{
  "fsc_0143_resolution_A": 2.31,
  "total_wall_time_min": 387,
  "preprocessing_wall_time_min": 42,
  "classification_wall_time_min": 95,
  "refinement_wall_time_min": 180,
  "qc_gates_fired": 0,
  "qc_gates_passed": 23,
  "micrographs_accepted": 1081,
  "micrographs_rejected": 23,
  "particles_final": 289433,
  "gpu_hours": 6.45,
  "estimated_cost_usd": 3.22
}
```

---

## G10: Test Cases

### Unit tests (pytest)

```python
# tests/test_qc_gates.py

def test_fsc_gate_fires_on_poor_convergence():
    """FSC that never crosses 0.143 → GOLD halt"""
    fsc_data = make_fsc_data(values=np.ones(50) * 0.5)  # flat at 0.5, never drops
    # Patch so it drops at very low resolution
    fsc_data['fsc_nomask'][-1] = 0.10
    result = _check_fsc_gate_mock(fsc_data)
    assert result['action'] == 'halt'
    assert result['level'] == 'GOLD'

def test_fsc_gate_passes_good_reconstruction():
    fsc_data = make_realistic_fsc(resolution_A=2.2)  # crosses 0.143 at 2.2Å
    result = _check_fsc_gate_mock(fsc_data)
    assert result['action'] == 'pass'
    assert abs(result['resolution_A'] - 2.2) < 0.1

def test_junk_class_gate_halt():
    classes = make_class_data(n_classes=50, junk_fraction=0.75)
    result = _check_junk_gate_mock(classes)
    assert result['action'] == 'halt'

def test_junk_class_gate_advisory():
    classes = make_class_data(n_classes=50, junk_fraction=0.55)
    result = _check_junk_gate_mock(classes)
    assert result['action'] == 'advisory'

def test_preferred_orientation_halt():
    poses = make_biased_poses(anisotropy=15.0)  # strong preferred orientation
    result = _check_orientation_gate_mock(poses)
    assert result['action'] == 'halt'
    assert result['value'] > 10.0

def test_membrane_profile_relaxed_drift():
    """TRPV1-like: 65Å drift passes membrane profile, fails purified profile"""
    drift_A = 65.0
    purified = _check_drift_gate(drift_A, profile='cryoem_spa_purified')  # threshold 50
    membrane = _check_drift_gate(drift_A, profile='cryoem_spa_membrane')  # threshold 80
    assert purified['action'] == 'halt'
    assert membrane['action'] == 'pass'

def test_parallel_batch_split():
    """1000 micrographs → 5 batches of 200"""
    batches = _split_into_batches(list(range(1000)), batch_size=200)
    assert len(batches) == 5
    assert all(len(b) == 200 for b in batches)

def test_fsc_interpolation():
    freq = np.linspace(0.01, 0.5, 100)
    fsc  = np.linspace(1.0, 0.0, 100)   # linear drop
    res  = _fsc_to_resolution_mock(freq, fsc, threshold=0.143)
    # At threshold=0.143, freq should be ~0.143, so resolution ~7.0Å
    assert abs(res - 7.0) < 0.2
```

### Integration test plan

| Test | Dataset | Expected | Metric |
|------|---------|----------|--------|
| INT-1: Clean run | EMPIAR-10061 (100 mic) | All gates pass, FSC ≈ 2.2Å | resolution_A < 2.5 |
| INT-2: Drift failure | EMPIAR-10061 + injected drift | Motion gate halts at step 2 | halt_step == 'motion_correction' |
| INT-3: Membrane profile | EMPIAR-10005 (50 mic) | Default halts, membrane passes | profile_comparison correct |
| INT-4: Parallel speedup | EMPIAR-10061 (200 mic), 4 batches | Wall time ≤ serial/3.5 | speedup_ratio >= 3.0 |
| INT-5: Audit trail | Any run | JSONL written, all events present | len(audit_events) >= n_steps |

### Evaluation metrics for paper

| Metric | Measurement | Target |
|--------|-------------|--------|
| FSC resolution parity | BioMate vs expert CryoSPARC GUI, EMPIAR-10061 | Within 0.2Å |
| Expert time saved | Keyboard time: manual vs BioMate | ≥80% reduction |
| GPU compute saved (early halt) | GPU-hours at halt vs full pipeline | ≥85% at step 2 |
| False positive rate | Gates on clean datasets (EMPIAR-10061) | <5% |
| False positive elimination | Membrane profile on EMPIAR-10005 | Default halts, membrane passes |
| Speedup ratio | Wall time: parallel vs serial, same data | ≥3.5x on 4 GPUs |
| Audit completeness | Events per run vs expected | 100% |
| Non-expert completion | 5 participants, EMPIAR-10061 | ≥70% task completion |

---

## Implementation Order (parallel tracks)

### Track A — Core pipeline (cryosparc_executor.py)
1. Add all 23 job types as constants
2. Implement `_execute_spa_pipeline_sync` phases B, C, D
3. Add parallel batch submission with `ThreadPoolExecutor`
4. Wire QC gates G3/G4/G5 at correct steps

### Track B — Nextflow + config (main.nf)
1. Replace serial process chain with channel fan-out
2. Add `buffer(size: batch_size)` for preprocessing
3. Add `splitText` for particle batches
4. Update `nextflow.config` with `queueSize`

### Track C — QC gates (standalone module)
1. `backend/lib/galaxy/webapps/galaxy/api/cryosparc_qc_gates.py`
2. `_check_fsc_gate`, `_check_junk_gate`, `_check_orientation_gate`, `_check_ice_gate`
3. `_fire_qc_halt`, `_fire_qc_advisory`, `_write_audit_jsonl`

### Track D — Tests
1. `backend/tests/test_cryosparc_qc_gates.py`
2. `backend/tests/test_cryosparc_parallel.py`
3. `scripts/run_empiar_benchmark.sh`
4. `scripts/extract_benchmark_metrics.py`

---

## Implementation Status as of 2026-04-16

### Completed
- Full 23-step executor with parallel phases A/B/C/D (ThreadPoolExecutor)
- All QC gate functions (motion, CTF, junk, orientation, FSC, ice) with 30/30 unit tests
- main.nf refactor with channel fan-out + nextflow.config queueSize
- EMPIAR benchmark harness (run + extract scripts)
- Audit trail (JSONL per run)

### Remaining gaps

1. **QC gate output parser wiring** (in progress): After each CryoSPARC job, parse output fields and call the gate functions. Exact CryoSPARC-tools field names needed:
   - Motion: `micrographs_ctf[*].total_motion` → convert pixels to Å using pixel_size
   - CTF: `micrographs_ctf[*].ctf_fit_to_A` → normalize to quality score
   - 2D: `class_averages[*].num_particles` → junk fraction
   - Refine: `particles[*].alignments3D/pose` → orientation anisotropy
   - FSC: `fsc[*].freq_A_inv` + `fsc[*].fsc_nomask` → resolution at 0.143

2. **Benchmark runs** (needs live CryoSPARC + EMPIAR data): EMPIAR-10061, EMPIAR-10005 experiments as specified in evaluation protocol

3. **Expert comparison study**: 5-8 wet-lab biologists completing a run using BioMate vs CryoSPARC GUI (as described in paper plan Experiment 4)

4. **Paper writing**: Introduction, Methods, Results, Discussion sections need results from experiments 1-3

### Architecture diagram

Where QC gates fire in the pipeline:

```
Phase A → Motion + CTF jobs → [Motion gate] [CTF gate] → continue or HALT
Phase B → Junk 2D job → [Junk class gate] → continue or HALT
Phase D → Homo Refine → [Orientation gate] → continue or HALT
Phase D → Validation FSC → [FSC 0.143 gate] → continue or HALT
```

Each HALT event:
1. Stops downstream job submission (ThreadPoolExecutor future not submitted)
2. Emits SSE event to frontend with metric, threshold, evidence level, and suggested fix
3. Awaits explicit human decision (Override / Retry with new params / Abort)
4. Records decision in `{outdir}/qc_audit.jsonl` with timestamp, approver, justification

---

## Implementation Status as of 2026-04-16 (Session 2)

### Architecture diagram (updated — gates now fully wired)

```
Phase A → Motion + CTF jobs → [Motion gate G1] [CTF gate G2] → continue or HALT
Phase B → Junk 2D job       → [Junk class gate G4]           → continue or HALT
Phase D → Ab initio         → [Ab initio quality gate G9]    → continue or HALT
Phase D → Homo Refine       → [Orientation gate G5]          → continue or HALT
Phase D → Validation FSC    → [FSC 0.143 gate G3]            → continue or HALT
Phase D → NU Refine         → [3DVA job, if use_3dva=True]   → non-fatal, continues
Phase D → NU Refine         → [Multi-body advisory, if HIGH] → advisory only
Phase D → Sharpening        → [MolProbity gate G12]          → advisory + reminder
```

### Completed this session (Session 2)
- G3 FSC gate: `check_fsc_gate()` + `_check_fsc_gate_from_job()` — correct Dataset API field names (`fsc["freq_A_inv"]`, `fsc["fsc_nomask"]`)
- G4 junk class gate: `check_junk_class_gate()` + `_check_junk_gate()` — `class_averages["class_num_particles"]`
- G5 orientation gate: `check_orientation_gate()` + `_check_orientation_gate_from_job()` — `particles["alignments3D/pose"]` rotation vectors → theta, Fibonacci-sphere anisotropy
- G9 ab initio quality gate: `check_abinitio_gate()` — BRONZE evidence, 3 halt conditions (map_mass, symmetry_mismatch, resolution_divergence) + 2 advisory conditions
- G12 MolProbity gate: `check_model_quality_gate()` — GOLD evidence (PDB deposition standard), advisory + reminder to run phenix.molprobity externally
- Smart params: `_resolve_smart_params()` — box size from pixel size + expected diameter, count from resolution target, heterogeneity depth (num_ab_initio_classes: 1/3/6), CTF level, symmetry discipline
- AI rationale: `_build_cryoem_rationale()` in ai_assistant.py — sample class detection (purified/membrane/VLP/complex/cell) + 4 bug fixes
- Tests: 181/181 passing (test_cryosparc_qc_gates.py: 46, test_cryosparc_smart_params.py: 112, test_cryoem_rationale.py: 23)
- 3DVA wiring in Phase D (this session): `var_3D` job submitted after NU refinement when `use_3dva=True`; non-fatal (pipeline continues on failure); connected to `nu_refine_job` particles + volume
- Multi-body advisory in Phase D (this session): `use_multibody=True` emits `qc_advisory` SSE with GUI instructions; no job submitted (masks require human GUI interaction per GENERAL_FRAMEWORK V4)

### Remaining
- Pre-cryo-EM G1-G5 advisory guidance in AI chat (proactive sample prep hints before pipeline launch)
- EMPIAR benchmark runs: EMPIAR-10061, 10005, 10017, 10028 (needs live CryoSPARC + EMPIAR staging)
- Paper writing: Introduction + Methods sections ready to draft; Results pending benchmark numbers from live runs
