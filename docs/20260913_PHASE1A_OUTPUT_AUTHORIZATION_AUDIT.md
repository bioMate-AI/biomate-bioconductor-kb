# Phase 1A audit — Authenticated output truth (IDOR closure)

**Date:** 2026-09-13
**Scope:** the P0 "Authenticated output truth" gap in Phase 1 (execution &
object coherence) of
[`20260912_V2_GAP_REBASE_AFTER_SIMPLIFICATION.md`](20260912_V2_GAP_REBASE_AFTER_SIMPLIFICATION.md).
**Commit(s):** `01442d7e5` (fix), building on `badb4c069` (chat-to-file
resolution) and `70186671b` (sync silent-fail hardening).

## Problem

Six output/artifact surfaces fetched by id and returned bytes/content with **no
authentication and no ownership check** — a caller could enumerate ids and read
another user's run outputs (IDOR / broken object-level authorization):

| Route | Behavior before |
|---|---|
| `GET /api/outputs/:id` | returned output metadata for any id |
| `GET /api/outputs/:id/download` | streamed output file bytes for any id |
| `GET /api/outputs/:id/preview` | returned first N lines for any id |
| `GET /api/outputs/:id/parse` | parsed VCF/FASTA/etc for any id |
| `GET /api/invocations/:id/download-all` | zipped all outputs for any id |
| `GET /api/invocations/:id/report` | returned the workflow report for any id |

The run-level surfaces (`/api/runs/*`, `/api/workflows/runs/*`) were already
authorized via `decideRunAccess`; these legacy id-addressed routes predated that
policy and were never brought under it.

## Fix

New canonical resolver `frontend/server/output-access.ts` applies the **same**
owner/project-member policy the run surfaces use (`decideRunAccess`), by walking
the object graph back to the owning `ExecutionRun`:

```
output --(invocationId)--> invocation --(galaxyInvocationId)--> run(userId,projectId)
```

- `decideOutputAccess(outputId, userId, deps)` — for the four `/api/outputs/:id*`
  routes; returns the fetched output on success (no re-read). Generic over the
  concrete output type so route bodies keep `OutputDataset`.
- `decideInvocationAccess(invocation, userId, deps)` — for the two
  `/api/invocations/:id*` routes, called after each route resolves its
  invocation (by id / galaxy id / execution run).
- **Fail-closed:** an object that cannot be resolved to an owning run is denied
  (403 authenticated / 401 unauthenticated), never served. Legacy invocations
  with no linked run authorize by their own `userId` only.

All six routes now carry `authenticateToken`. Dependencies are injected, so the
policy is unit-testable without a live store.

## Tests

- `frontend/server/output-access.test.ts` (10 tests): owner allow, project-member
  allow, stranger→403 (IDOR blocked), unauthenticated→401, missing→404, orphan
  fail-closed→403, legacy-invocation owner fallback (+ stranger denied, no run
  query).
- `frontend/server/run-output-route-auth.test.ts`: extended `protectedRoutes`
  with all six routes — asserts each registration includes `authenticateToken`.
- `frontend/server/run-access.test.ts` (22 tests): the underlying policy,
  unchanged.
- Commands: `npx tsc --noEmit -p .` → clean; `npx vitest run` → **1471 passed,
  7 skipped, 0 failed**.

## Authenticated dev exercise

- **Environment:** https://dev-public.biomate.ai (frontend image
  `cac605b6…`→ rebuilt to the `01442d7e` bundle, container created
  2026-09-13T23:25:42Z; `grep -c decideOutputAccess /app/dist/index.js` = 5).
- **Identity:** shared E2E fixture `lifeifei163361@163.com` (JWT via
  `/api/auth/login`, `X-E2E-Test-Token` bypass on dev).
- **Result** (random non-existent id `00000000-…-0000deadbeef`):

| Route | No token | With token |
|---|---|---|
| `/api/outputs/:id` | **401** | 404 |
| `/api/outputs/:id/download` | **401** | 404 |
| `/api/outputs/:id/preview` | **401** | 404 |
| `/api/outputs/:id/parse` | **401** | 404 |
| `/api/invocations/:id/download-all` | **401** | 404 |
| `/api/invocations/:id/report` | **401** | 404 |

Before the fix these routes ran the handler with no auth (lookup → 404/500 or,
for a real id, served the bytes). Now unauthenticated access is rejected at the
middleware (401) and authenticated access is scoped by the ownership policy
(random id → 404). The cross-user 403 path is covered by the unit tests
(`stranger→403`, `orphan→403`); it was not re-exercised live because the repo's
E2E discipline mandates a single fixture account and cross-user isolation is
owned by the unit/policy tests.

## Remaining risks / follow-ups

- **Output metadata carries no direct `userId`/`projectId`.** Authorization
  relies on the output→invocation→run chain. If an output's `invocationId` is
  null and there is no linked run, it is denied (fail-closed) — correct, but
  such orphans become unreadable; acceptable for P0.
- Broader Phase-1 P0 items remain open and are the next work: **real inputs
  bound before compute** (record resolved dataset id/version in the run record;
  never report success for an unbound/default workflow), **compatibility
  validation for comparisons**, and **honest blocked states** (block
  `workflowGenerationFailed`, thread unresolved references into execute).

## Conclusion

**GO** for the "Authenticated output truth" P0 within Phase 1A. No unresolved P0
finding remains in this sub-scope: every id-addressed output/invocation surface
now enforces the same owner/project-member authorization as the run surfaces,
verified by unit tests and an authenticated dev exercise. Phase 1 as a whole is
not yet complete — see remaining P0 items above.
