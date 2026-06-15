# Auto-loop SSE silent on ADMET dev runs — root cause + fix

**Status:** Root cause confirmed. Fix not yet applied.
**Detected by:** `frontend/e2e/admet-autoloop-workflows-ux-e2e.e2e.ts` audit JSON
(all 5 substantive tests log `"no SSE autoloop_gate_results"` while Playwright
reports green due to soft assertions).
**Date:** 2026-06-14

## Symptom

ADMET runs complete (or time out at 6-7 min) on dev. The UI never receives
`autoloop_gate_results` or `autoloop_update` SSE events, so `AutoLoopPanel` and
`autoloop-remediation-card` never render. User-visible: "auto-loop seems
broken" even though gate thresholds, profile registration, and the front-end
panel code are all healthy.

## Root cause

`backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py:2300`

```python
# ── ADMET path ─────────────────────────────────────────────────────
# Build a dummy handler just to reuse _check_qc_thresholds
handler = NextflowQCGateHandler(
    invocation_id=run_id,
    work_dir=Path("/tmp"),
    sse_callback=lambda *a: None,   # ← deliberate no-op
    app=None,
    workflow_domain=workflow_domain,
    qc_overrides=qc_overrides,
)
```

The ADMET QC gate handler is constructed with a **no-op `sse_callback`**.
So when `_evaluate_qc_from_s3` runs at completion time (caller:
`nextflow_executor.py:3158`) and the handler evaluates `toxicity_report.json`
against profile thresholds, the gate failures are stored on
`_runs[run_id]["qc_gates"]` but **never broadcast as SSE**.

The intent of the no-op was probably "this runs post-completion, no live
subscriber to push to anyway." That assumption is wrong: clients that opened
the SSE stream at run-start remain subscribed until the workflow reaches a
terminal state, and the AutoLoopPanel relies on these mid/late-run events to
render. Even for late-arriving clients, the SSE inject infrastructure
broadcasts to all current subscribers for the given `invocation_id`.

## The infrastructure is already there

`nextflow_executor.py:91-105` defines `_post_sse(event_type, data)` which
POSTs to `${FRONTEND_URL}/internal/sse-inject` with `invocation_id`,
`event_type`, `data`. This is the canonical SSE broadcast path used by
the narrator. It would work identically for the ADMET QC handler.

## Fix (surgical)

Inside `_evaluate_qc_from_s3` (line ~2228), build a real callback that POSTs
to `/internal/sse-inject` for the given `run_id`, and pass it in place of
`lambda *a: None`:

```python
def _evaluate_qc_from_s3(run_id, s3_output_files, workflow_domain, qc_overrides):
    import os, json as _json, urllib.request as _urllib

    frontend_url = os.environ.get("FRONTEND_URL", "http://localhost:5000")
    inject_url = f"{frontend_url}/internal/sse-inject"

    def _sse_emit(event_type: str, data: dict) -> None:
        try:
            req = _urllib.Request(
                inject_url,
                data=_json.dumps({
                    "invocation_id": run_id,
                    "event_type": event_type,
                    "data": data,
                }).encode("utf-8"),
                headers={"Content-Type": "application/json"},
            )
            with _urllib.urlopen(req, timeout=5):
                pass
        except Exception as exc:
            log.debug("[autoloop SSE] inject failed for %s: %s", event_type, exc)

    # ... existing classification + handler construction ...
    handler = NextflowQCGateHandler(
        invocation_id=run_id,
        work_dir=Path("/tmp"),
        sse_callback=_sse_emit,        # ← real broadcast
        app=None,
        workflow_domain=workflow_domain,
        qc_overrides=qc_overrides,
    )
```

That's the entire fix on the backend side. The `NextflowQCGateHandler`
already calls `sse_callback("autoloop_gate_results", event)` and
`autoloop_bridge.evaluate_and_emit` already emits `autoloop_update` —
both paths go through the same callback we just wired.

## Two follow-ups (separate PR)

1. **REST fallback for late subscribers.** If a user opens the panel after
   the run terminated, SSE will never replay. Add
   `GET /api/invocations/:id/autoloop` that returns the persisted
   `qc_gates` from `_runs[run_id]` (or the durable study log if the run
   has rolled out of memory). `AutoLoopPanel` should fetch this on mount
   as a fallback when no SSE events have arrived after N ms.

2. **Tighten the e2e to hard-fail on missing SSE.** The existing
   `admet-autoloop-workflows-ux-e2e.e2e.ts` writes failures to an audit
   JSON but the Playwright assertion passes. Convert
   `audit.fail("no SSE autoloop_gate_results")` records to
   `expect(received).toBe(true)` so future regressions can't ship silently.

## Verification plan

After applying the fix:

1. Run `scripts/sync_to_dev.sh` from canonical `integration/next-phase`.
2. Re-run `npx playwright test e2e/admet-autoloop-workflows-ux-e2e.e2e.ts --workers=1` against dev.
3. Inspect `frontend/e2e/screenshots/admet-ux/audit_*.json` —
   `autoloop_gate_results` and `autoloop_update` should appear with non-empty
   `gates[]` and `param_changes{}` for AD-1 / AD-2.
4. Screenshot `AD1_*_after_run.png` should show the remediation card with
   was→now diff instead of an empty panel.

## Why no one noticed

- The narrator-side `workflow.autoloop_started` chat message DID fire,
  giving the illusion of a working auto-loop in chat.
- The e2e tests soft-failed, so CI stayed green.
- The `qc_gates` field on `_runs[run_id]` exists and looks correct in
  `/api/workflows/runs/:id`, so backend smoke tests showed gates being
  evaluated.
- The combination was: chat looked alive + REST showed gates + tests passed,
  but the actual panel UI rendered empty. None of these signals fail loudly.

The hard-fail e2e (follow-up 2 above) closes that loop.
