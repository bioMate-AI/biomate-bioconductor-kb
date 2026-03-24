# Supplementary Note S4: QC Gate API Contract, SSE Event Schema & Audit Log Format
**BioMate QC Governance Stack — Paper 1 Supplementary Material**
**Last updated:** 2026-02-26

---

## 1. QC Gate API

### Start a workflow with a named QC profile

```http
POST /api/nextflow/execute
Content-Type: application/json
Authorization: Bearer <user_token>
```

```json
{
  "nextflow_path": "nf-core/rnaseq",
  "parameters": {
    "input": "s3://bucket/samplesheet.csv",
    "genome": "GRCh38"
  },
  "qc_profile": "rnaseq_ffpe",
  "qc_overrides": {
    "reads_surviving_pct": 55.0
  }
}
```

**Field definitions:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `nextflow_path` | string | yes | Workflow identifier (nf-core name or local path) |
| `parameters` | object | yes | Nextflow workflow parameters |
| `qc_profile` | string | no | Named QC profile ID (see Supplementary S2) |
| `qc_overrides` | object | no | Per-metric threshold overrides; takes precedence over profile |

**Override precedence (highest to lowest):**
1. `qc_overrides` (explicit per-invocation)
2. Named `qc_profile` overrides
3. Platform defaults

**Immutable thresholds** — the following are never overridable regardless of `qc_overrides`:

| Metric | Red Line |
|--------|----------|
| `negative_control_contamination_pct` | > 5% → always fail |
| `sequencing_error_rate_pct` | > 10% → always fail |
| `phix_spike_pct` | > 20% → always fail |
| `adapter_dimer_pct` | > 30% → always fail |

**Clamping** — user overrides are silently clamped so they cannot loosen a threshold beyond 2× the platform default. Example: alignment_rate default = 70% → minimum override = 35%.

---

### List available QC profiles

```http
GET /api/qc/profiles
Authorization: Bearer <user_token>
```

Response:
```json
{
  "profiles": [
    {
      "id": "rnaseq_ffpe",
      "description": "FFPE-preserved tissue RNA-seq ...",
      "domain_hint": "rnaseq",
      "overrides": {"alignment_rate": 45.0, "reads_surviving_pct": 60.0, "q30_pct": 65.0},
      "references": ["Sinicropi D et al. 2012 PLoS ONE 7(5):e38396"]
    }
  ]
}
```

---

### Record a QC gate decision (SSE-driven flow)

When a `qc_gate_triggered` SSE event is received, the frontend submits the researcher's decision:

```http
POST /api/qc/decision
Content-Type: application/json
Authorization: Bearer <user_token>
```

```json
{
  "invocation_id": "wf-abc123",
  "process_name": "STAR_ALIGN",
  "decision": "retry",
  "applied_suggestions": [
    {"parameter": "alignSJoverhangMin", "value": 8}
  ]
}
```

| `decision` value | Meaning |
|-----------------|---------|
| `"retry"` | Re-run the process with the applied suggestions |
| `"proceed"` | Continue the workflow despite the failure (recorded in audit log) |
| `"cancel"` | Stop the workflow at this step |

---

## 2. SSE Event Schema

BioMate uses Server-Sent Events to push QC status to the frontend in real time. The SSE endpoint is:

```
GET /api/workflows/{invocation_id}/sse
```

Events are emitted in the format:

```
event: <event_type>
data: <JSON payload>
```

### `qc_gate_triggered` — blocking failure

Emitted when one or more metrics fail a hard gate. The workflow is paused at this step.

```json
{
  "event_type": "qc_gate_triggered",
  "invocation_id": "wf-abc123",
  "process_name": "STAR_ALIGN",
  "task_id": "ab/cd1234",
  "timestamp": "2026-02-26T14:30:00Z",
  "qc_passed": false,
  "failures": [
    {
      "metric": "alignment_rate",
      "value": 45.2,
      "threshold": 70.0,
      "operator": "<",
      "severity": "warning",
      "advisory": false,
      "message": "Low alignment rate: 45.2% (threshold: 70%)"
    }
  ],
  "qc_metrics": {
    "alignment_rate": 45.2,
    "uniquely_mapped_pct": 44.8,
    "multimapping_pct": 5.1
  },
  "suggestions": [
    {
      "parameter": "alignSJoverhangMin",
      "current_value": 5,
      "suggested_value": 8,
      "reason": "Increasing minimum splice junction overhang often improves alignment rate for samples with short reads",
      "confidence": 0.82
    }
  ]
}
```

**`failures[]` fields:**

| Field | Type | Notes |
|-------|------|-------|
| `metric` | string | Key in `qc_metrics` |
| `value` | number | Measured value |
| `threshold` | number | Gate threshold |
| `operator` | `"<"` or `">"` | Failure direction |
| `severity` | `"warning"` \| `"critical"` | `"critical"` for values indicating data corruption |
| `advisory` | boolean | If `true`, failure is non-blocking (workflow continues) |
| `message` | string | Human-readable explanation with threshold context |

**`suggestions[]` fields:**

| Field | Type | Notes |
|-------|------|-------|
| `parameter` | string | Nextflow/tool parameter name |
| `current_value` | any | Value used in the failed run |
| `suggested_value` | any | Recommended adjustment |
| `reason` | string | Scientific rationale for the suggestion |
| `confidence` | float [0,1] | Confidence in the suggestion; < 0.7 should be reviewed before applying |

---

### `qc_warning` — near-threshold advisory

Emitted when metrics pass all hard gates but are within 10% above a minimum threshold, or when advisory (non-blocking) failures occur alongside a passing QC check.

```json
{
  "event_type": "qc_warning",
  "invocation_id": "wf-abc123",
  "process_name": "MOSDEPTH",
  "task_id": "ef/gh5678",
  "timestamp": "2026-02-26T14:31:00Z",
  "qc_passed": true,
  "warnings": [
    {
      "metric": "mean_coverage",
      "value": 32.5,
      "threshold": 30.0,
      "operator": "<",
      "severity": "near_threshold",
      "message": "Coverage 32.5X is near the 30X threshold — monitor for any library-quality issues"
    }
  ],
  "qc_metrics": {
    "mean_coverage": 32.5,
    "median_coverage": 31.8
  }
}
```

Near-threshold range: `threshold <= value <= threshold × 1.10`.

---

### `process_completed` — successful step

```json
{
  "event_type": "process_completed",
  "process_name": "FASTP",
  "task_id": "ij/kl9012",
  "timestamp": "2026-02-26T14:29:00Z",
  "qc_passed": true
}
```

---

### `workflow_completed` — all steps done

```json
{
  "event_type": "workflow_completed",
  "invocation_id": "wf-abc123",
  "timestamp": "2026-02-26T14:45:00Z",
  "status": "success"
}
```

---

## 3. QC Override Audit Log

Every workflow invocation that uses `qc_overrides` writes a JSONL audit file to the Nextflow work directory:

```
work_dir/qc_overrides_audit.jsonl
```

Each line is one JSON object recording:

```json
{
  "timestamp": "2026-02-26T14:30:00Z",
  "invocation_id": "wf-abc123",
  "metric": "alignment_rate",
  "original_threshold": 70.0,
  "override_value": 55.0,
  "clamped": false,
  "evidence_tier": "SILVER",
  "override_source": "user_explicit"
}
```

| Field | Notes |
|-------|-------|
| `clamped` | `true` if the override was silently adjusted to stay within the 2× clamp |
| `evidence_tier` | GOLD / SILVER / BRONZE / RED_LINE from the threshold definition |
| `override_source` | `"user_explicit"` (from `qc_overrides`) or `"named_profile"` (from `qc_profile`) |

**GOLD thresholds are not written to the audit log** — they are silently ignored if provided in `qc_overrides`.

---

## 4. Named Profile Validation Endpoint

```http
GET /api/qc/profiles/{profile_id}
Authorization: Bearer <user_token>
```

Returns `404` with `{"error": "unknown_profile"}` for unrecognised profile IDs.

Returns `200` with the full profile object including description, overrides, and references for valid IDs.

---

*Implementation: `backend/lib/galaxy/jobs/qc_trace_monitor.py` (monitor and gate logic), `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py` (API endpoints), `frontend/server/workflow-sse.ts` (SSE relay), `frontend/client/src/components/workflow-artifact.tsx` (SSE consumer).*
