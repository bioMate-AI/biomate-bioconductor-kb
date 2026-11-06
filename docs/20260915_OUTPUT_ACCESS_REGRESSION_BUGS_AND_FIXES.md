# Output-access regression + reproducibility-record output resolution — bugs & fixes

**Date:** 2026-09-15
**Branch:** `integration/dev-test`
**Trigger:** while verifying the Phase-2 reproducibility record end-to-end against a
completed ADMET run, a completed run's outputs would not resolve, and a
logged-in owner could no longer download/preview their own outputs — a
regression on functionality that previously worked.

This document records the two related bugs found by tracing the session's
commits, their root causes, and the fixes.

---

## Bug 1 (CRITICAL, user-visible regression) — owner gets 403/404 on their own outputs

### Symptom
On dev, a logged-in owner hitting any of the output surfaces returned an error
where it **previously returned the file**:

| Route | Before IDOR fix | After IDOR fix (broken) |
|---|---|---|
| `GET /api/outputs/:id` | 200 (no auth) | **403** for the owner |
| `GET /api/outputs/:id/download` | 200 | **403** |
| `GET /api/outputs/:id/preview` | 200 | **403** |
| `GET /api/outputs/:id/parse` | 200 | **403** |
| `GET /api/invocations/:id/download-all` | 200 | **404** |
| `GET /api/invocations/:id/report` | 200 | 404 (galaxy-id case) |

Reproduction (dev, fixture owner of ADMET run `15736778…`, output `cba3777a…`):
```
/api/outputs/cba3777a…            no auth        → 401   (IDOR fix: correct)
/api/outputs/cba3777a…            cookie (owner) → 403   ← REGRESSION
/api/outputs/cba3777a…/download   cookie (owner) → 403   ← REGRESSION
/api/invocations/ea16ef8c…/download-all  cookie  → 404   ← REGRESSION
/api/runs/15736778…/reproducibility-record  bearer → 200 (same user ALLOWED on the run)
```
The last line is the tell: the **same user** was allowed by the canonical run
resolver (`resolveAuthorizedRun`) but denied by the output resolver
(`decideOutputAccess`) for outputs **of that same run**.

### Root cause
Commit `01442d7e5` ("fix(security): authorize legacy output/invocation routes
(close IDOR)") correctly added `authenticateToken` + ownership checks to six
previously-unauthenticated routes. But `decideOutputAccess`
(`frontend/server/output-access.ts`) resolved the owning run **only** by
interpreting `output.invocationId` as a `WorkflowInvocation` primary key:

```
output --(getInvocation by PK)--> invocation --(galaxyInvocationId)--> run --> decideRunAccess
```

For **nextflow** runs that assumption is wrong:
- an output's `invocationId` field holds the **`galaxyInvocationId`** (outputs
  are keyed by galaxy id — `getInvocationOutputs("ea16ef8c…")` returns them),
  **not** a `WorkflowInvocation` PK;
- there is frequently **no `WorkflowInvocation` PK row at all** — the owner
  lives on the `ExecutionRun` (resolvable by galaxy id).

So `getInvocation(galaxyId)` returned `undefined` → the access target was
`undefined` → the resolver **failed closed** to 403 (its designed behavior for
"no resolvable owner"). Because the routes had **no auth before**, they always
served; after the fix they always denied — for everyone, including the owner.
`download-all` failed one step earlier (its own id→invocation resolution had no
galaxy-id→ExecutionRun fallback) and returned 404.

This is a fail-closed authorization bug, not a data bug: the outputs and the
ownership link both existed; the resolver just didn't know how to walk from a
galaxy-id-keyed output back to the owning run.

### Fix (root cause) — commit `962a3fb4b`
Resolve the owning run **the way outputs are actually keyed**, trying each
meaning of `output.invocationId` in turn and failing closed only if none
resolve (so IDOR stays closed for strangers):

`frontend/server/output-access.ts` — new `accessTargetForOutputInvocationId(invId, deps)`:
1. `getInvocation(invId)` — `invId` as a `WorkflowInvocation` PK → invocation → run/owner (original path, preserved).
2. `getRunByGalaxyId(invId)` — `invId` as a `galaxyInvocationId` → owning `ExecutionRun` **(the nextflow case)**.
3. `getInvocationByGalaxyId(invId)` — `invId` as a `galaxyInvocationId` → `WorkflowInvocation` → run/owner.

- `OutputAccessDeps` gains optional `getInvocationByGalaxyId`.
- `routes.ts` `outputAccessDeps` now injects `getInvocationByGalaxyId: storage.getInvocationByGalaxyId`.
- `GET /api/invocations/:id/download-all`: added a fallback that resolves the
  owning `ExecutionRun` by galaxy id / run id when there is no
  `WorkflowInvocation`, authorizes via that run (`decideInvocationAccess` with a
  synthetic owner target), and streams the outputs keyed by the galaxy id.
- `GET /api/invocations/:id/report`: resolves by `getInvocationByGalaxyId` too.

### Tests
`frontend/server/output-access.test.ts` +2 regression tests:
- owner of a nextflow output keyed by `galaxyInvocationId` (no PK invocation) is
  **authorized** via `getRunByGalaxyId`; a stranger is still **403**;
- authorization also works when the galaxy id resolves a `WorkflowInvocation`
  row (path 3).

`tsc` clean; `output-access` + `run-output-route-auth` + `reproducibility-record`
suites green (35 tests).

### Why the IDOR fix's own tests didn't catch it
The unit tests modeled the Galaxy shape only: `output.invocationId` = a
`WorkflowInvocation` PK whose `getInvocation` returns a row with a
`galaxyInvocationId`. They never modeled the nextflow shape (invocationId **is**
a galaxy id, no PK row). The route-auth tests asserted "stranger denied /
unauth 401" but used the same Galaxy-shaped fixtures, so the owner-allow case
for a galaxy-id-keyed output was never exercised. The new tests close that gap.

---

## Bug 2 (related) — reproducibility record shows 0 outputs for a completed run

### Symptom
`GET /api/runs/:id/reproducibility-record` (and `?checksums=1`) returned
`outputCount = 0` for a completed ADMET run whose outputs were reachable via
`/api/invocations/:galaxyId/outputs` (5) and `/output_files` (6).

### Root cause
The record endpoint fetched outputs via the canonical `runsOutputsService.list()`
(which derives the S3 output prefix and returned 0 for this run's actual
prefix), then fell back to `storage.getInvocationOutputs(...)`. The fallback
keyed by the wrong id and did not consistently reach the outputs that are keyed
by `galaxyInvocationId`. This is the same output-resolution fragmentation as
Bug 1: outputs are addressable by several id shapes across
`runsOutputsService` / `getInvocationOutputs` / `/output_files`, and the record
endpoint didn't align with how they are actually stored.

### Status / fix direction
Partially addressed (invocation-output fallback added in `3b479671`); the
record endpoint should reuse the **same** galaxy-id-first resolution now proven
correct in Bug 1's fix rather than more ad-hoc fallbacks. Tracked as the
remaining Phase-2 "one common output resolver" unification: make
`runsOutputsService` authoritative and have the record endpoint call it, so
outputs resolve identically for the Outputs tab, the record, and downloads.

---

### Verification on dev (after deploy `962a3fb4`, healthy)
Against the completed ADMET run (owner = fixture user), using a **current**
output id (the earlier id had regenerated — see note below):

| Route | Before | After |
|---|---|---|
| `GET /api/outputs/:id` (owner, cookie) | 403 | **200** |
| `GET /api/invocations/:id/download-all` (owner) | 404 | **200** |
| `GET /api/outputs/:id` (stranger, no auth) | 401 | **401** (IDOR closed) |

Confirmed the output's `invocationId` field is literally the run's
`galaxyInvocationId` (`ea16ef8c…`) — exactly the shape that broke resolution.

> **Note (in-memory storage):** `storage.getOutput`/`getInvocationOutputs` are
> in-memory maps and `addOutput` assigns a fresh `randomUUID()` on each
> ingest, so output **ids are not stable across container restarts**. After a
> deploy, re-fetch ids from `/api/invocations/:galaxyId/outputs` before testing
> a specific output. (This id instability is a separate durability concern.)

---

## Bug 3 (pre-existing, not a regression) — single-file download of S3 outputs 404s

### Symptom
`GET /api/outputs/:id/download` returns `404 {"error":"Output has no
downloadable source"}` for nextflow outputs, even for the authorized owner.

### Root cause
The download route only streamed from `output.galaxyDatasetId` (Galaxy) or a
local path. Nextflow outputs have neither — their bytes live in **S3**, recorded
at `output.metadata.s3Uri`. The route never read `s3Uri`, so every S3-backed
output fell through to the 404 branch. This predates the auth work (the IDOR
commit left the source-resolution branch untouched), but it means "download my
result file" was silently broken for all nextflow runs.

### Fix — same commit series
`GET /api/outputs/:id/download` gains an S3 branch: when there is no
`galaxyDatasetId`/local path but an `s3Uri` (top-level or `metadata.s3Uri`),
parse `s3://bucket/key`, `GetObject`, and stream the body — the same S3 access
pattern already used by the reproducibility-record checksum enrichment.
`download-all` already tolerates missing sources (it skips them), which is why
it returned 200 while single-file download 404'd.

---

## Broader lesson

Both bugs are the same shape: **output resolution is fragmented** — outputs are
keyed by `galaxyInvocationId`, the owner lives on the `ExecutionRun`, and there
is often no `WorkflowInvocation` PK row for nextflow runs, yet several code
paths assume the Galaxy shape (PK invocation with linked outputs). Any new code
that resolves an output → its run (for auth, for the record, for downloads)
must handle the galaxy-id-keyed shape or it will silently fail closed / return
empty. The durable fix is a single resolver used by every surface; until then,
new surfaces must be tested against a **real nextflow run**, not only
Galaxy-shaped fixtures.
