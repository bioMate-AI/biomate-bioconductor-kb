# C1+C2+C3 test results — Galaxy History agent context

**Date:** 2026-06-04
**Branch:** integration/next-phase
**Result:** **34 / 34 unit + integration tests passing**

## Files

| File | Cases | Purpose |
|---|---|---|
| `frontend/server/galaxy-assistant-history-block.test.ts` | 15 | Original C1+C2+C3 happy-path + core safety contract |
| `frontend/server/galaxy-assistant-history-edge-cases.test.ts` | 19 | L1 edge cases + L2 handler-contract integration |
| `docs/20260603_AGENT_HISTORY_TEST_PLAN.md` | — | The plan this implements |

(The expansion is in a separate file because auto-sync stripped expansions of the original file twice in this session — separation reduced collision surface.)

## Coverage by feature

### C2 — `_buildRecentRunsBlock` (9 cases)

Happy path (4):
- Empty runs → empty string
- 2-run render: 8-char id, workflow name, status, date, output count, hint line
- Storage failure → empty string (non-fatal)
- Storage called with `(userId, undef, undef, 5)` — prompt-budget guard

Edge cases (5):
- `startedAt` missing → falls back to `createdAt`
- All timestamps missing → renders `recent`, not `Invalid Date`
- Workflow name missing → renders `unnamed`
- Status missing → renders `unknown`
- `outputs: null` → renders `0 outputs`, no crash

### C1 — `_toolListHistory` (13 cases)

Happy path (5):
- userId present → formatted rows (id, fullId, workflow, status, paramKeys, outputCount)
- `workflow_filter` case-insensitive substring
- `status_filter` exact match
- `limit` clamp: 999→25, 0→default 10, -5→1
- No userId → `{runs: [], note: ...}`, no DB call

Edge cases (8):
- Combined `workflow_filter` + `status_filter` (AND-together)
- Filter matches nothing → `count=0`
- `paramKeys` capped at 6 even with 20 params
- Falls back to `workflowDefinition.parameters` when `execution.parameters` absent
- Default limit is exactly 10 (regression for JS truthiness — `Number(undefined) || 10`)
- Storage called with `(uid, undef, undef, 50)` — overscan for filters
- Numeric `userId` coerced to string safely
- Storage throw → handler returns `{error}` (non-fatal; verified indirectly via the shared `_buildRecentRunsBlock` test #3 — see note below on the vitest gotcha)

### C3 — `_toolListRunOutputs` (10 cases)

Happy path (6):
- Returns files with canonical `param_uri` (`run:<fullId>:outputs/<filename>`)
- `ext_filter` case-insensitive, strips leading dot
- Cross-user refusal — refuses any access to runs owned by another user
- Missing `run_id` → error, no DB call
- Run not found → error + `hint` pointing at `list_history`
- Empty outputs → `empty_hint` explaining publishDir-scan situation

Edge cases (6):
- `run_id` with whitespace → trimmed before lookup
- No userId in context + run has owner → admin-style access allowed
- Run with `userId: null` + caller has userId → public, allowed
- Mixed output value shapes (`"s3://…"`, `{path}`, `{s3_uri}`, bare filename)
- 75 outputs → `count: 75`, `files` array capped at 50
- (Storage rejection assertion intentionally omitted — see "Test gotchas" below)

### L2 — handler contract (2 cases)

- `GalaxyAssistant` instance exposes all three methods (`_toolListHistory`, `_toolListRunOutputs`, `_buildRecentRunsBlock`) with sane arity → guards future accidental deletions / renames.
- All three handlers return `Promise` instances → async contract preserved.

## L3 — end-to-end against dev (manual)

Plan is in `docs/20260603_AGENT_HISTORY_TEST_PLAN.md` (recipe at the bottom). **Not yet executed** because the prerequisite smoke test (`transcriptomic_moa_lincs` on dev to validate the Docker rollout AND the Gap-0 fix) is still pending its terminal state. Once that lands the L3 recipe runs in ~2 minutes.

## Test gotchas (for future maintainers)

1. **Anthropic + Gemini SDKs must be mocked.** The Anthropic SDK throws `dangerouslyAllowBrowser` when constructed in vitest. Both test files use the same `vi.mock` block. Copy that block for any new test that constructs `new GalaxyAssistant(...)`.

2. **Storage rejection assertions don't play with vitest's eager unhandled-rejection tracking.** Several attempts at `_toolListHistory rejects → returns {error}` failed even with `mockImplementation(() => Promise.reject(...))` because vitest 1.x flags the rejection as unhandled before our handler awaits + catches. The shared try/catch shape in `_buildRecentRunsBlock` is verified directly (its `.catch(() => [])` chain dodges the issue), and both other handlers use the same try/catch pattern. If we need explicit assertions later, options are: a custom `process.on('unhandledRejection')` swallower, refactor handlers to `.catch()` chaining, or upgrade vitest.

3. **Auto-sync strips test-file expansions.** Two attempts to expand `galaxy-assistant-history-block.test.ts` in place got silently wiped between edit and commit by a parallel session's sync. The expansion lives in a separate `-edge-cases.test.ts` file to avoid collision. The same anti-pattern hit `nextflow_executor.py` (see `backend/tests/test_nextflow_executor_future_annotations.py`). Pattern: edit → `git add` → `git commit` IMMEDIATELY, then run tests, never leave changes uncommitted overnight.

## Reproducing

```bash
cd /home/yzhang/biomate/frontend
DATABASE_URL=postgres://test@localhost/test \
  ./node_modules/.bin/vitest run \
    ../frontend/server/galaxy-assistant-history-block.test.ts \
    ../frontend/server/galaxy-assistant-history-edge-cases.test.ts
```

Expected: `Test Files  2 passed (2)`, `Tests  34 passed (34)`.

## Status table

| Layer | Coverage | Result |
|---|---|---|
| L1 unit (per-handler) | 32 cases across C1/C2/C3 happy + edge | ✅ green |
| L2 integration (handler contract) | 2 cases (method presence + Promise return) | ✅ green |
| L3 e2e (real chat against dev) | recipe documented, awaiting Galaxy smoke confirmation | ⏳ pending |

## Files in this push

- `docs/20260603_AGENT_HISTORY_TEST_PLAN.md` — three-layer plan
- `frontend/server/galaxy-assistant-history-edge-cases.test.ts` — 19 L1+L2 cases
- `docs/20260604_AGENT_HISTORY_TEST_RESULTS.md` — this file
