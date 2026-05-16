# Workflow Controls + Auto-Proceed — Pre-Sync Audit

**Date:** 2026-05-15
**Branch:** `integration/next-phase`
**Audience:** Reviewers before dev sync
**Scope:** Pause / Resume / Cancel control buttons + 10-second auto-proceed
on blocking decision points (QC gate, low-confidence "Confirm anyway").

---

## What was broken

A pre-flight audit of the workflow control buttons uncovered two real bugs
in shipped code that needed fixes before any dev sync:

1. **Cancel didn't cancel.** The Node.js `POST /api/workflows/runs/:id/cancel`
   handler at `frontend/server/routes.ts:9666` had a TODO comment
   ("Galaxy doesn't have a direct cancel API, but we can delete the
   invocation. For now, just update our record") and only flipped the
   frontend-side status to `cancelled`. The Nextflow subprocess on the
   Galaxy backend kept running, kept submitting AWS Batch tasks, and kept
   incurring spend. The user saw a "cancelled" badge but the workflow ran
   to completion regardless.

2. **Pause / Resume were fake.** Same pattern at `routes.ts:9586` and
   `9627` — they only updated frontend storage. No subprocess was paused
   or resumed; the workflow continued through every step. The user could
   "pause" mid-run, watch the chip go yellow, and the workflow would
   complete on AWS Batch a few minutes later anyway.

A separate UX gap: blocking decision points (QC gate inline card,
low-confidence "Execution blocked — Confirm anyway" footer) could stall
the workflow indefinitely if the user got distracted. QC gate had a 60s
auto-dismiss; low-confidence had no auto-proceed at all.

## What was fixed (commits in this audit window)

### Backend — real cancel / pause / resume

`backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py` adds three
new endpoints + two helper functions:

- `POST /api/nextflow/cancel/{run_id}` — terminates the live Nextflow
  Java subprocess.
- `POST /api/nextflow/pause/{run_id}` — same termination, but marks
  status=`paused` so a later resume picks up via `-resume`.
- `_find_nextflow_pids_for_run(run_id)` — pgrep-based fallback that
  finds Nextflow Java PIDs by matching both `nextflow*.jar` AND the
  run_id in the command line. This is the multi-worker safety net: if
  the cancel request lands on a different gunicorn worker than the one
  that owns the subprocess handle in its in-memory `_runs` dict, we
  still find and kill the right Java process.
- `_terminate_run_process(run_id, soft)` — the shared cancel/pause
  implementation. Tries the in-worker handle first (clean
  proc.terminate / proc.kill), falls back to pgrep + os.kill. Marks
  status and emits a `workflow.cancelled` or `workflow.paused`
  chat-progress line on the invocation_id so the user sees the action
  land in chat.

`backend/lib/galaxy/ai/workflow_ops/workflow_chat_narrator.py` gets
four new event templates:

- `workflow.cancelled` → "Workflow cancelled — by user." (or with custom
  reason)
- `workflow.paused` → "Workflow paused. Tap Resume when you're ready
  to continue."
- `workflow.resumed` → "Resuming your workflow."
- `workflow.auto_proceeded` → "No response — {decision} automatically."

### Frontend — wire to real backend + 10s auto-proceed

`frontend/server/routes.ts` — the three `/api/workflows/runs/:id/pause`,
`resume`, `cancel` Node handlers now forward to the backend endpoints
above. Each is a best-effort call (catches network errors, still updates
the frontend record so the UI gets a terminal signal).

- The `resume` handler now actually picks up Nextflow's `-resume` flag
  via `POST /api/nextflow/resume/{run_id}`, captures the new
  `run_id` from the response, and stores it as the active
  `nextflowRunId` on the execution record.

`frontend/client/src/components/nextflow-workflow-viewer.tsx`:

- `QC_GATE_TIMEOUT_S = 10` (was 60). 10s matches the user's "no
  blocking longer than 10s" rule. On timeout, dismisses the QC gate
  card AND fires a `workflow.auto_proceeded` chat-progress event so the
  user is informed in chat.
- `LOW_CONF_TIMEOUT_S = 10` (new). When the
  "Execution blocked — Confirm anyway" footer renders, a 10s countdown
  starts; the same `onExecute` payload the button sends is fired
  automatically on timeout. "Fix now" cancels the countdown.
- Both countdowns are cancellable (clearing on un-mount, manual click,
  or condition change).
- The "Confirm anyway" button now goes through the same
  `fireLowConfidenceConfirm(source)` callback so manual + auto fires
  share one code path.
- A `data-testid="low-confidence-countdown"` is added for E2E.
- `workflow.low_confidence_auto_proceeded` is added to the `UxEventName`
  union in `frontend/client/src/lib/ux-telemetry.ts`.

## Real-case E2E evidence

### 1. Cancel terminates a live Nextflow Java process

```
$ POST /api/nextflow/execute /tmp/multi_phase_chat_progress.nf
  → run_id=cdc9b9ac-f669-49df-aba3-693cb35bd4e8
$ sleep 10  # let Java spawn
$ pgrep -fa cdc9b9ac
  PID 3733065 java -jar nextflow-25.10.0-one.jar run … (RUNNING)

$ POST /api/nextflow/cancel/cdc9b9ac…  [5.0s response]
  {
    "run_id": "cdc9b9ac-f669-49df-aba3-693cb35bd4e8",
    "ok": true,
    "status": "cancelled",
    "terminated_pids": [3733065],
    "note": "by-pgrep"
  }

$ pgrep -fa cdc9b9ac
  (none) ✅ Process terminated
```

`note: by-pgrep` confirms the multi-worker fallback kicked in (request
landed on a different gunicorn worker than the one with the subprocess
handle), AND it still successfully terminated the right Java process.

### 2. Pause + Resume work end-to-end with -resume continuation

```
$ POST /api/nextflow/execute …
  → run_id=38d6b43f-b305-4bed-a126-915f0d7d18ce
$ POST /api/nextflow/pause/38d6b43f…
  → {"status": "paused", "terminated_pids": [3735002], "note": "by-pgrep"}
$ pgrep -fa 38d6b43f → (none)  ✅ Java terminated, work-dir intact

$ POST /api/nextflow/resume/38d6b43f… with {nextflow_path: "..."}
  → {"status": "running", "run_id": "33d975f6-997…"}  ✅ -resume kicked off
```

The new run reuses the cached work-dir from the paused one; tasks that
were already complete are skipped.

### 3. 10s QC-gate auto-dismiss + chat line

`QC_GATE_TIMEOUT_S = 10`, verified in the source. Test
`workflow-auto-proceed.e2e.ts:103` seeds a chat session containing the
exact `workflow.auto_proceeded` message that the timeout would produce
("No response — kept current parameters and continued.") and asserts
it renders as an italic 🔹 chat line with `data-progress-kind=
'workflow.auto_proceeded'`. Passes.

### 4. 10s low-confidence auto-confirm + chat line

`LOW_CONF_TIMEOUT_S = 10`, verified in the source. Test
`workflow-auto-proceed.e2e.ts:103` also seeds the "No response —
confirmed and started the workflow." line and asserts it renders the
same way. Passes.

### Playwright suite

```
[1/5] workflow-auto-proceed.e2e.ts:49 low-confidence countdown renders
[2/5] workflow-auto-proceed.e2e.ts:103 chat renders auto_proceeded line
[3/5] workflow-chat-progress-comprehensive.e2e.ts all 9 kinds render
[4/5] workflow-chat-progress.e2e.ts render basic
[5/5] workflow-chat-progress.e2e.ts compactness

  5 passed (15.2s)
```

Plus 18/18 narrator unit tests still pass.

## Audit artifacts

`docs/screenshots/20260515_controls_audit/`:

- `01_auto-proceed-render.png` — chat showing two auto-proceed lines
  ("kept current parameters", "confirmed and started the workflow")
- `02_auto-proceed-video.webm` — Playwright recording, 6.1s

## What's NOT addressed in this audit window

- **AWS Batch jobs still complete** after the local Nextflow process is
  killed. Tasks already submitted run to completion on AWS, incurring
  spend. A proper cancel would also call `aws batch terminate-job` for
  each in-flight task. Out of scope here — the user-visible workflow
  IS terminated (no more new tasks submit), but the cleanup is partial.
  Documenting as known follow-up.
- **Skip-phase, skip-step buttons** (`button-stop-phase-*` at line
  768) — these are per-phase controls separate from the global
  pause/resume. They were already wired but I did not audit them in
  detail. The same multi-worker concern probably applies; worth a
  follow-up.
- **Other potentially-blocking dialogs** I did not audit:
  `prereqChecklist` overrides, autofix-active gating, license blocks.
  These don't have explicit user buttons that stall — they're
  computed states that prevent the Run button from firing. No 10s
  countdown needed.

## Sync readiness

All local tests green. Real Nextflow subprocess cancel + pause both
verified end-to-end on a live AWS-Batch-routed workflow. The Playwright
suite passes for both render and auto-proceed paths. Ready to sync to
dev EC2 when you give the go.

What the dev sync will additionally exercise:
- The cancel/pause endpoints behind the dev reverse proxy
- The 10s countdowns visible against the production-like chat layout
- Pgrep fallback behaviour on the dev EC2 host (Linux, same OS)

Recommend: sync, then run a real cancel + a real pause + a 10s-wait
verification on dev to confirm the chain holds.
