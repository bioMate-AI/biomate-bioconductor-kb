# Execution Tracing & UX Visibility — Gap Analysis

**Date:** 2026-03-10  
**Scope:** What execution trace data is generated in the backend vs what the user actually sees

---

## What Exists Today

### SSE System 1 — Galaxy Workflow State (`/api/galaxy/workflows/sse/{workflowId}/{invocationId}`)

**Backend:** `frontend/server/workflow-sse.ts` — `WorkflowSSEManager`  
**Source:** `GalaxyStatePoller` polling Galaxy's native invocation API every N seconds

**Events the frontend currently receives:**

| Event | Payload | Displayed to user? |
|-------|---------|-------------------|
| `workflow_state` | overall state: `new / ready / scheduled / cancelled / failed` | ✅ Yes — status badge |
| `step_state` | per-step: `queued / running / ok / error / paused / waiting` + `step_id`, `job_id` | ✅ Yes — step list |
| `job_log` | raw log lines appended per step | ✅ Partially — in job log viewer (not always visible) |
| `error` | error-level event | ✅ Yes — error banner |
| `workflow_completed` | triggers client disconnect | ✅ Implicit |
| `progress_milestone` | milestone marker | ❌ **Received but silently discarded** (console.log only) |
| `polling_error` / `polling_failed` | SSE error escalation | ✅ Yes — error state |

### SSE System 2 — QC Gate Events (`/api/workflows/{invocationId}/events`)

**Backend path:** `nextflow_executor.py` → `NextflowQCGateHandler` → `_sse_callback()` → HTTP POST `/internal/sse-inject` → `WorkflowSSEManager.injectRawEvent()` → frontend  
**Frontend consumer:** `workflow-artifact.tsx`

| Event | Payload | Displayed to user? |
|-------|---------|-------------------|
| `qc_gate_triggered` | `{ process_name, qc_metrics, failures, suggestions, overrides_active, active_profile }` | ✅ Yes — `QCGateModal` opens |
| `qc_warning` | `{ process_name, qc_metrics, warnings }` | ✅ Yes — step annotation |
| `pilot_qc_passed` | all pilot QC gates clean | ✅ Yes — triggers full run |
| `connected` | SSE handshake | ✅ Implicit |

---

## What's Missing — The 7 Gaps

### Gap 1: Raw Nextflow logs never reach the frontend ❌

**What exists:** `nextflow_executor.py`'s `_stream_logs` writes stdout/stderr to a local file. `NextflowMonitor` reads `.nextflow.log`, `nextflow.out`, `nextflow.err` and passes them to Galaxy's Python logger.

**What's missing:** There is a TODO comment in the monitor to write logs to `workflow_invocation_step` messages, but it's not implemented. The `workflow-sse.ts` SSE system only carries Galaxy step-state events from the Galaxy API poller — not raw Nextflow log lines.

**User impact:** Users cannot see what Nextflow is actually doing between step state transitions.

**Fix:** Stream `nextflow.out` tail to the SSE channel as `log_line` events:
```python
# In NextflowMonitor._monitor_loop():
for line in _tail_file(work_dir / "nextflow.out", last_pos):
    sse_callback("log_line", {"source": "nextflow", "line": line, "ts": now_iso()})
```

---

### Gap 2: Workflow-trace.txt task data is never shown ❌

**What exists:** `NextflowQCGateHandler` polls `workflow-trace.txt` every 5 seconds and processes task completions. The trace columns contain per-task: `task_id`, `status`, `exit`, `submit`, `start`, `complete`, `duration`, `realtime`, `%cpu`, `rss`, `vmem`, `rchar`, `wchar`, `module`, `container`.

**What's missing:** This rich resource-usage data is only used internally for QC gate evaluation. The raw trace data per task (CPU %, memory RSS, wall time, read/write bytes, exit code) is never forwarded to the frontend in structured form.

**User impact:** Users cannot see which tasks are slow, which are memory-hungry, or which failed with specific exit codes.

**Fix:** Emit a `task_trace` SSE event when each task completes:
```python
sse_callback("task_trace", {
    "task": task_name,
    "status": "COMPLETED",
    "exit": exit_code,
    "duration_s": duration,
    "cpu_pct": cpu_pct,
    "rss_mb": rss_mb,
    "container": container,
})
```

---

### Gap 3: `workflow_ai_realtime.py` endpoint exists but frontend never calls it ❌

**What exists:** A complete API endpoint at `/api/workflows/{invocation_id}/realtime/status` that aggregates:
- Workflow state + progress
- Detected issues with severity, suggestion, `auto_fixable` flag
- AutoFix status (enabled, in_progress, fixes_applied, pending_approval count)
- Recommendations list
- Restart info (new invocation ID if restarted)
- Cost estimate

The data is read from JSON files written by `nextflow_monitor.py` (`database/ai_workflow_ops/analysis_results/workflow_{id}/latest.json`).

**What's missing:** No frontend component calls this endpoint. No `fetch('/api/workflows/*/realtime/status')` calls exist anywhere in `frontend/client/src/`.

**User impact:** Users never see: AI-detected issues, whether an autofix was applied or is pending their approval, whether the workflow was restarted with new parameters, or the LLM's analysis of what went wrong.

**Fix:** Add a polling hook in the workflow execution view:
```typescript
// In useWorkflowExecution.ts — poll every 5s during execution
const { data: aiStatus } = useQuery({
  queryKey: ['workflow-ai-status', invocationId],
  queryFn: () => fetch(`/api/workflows/${invocationId}/realtime/status`).then(r => r.json()),
  refetchInterval: 5000,
  enabled: isRunning,
});
```

---

### Gap 4: AutoFix results are invisible to users ❌

**What exists:** `_save_analysis_result()` and `_send_user_notification()` in `nextflow_monitor.py` write JSON files (`latest.json`, `notifications.json`) that `workflow_ai_realtime.py` reads. The `AutoFixOrchestrator` produces `applied_fixes`, `pending_fixes`, and audit log entries.

**What's missing:** Since the frontend never calls the realtime status API (Gap 3), users never see:
- Which issues were auto-detected
- Whether an autofix was applied automatically (and what changed)
- Whether there's a fix waiting for their approval
- Whether the workflow was restarted with new parameters

**Fix:** Surface the autofix status in the UI:

```
┌─────────────────────────────────────────┐
│ 🔧 AI AutoFix                           │
├─────────────────────────────────────────┤
│ ✅ Applied: increased max_memory 8→16GB │
│ ⏳ Pending approval:                    │
│    Change aligner: bowtie → star        │
│    [Approve] [Reject]                   │
│                                         │
│ 🔄 Workflow restarted (invocation #746) │
└─────────────────────────────────────────┘
```

---

### Gap 5: AWS Batch / CloudWatch container logs not surfaced ❌

**What exists:** `BatchLogCollector` in `nextflow_monitor.py` fetches container logs from CloudWatch and persists them under `work_dir/aws_batch_logs/`. `ContainerErrorFixer` uses them for LLM analysis.

**What's missing:** Neither `workflow_ai_realtime.py` nor the SSE system exposes these logs to the user. Users cannot see per-container stdout/stderr from failed Batch tasks without backend filesystem access.

**Fix:** Add a per-task log endpoint and stream via SSE:
```
GET /api/workflows/{invocation_id}/tasks/{task_id}/logs
```
Stream CloudWatch log lines as `container_log` SSE events.

---

### Gap 6: `progress_milestone` events silently discarded ❌

**What exists:** Both `useUnifiedExecution.ts` and `workflow-sse.ts` relay `progress_milestone` events. `useUnifiedExecution.ts` receives them but the handler only does `console.log`.

**What's missing:** No UI state is updated; the user sees nothing when milestones are reached (e.g., "50% complete", "alignment finished", "QC passed").

**Fix:**
```typescript
case 'progress_milestone':
  setMilestones(prev => [...prev, {
    label: event.data.milestone,
    ts: event.data.timestamp,
  }]);
  break;
```
Display as a timeline of completed stages in the execution panel.

---

### Gap 7: No dedicated trace display component ❌

**What exists:** `job-log-viewer.tsx` exists but is not plumbed into real-time SSE log delivery. Despite a `trace-chat-flow.e2e.ts` test file hinting at a trace chat flow feature, there are no `TraceDisplay.tsx`, `WorkflowTracePanel.tsx`, or similar components in `frontend/client/src/`.

**What's missing:** A unified trace view that shows:
- Task timeline (Gantt-style)
- Per-task resource usage (CPU%, RAM, wall time)
- Log lines with timestamps
- AI analysis annotations inline with tasks

---

## Priority Implementation Order

| Priority | Gap | Effort | User Value |
|----------|-----|--------|-----------|
| P1 | Gap 3: Wire `/realtime/status` API to frontend | Low — add polling hook | High — shows AI analysis + autofix status |
| P1 | Gap 4: Display autofix results and pending approvals | Medium — new UI panel | High — closes the human-in-the-loop for medium-risk fixes |
| P2 | Gap 6: Handle `progress_milestone` events | Low — 5 lines of code | Medium — progress visibility |
| P2 | Gap 1: Stream `nextflow.out` tail via SSE | Medium — add log streamer | Medium — real-time log visibility |
| P3 | Gap 2: Emit `task_trace` events per task | Medium — SSE event in QC monitor | Medium — resource usage visibility |
| P3 | Gap 5: Surface CloudWatch container logs | High — log endpoint + SSE | Medium — debug failed containers |
| P4 | Gap 7: Build trace display component | High — new component | High — full observability |

---

## Quickest Win: P1 Implementation

The highest-value change is wiring up the existing backend data to the frontend in two steps:

**Step 1** — Add a polling call in `useWorkflowExecution.ts`:
```typescript
const pollAiStatus = async () => {
  const res = await fetch(`/api/workflows/${invocationId}/realtime/status`);
  if (res.ok) setAiStatus(await res.json());
};
```

**Step 2** — Add an `AutofixStatusPanel` component (small, ~50 lines) to the workflow execution view that shows:
- Issues detected with severity badges
- Applied fixes (green ✅)
- Pending fixes with Approve/Reject buttons (calls `/api/workflows/{id}/autofix/run` with `force_apply=false`)
- Restart info with link to new invocation

This requires **no backend changes** — all the data is already written to disk by `NextflowMonitor` and served by `workflow_ai_realtime.py`.
