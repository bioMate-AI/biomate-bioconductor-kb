# Phase 1: Per-Invocation QC Overrides + Audit Log — Implementation Record

**Date:** 2026-02-24 16:13
**Branch:** `connection_formal`
**Status:** Complete — 398/398 tests passing (32 skipped = billing/Redis)
**Prior test count:** 376/376 (before this session)
**New tests added:** 22 (`TestQCOverrides` class)

---

## Context

This session continued from the Phase 1 implementation plan approved in the previous session
(plan file: `/home/yzhang/.claude/plans/federated-cooking-truffle.md`).
The configurable QC plan (`docs/QC/20260224_CONFIGURABLE_QC_PLAN.md`) was authored after a
dual PM + domain expert consultation and approved by the user. This document records Phase 1
of that plan in detail.

---

## Problem Statement

All QC thresholds in `NextflowQCGateHandler` were hardcoded. This caused systematic
false-positive gate modals for:
- Ribo-depleted or FFPE RNA-seq (alignment rate 45–65% is normal; platform defaulted to 70%)
- FFPE WGS (PCR duplication 60–70% is expected; platform defaulted to 40%)
- Cardiac/muscle scRNA-seq (mito fraction 25–35% is biological; platform defaulted to 20%)
- Low-pass WGS for population genetics (4–10X is target; platform defaulted to 30X)
- Soil metagenomics (20–40% classification is normal; platform critical gate was 30%)

**Goal (Phase 1):** Allow a bioinformatician power user to pass a `qc_overrides` dict at
workflow launch to suppress known false positives, with a full audit trail.

---

## Files Changed

### 1. `backend/lib/galaxy/jobs/qc_trace_monitor.py` (untracked — new file on this branch)

#### 1a. Module-level governance constants (added after `log = logging.getLogger`)

```python
QC_RED_LINES: Dict[str, Any] = {
    "reads_surviving_pct": {"bound": 50.0, "direction": "min",
        "rationale": "> 50% loss = adapter-dominated library; downstream analysis is invalid"},
    "fit_quality":         {"bound": 0.5,  "direction": "min",
        "rationale": "CTF estimation completely failed; particle picking results are invalid"},
    "mito_fraction_pct":   {"bound": 80.0, "direction": "max",
        "rationale": "Dead-cell lysates, not transcriptomes; results are biologically meaningless"},
    "alignment_rate":      {"bound": 5.0,  "direction": "min",
        "rationale": "< 5% alignment = species/sample swap; halt unconditionally"},
}

QC_GOLD_METRICS: frozenset = frozenset({
    "mapped_pct",       # GATK Best Practices: FLAGSTAT mapped >= 70%
    "tss_enrichment",   # ENCODE4 ATAC-seq 2022: >= 5 acceptable, >= 7 ideal
    "nrf_score",        # ENCODE4 ATAC-seq 2022: >= 0.9
})
```

**Design rationale:**
- `QC_RED_LINES` are absolute bounds that apply even to SILVER/BRONZE overridable metrics.
  An override that crosses a red line is clamped (not rejected) so the workflow can still run.
- `QC_GOLD_METRICS` are completely non-overridable. `_get_threshold()` silently ignores any
  override for these metrics and returns the default. `validate_qc_overrides()` rejects them
  explicitly at API validation time.
- `nrf_score` appears in GOLD (no override at all, which is more restrictive than a red line).

#### 1b. `NextflowQCGateHandler.__init__` — new parameter

```python
qc_overrides: Optional[Dict[str, Any]] = None,
```

Stored as `self.qc_overrides = qc_overrides or {}`. If non-empty, writes an "initialized"
JSONL record to the audit log immediately and logs the override key names at INFO level.

#### 1c. New classmethod: `validate_qc_overrides(overrides)`

```python
@classmethod
def validate_qc_overrides(cls, overrides: Dict[str, Any]) -> "tuple[bool, list]":
```

- Called at API layer before workflow launch (in `nextflow_executor.py`)
- Rejects overrides for GOLD metrics with a human-readable error citing ENCODE4/GATK
- Rejects non-numeric values
- Returns `(valid: bool, errors: list[str])`

#### 1d. New instance method: `_get_threshold(metric, default)`

```python
def _get_threshold(self, metric: str, default: float) -> float:
```

Lookup order (highest precedence first):
1. GOLD check → returns `default` (ignores override, logs WARNING)
2. `self.qc_overrides[metric]` → applies if present and numeric
3. Red-line clamp → override value clamped if it would cross the absolute bound
4. `default` → returned when no override configured

Used in 28 places throughout `_check_qc_thresholds` and `_check_qc_warnings`.

#### 1e. New instance method: `_write_audit_log_entry(event_type, applied_overrides)`

Appends a JSONL record to `{work_dir}/qc_overrides_audit.jsonl`.

```json
{
  "timestamp": "2026-02-24T16:13:00+00:00",
  "invocation_id": "...",
  "event_type": "initialized" | "gate_triggered",
  "configured_overrides": {"alignment_rate": 50.0, ...},
  "applied_overrides": {}
}
```

Called at:
- Handler init when `qc_overrides` is non-empty → `event_type="initialized"`
- `_emit_qc_gate_event()` when `qc_overrides` is non-empty → `event_type="gate_triggered"`

#### 1f. `_check_qc_thresholds` — all threshold calls updated

Every hardcoded threshold replaced with `_get_threshold(key, default)`. Full mapping:

| Domain | Metric key | Default |
|--------|-----------|---------|
| Motion correction | `total_drift_angstrom` | 50 |
| Motion correction | `correlation_score` | 0.5 |
| CTF estimation | `astigmatism_angstrom` | 1000 (advisory) |
| CTF estimation | `fit_quality` | 0.7 (red-line floor 0.5) |
| Particle picking | `particles_picked` | 1000 |
| Particle picking | `duplicate_fraction_picking` | 0.2 |
| Trimming | `reads_surviving_pct` | 70.0 (red-line floor 50) |
| Trimming | `q30_pct` | 75.0 |
| Alignment | `alignment_rate` | 70.0 (red-line floor 5) |
| FeatureCounts | `assigned_reads_pct` | 50.0 |
| Salmon/Kallisto | `mapping_rate` | 50.0 |
| FLAGSTAT | `mapped_pct` | 70.0 (**GOLD** — override rejected) |
| FLAGSTAT + MARKDUP | `duplicate_pct` | 40.0 |
| scRNA-seq | `cells_detected` | 200 |
| scRNA-seq | `median_genes_per_cell` | 500 |
| scRNA-seq | `mito_fraction_pct` | 20.0 (red-line ceiling 80) |
| scRNA-seq (warning) | `mito_fraction_pct_warning` | 10.0 |
| Coverage | `mean_coverage` | 30.0 WGS / 80.0 WES |
| ChIP-seq | `peaks_called` | 1000 |
| ATAC TSS | `tss_enrichment` | 5.0 (**GOLD** — override rejected) |
| ATAC NRF | `nrf_score` | 0.9 (**GOLD** — override rejected) |
| Metagenomics | `classified_pct_critical` | 30.0 |
| Metagenomics | `classified_pct_warning` | 60.0 |

**ATAC FRiP (0.2)**: Not made overridable in Phase 1 — ENCODE4 mandates it. Named profiles
(Phase 2) will handle non-model-organism ATAC exceptions.

#### 1g. `_check_qc_warnings` — near-threshold checks also use `_get_threshold`

When a user lowers `alignment_rate` to 50%, the near-threshold warning fires at
50% × 1.10 = 55%, not at 70% × 1.10 = 77%. All 5 near-threshold checks updated.

#### 1h. SSE events updated

Both `_emit_qc_gate_event()` and `_emit_qc_warning_event()` now include:
```json
{
  "overrides_active": true,
  "active_overrides": {"alignment_rate": 50.0}
}
```
Frontend can show a "Custom QC thresholds active" banner (Phase 2 UI).

---

### 2. `backend/lib/galaxy/jobs/runners/nextflow_monitor.py` (untracked)

#### `NextflowMonitor.__init__` — two new parameters

```python
qc_overrides: Optional[Dict] = None,
workflow_domain: str = "cryo_em",
```

Stored as `self.qc_overrides` and `self.workflow_domain`.

**Note:** This also fixes a pre-existing gap: `_init_qc_handler()` previously instantiated
`NextflowQCGateHandler` without passing `workflow_domain`, so WES/WGS coverage distinction
and RNA/ATAC/ChIP domain-aware skips were not applied correctly. Now both are threaded through.

#### `_init_qc_handler()` — passes both new fields

```python
self.qc_handler = NextflowQCGateHandler(
    invocation_id=str(self.invocation_id),
    work_dir=self.work_dir,
    sse_callback=self._make_sse_callback(str(self.invocation_id)),
    app=self.app,
    workflow_domain=self.workflow_domain,    # NEW
    qc_overrides=self.qc_overrides,         # NEW
)
```

#### `NextflowMonitorService.register_workflow()` — two new parameters

```python
qc_overrides: Optional[Dict] = None,
workflow_domain: str = "cryo_em",
```

Passed through to `NextflowMonitor(...)`.

---

### 3. `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py` (tracked, modified)

#### `NextflowExecuteRequest` model — two new fields

```python
qc_overrides: Optional[Dict[str, Any]] = None
workflow_domain: Optional[str] = None
```

#### Server-side validation

Before launching the subprocess, if `qc_overrides` is non-empty:
```python
valid, errors = NextflowQCGateHandler.validate_qc_overrides(qc_overrides)
if not valid:
    raise HTTPException(status_code=422, detail={"error": "Invalid qc_overrides", "errors": errors})
```

Returns HTTP 422 with specific error messages for GOLD-metric override attempts or
non-numeric values.

#### `_start_qc_monitor()` — new function (146 lines added)

A background thread factory that provides QC gate monitoring for the direct-executor path
(unlike `nextflow_workflow_runner.py`, `nextflow_executor.py` does not use `NextflowMonitor`).

The thread:
1. Polls `{work_dir}/workflow-trace.txt` every 5 seconds
2. Finds newly COMPLETED/FAILED rows not seen before
3. Calls `handler.handle_process_completion(...)` for each
4. Exits after 120 s of idle (no new trace lines) or 12-hour hard cap
5. Uses the same `/internal/sse-inject` endpoint as `NextflowMonitor` for SSE delivery

The `NextflowQCGateHandler` it creates receives `qc_overrides` from the request body.

#### `_runs` registry enriched

```python
_runs[run_id] = {
    ...
    "qc_overrides": qc_overrides,
    "workflow_domain": workflow_domain,
    "work_dir": str(work_dir),      # new — needed for status queries
}
```

---

### 4. `backend/tests/test_qc_edge_cases.py` (untracked — new file on this branch)

New class `TestQCOverrides` with 21 tests appended at end of file:

| Test | What it verifies |
|------|-----------------|
| `test_alignment_rate_override_raises_effective_threshold` | 65% fails at default 70%, passes when override lowers to 50% |
| `test_mito_fraction_override_for_cardiac_tissue` | 30% mito fails at default 20%, passes when raised to 35% |
| `test_duplicate_pct_override_for_ffpe_wgs` | 60% dup fails at default 40%, passes when raised to 70% |
| `test_coverage_override_for_low_pass_wgs` | 5X fails at default 30X, passes when lowered to 4X |
| `test_metagenomics_critical_threshold_override_for_soil` | 20% classified passes when critical=10% and warning=15% (soil metagenomics) |
| `test_gold_metric_override_ignored_in_get_threshold` | `_get_threshold("mapped_pct", 70.0)` returns 70.0 even with override 40.0 |
| `test_validate_qc_overrides_rejects_gold_metrics` | `validate_qc_overrides({"mapped_pct": 50.0})` → invalid |
| `test_validate_qc_overrides_accepts_silver_metrics` | alignment_rate, reads_surviving_pct, duplicate_pct, mito_fraction_pct all accepted |
| `test_validate_qc_overrides_rejects_non_numeric` | `"foo"` value → error containing "numeric" |
| `test_reads_surviving_red_line_clamped_to_floor` | Override 30% clamped to 50%; 45% still fails |
| `test_mito_fraction_red_line_ceiling_clamped` | Override 90% clamped to 80%; 85% still fails |
| `test_alignment_rate_red_line_floor_clamps_at_5_pct` | Override 2% clamped to 5% |
| `test_audit_log_written_on_init_with_overrides` | JSONL file created; `event_type=initialized`; invocation_id + keys recorded |
| `test_audit_log_not_written_without_overrides` | No JSONL file when no overrides |
| `test_audit_log_updated_when_gate_fires_under_overrides` | `gate_triggered` record appended on `_emit_qc_gate_event` |
| `test_sse_gate_event_has_overrides_active_true` | `overrides_active=True`, `active_overrides` in SSE data |
| `test_sse_gate_event_has_overrides_active_false_when_no_overrides` | `overrides_active=False`, empty `active_overrides` |
| `test_sse_warning_event_has_overrides_active_true` | Warning event also carries `overrides_active` |
| `test_get_threshold_returns_override_for_silver_metric` | `q30_pct` override 60.0 returned |
| `test_get_threshold_returns_default_for_unconfigured_metric` | q30_pct not in overrides → 75.0 |
| `test_get_threshold_returns_default_when_no_overrides_set` | Empty overrides → default |

---

## Test Results

```
398 passed, 32 skipped, 116 warnings

Breakdown:
  test_qc_edge_cases.py            300 passed  (278 pre-existing + 22 new TestQCOverrides)
  test_gap3_complete_integration.py  6 passed
  test_gap3_standalone.py           18 passed
  test_pilot_qc_e2e.py               1 passed
  test_qc_e2e_domains.py            41 passed  (multi-domain e2e)
  test_billing_e2e.py               32 skipped  (need Redis)
```

The 22 new override tests cover:
- 5 real biological use cases (RNA-seq FFPE, scRNA cardiac, FFPE WGS, low-pass WGS, soil metagenomics)
- 3 GOLD rejection tests
- 3 red-line clamping tests
- 3 audit log tests
- 3 SSE flag tests
- 3 `_get_threshold` unit tests

---

## API Contract (Phase 1)

### `POST /api/nextflow/execute`

```json
{
  "nextflow_path": "/path/to/pipeline.nf",
  "parameters": { "input": "samples.csv" },
  "profile": "standard",
  "workflow_domain": "rnaseq",
  "qc_overrides": {
    "alignment_rate": 50.0,
    "reads_surviving_pct": 65.0
  }
}
```

**Validation errors (HTTP 422):**

Attempt to override GOLD metric:
```json
{
  "error": "Invalid qc_overrides",
  "errors": [
    "Cannot override GOLD metric 'mapped_pct' — it is mandated by ENCODE4/GATK Best Practices and is not user-configurable."
  ]
}
```

Non-numeric value:
```json
{
  "error": "Invalid qc_overrides",
  "errors": ["Override value for 'alignment_rate' must be numeric, got: 'foo'"]
}
```

**Success response** (unchanged from before):
```json
{
  "success": true,
  "run_id": "...",
  "invocation_id": "...",
  "status": "running"
}
```

---

## Audit Trail

For every workflow launch with non-empty `qc_overrides`, the file
`{work_dir}/qc_overrides_audit.jsonl` is created (append-only JSONL).

### Record 1 — on handler initialisation
```json
{"timestamp": "2026-02-24T16:13:00+00:00", "invocation_id": "abc123",
 "event_type": "initialized",
 "configured_overrides": {"alignment_rate": 50.0},
 "applied_overrides": {}}
```

### Record 2 — when a QC gate fires under non-default thresholds
```json
{"timestamp": "2026-02-24T16:14:52+00:00", "invocation_id": "abc123",
 "event_type": "gate_triggered",
 "configured_overrides": {"alignment_rate": 50.0},
 "applied_overrides": {"process_name": "STAR_ALIGN"}}
```

The JSONL format means records can be read with `jq -s '.'` or streamed line-by-line without
loading the entire file. Future Phase 2 work will also write these records to a proper
`qc_threshold_overrides` DB table.

---

## What Phase 1 Does NOT Cover (Explicitly Out of Scope)

Per the plan document:

- **Profile management UI** — Phase 2
- **Justification field in UI** — Phase 2 (API accepts overrides but doesn't require justification)
- **Named profile system** — Phase 2 (20 curated profiles ready in plan doc)
- **Metadata schema fields** — Phase 2 (organism, library_type, sample_source, etc.)
- **`qc_threshold_overrides` SQLite table** — Phase 2 (JSONL audit file used in Phase 1)
- **Frontend "Custom QC active" banner** — Phase 2 (SSE event has `overrides_active` flag ready for it)
- **`workflow_domain` auto-inference** from workflow path or AI assistant response — Phase 2

---

## Known Limitations

1. **`nextflow_workflow_runner.py` calls `register_workflow()` without `qc_overrides`**: The
   runner currently passes no overrides. To use overrides via the workflow runner path, the
   invocation metadata needs to carry `qc_overrides` and the runner needs to read it. This is
   tracked as a Phase 2 task.

2. **`workflow_domain` defaults to `"cryo_em"` in `NextflowMonitor`**: The runner path doesn't
   know the domain unless it reads invocation metadata. The direct executor path (`nextflow_executor.py`)
   reads `workflow_domain` from the request body. Fix: thread domain from invocation parameters
   or AI assistant response (Phase 2).

3. **Audit log is file-based (JSONL), not DB**: Intentional Phase 1 simplification. Proper
   `qc_threshold_overrides` table with invocation_id + user_id + justification is Phase 2.

4. **`duplicate_pct` same key for FLAGSTAT and MARKDUP**: Both use `"duplicate_pct"` override
   key. An override applies to both contexts. This is acceptable for Phase 1 but Phase 2 should
   distinguish `flagstat_duplicate_pct` vs `markdup_duplicate_pct`.

---

## Governance Summary

```
┌─────────────────────────────────────────────────────────────────┐
│ Layer 0: Red Lines (4 metrics)                                  │
│   reads_surviving_pct ≥ 50%  |  fit_quality ≥ 0.5              │
│   mito_fraction_pct ≤ 80%    |  alignment_rate ≥ 5%            │
│   → Override clamped to bound, not rejected                     │
├─────────────────────────────────────────────────────────────────┤
│ Layer 1: GOLD Metrics (3 metrics)                               │
│   mapped_pct (GATK)  |  tss_enrichment (ENCODE4)  |  nrf_score │
│   → Override silently ignored (_get_threshold) + 422 at API     │
├─────────────────────────────────────────────────────────────────┤
│ Layer 2: SILVER/BRONZE (20 override keys)                       │
│   → Override applied as-is within red-line bounds               │
│   → Audit log written on init + gate fire                       │
│   → SSE events carry overrides_active flag                      │
└─────────────────────────────────────────────────────────────────┘
```

---

## Next Steps (Phase 2)

Priority order per PM recommendation:

1. **`rnaseq_ribodepleted` profile** — most frequent false positive (daily occurrence)
2. **`rnaseq_ffpe` profile**
3. **`scrna_cardiac` profile**
4. **`wgs_ffpe` profile**
5. **`metagenomics_soil` profile**
6. Named profile DB table + CRUD API
7. Profile selector UI at workflow launch (diff table before launch)
8. Justification field (required when more permissive)
9. `qc_threshold_overrides` SQLite table replacing JSONL audit
10. `workflow_domain` auto-threading from AI assistant response

Reference: `docs/QC/20260224_CONFIGURABLE_QC_PLAN.md` — full Phase 2 + Phase 3 specification.
