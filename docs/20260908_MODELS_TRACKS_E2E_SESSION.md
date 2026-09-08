# Models Tracks — E2E Session Record

**Date:** 2026-09-08
**Scope:** comprehensive end-to-end testing of the Models-module phase upgrade
(PR #212, approved/merged to `feat/dl-upgrade-wave3`), plus fixes + audit.
**Harness:** `scripts/e2e_models_tracks.sh` (new; modeled on the canonical
`scripts/e2e_use_cases.sh`).
**Companion:** `docs/20260907_MODELS_MODULE_PHASE_UPGRADE_ARCHITECTURE.md`,
`docs/20260907_MODELS_MODULE_TEST_PLAN.md`.

---

## What was built

`scripts/e2e_models_tracks.sh` — a consolidated HTTP-level E2E for the new
functions, following the CLAUDE.md e2e discipline (single canonical fixture, one
login + one project, Flow A journey + Flow B gate probes, per-run log,
P0/P1/P2 gating, 90 s LLM/worker timeouts). It proves the **live wiring** the
unit suites cannot:

- **A1** `GET /api/models` is a live array (registry catalog).
- **A2** `GET /api/model-tracks/train` → `{runs: [...]}` (honest-empty on a fresh project).
- **A3** `GET /api/model-tracks/adapt` → `{pairs: [...], pendingCount}`.
- **A4** `GET /api/model-tracks/optimise` → `{active:false}` or a loop with `rounds[]`.
- **A5** `POST /api/model-tracks/adapt/retrain` → terminal status + `runId`.
- **A6** the retrain `runId` appears in the runs/dashboard list, tagged training.
- **A7** `POST /adapt/{id}/toggle` **persists** across a re-read (the sidecar override).
- **Flow B** route-gate posture (see the auth note below).

Coverage map (documented in the harness header, not re-implemented): rendering /
objects-not-strings / empty states / safety-gate display live in
`models.test.tsx`; Optimise math + toggle flip/round-trip live in
`test_models_inference_shape.py`. The harness adds only the live proxy→Galaxy→
store wiring + persistence + cross-surface run.

---

## Findings (this is the audit)

### F1 — BLOCKER: the Models-module code is NOT deployed to dev
`GET /api/models` and `GET /api/model-tracks/*` return
`{"error":"NotFound","message":"API route … not found"}` (HTTP 404) on
`https://dev-public.biomate.ai`.

- **Root cause:** PR #212 merged to `feat/dl-upgrade-wave3`, but that branch has
  not been merged to `integration/next-phase` (the branch that syncs to dev),
  so the routes are not live. This is a **deploy-pipeline state**, not a code bug.
- **Proof the code is correct:** both the Node routes
  (`frontend/server/routes.ts:4944-4945`, `_adaptRetrainHandler`) and the Galaxy
  routes (`models_inference.py:486/580/693/711/767`) are present and correctly
  wired in the merged branch; `tsc`, FE vitest (19/19), and BE shape tests
  (19/19) are green.
- **Correct next step (NOT taken here — it is a release action):** merge
  `feat/dl-upgrade-wave3 → integration/next-phase`, run the pre-sync checklist,
  `scripts/sync_to_dev.sh`, then re-run this harness. Per CLAUDE.md we do **not**
  sync un-merged code out of band.

### F2 — FIXED (test-quality bug in the harness): false-green on JSON error pages
The first draft asserted "returns JSON" via `is_json`. A Node 404 envelope
(`{"error":"NotFound"}`) *is* valid JSON, so those assertions false-greened even
though the route was missing. **Fix:** added a `route_missing` detector + a
**preflight** that aborts with a clear deploy diagnosis (exit code **3**), and
changed every read assertion to check the **contract shape** (`runs`/`pairs`/
`rounds`/array), not merely "parses as JSON".

### F3 — FIXED (test-correctness bug): wrong 401 expectation in Flow B
The first draft expected `GET /api/model-tracks/train` (no token) → 401. But the
Models + model-tracks routes use **`optionalAuth`**
(`frontend/server/auth-middleware.ts:219`), which calls `next()` with no user
when there is no token — it **never returns 401**. (Only `requireAuth` routes
like `/api/projects` do.) Asserting 401 would have been a fabricated expectation.
**Fix:** Flow B now asserts the real posture — the route is *reachable* (not a
404 "route not found") and the greedy `/api/models/{id}` route does not swallow
the `/api/model-tracks/*` prefix (risk R1 in the test plan).

### F4 — reviewed, NO bug: retrain run-registration under no-auth
`_adaptRetrainHandler` reads `req.user?.id` (undefined under optionalAuth with no
token) and `req.query.project`; both are optional to `createExecutionRun`, and
the whole registration is best-effort in a try/catch that only logs. A missing
user or a Postgres failure cannot break the retrain API response. Confirmed
correct by reading the diff end-to-end.

---

## Exit-code contract (for CI)

| Code | Meaning |
|---|---|
| 0 | all P0+P1 green |
| 1 | P1 fail(s) — sync possible, file a release note |
| 2 | P0 fail — do NOT sync |
| 3 | **preflight: endpoints not deployed to the target** (merge+sync first) |

Current run against dev: **exit 3** (not deployed) — as expected.

---

## Status & next steps

- Harness authored, syntax-valid, and **correctly self-diagnoses** the deploy
  state (verified: exit 3 against dev with a clear message).
- Two harness bugs found and fixed (F2, F3); one handler path reviewed clean (F4).
- **The functional E2E assertions (A1–A7) cannot go green until PR #212's branch
  reaches dev.** That is a release step (merge to `integration/next-phase` +
  sync), intentionally out of band of this testing session.
- When deployed, re-run `BIOMATE_URL=https://dev-public.biomate.ai
  bash scripts/e2e_models_tracks.sh` and drive A1–A7 to green; A6/A7 self-skip
  with a documented pointer when the project has no runs/pairs yet.
