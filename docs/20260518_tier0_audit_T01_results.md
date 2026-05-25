# Tier 0 Audit — T01 First Run Results (2026-05-18)

First end-to-end audit run against the refactored Tier 0 chain. Single test:
T01 `bispecific_format_triage` via `frontend/e2e/tier0-audit.e2e.ts`.

**Score**: 9 passed / 15 failed (24 assertions). RunId `3be9c093-32fc-439f-9c5f-6da47b8627b7`.

JSON dump: `frontend/e2e/screenshots/tier0-audit/tier0_audit_1779122652004.json`.

## What works ✓

The structural plumbing from the Scope B refactor is sound:

- **4 phase-group cards render** in the panel (`phase-group-cards-render` ✓ — got 4, expected ≥4)
- **First phase shows `data-status="pending"`** before Run (`first-phase-initial-status-pending` ✓)
- **Run dispatch works** (`click-run-dispatched` ✓ — runId returned, clickRunOnly's hard-fail didn't trigger, meaning the dispatch chain is unbroken)
- **First phase transitions `pending → running`** in real time (`first-phase-transitions-running` ✓ — SSE phase status updates are propagating)
- **Findings endpoint returns 200** (`findings-endpoint-returns-200` ✓)
- **Both after-run buttons render** (`analyze-results-btn-renders` + `download-methods-report-btn-renders` ✓)
- **Workflow card appears after chat** (`workflow-card-appeared` ✓)

The cryo-style audit pattern translates correctly to Tier 0 once the workflows
are properly phased and the step parser knows where to find them.

## 4 distinct root-cause bugs surfaced

### Bug A — Execute payload drops LLM-extracted inline params (production bug)

**Most important finding.** The Nextflow log tail shows:
```
[2e/1a2b03] BIS…bispec:phaseA:null_x_null) | 0 of 1
```
Phase A's `tag` directive reads `${params.target_a}_x_${params.target_b}` — both are
the string literal `null` (the workflow's `params.target_a = 'null'` default).

The chain that's broken:
- ✓ chat-stream emits `inlineParameters: {target_a:"PD-1", target_b:"VEGF", format:"CrossMab", indication:"NSCLC"}` (verified earlier via direct curl)
- ✗ Frontend form does not prefill those values (audit Bug C below)
- ✗ Run dispatch POSTs to `/api/nextflow/execute` with empty `toolParameters: {}` (verified via `executionRun.parameters.toolParameters` in the run record)

**Where to fix**: the form-prefill step in `nextflow-workflow-viewer.tsx` (or wherever
the workflow card surfaces inlineParameters into the form) must run before Run is
clicked. Bug 1's `WORKFLOW_PARAM_ALIASES` remap in `galaxy-assistant.ts` (already
landed) gets the keys right; we now need the frontend to actually push them into
the form fields and forward them to the execute payload.

This is the SAME bug class as the 20260514 demos: workflow runs with defaults instead
of the user's values. The phase-split work fixed phase rendering but didn't fix the
param flow. **Demos still cannot ship until this is fixed.**

### Bug B — Audit's SSE parser fails to find `workflow_ready` event

Test reports `no workflow_ready event found` from the chat-stream SSE response,
even though direct curl shows the event fires cleanly. This is a test-harness bug
in `frontend/e2e/tier0-audit.e2e.ts` — the `ReadableStream`-based SSE consumer
likely terminates the read loop before the event arrives, or the regex
`/^event:\s*workflow_ready\s*$/` doesn't match the encoding used (possibly
multi-byte chunk boundaries).

Doesn't block demo recording but blocks 9 of the 15 failed assertions in this run.
Fix is local to the test harness, no production code change needed.

### Bug C — Form prefill doesn't happen (production bug, related to Bug A)

`form-prefilled:target_a` etc. all report `form target_a=undefined`. Either:
- The form input selectors in the test don't match the actual DOM (test bug), OR
- The frontend never inserts the values into the inputs (production bug)

To distinguish: open `screenshots/tier0-audit/T01/01_card.png` and visually verify
whether the inputs are populated. If populated → fix selectors. If empty → fix
frontend (probably the workflow-card render path needs to apply `inlineParameters`
to the form on mount). Given that **Bug A confirms the values don't reach the
backend either**, this is most likely a production bug, not a test bug.

### Bug D — AWS Batch queue cold start (infrastructure)

`any-phase-reaches-completed` failed because Phase A still showed `0 of 1` after
the test's 900s wait. The job was submitted to AWS Batch (visible: `awsbatch (1)`,
work hash `2e/1a2b03`) but hadn't started yet. The Batch queue has cold-start
delay when there are no warm workers — this varies between 3 and 25 min depending
on capacity.

Not a code bug. Either (a) accept the latency and lengthen the audit timeout to
30 min, or (b) keep a warm worker in the queue.

### Bug E — methods-report endpoint HTTP -1

`methods-report-returns-200` reports HTTP -1, which Playwright uses for "request
never reached the server" — typically a timeout or connection refused. Since
`findings-endpoint-returns-200` (HTTP 200) succeeded right before this, both endpoints
share the same auth; the issue is likely the workflow-id route shape. Worth checking
whether `/api/invocations/:id/methods-report` expects `galaxyInvocationId`
(b8f38dc4) or runId (3be9c093) — the test passes runId.

## Punch list (fix order)

1. **Bug A + C together**: trace `inlineParameters` from chat-stream → workflow card
   props → form input `defaultValue`/`value` → `toolParameters` in the execute POST
   body. Fix at the first break in the chain. (1-2 hrs)
2. **Bug B**: rewrite the SSE consumer in `tier0-audit.e2e.ts` lines ~272-376 to use
   `text/event-stream` chunked-encoding-aware buffering, or switch to `EventSource`
   in the page context. (30 min)
3. **Bug E**: verify which ID `methods-report` expects; if it expects
   `galaxyInvocationId`, pass that in the test. (15 min)
4. **Bug D**: accept the latency; rerun audit when Batch capacity is warm, OR
   bump `waitForAnyCompletedPhase` timeout to 1_500_000 (25 min). (5 min)
5. Re-run T01 audit. Once green, run T02–T05.

## Cost of this run

~$1.50 AWS Batch (job submitted but hadn't materially executed yet —
mostly queue idle time). ~5 min of human-equivalent wall clock for the test harness.
Production audit identified 4 distinct bugs that no prior smoke test caught.

## What is NOT broken

- Phase-split refactor (Tier 0 commits `409844dae` / `b9255f490` / `a75ee1fd7` /
  `751b1338e` / `ebdaa8ade`): the 4 phase cards render, first transitions to running,
  the Nextflow pipeline recognizes all 4 process definitions.
- Step parser path fix (`ee1be8b56`): `/api/nextflow/steps` returns the correct 4
  phases with A/B/C/D labels.
- `clickRunOnly` hard-fail (`c6f386cab`): dispatched cleanly, returned a real runId
  without the silent-null failure the original demos had.
- Frontend dev server, Galaxy backend HUP path, JWT auth flow, AWS Batch submission.

These three pieces of session work are validated by this audit even though the run
overall failed — the failure is in places we hadn't fixed yet, not in places we
thought we had.
