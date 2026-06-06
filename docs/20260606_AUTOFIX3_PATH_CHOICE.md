# AutoFix3 auto-trigger: Path B chosen over Path A (2026-06-06)

## Goal

Make AutoFix3 (the comprehensive 19-fixer system already built + deployed
+ healthy on dev) fire automatically when a workflow execution fails —
instead of requiring a user to click the AutoFix button in the v1
workflow card or browse historical sessions in the v2 AfterRunReport.

## What's already in place

- `backend/lib/galaxy/ai/workflow_ops/autofix/` — full stack
  (DeepAnalysisAgent, IterativeDebugger, EnhancedToolKit, 19 fixers)
- `/api/autofix3/status` on dev: `{operational: true, all 4 components: true}`
- `/api/workflows/:wid/invocations/:iid/autofix3/run` — manual trigger endpoint
- `/api/workflows/:wid/invocations/:iid/autofix3/sessions` — history endpoint
- Frontend buttons in `workflow-artifact.tsx` (v1) and sessions panel in
  `AfterRunReport.tsx` (v2)

Gap: nothing auto-invokes it. `total_invocations_tracked: 0`.

## Two paths considered

### Path A — finish "Workstream B" via LangGraph

The original plan (referenced in `langgraph_pipeline.py:252` comment).
Four landing pieces:

1. Wire `run_autofix` node → AutoFix3 ✓ (done locally, 9 unit tests pass)
2. Install `langgraph` in the Galaxy container
3. Set `BIOMATE_USE_LANGGRAPH=true` env var
4. **Replace `dispatch_execution` stub** in `langgraph_pipeline.py:202-231`
   that currently returns a synthetic UUID + `error: None` with a real
   call into `nextflow_executor` that propagates the actual failure state

Piece #4 is the dealbreaker — it's a substantial refactor with its own
risks, and without it the autofix loop's trigger condition
(`has_error AND under_limit`) never evaluates true.

### Path B — wire AutoFix3 into the existing executor

`backend/lib/galaxy/jobs/runners/nextflow_workflow_runner.py:590-629`
already has the QC-gate auto-loop integration and runs for every
workflow today (no feature flag, no env var, no langgraph). Add a
parallel hook at the *execution failure* detection point in the same
file that calls `run_nextflow_autofix(invocation_id=…)`. Reuses the
standalone runner module I wrote today.

## Recommendation: Path B

Five reasons in priority order:

1. **Scope matches goal.** One hook in code that already runs for every
   workflow vs a four-piece chain whose biggest piece is a multi-day
   refactor with its own risks.
2. **Path A's draws aren't required for autofix.** LangGraph buys
   session checkpointing + LangSmith tracing — both valuable but
   independent of the autofix-on-failure feature. Bundling them
   inflates risk + delays the user-visible win.
3. **Both paths share the same primitive.** Both call
   `run_nextflow_autofix()` from the new `nextflow_runner.py` module
   (9 unit tests green). Today's work survives either choice.
4. **`nextflow_workflow_runner.py` is the right home.** It's where the
   QC auto-loop already lives, has real access to invocation state +
   failure detection + the merge-back-into-rerun mechanism
   (`META_PARAMETERS`). Adding error-driven autofix3 here is a natural
   extension of an existing pattern.
5. **Smaller blast radius.** Path B can ship behind a single
   `BIOMATE_AUTOFIX3_AUTO=true` env gate, flip on dev first, observe
   for a week, then turn on for prod. Path A requires the full chain
   working before any user-visible change.

## What gets discarded if Path B ships

Only the `_make_run_autofix_node` edit (~30 lines in
`langgraph_pipeline.py`). The 200-line `nextflow_runner.py` module + 12
unit tests + the `langgraph_state.py` `autofix_result` field transfer
directly. ~85% of today's diff stays useful.

The `langgraph_pipeline.py` edit isn't dead either — it's the right
wiring for Path A if/when that track resumes (e.g. when someone tackles
piece #4 of the original Workstream B plan).

## Path B implementation plan

1. Find the execution-failure detection point in
   `nextflow_workflow_runner.py` (likely the post-`nextflow run` block
   that processes exit code + workflow-trace.txt).
2. Add a single hook there that calls
   `run_nextflow_autofix(invocation_id=…, max_attempts=3, timeout=180)`
   when a non-zero exit + non-QC-gate failure is detected. (QC-gate
   failures already go through the existing auto-loop.)
3. Persist the result into the same on-disk session record format
   `/tmp/biomate_autofix3_sessions/<id>.json` so the UI's existing
   sessions panel picks it up without frontend changes.
4. Gate behind `BIOMATE_AUTOFIX3_AUTO` env var:
   - default `false` — prod behavior unchanged
   - flip `true` on dev — validate on real workflow failures
   - flip `true` on prod after a clean observation week
5. Local tests first:
   - mock `run_nextflow_autofix` and verify the hook calls it with
     correct args on a fabricated failure
   - verify it does NOT fire on success
   - verify it does NOT fire on QC-gate failures (those have their own loop)
   - verify the env-var gate
6. Sync only after `python3 -c "import nextflow_workflow_runner"` smoke
   passes locally (PEP 604 / missing imports surfaced early).

## Status of today's local work

| Artifact | Status |
|---|---|
| `nextflow_runner.py` (standalone runner) | written + 9 runner tests pass |
| `_make_run_autofix_node` (Path A wiring) | written + 3 integration tests pass with langgraph installed |
| `langgraph_state.py` `autofix_result` field | added |
| `test_nextflow_runner.py` (12 tests total) | all green locally |
| Committed | ❌ — held per user direction "hold and ship together" |
| Synced | ❌ — same |

Next step: implement Path B locally, test, then commit + sync the whole
thing (runner + Path A wiring + Path B hook + tests) as a single atomic
deploy.
