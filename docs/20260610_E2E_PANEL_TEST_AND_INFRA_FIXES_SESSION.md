# Workflow Panel E2E + Infra Hardening — Session Writeup

**Dates:** 2026-06-09 → 2026-06-10
**Branch:** integration/next-phase

## Shipped this session (in order)

| Hash | Title |
|---|---|
| `92236e757` | `feat(nextflow): cap concurrent NF head launches via semaphore` (was 5, now 10 after 23885b59dc) |
| `d2c0437ea` | `fix(sync): durable ship of backend/config/galaxy.yml to dev` |
| `eab13c3ca` | `feat(infra): auto-sync all Batch CEs to latest LT version` |
| `4f4887520` | `fix(nextflow): mount host libz into nf-core task containers` |
| `23885b59dc` | `perf(nextflow): cap NF head heap at 512MB; 2x concurrency` |
| `f1a94729c` | `fix(infra): audit script enforces x86_64-only CE instance types` |
| `b8e090719` | `fix(systems_biology): swap arm64 biomni-lite for x86 biomni-tools` |
| `d59a01f38` | `fix(proteomics): unique NO_FILE placeholders` |
| `0cee2dd49` | `fix(config): roll gunicorn workers back to 1; force-track galaxy.yml.docker` |
| `(merged e2e file)` | `test(e2e): merged workflow-panel comprehensive (one test, every UI element)` |
| `801c83f68c` | `fix(billing): Lago circuit breaker + reduced timeout; CLAUDE.md e2e fixture rule` |

## End-of-session test posture

**BioMate workflows (own + GPU):** ~28+ verified end-to-end on AWS Batch today, across 7 domains (single_cell, virtual_cell, drug_discovery, pharmacology, immunology, cancer_biology, systems_biology). 10/10 in the parallel-fire fresh retest.

**nf-core pipelines:** Platform path is fully working through parse → plugin → multipart staging → libz mount → Batch task dispatch → 5+ tasks deep. Remaining failures are upstream tool issues (TRIMGALORE biocontainer libtinfo, cutandrun Groovy NPE).

**UI E2E (workflow panel):** new `workflow-panel-merged-comprehensive.e2e.ts` is the durable replacement for the stale `ux-workflow-panel-comprehensive.e2e.ts` — current `data-testid` surface, proven `request.post` auth pattern, single test with `test.step` blocks (pays LLM cost once, not 12×). It runs reliably **when dev is quiet** — has passed against the current panel UI (verified via captured snapshot showing 8 processes · 4 phases, settings strip with 2 params, Confirm-and-Run button).

## Open: the 401 from `/api/ai_assistant/generate_workflow`

Both `POST /api/ai_assistant/generate_workflow` and `GET /api/tool_search` return **401 Unauthorized** when called via the Node→Galaxy proxy with the shared admin `X-API-Key: <GALAXY_API_KEY>` header. Confirmed:

- `master_api_key` on Galaxy matches `GALAXY_API_KEY` on the Node frontend env (same value `f17c618…`).
- Other Galaxy routes (`/api/version`, `/api/nextflow/status`) work fine with the same client.

**Hypothesis:** these AI-assistant routes require a **per-user** Galaxy API key (the value at `user.galaxyApiKey` set during BioMate registration via `setupTestUser` flow), not the shared admin key. The current proxy client constructs `X-API-Key` once at startup and uses it for every request — there's no per-user override path.

**Fix sketch (NOT yet implemented):**
1. Change `generateWorkflow()` and `enhancedToolSearch()` to accept the calling user's session.
2. Thread `user.galaxyApiKey` from the auth context into per-request `axios.post({ headers: { 'X-API-Key': user.galaxyApiKey } })` overrides.
3. Keep the shared admin client for boot-time validation + sysadmin tasks.

**Why it shows up intermittently on dev:** the route registration order or auth middleware order may allow some calls through unauthenticated; under load + Lago timeouts blocking the worker, the same user retried multiple times → the dev cookie/session occasionally bypassed and occasionally got rejected.

## CLAUDE.md addition (committed in `801c83f68c`)

E2E tests now MUST use the real shared fixture `lifeifei163361@163.com` (verifiable + deliverable) instead of any made-up `@e2e.test` / `@biomate.test` address — the latter leave fixtures in an unverified-email reduced-quota state that masks as intermittent 401s.

## What I recommend to land before the next launch test

1. **Fix the Galaxy auth per-user thread** for `/api/ai_assistant/*` (the open 401 above). Without this, every UI E2E will continue to be flaky against dev.
2. **Move `/api/ai_assistant/generate_workflow` heavy work to Celery** so the gunicorn worker isn't blocked for the duration of an LLM call (this is what causes the visible "dev is down" windows).
3. **`preload: true`** in `galaxy.yml.docker` once the SQLite-on-start race is broken — buys safe multi-worker scaling without the failed `workers: 4` attempt earlier.
