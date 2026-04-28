# CryoEM Auto-Loop Architecture

**Date:** 2026-04-16  
**Status:** Prototype complete (76/76 tests passing); production wiring designed but not yet merged  
**Location:** `backend/experiments/cryo_em_autoloop/`

---

## 1. What Problem This Solves

The existing CryoSPARC Standard SPA workflow in BioMate already detects when data is
bad — `QCHaltException` fires when a gate fails in `cryosparc_executor.py`.
But it does exactly one thing: stop the run, set `status = "qc_halt"`, and wait for a
human to look at the audit log and re-submit with adjusted parameters.

That is the entire manual loop.

The auto-loop replaces the human in that loop for all failure modes that have a
well-understood algorithmic remediation. A human is only paged when:
- Max retries are exhausted (true escalation), or
- The gate has no automated fix (e.g. physical lens astigmatism)

Inspired by the AI Scientist (Sakana AI, Nature 2026 — DOI: 10.1038/s41586-026-10265-5).

---

## 2. Pipeline Overview

The SPA pipeline is divided into 5 sequential phases. Each phase has its own QC gates
and a dedicated set of tunable parameters.

```
 User submits CryoEM run
          │
          ▼
 ┌─────────────────────────────────────────────────────────────────────┐
 │  CryoEMAutoLoop.run(phase_runner_fn)                                │
 │                                                                     │
 │  ┌── phase_A ──────────────────────────────────────────────────┐   │
 │  │  Motion correction + CTF estimation                         │   │
 │  │  MetricsExtractor → QCEvaluator → ParamTuner               │   │
 │  │  Retry up to max_retries times with adjusted params         │   │
 │  └────── pass ──────────────────────────────────────────────── ┘   │
 │                          │                                          │
 │  ┌── phase_B ────────────▼─────────────────────────────────────┐   │
 │  │  Particle picking + extraction                              │   │
 │  └─────────────────────────────────────────────────────────────┘   │
 │                          │                                          │
 │  ┌── phase_C ────────────▼─────────────────────────────────────┐   │
 │  │  2D classification (orientation anisotropy check)           │   │
 │  └─────────────────────────────────────────────────────────────┘   │
 │                          │                                          │
 │  ┌── phase_D ────────────▼─────────────────────────────────────┐   │
 │  │  Ab-initio 3D + homogeneous refinement                      │   │
 │  └─────────────────────────────────────────────────────────────┘   │
 │                          │                                          │
 │  ┌── phase_E ────────────▼─────────────────────────────────────┐   │
 │  │  FSC validation (final map resolution check)                │   │
 │  └─────────────────────────────────────────────────────────────┘   │
 └─────────────────────────────────────────────────────────────────────┘
          │
          ▼
   LoopResult (phases_passed, phases_escalated, audit_path)
```

---

## 3. Modules and Responsibilities

### 3.1 `params.py` — `CryoEMParams`

All 25 tunable parameters in a single dataclass. Each phase owns a subset:

| Phase   | Parameters it controls |
|---------|------------------------|
| phase_A | `micrograph_batch_size`, `motion_correction_dose_weighting`, `dose_per_frame`, `ctf_fitting_resolution_min/max` |
| phase_B | `particle_diameter_angstroms`, `particle_box_size`, `blob_picker_min/max_diameter` |
| phase_C | `num_2d_classes`, `class2d_similarity_threshold`, `class2d_iterations`, `particle_batch_size` |
| phase_D | `num_ab_initio_classes`, `max_resolution_refinement`, `symmetry` |
| phase_E | *(none — driven by upstream; FSC failure triggers upstream re-run)* |

`CryoEMParams.copy()` returns a deep copy so remediations never mutate in-flight state.

---

### 3.2 `simulation.py` — `SimulatedCryoSPARCJob` and `ScenarioRunner`

Produces **numpy-array job outputs** in exactly the same format as the real
`cryosparc.tools` API. This lets the full extraction → evaluation → remediation
pipeline be tested without a live CryoSPARC instance.

Real CryoSPARC API (from `cryosparc_executor.py:587–640`):
```python
job.load_output("micrographs")["total_motion"]          # numpy array (N,) pixels
job.load_output("micrographs")["ctf/cross_corr_ctffind"] # numpy array (N,) 0–1
job.load_output("class_averages")["class_num_particles"] # numpy array (K,) counts
job.load_output("particles")["alignments3D/pose"]        # numpy array (N,3) rotations
job.load_output("class_scores")["class_score"]           # numpy array (K,) floats
job.load_output("fsc")["freq_A_inv"]                     # numpy array frequencies
job.load_output("fsc")["fsc_nomask"]                     # numpy array 0–1
```

`ScenarioConfig` lets you set per-attempt parameter progressions, e.g.:
```python
config = ScenarioConfig(
    drift_per_attempt=[90.0, 20.0],   # attempt 0: bad drift; attempt 1: fixed
    ctf_fom_per_attempt=[0.85, 0.88],
)
```

---

### 3.3 `metrics_extractor.py` — `MetricsExtractor`

The **critical bridge** between raw job objects and the scalar metrics the
evaluator uses. Works with both simulated jobs and real `cryosparc.tools` Jobs —
they share the same `load_output()` interface.

```
list[Job] → MetricsExtractor → dict[str, float] → CryoEMQCEvaluator
```

What it computes per phase:

| Phase   | Columns read | Output metrics |
|---------|-------------|----------------|
| phase_A | `total_motion` (px), `average_motion` (px), `ctf/cross_corr_ctffind`, `ctf/ctf_fit_to_A`, `ctf/df1_A`, `ctf/df2_A` | `mean_total_drift_A`, `mean_per_frame_drift_A`, `mean_ctf_fit_quality`, `mean_astigmatism_A` |
| phase_B | `class_num_particles` | `junk_fraction`, `num_particles_selected` |
| phase_C | `alignments3D/pose` (N×3) | `orientation_anisotropy` (sin-weighted polar angle bins) |
| phase_D | `class_score` | `best_abinitio_class_score`, `best_abinitio_resolution_A` (proxy) |
| phase_E | `freq_A_inv`, `fsc_nomask` | `fsc_resolution_A` (FSC 0.143 criterion, interpolated) |

All multi-batch jobs are concatenated before computing medians (not means —
medians are robust to a few catastrophically bad micrographs without losing
the central tendency).

**Orientation anisotropy detail:** Uses sin-weighted theta bins. A perfectly
isotropic dataset gives ~1.0; preferred-orientation datasets give 2–4×. The QC
halt threshold is 10× (configurable per profile), so the gate only fires on
severe preferred orientation.

---

### 3.4 `qc_evaluator.py` — `CryoEMQCEvaluator`

Evaluates scalar metrics against profile thresholds and returns structured
`PhaseQCResult` objects.

**Three threshold profiles:**

| Profile | Drift limit | CTF FOM min | Junk halt | Anisotropy halt |
|---------|-------------|-------------|-----------|-----------------|
| `cryoem_spa_purified` | 50 Å | 0.70 | 70% | 10× |
| `cryoem_spa_membrane` | 80 Å | 0.65 | 75% | 15× |
| `cryoem_spa_phase_plate` | 50 Å | 0.65 | 70% | 10× |

**Gate action levels:**
- `PASS` — within acceptable range (GOLD/SILVER QC level)
- `ADVISORY` — between advisory band and halt threshold (BRONZE) — pipeline continues
- `HALT` — above halt threshold (FAIL) — triggers retry/remediation

A `PhaseQCResult` passes only if all gates pass or advisory. Any HALT fails
the phase.

---

### 3.5 `param_tuner.py` — `ParamTuner`

Maps each HALT gate to a specific parameter change. One remediation rule per gate:

| Gate | What changes | Why |
|------|-------------|-----|
| `motion_drift` | `micrograph_batch_size ÷ 2` (min 50), `dose_weighting=True` | Smaller batches improve patch-motion alignment |
| `per_frame_drift` | `micrograph_batch_size ÷ 2` | Same — reduces inter-frame motion |
| `ctf_fit_quality` | `ctf_fitting_resolution_min → 30 Å`, `max → 3 Å` | More Thon rings in fit window |
| `astigmatism` | *(advisory only — no param fix)* | Physical lens issue; operator must inspect |
| `junk_fraction` | `particle_diameter_angstroms × 0.9` | Tighter diameter = better picker selectivity |
| `particle_yield` | `blob_picker_min_diameter × 0.8` | Looser minimum = capture smaller/fainter particles |
| `orientation_anisotropy` | `symmetry = "C1"`, `num_2d_classes → 150` | Avoid inflating symmetry; more classes = better orientation sampling |
| `abinitio_class_score` | `num_ab_initio_classes + 2` (max 8) | More classes = better compositional separation |
| `abinitio_resolution` | `max_resolution_refinement + 1.0 Å` | Relaxes convergence criterion |

Rules are deterministic and stackable — multiple HALT gates in the same phase
each apply their fix to the running parameter copy.

---

### 3.6 `orchestrator.py` — `CryoEMAutoLoop`

The main retry loop:

```
for phase in [A, B, C, D, E]:
    for attempt in 1..(max_retries + 1):
        jobs  = phase_runner_fn(phase, current_params)   ← execute
        metrics = MetricsExtractor.extract(phase, jobs)   ← extract
        qc    = CryoEMQCEvaluator.evaluate_phase(metrics) ← evaluate
        log_attempt(phase, attempt, params, qc, remeds)   ← audit
        if qc.passed → break → move to next phase
        new_params, remeds = ParamTuner.remediate(qc, params)
        current_params = new_params
    else:
        → phase escalated (human notified)
```

`LoopResult` reports:
- `phases_passed` — list of phases that passed (possibly after retries)
- `phases_escalated` — phases that exhausted retries
- `total_attempts` — total CryoSPARC job executions across all phases
- `audit_path` — JSONL file path (every attempt, every gate, every change)
- `summary_path` — human-readable text report

---

### 3.7 `audit_logger.py` — `AuditLogger`

Writes two files per run:

**`{run_id}_audit.jsonl`** — one JSON line per event:
```json
{"ts": "2026-04-16T10:23:01+00:00", "run_id": "...", "event": "attempt",
 "phase": "phase_A", "attempt": 1,
 "params": {"micrograph_batch_size": 200, ...},
 "gate_results": [{"gate": "motion_drift", "action": "halt", "value": 82.3, "threshold": 50.0}, ...],
 "remediations": [{"gate": "motion_drift", "param_changes": {"micrograph_batch_size": 100}, "rationale": "..."}],
 "outcome": "halt"}

{"ts": "...", "event": "phase_final", "phase": "phase_A", "total_attempts": 2, "outcome": "pass"}
```

**`{run_id}_summary.txt`** — human-readable per-phase breakdown with pass/fail marks
and all parameter changes.

---

## 4. Test Coverage

| File | Tests | Coverage |
|------|-------|---------|
| `tests/test_autoloop.py` | 23 | Unit tests: `CryoEMParams`, `QCEvaluator`, `ParamTuner`, `AuditLogger`, `CryoEMAutoLoop` with `MockPhaseRunner` |
| `tests/test_simulation_integration.py` | 30 | Integration: `MetricsExtractor` (all phases), `ScenarioRunner → Extractor → Evaluator`, full orchestrator with `SimulatedPhaseRunner` |
| **Total** | **53** | **53/53 passing** |

The integration tests validate the *complete realistic pipeline*:

```
ScenarioRunner        MetricsExtractor      CryoEMQCEvaluator   CryoEMAutoLoop
(numpy job outputs) → (median aggregation) → (gate evaluation) → (retry loop)
```

The same `MetricsExtractor` and `CryoEMAutoLoop` code will be used in production;
only `ScenarioRunner` is replaced by real CryoSPARC job calls.

---

## 5. Production Wiring Plan

### 5.1 Where the hook goes in `cryosparc_executor.py`

Currently at line 1100:
```python
# CURRENT CODE (no retry)
except QCHaltException as exc:
    run.status = "qc_halt"
    run.error_message = str(exc)
    run.finished_at = time.time()
    # … auto-stop after 5 min
```

**Proposed replacement** (the key change is catching `QCHaltException` differently
inside `_execute_spa_pipeline_sync` rather than in the thread wrapper, and calling
the loop there):

```python
# PROPOSED: wrap _execute_spa_pipeline_sync in a per-phase retry loop

from cryo_em_autoloop import CryoEMAutoLoop, CryoEMParams, MetricsExtractor

def _execute_spa_with_autoloop(run, progress_callback):
    params = CryoEMParams(
        pixel_size=run.params.get("pixel_size", 1.05),
        micrograph_batch_size=run.params.get("micrograph_batch_size", 200),
        # … map all run.params → CryoEMParams fields
    )
    qc_profile = run.params.get("qc_profile", "cryoem_spa_purified")
    loop = CryoEMAutoLoop(
        run_id=run.run_id,
        params=params,
        qc_profile=qc_profile,
        max_retries_per_phase=2,
        output_dir=run.audit_dir,
    )
    extractor = MetricsExtractor(pixel_size=params.pixel_size)

    def real_phase_runner(phase: str, current_params: CryoEMParams) -> dict:
        """Executes one phase on the live CryoSPARC instance."""
        cs_jobs = _run_cryosparc_phase(run, current_params, phase, progress_callback)
        return extractor.extract(phase, cs_jobs)

    result = loop.run(real_phase_runner)
    _emit_loop_result_to_frontend(run, result, progress_callback)
```

The internal function `_run_cryosparc_phase` would call the existing
`_check_motion_ctf_gates`, `_check_picking_gates`, etc. but return the job objects
instead of raising `QCHaltException` — the gate evaluation is now done by the loop,
not inline.

### 5.2 Two wiring strategies

**Strategy A — Replace gate fire with job return (preferred)**

Refactor `_check_motion_ctf_gates()` and siblings:
- Instead of calling `_fire_qc_halt()` internally, return the job list
- Let `MetricsExtractor + CryoEMQCEvaluator` do the evaluation
- This makes the gate logic testable in isolation and the retry loop clean

**Strategy B — Wrap existing halt (faster to ship)**

Keep `_fire_qc_halt` / `QCHaltException` in place.  
Catch `QCHaltException` in the phase runner, extract gate identity from the
exception message, look up the remediation rule from `ParamTuner`, apply it to
params, and re-run. This is 1 file change but less clean.

Recommendation: **Strategy A** for the full implementation; **Strategy B** for a
fast pilot.

---

## 6. UX Wiring

This is the most important part — the auto-loop needs to be visible and controllable
in the frontend.

### 6.1 New SSE event type: `autoloop_update`

The existing progress callback `cb(progress_percent, json_message)` already streams
SSE events to the frontend. The auto-loop adds a new event type:

```json
{
  "type": "autoloop_update",
  "phase": "phase_A",
  "attempt": 2,
  "outcome": "halt",
  "gate": "motion_drift",
  "value": 82.3,
  "threshold": 50.0,
  "message": "Mean total drift 82.3 Å (limit 50 Å)",
  "param_changes": {"micrograph_batch_size": 100, "motion_correction_dose_weighting": true},
  "rationale": "Reduced batch size 200→100 and enabled dose_weighting to improve frame alignment stability.",
  "total_attempts_used": 2,
  "phases_remaining": ["phase_B", "phase_C", "phase_D", "phase_E"]
}
```

And when a phase escalates:
```json
{
  "type": "autoloop_escalation",
  "phase": "phase_A",
  "total_attempts": 3,
  "gates_failed": ["motion_drift", "per_frame_drift"],
  "message": "Phase A could not be resolved after 3 attempts. Human review required.",
  "audit_url": "/api/cryo/runs/{run_id}/audit"
}
```

### 6.2 Frontend component: `AutoLoopStatusPanel`

A new panel shown inside the existing `CryoEMWorkflowViewer` (right panel) while a
run is active. Structure:

```
┌─ CryoEM Run: P1-R42 ──────────────────────────────────────────────┐
│  Status: running  [QC Profile: Purified Protein]                   │
│                                                                    │
│  ┌── Auto-Loop Status ──────────────────────────────────────────┐  │
│  │  Phase A  [● Attempt 2/3]  ←── spinner while running        │  │
│  │                                                              │  │
│  │  Retry triggered:                                            │  │
│  │  ⚠ motion_drift: 82.3 Å exceeded 50 Å limit                 │  │
│  │  → micrograph_batch_size: 200 → 100                         │  │
│  │  → dose_weighting: enabled                                   │  │
│  │                                                              │  │
│  │  Phase B  [○ Waiting]                                        │  │
│  │  Phase C  [○ Waiting]                                        │  │
│  │  Phase D  [○ Waiting]                                        │  │
│  │  Phase E  [○ Waiting]                                        │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                                                                    │
│  [Pause Auto-Loop]   [Override Params]   [View Audit Log]          │
└────────────────────────────────────────────────────────────────────┘
```

Phase icons:
- `●` spinning = currently running
- `✓` green = passed (with attempt count if > 1)
- `!` yellow = passed after retries
- `⚡` red = escalated

### 6.3 Chat message integration

When the auto-loop fires a remediation, the AI assistant should post a
non-blocking chat message:

> **Auto-Loop:** Phase A attempt 1 failed QC — mean drift 82.3 Å exceeded 50 Å limit.
> Automatically reducing batch size (200→100) and enabling dose weighting. Retrying...

When escalation occurs:
> **Auto-Loop:** Phase A exhausted 3 attempts without passing QC. Gates still failing:
> drift 78 Å (limit 50 Å). The run will continue from Phase B, but Phase A metrics
> may affect final map quality. [View audit log →]

This is generated server-side (no LLM call needed — it's a template fill from the
`Remediation` and `PhaseQCResult` objects) and pushed via the existing SSE stream.

### 6.4 User controls

Three controls are available at any time during a run:

| Control | Backend API | Behavior |
|---------|------------|----------|
| **Pause Auto-Loop** | `POST /api/cryo/runs/{id}/autoloop/pause` | After current phase completes, waits for user confirmation before the next attempt |
| **Override Params** | `POST /api/cryo/runs/{id}/autoloop/params` | Injects a `CryoEMParams` override for the next attempt (bypasses `ParamTuner`) |
| **View Audit Log** | `GET /api/cryo/runs/{id}/audit` | Returns the JSONL audit trail (rendered as a timeline in a modal) |

### 6.5 Post-run audit view

After completion, the `CryoEMWorkflowViewer` shows a collapsible **Auto-Loop Report**
section, which is the summary text from `AuditLogger.write_summary_report()` rendered
as a structured timeline:

```
Phase A  [PASSED — 2 attempts]
  Attempt 1:  ✗ motion_drift (82.3 Å > 50 Å)
              → batch_size: 200 → 100, dose_weighting: on
  Attempt 2:  ✓ all gates passed (drift 24.1 Å)

Phase B  [PASSED — 1 attempt]
  Attempt 1:  ✓ junk fraction 22%, particles 84,000

Phase C  [PASSED — 1 attempt]
Phase D  [PASSED — 1 attempt]
Phase E  [PASSED — 1 attempt]  FSC 0.143 = 4.2 Å (GOLD)
```

---

## 7. Current State vs Production Gap

| Component | Status | Gap |
|-----------|--------|-----|
| `CryoEMParams` | ✅ Complete | Map to `run.params` dict |
| `MetricsExtractor` | ✅ Complete | Import into `cryosparc_executor.py` |
| `CryoEMQCEvaluator` | ✅ Complete | Replace inline gate checks |
| `ParamTuner` | ✅ Complete | Call from exception handler |
| `AuditLogger` | ✅ Complete | Wire to run's `audit_dir` |
| `CryoEMAutoLoop` | ✅ Complete | Wrap `_execute_spa_pipeline_sync` |
| `SimulatedPhaseRunner` | ✅ Complete (tests only) | — |
| SSE event `autoloop_update` | ❌ Not yet | Add to `_fire_qc_halt` / callback |
| `AutoLoopStatusPanel` (frontend) | ❌ Not yet | New React component |
| Chat message on retry | ❌ Not yet | Template in `ai_assistant.py` |
| Pause / Override controls | ❌ Not yet | New API endpoints + React state |
| Audit timeline view | ❌ Not yet | Modal + JSONL renderer |

The backend loop itself is one file integration (`cryosparc_executor.py` ~line 1100).
The UX work (SSE events, panel component, chat messages) is the larger chunk.

---

## 8. Files

```
backend/experiments/cryo_em_autoloop/
├── __init__.py              — package exports
├── params.py                — CryoEMParams (25 fields), PHASE_PARAM_OWNERS
├── simulation.py            — SimulatedCryoSPARCJob, ScenarioRunner, factory fns
├── metrics_extractor.py     — MetricsExtractor (numpy arrays → scalar dicts)
├── qc_evaluator.py          — CryoEMQCEvaluator, QC_PROFILES, GateResult
├── param_tuner.py           — ParamTuner, Remediation (9 gate handlers)
├── orchestrator.py          — CryoEMAutoLoop, LoopResult, MockPhaseRunner
├── audit_logger.py          — AuditLogger (JSONL + summary text)
└── tests/
    ├── test_autoloop.py              — 23 unit tests
    └── test_simulation_integration.py — 30 integration tests
```

Reference implementation in production code:
```
backend/lib/galaxy/webapps/galaxy/api/cryosparc_executor.py
  line 533  — QCHaltException, _fire_qc_halt, _fire_qc_advisory
  line 587  — _check_motion_ctf_gates (currently raises inline)
  line 1100 — catch QCHaltException → status = "qc_halt"  ← wiring point
```
