# Gap 1 — Narrator / Executor Event Parity

**Status:** Mostly resolved as of 2026-05-21. One Node-side follow-up remains.
**Owner:** unassigned
**Opened:** 2026-05-21
**Related:** Gap 2 (`20260521_GAP2_CHAT_DRIVEN_EDITS.md`), Gap 3 (`20260521_GAP3_RUN_AGAIN_PARAM_CARRYOVER.md`), Inventory (`20260521_GAP1_EVENT_INVENTORY.md`)

> **Update 2026-05-21:** Inventory revealed both QC emit sites
> (`qc_trace_monitor.py:5543` and `:5744`) already wire narrator emits alongside
> the raw SSE callback. The auto-loop event family has no production emit site
> (only `backend/experiments/*`), so its parity work is out of scope until that
> path lands in `backend/lib/galaxy/`. The only remaining real divergence is
> Node-side: `step_state` / `workflow_state` from `frontend/server/workflow-sse.ts`
> are not narrated on Galaxy-classic runs. See the inventory doc for the
> revised, single-task scope. The steps below are kept for historical context.

## Problem

The right-side workflow panel and the chat progress lines consume the same SSE stream (`/api/workflows/runs/:id/stream`), but they listen to two different sets of event kinds emitted by two different producers:

- **Chat progress lines** are emitted by `backend/lib/galaxy/ai/workflow_ops/workflow_chat_narrator.py` (~line 177-216) as `chat_progress` events with friendly messages. Kinds: `workflow.phase_*`, `workflow.step_*`, `workflow.qc_*`, `workflow.autoloop*`.
- **Panel state** at `frontend/client/src/components/nextflow-workflow-viewer.tsx:1712-1839` *also* listens to executor-emitted raw events the narrator does not re-emit: `qc_gate_triggered` (line 1736), `autoloop_gate_results` (1799), `autoloop_update` (1814), `autoloop_phase_complete` (1832).

**Symptom:** a QC gate trip or an auto-loop step changes the panel without a corresponding chat line. The user sees the panel turn red but the chat is silent, or vice versa.

## Goal

Every panel-visible state change produces a chat progress line, and every chat progress line corresponds to an observable panel state change. Single source of truth for "what is the user told about."

## Approach

**Single producer, dual consumer.** Make the narrator the only emitter of `chat_progress`. Have it subscribe to the executor's raw events instead of having the executor emit some narration-worthy events directly to SSE. Raw events keep flowing under their existing names so the panel doesn't need changes.

## Steps

1. **Inventory the divergence.** Grep `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py` and `backend/lib/galaxy/ai/workflow_ops/qc_trace_monitor.py` for every `sse_callback(...)` call site. Compare to kinds the narrator already emits in `workflow_chat_narrator.py`. Produce a table: `event_kind → emitted_by → also_narrated?`. Commit as `docs/20260521_GAP1_EVENT_INVENTORY.md`.
2. **Extend the narrator.** Add handlers in `workflow_chat_narrator.py` for the missing kinds:
   - `qc_gate_triggered` → `workflow.qc_gate_{warn,fail,pass}` with a templated friendly message ("hERG QC failed: 12.3 µM > 10 µM threshold")
   - `autoloop_gate_results` → `workflow.autoloop_gate` ("Auto-loop checking gates: 2 of 3 pass")
   - `autoloop_update` → `workflow.autoloop_step` ("Auto-loop iteration 2: trying logP filter ≤5")
   - `autoloop_phase_complete` → `workflow.autoloop_phase_done` ("Auto-loop converged after 3 iterations")
3. **Re-route the executor.** Change executor sites that currently call `sse_callback("qc_gate_triggered", payload)` directly to instead call `narrator.on_executor_event("qc_gate_triggered", payload)`. The narrator decides whether to emit a `chat_progress` line, then re-emits the raw event under its existing name so the panel listeners stay valid.
4. **No panel changes required.** Listeners at `nextflow-workflow-viewer.tsx:1712-1839` continue to receive the technical payload under the same event names. Verify by running an ADMET flow with `tail -f` on the SSE stream.
5. **Add parity E2E.** New test `frontend/e2e/workflow-narrator-parity.e2e.ts`. Run an ADMET workflow that trips hERG and triggers an auto-loop remediation. Assert: for every panel `data-status` transition observed on a phase card, there is at least one `chat_progress` message with a matching timestamp ±2s.

## Files Touched

| File | Change |
|---|---|
| `backend/lib/galaxy/ai/workflow_ops/workflow_chat_narrator.py` | Add 4 handlers + templates |
| `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py` | Re-route 3-5 sse_callback sites |
| `backend/lib/galaxy/ai/workflow_ops/qc_trace_monitor.py` | Re-route QC sse_callback site |
| `frontend/e2e/workflow-narrator-parity.e2e.ts` | New test |

No frontend component changes if SSE event shapes stay stable.

## Risks

- **Double-emit.** Narrator re-emits raw events → panel receives them twice. Mitigation: narrator only *adds* `chat_progress`; never republishes the raw kind. Tested by counting SSE messages in the parity E2E.
- **Spammy chat.** Auto-loop ticks fire every few seconds; narrating each one floods chat. Mitigation: throttle `workflow.autoloop_step` to at most one per 10s, collapse runs into a single "iteration N" line.

## Done When

- [ ] Inventory doc committed
- [ ] Narrator handles all 4 missing kinds
- [ ] Executor + QC monitor routed through narrator
- [ ] Parity E2E green
- [ ] One full ADMET → hERG → auto-loop run shows narrator+panel alignment in a screenshot
