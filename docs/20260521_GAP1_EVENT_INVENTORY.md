# Gap 1 — Executor SSE Event Inventory

**Produced for:** `docs/20260521_GAP1_NARRATOR_EXECUTOR_PARITY.md` step 1.
**Date:** 2026-05-21

## Panel listeners (`frontend/client/src/components/nextflow-workflow-viewer.tsx`)

| Event name | Listener line |
|---|---|
| `chat_progress` | 1761 |
| `qc_gate_triggered` | 1779 |
| `autoloop_gate_results` | 1842 |
| `autoloop_update` | 1857 |
| `autoloop_phase_complete` | 1875 |
| `autoloop_escalation` | 1884 |
| `step_state` | 1902 |
| `workflow_state` | 1928 |

## Producers in production code

### Through narrator (`_narrate_chat` → emits `chat_progress` only)
Located in `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py:50-88`. Every `_narrate_chat` call routes through `workflow_chat_narrator.emit()` which writes a `chat_progress` payload to the SSE inject endpoint. Kinds emitted by the narrator templates (`workflow_chat_narrator.py:133-158`):

- `workflow.submitted`, `workflow.uploading_inputs`, `workflow.queued`, `workflow.running`
- `workflow.phase_started`, `workflow.phase_completed`, `workflow.phase_failed`
- `workflow.qc_gate_warning`, `workflow.qc_gate_blocked`
- `workflow.autoloop_started`
- `workflow.completed`, `workflow.failed`
- `workflow.cancelled`, `workflow.paused`, `workflow.resumed`
- `workflow.auto_proceeded`
- `deepagent.start`, `deepagent.investigating`, `deepagent.tool_call`, `deepagent.suggestion`

### Direct executor SSE emits (bypass narrator)

| event_type | Emit site | Narrator equivalent today |
|---|---|---|
| `qc_gate_triggered` | `backend/lib/galaxy/jobs/qc_trace_monitor.py:5543` | **WIRED** — narrator emit at `qc_trace_monitor.py:5552-5572` immediately after the raw SSE call. Chooses `workflow.qc_gate_blocked` vs `workflow.qc_gate_warning` based on whether any failure is non-advisory. |
| `qc_warning` | `backend/lib/galaxy/jobs/qc_trace_monitor.py:5744` | **WIRED** — narrator emit at `qc_trace_monitor.py:5749-5765` emits `workflow.qc_gate_warning` with `advisory_only: true`. |
| `step_state` | (not located in our search — likely a Galaxy/Nextflow poller layer, not the executor) | partial — `workflow.phase_started/completed/failed` cover the high-level phases but not per-step state ticks |
| `workflow_state` | (same as above) | partial — `workflow.running/completed/failed` cover this but only on transitions, not on periodic state pulses |
| `autoloop_gate_results` | **No production emit site found.** Only appears in `backend/experiments/*` standalone servers. Panel listener at viewer:1842 may be dead in the main app, or wired through a path not yet located. | `workflow.autoloop_started` exists |
| `autoloop_update` | **No production emit site found** (same as above) | none |
| `autoloop_phase_complete` | **No production emit site found** (same as above) | none |
| `autoloop_escalation` | **No production emit site found** (same as above) | none |

## Observations

1. **The QC parity gap is already fixed.** Both `qc_gate_triggered` (5543) and `qc_warning` (5744) have narrator emits wired alongside the raw SSE callback. The original audit was based on an earlier code state. Net: every QC panel state change today *does* produce a chat line.

2. **`step_state` and `workflow_state` come from the Node.js Galaxy poller, not Python.** Producers: `frontend/server/workflow-sse.ts:49,65` re-broadcasts from `galaxy-state-poller.ts:199-247`. The Python narrator can't observe these directly — they happen entirely in the Node.js polling layer. The narrator's `workflow.phase_started/completed/failed` is emitted from `nextflow_executor.py` at Python-side lifecycle transitions, which is a different timeline. There is no current sync between the two — they happen to align on Nextflow-native runs because both are driven by the same execution thread, but on Galaxy-classic runs the Node poller can emit panel updates with no corresponding chat line.

3. **The auto-loop event family is panel-only and currently dormant in production.** Viewer listeners at lines 1842/1857/1875/1884 expect events whose only emit sites today are `backend/experiments/*` standalone autoloop servers, not the main `backend/lib/galaxy/` execution path. For Gap 1 we treat them as "not in production scope" — wiring narrator handlers that will never fire is dead code.

## Revised scope for Gap 1.2 / 1.3

Most of Gap 1 is **already resolved**. The remaining work is one specific, well-scoped fix:

- **Node-side parity for `step_state` / `workflow_state`** (Galaxy-classic runs): in `frontend/server/workflow-sse.ts`, when the poller emits `workflow_state` with a terminal status (`ok`/`error`/`paused`/`deleted`), also POST to `/internal/sse-inject` with a `chat_progress` payload generated server-side. This guarantees chat tracks panel for Galaxy-classic runs the same way Nextflow-native runs already do. Same for `step_state` on transitions that the Python narrator can't see.

- **Defer:** the auto-loop family until a production emit site is located.

This collapses the original 4 sub-tasks (1.1-1.4) into a single concrete change. Skip Gap 1.2 (already done in qc_trace_monitor.py) and Gap 1.3 (mostly already done). Repurpose those tasks below.
