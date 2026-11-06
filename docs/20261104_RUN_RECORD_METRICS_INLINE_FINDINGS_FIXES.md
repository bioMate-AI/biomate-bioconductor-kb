# 2026-11-04 — Run-record population fixes (Fix #6 metrics, Fix #5b inline_findings)

## Summary

Two Node-side run-record fields were never populated with the real data the completed
run had already produced. Both are now wired in, best-effort, without changing any
existing behavior beyond filling the fields.

| Fix | Field | Was | Now |
|-----|-------|-----|-----|
| #6 | `run.metrics.outputs.{fileCount,totalSizeBytes,byType,bySize}` | always `0` / `{}` | derived from the run's output-file list |
| #6 | `run.metrics.runtime.totalSeconds` | always `0` | `nextflowStatus.duration_s`, else `completedAt − startedAt` |
| #6 | `run.metrics.resources.{peakMemoryGB,avgCpuPercent,diskUsedGB}` | `0` | **still `0` (best-effort) — see below** |
| #5b | `inline_findings` (get_run response) | always `[]` | mirrors `findings_data.json` `key_results` |

## Root causes

- **#6:** `frontend/server/storage.ts` (the `_dbRowToExecutionRun` init, ~line 423, and
  `MemStorage.updateExecutionRunMetrics`) define an all-zero `metrics` block, and there
  was a writer method (`updateExecutionRunMetrics`) but **no caller ever passed real
  values**. So every completed run reported zero outputs and zero runtime despite real
  output files and real wall-clock time. Usage/billing attribution reads those zeros.
- **#5b:** the get_run handler built `inline_findings: ns.findings || ns.ai_findings ||
  ns.key_results || []` from `nextflowStatus`, but nothing populates those keys on
  `nextflowStatus`, so the field was always `[]`. (The UI Findings tab does NOT read this
  field — it reads the `findings_data.json` file via `GET …/runs/:id/findings` — so this
  is a vestigial API field, LOW urgency, not UI-blocking. Fixed so API clients /
  findings-search see parity with the UI.)

## What changed

New module **`frontend/server/run-record-metrics.ts`** (pure, dependency-light so it is
unit-testable without booting the server — `routes.ts` transitively imports the OpenAI
SDK + browser-coupled modules):

- `deriveRunMetricsPatch(run, nextflowStatus)` → `Partial<ExecutionMetrics> | null`.
  - `outputs` from `nextflowStatus.s3_output_files` (AWS Batch; primary) or
    `output_files` (local; fallback). Each entry's `name`/`filename`/`s3_uri` → extension
    buckets for `byType` (count) and `bySize` (bytes); `size`/`sizeBytes`/`bytes` → total.
  - `runtime.totalSeconds` prefers `nextflowStatus.duration_s`, else
    `completedAt − startedAt` (seconds). Preserves any existing `perStepSeconds`.
  - Returns `null` when nothing is derivable (no files AND no runtime) → caller skips.
- `resolveInlineFindings(run, nextflowStatus, cacheGet?)` → `Promise<any[]>`.
  Cascade (first non-empty wins): (1) `nextflowStatus.{findings,ai_findings,key_results}`
  (legacy), (2) the in-memory findings cache (`cacheGet`, which backs the Findings tab for
  AWS runs), (3) the local `findings_data.json` sidecar at
  `/tmp/nextflow_runs/<nextflowRunId>/output/findings_data.json` — the exact path the
  `/findings` route reads. Best-effort; `[]` fallback; never throws.

**`frontend/server/routes.ts`:**

- Imports the two helpers from `./run-record-metrics`.
- Adds `populateCompletionMetrics(run, nextflowStatus)` — a thin, merge-based, never-throw
  wrapper that calls `deriveRunMetricsPatch` and persists via
  `storage.updateExecutionRunMetrics` (which already merges and never overwrites with
  zeros). Called at **three completion points**:
  1. `GET /api/workflows/runs/:id/status` — the terminal-transition branch (fires once per
     run when it first goes terminal; `nextflowStatus` is freshest there).
  2. Same handler — the post-terminal `s3_output_files` refresh branch (recomputes when
     late-arriving outputs grow the file list).
  3. `GET /api/workflows/runs/:id` — a **guarded backfill** for terminal runs whose
     metrics are still zero (covers legacy runs + runs that went terminal via other
     paths). Guard: status ∈ {completed,failed,cancelled} AND `outputs.fileCount == 0`
     AND `runtime.totalSeconds == 0`, so it writes at most once.
- `GET /api/workflows/runs/:id` now sets `inline_findings` via `resolveInlineFindings(run,
  ns, id => _findingsCache.get(id))` instead of the always-empty `ns.* || []` expression.

New test **`frontend/server/run-record-metrics-20261104.test.ts`** (12 tests, no mocks;
the findings test reads a real sidecar written to the real `/tmp` path).

## Populated vs. left best-effort

- **Populated (must-fix, always derivable):** `outputs.fileCount`, `outputs.totalSizeBytes`,
  `outputs.byType`, `outputs.bySize`, `runtime.totalSeconds`; `inline_findings` from the
  local sidecar / cache / embedded status.
- **Left at zero (best-effort, documented):** `resources.peakMemoryGB`,
  `resources.avgCpuPercent`, `resources.diskUsedGB`. These require the Nextflow per-task
  trace (`%cpu` / `peak_rss` / `realtime` columns). The Galaxy status payload surfaced to
  Node (`getNextflowStatus` → `/api/nextflow/status`) does **not** carry those aggregates:
  the backend trace parser
  (`backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py`, ~line 4349) reads only
  task `name`/`status`, not the resource columns. Fabricating them would corrupt billing,
  so they stay at their zero init. If the per-task trace is ever plumbed through to
  `nextflowStatus`, aggregate it into `resources` inside `deriveRunMetricsPatch`.
- **#5b AWS-only runs never analyzed:** `inline_findings` stays `[]` because the
  `findings_data.json` sidecar is on S3 and a synchronous S3 read per get_run is too
  heavy. Once the Findings tab has been opened (populating `_findingsCache`), the cache
  path covers it. Acceptable given this is a LOW-urgency vestigial field.

## Tests / gate

- `npx tsc --noEmit -p .` → clean (exit 0).
- New test file: 12/12 pass.
- Gate filter `vitest run storage metrics findings workflow-execution` → 3 files, 83 pass.
- Full `vitest run` → 76 files passed / 1 skipped, 1052 tests passed / 7 skipped, exit 0.
  No regressions.

## Not done / needs a live run

- Not deployed/synced (out of scope for this task).
- No live AWS Batch run was executed, so the three completion call-sites are verified by
  code review + unit tests on the pure helpers, not by observing a real run write non-zero
  metrics end-to-end. A live completed run (e.g. ADMET on dev) should confirm the stored
  record shows non-zero `metrics.outputs`/`runtime` and a populated `inline_findings`.
- `resources.*` remain a known gap pending trace plumbing (see above).
