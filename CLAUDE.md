# BioMate Project Instructions

## Development Process

**Every task follows this iterative loop — no exceptions:**

1. **Implement** — write the code change
2. **Test** — run the relevant E2E or unit test suite
3. **Record** — capture screenshots / logs / audit JSON
4. **Audit** — visually review screenshots; read logs for regressions or wrong content
5. **Fix** — patch any failures or UI issues found in the audit
6. **Repeat** — loop until all assertions pass and screenshots look correct

Do not consider a task done until the full loop completes with a green test run and a clean screenshot audit.

**Cross-environment iterative loop (multi-use-case testing):**

After any significant fix or feature:
1. Test all use cases from the Claude design reference (ADMET, RNA-seq, WGS, CryoEM, CRO compliance, drug discovery)
2. Cover all features: workflow execution, auto-loop QC, AI findings, final report download, parameter overrides, real-time SSE step updates
3. Commit changes with `git add + git commit`
4. Run `scripts/sync_to_dev.sh` to push to dev EC2
5. Re-test the same use cases on dev (http://dev.biomate.ai or the dev EC2 URL)
6. Fix any regressions found on dev and repeat from step 1

Never ship a fix that only works locally — always verify on dev.

**Document periodically:** After every significant session, create a date-prefixed doc in `docs/` capturing: what was changed, what was tested, known open issues, and next steps. This is required — do not skip it.

---

## Documentation Rule

**All session documents, findings, plans, and technical notes MUST go into `docs/` or a subfolder of `docs/`.**

- Use date-prefixed filenames: `docs/20260318_TOPIC_NAME.md`
- Never create `.md` files in the repo root, backend root, or frontend root
- The `docs/` directory is the single source of truth for all written technical outputs

---

## Testing Rules

**NEVER mock API calls in E2E tests.** All E2E tests run against the live server with real backend responses. No `page.route()` interception, no `msw`, no `nock`, no stub responses. If a test requires data that depends on backend state, set it up through the real API or real UI actions.

Unit tests may use mocks only for external third-party services (e.g. AWS, Stripe) where real calls are impractical.

---

## Billing System

**Always use and test the AWS production billing stack. Never use or test against the local Lago Docker container.**

### Architecture

BioMate billing has three layers that must all be exercised together:

1. **Lago (SaaS metering)** — hosted on AWS EC2 at `http://35.86.137.71:3000`
   - API key: `01b71711-be39-49af-8d14-87a4ee827157`
   - Tracks LLM token usage, vCPU-hours, memory-hours, GPU-hours, S3 storage
   - Customers keyed by `userId` (integer from DB)

2. **Java billing service** — hosted on AWS EC2 at `http://35.86.137.71:8080`
   - Set `JAVA_BILLING_ENABLED=true` and `JAVA_BILLING_SERVICE_URL=http://35.86.137.71:8080`
   - Handles subscription lifecycle, plan enforcement, invoice generation
   - Must be enabled when testing quota enforcement or plan gating

3. **AWS Lambda functions** (event-driven, always-on in production):
   - `biomate-batch-billing` — triggered by EventBridge on Batch state changes (RUNNING/SUCCEEDED/FAILED); records job_started and job_completed events
   - S3 billing Lambda — triggered by S3 PutObject/DeleteObject; records storage events
   - Both call `POST /internal/billing/job_completed` and `/internal/billing/s3_put` on the Galaxy backend

4. **Redis** — AWS ElastiCache at `redis://biomate-billing-redis.xzhevl.0001.usw2.cache.amazonaws.com:6379`
   - Stores real-time in-flight cost accumulators (per-job vCPU-second counters)
   - Required for `/api/billing/jobs/running` live cost estimates

5. **Galaxy billing API** — internal endpoints on the Galaxy backend (port 8081):
   - `POST /internal/billing/llm_cost` — called by Node.js after each chat stream; records LLM tokens to Lago
   - `POST /internal/billing/job_completed` — called by Nextflow executor on run completion
   - `GET /api/billing/usage` — user-facing usage breakdown (proxied through Node.js port 5000)
   - `GET /api/billing/quota` — plan limits and current % consumed

### Environment Variables (for AWS billing)

When running tests or starting the backend for billing work, use:

```bash
# AWS Redis (not local)
export REDIS_URL=redis://biomate-billing-redis.xzhevl.0001.usw2.cache.amazonaws.com:6379

# AWS Lago (not local Docker)
export LAGO_API_URL=http://35.86.137.71:3000
export LAGO_API_KEY=01b71711-be39-49af-8d14-87a4ee827157
export LAGO_WEBHOOK_SECRET=9ef2c8b4-9d99-47f5-98d8-520a22ed3bde

# Java billing service (enabled)
export JAVA_BILLING_SERVICE_URL=http://35.86.137.71:8080
export JAVA_BILLING_ENABLED=true

# Internal key (used by Galaxy → Lago relay)
export BILLING_INTERNAL_KEY=w498JF1dufdEd9O8AInfhS4VyJXi7CKiBz_0qzNVGOE
```

### Billing Smoke Test

The canonical billing smoke test is `e2e/billing-smoke.e2e.ts`. It verifies:
1. LLM chat call emits cost events to Lago
2. `/api/billing/usage` returns a structured breakdown
3. Customer and active subscription exist in Lago for a real user
4. Quota enforcement kicks in when the plan limit is exceeded

Run with AWS env vars set — the test is skipped (not failed) when `LAGO_API_KEY` points to a local container that doesn't have production customers.

### What NOT to do

- Do NOT set `LAGO_API_URL=http://localhost:3010` when billing work is in scope
- Do NOT start `docker-compose` for Lago locally to test billing flows
- Do NOT disable billing (`JAVA_BILLING_ENABLED=false`) when testing cost gating or quota enforcement
- Do NOT treat billing as optional infrastructure — it is a core product feature tested with real events

### Dev-sync note

`scripts/sync_to_dev.sh` does not sync billing env vars — those are set on the dev EC2 instance directly. After any change to `billing_router.py`, `billing_internal.py`, or `nextflow_executor.py` billing paths, run the sync script and then verify `/api/billing/usage` returns correct data on dev.

---

## Local Service Map

When running locally, all services are on `localhost`:

| Service | Port | Notes |
|---------|------|-------|
| Main app (UI + API) | **5000** | Node.js Express + Vite HMR; open this in browser |
| Galaxy backend | **8081** | gunicorn; HUP to reload Python changes (`kill -HUP <master-pid>`) |
| Reference design | **7779** | Static HTTP server; `http://localhost:7779/cro/Workflow%20Panel%20Redesign.html` |
| Lago (local, DO NOT USE for billing tests) | 3010 | Docker; only for UI development that doesn't touch billing logic |
| Java billing (AWS EC2) | via env | `35.86.137.71:8080`; set `JAVA_BILLING_ENABLED=true` |

To restart the Galaxy backend after Python changes:

```bash
kill -HUP $(pgrep -f "gunicorn.*8081" | head -1)
```

---

## Key File Locations

| What | Where |
|------|-------|
| Workflow panel component | `frontend/client/src/components/nextflow-workflow-viewer.tsx` |
| Reference CSS | `frontend/client/src/styles/workflow-panel.css` |
| Chat + right panel | `frontend/client/src/components/chat-with-artifacts.tsx` |
| Node.js routes | `frontend/server/routes.ts` |
| Galaxy AI assistant | `frontend/server/galaxy-assistant.ts` |
| Galaxy backend AI | `backend/lib/galaxy/ai/ai_assistant.py` |
| Nextflow executor | `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py` |
| Step parser (lazy fetch) | `backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py` |
| Billing router | `backend/lib/galaxy/ai/billing/api/billing_router.py` |
| Billing internal | `backend/lib/galaxy/webapps/galaxy/api/billing_internal.py` |
| Workflow DB | `backend/database/galaxy_ai_tools.db` |
| E2E tests | `frontend/e2e/` |
| Dev sync script | `scripts/sync_to_dev.sh` |

---

## Workflow Database

- Location: `backend/database/galaxy_ai_tools.db`
- 2,455 workflows across 34 biological domains
- Key domains: transcriptomics (865), genomics (369), epigenomics (133), proteomics (113), drug_discovery (61), cryo_em (10+)
- `general` (464) = Bioconductor R utility packages — correct classification, not a data quality issue
- The `workflow_ga` object returned by `/api/ai_assistant/generate_workflow` includes: `name`, `domain`, `description`, `required_params`, `optional_params`, `steps`, `nextflow_path`
- Steps are lazily fetched from `/api/nextflow/steps?nextflow_path=…` when `workflow_ga.steps = {}`
- nf-core subworkflow files resolve via `nf-core-modules/subworkflows/nf-core/<name>/main.nf`
