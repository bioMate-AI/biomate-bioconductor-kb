# Agent-engineering gap fixes — implemented + validated (2026-10-05)

Follow-on to the evaluation in `docs/20261005_AGENT_ENGINEERING_EVALUATION.md` (BioMate vs the 6
production agent-engineering principles). Of the prioritized gaps, two high-value, low-risk ones were
implemented, deployed to dev, and **validated live**. This records what was done, why, and the evidence.

## Fix 1 — Compute-dispatch idempotency (eval gap 3e) ✅ implemented + validated
**Problem:** `/api/workflows/execute` had no idempotency on first dispatch — a rapid duplicate
submission (double-click / client retry / network hiccup) launched a **second paid AWS Batch job**. The
existing dedupe only covered *retries of failed runs during AutoFix*.

**Fix** (`frontend/server/routes.ts`, commit `e978afcbb`): before dispatch, if an **identical** workflow
(same `buildWorkflowFingerprint`, same user/project) is already **in flight** (configuring/pending/
submitted/queued/running) within a **120 s window**, return that existing run instead of launching again.
Only in-flight states dedupe — a user may legitimately re-run a **completed or failed** workflow, and
explicit retries are handled separately. Response carries `deduplicated: true` + the existing run's ids.

**Validated live on dev** (deploy `af5afbba`, healthy):
- 1st dispatch → new run `e4c02926` (`deduplicated: null`, launched).
- 2nd identical dispatch 3 s later → **same run `e4c02926`, `deduplicated: true`** ("An identical
  workflow is already running…") — **no second Batch job.** Server log confirms:
  `[execute] idempotent dedupe → identical workflow already in flight … returning it instead of launching a duplicate Batch job`.
- tsc clean; no new errors/tracebacks in dev logs.

**Scope/limits:** catches the real double-submit case (cost protection). A client-supplied idempotency
key (persisted on the run) would be the stricter form; deferred (needs a schema field) since the
fingerprint+window dedupe covers the practical case.

## Fix 2 — Configurable quota-on-execute (eval gap 3c, quota half) ✅ implemented + validated
**Problem:** `/api/workflows/execute` (the costliest op) had **no `checkBillingQuota`**, while cheaper
AI-generation/import endpoints did. Requirement from the owner: **check quota on our AWS platform; skip
it on-premise** (on-prem runs the customer's own compute — no SaaS metering).

**Fix** (`frontend/server/quota-middleware.ts` + `routes.ts`, commit `af5afbbaa`):
- New `quotaEnforcementEnabled()` — **explicit override** `BIOMATE_QUOTA_ENFORCEMENT=on|off`, else
  **inferred from deployment**: enforce ONLY on AWS SaaS (`NEXTFLOW_USE_AWS=true` and no MinIO
  `S3_ENDPOINT_URL`); on-prem (MinIO set, or not on AWS Batch) → **skip**. One toggle, applied inside the
  `checkBillingQuota` middleware so **all** quota-gated endpoints behave consistently.
- Middleware now short-circuits (`return next()`) when enforcement is off or for E2E-bypass requests (so
  on-prem never meters and tests/fixtures aren't blocked).
- Added `checkBillingQuota('Workflow execution')` to `/api/workflows/execute`.

**Validated:**
- Toggle logic unit test — **ALL_PASS**: AWS SaaS → enforce; on-prem MinIO → skip; on-prem no-AWS →
  skip; explicit `off` on AWS → skip; explicit `on` on-prem → enforce.
- Deployed; execute still succeeds under the E2E-skip path (not blocked); no quota errors in dev logs.

**Note on the auth half of gap 3c:** `/api/workflows/execute` still uses `optionalAuth` on HEAD. The
colleague **already adds `authenticateToken + ownership`** on `integration/next-phase` (`77e0de074`), so
that was deliberately **not** duplicated here (would conflict with their area) — it lands when next-phase
merges. This fix adds the complementary **quota** gate.

## Not done (scoped deliberately)
- **Unified production per-layer trace (eval gap 5d)** — a real observability build (persist model input +
  retrieved content + tool params + per-node latency + real token usage in one joined record). Larger
  than a point fix; scope separately. Documented as the #3 gap in the evaluation.
- **Auth on execute (3c auth half)** — handled on next-phase (see above).
- **Scoped on-prem deployment** — assessed separately in `docs/20261005_ONPREM_SCOPED_DEPLOYMENT.md`:
  on-prem *infra* is ready on next-phase; domain/task/instrument *scoping* (manifest + catalog subsetter +
  launch enforcement) is a documented, not-yet-built capability.

## Commits
- `e978afcbb` — idempotency dedupe on `/api/workflows/execute`.
- `af5afbbaa` — configurable quota (`quotaEnforcementEnabled`) + `checkBillingQuota` on execute.
- `2b5cef288` — the agent-engineering evaluation.
- `548a2c0c2` — the on-prem scoped-deployment assessment.
All synced to dev (`sync_to_dev.sh`, result=healthy); validations above are against the live dev stack.

## Pre-existing dev issues observed (NOT from this work, not fixed here)
- AWS SES email send errors (`@aws-sdk/client-ses`) and transient `[auth] Galaxy provisioning FAILED …
  fetch failed` — pre-existing dev-network/SES flakiness, unrelated to these changes.
