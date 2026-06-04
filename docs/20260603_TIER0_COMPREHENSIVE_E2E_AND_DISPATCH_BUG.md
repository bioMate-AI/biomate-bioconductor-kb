# Tier 0 — Comprehensive E2E + Node↔Galaxy dispatch bug

Date: 2026-06-03

## Outcome

- **All 5 tier 0 demos pass 4/4 phases on AWS Batch** (CLI sweep — T01–T05)
  - T01 bispecific_format_triage: ✅ (3 m 12 s)
  - T02 in_vivo_cart_codesign: ✅ (1 m 27 s)
  - T03 in_vivo_base_edit_design: ✅ (1 m 46 s)
  - T04 glp1_modality_bakeoff: ✅ (1 m 30 s)
  - T05 modality_triage: ✅ (1 m 56 s)
- **Comprehensive Playwright E2E built and live** (`frontend/e2e/tier0-full-e2e.e2e.ts`).
  Validates end-to-end UX from registration → chat → workflow card → param prefill →
  run dispatch → SSE `data-status="running"` transition → findings endpoint →
  methods-report download. **13/17 assertions pass** on T01 against dev.
- **One real frontend regression found and fixed**: dev was serving a stale bundle
  (`index-CeGFxOCv.js`) missing commit `abe8b45b8` (`fix(hooks): lift
  useAfterRunFlavor() out of JSX in ChatWithArtifacts`). Every chat turn crashed
  with React error #310. `sync_to_dev.sh` rebuilt to `index-DL9w8BxD.js` — fixed.

## Open issue — Nextflow JVM dies prematurely on dev (FD-decoupled fix lost again)

The Node↔Galaxy dispatch plumbing is actually fine. Verified via direct curl
to `/api/workflows/execute`: returns `runId`, `galaxyInvocationId`,
`nextflowRunId`, executionEngine, status="running" — all persisted. Status
endpoint `/api/workflows/runs/:id/status` returns rich `nextflowStatus` with
`log_tail` and live state. methods-report works (5223 chars).

The real bug is that **the Nextflow CLI process dies ~60 s after submitting
Phase A on dev**:

- Manual dispatch: runId `1a1cb5c1...` → Nextflow runId `94d3729e...`
  → status=failed at 02:51:55 (62 s), returncode=1
- `.nextflow.log` truncates at the AWS Batch submit line for Phase A
  (102 lines total). Phase A's Batch job (`b7bf4e2a-...`) was successfully
  submitted to AWS Batch, but the parent Nextflow JVM exited before the
  Batch job completed — no further log lines written.
- This matches the prior session's "gunicorn worker recycle kills the
  Nextflow child" failure mode that the FD-decoupled subprocess fix
  (commits `4efb990e1` then re-applied as `c02b72697`) was meant to solve.

**Root cause: the FD-decoupled fix has been stripped again** from both the
local working copy AND the deployed `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py`:

- Line 3127: `stdout=subprocess.PIPE` (should be `stdout=open(log_path, "wb", 0)`)
- Line 3661: `stdout=subprocess.PIPE` (same)
- `_stream_logs` at line 2506 still does `for line in process.stdout` — depends
  on PIPE, would need rewrite to `process.wait()` + post-process when stdout
  is redirected to a file handle.

This is a recurring parallel-session sweep regression (noted in previous
session: "multiple critical fixes lost during the session due to parallel
session edits; required re-application").

### 2026-06-04 follow-up: three fixes shipped (FD-decouple, CRT, WARN regex)

All three regressions diagnosed in this doc have been re-applied to
`nextflow_executor.py`, committed, pushed, and (for FD-decouple/CRT)
verified live on dev:

- **`41181b086`** — FD-decouple Nextflow subprocess. Both Popen sites
  (`stdout=open(log_path, "wb", 0)`) and `_stream_logs` rewritten to
  `process.wait()` + post-process. Verified live: a manual dispatch ran
  Phase A→D in 88s with status=completed, returncode=0.
- **`a5194128f`** — AWS CRT SIGSEGV mitigation. Per-run cache dir,
  `-Xss2m`, `-Daws.crt.disable.crt.in.client=true` appended to `NXF_OPTS`.
  Verified live: `ps -ef` on dev shows the flags applied to running
  Nextflow JVMs.
- **`4b4f96c37`** — `_NF_LOG_EXCEPTION_RE` no longer matches `WARN`.
  Previously, `WARN nextflow.Session - There's no process matching config
  selector: CRYODRGN_TRAIN` (benign) was triggering
  `_log_indicates_nextflow_failure → trace_failed=True →
  /api/nextflow/status returning status=failed,rc=1` while the JVM was
  still alive. Verified live: status correctly reports `running` for the
  full Phase A window (was `failed` within 20s before).

All three fixes have inline DO-NOT-REVERT comments pointing at this doc.
Local AST + smoke checks added before each sync (parallel-session sweep
risk was the recurring cause of these regressions).

Open infra issues this session (NOT in scope, but blocking the full
Playwright E2E rerun):

- Frontend container crash-loop on dev: `relation "users" already exists`
  on boot migration; addressed by parallel commit `573a43e90` (recover
  already-applied migrations instead of crashing).
- Galaxy dev container churning (multiple restarts during testing,
  visible as runs disappearing from `/tmp/nextflow_runs/`). Dev EC2 at
  80% disk per SSH banner — may be the underlying trigger.

Once dev is stable, the comprehensive Playwright E2E
(`frontend/e2e/tier0-full-e2e.e2e.ts`) should pass 17/17 on T01 because
all three failure modes diagnosed above are now resolved.

### Original recovery sketch (kept for reference)

1. Re-apply the FD-decouple at both Popen sites:
   ```python
   log_fh = open(log_path, "ab", buffering=0)
   process = subprocess.Popen(
       cmd, stdout=log_fh, stderr=subprocess.STDOUT,
       cwd=str(work_dir), env=env,
       start_new_session=True, close_fds=True,
   )
   log_fh.close()  # subprocess holds its own fd
   ```
2. Rewrite `_stream_logs` to `process.wait()` then post-process the file
   (the per-line iteration over stdout no longer applies).
3. Add an inline `# DO NOT REVERT — see docs/20260603_TIER0...` guard comment.
4. `scripts/sync_to_dev.sh`, manually dispatch one tier 0 run, verify it
   completes 4/4 phases on Batch via `/api/workflows/runs/:id/status`.
5. Only then re-run the comprehensive E2E (`tier0-full-e2e.e2e.ts`) and
   confirm all 17 assertions pass.

## Artifacts

- `frontend/e2e/tier0-full-e2e.e2e.ts` — comprehensive test harness
  (registration → chat → workflow card → params → run dispatch →
  SSE → findings → methods-report → download → output chips). Currently
  parameterized for T01 only via `TIER0_DEMOS` array; extending to
  T02–T05 is a one-line change once the dispatch bug above is fixed.
- `frontend/e2e/screenshots/tier0-full/T01/` — 6 stage screenshots
  (logged in, workflow card, form prefilled, after run click, phase running,
  final state). 05_phase_running confirms correct UX: bispecific_format_triage
  panel with PD-1/VEGF/CrossMab/NSCLC and Phase A in `Running` state.

## Files touched

- `frontend/e2e/tier0-full-e2e.e2e.ts` — added ESM-safe `__dirname`
  (`fileURLToPath(import.meta.url)`).
- Dev frontend bundle redeployed (`index-DL9w8BxD.js`).
