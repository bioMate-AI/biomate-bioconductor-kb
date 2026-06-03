# BioMate Project Instructions

## Engineering Discipline: Resolve Root Causes — Never Workaround

**This is the highest-priority rule in this file. It overrides all convenience shortcuts.**

When a test or system fails, always identify and fix the real root cause. Workarounds that make a test pass while leaving the underlying system broken are strictly forbidden — they accumulate technical debt, mask real problems, and will cause harder-to-diagnose failures later.

**Specifically:**
- If a feature fails because a user lacks a Galaxy account → fix the provisioning flow, don't skip Galaxy account operations
- If an API route conflicts with an existing framework route → fix the route path, don't add special-case logic in the caller
- If a dependency is missing → install it and fix the import guard, don't disable the feature
- If a credential store fails for a user type → fix the credential architecture, don't hard-code fallback keys
- Passing a test by bypassing the system it tests is worthless and actively harmful

**When facing a choice between a quick workaround and a proper fix**, always take the proper fix, even if it takes longer. If the proper fix is not achievable in the current session, document it clearly and do nothing rather than shipping the workaround.

---

## Review Code Before Testing — No Speculative Deploys

**Expensive tests (GPU E2E, AWS Batch runs, multi-minute pipelines) cost real money and wall-clock time. Never deploy + run them to "see if it works." Review the patch first.**

Before deploying a change and re-running an expensive test, you MUST:

1. **Read your own diff end-to-end.** Don't trust your memory of what you wrote.
2. **Trace every gating condition.** For each `if (...)`, ask: under what state does this fire? Under what state does it silently skip? Does the test state satisfy that condition?
3. **Trace the data flow.** What populates the fields your branch depends on? Are they populated for THIS test scenario (fresh run vs. orphan runId, MemStorage vs. DB, live SSE vs. mock)?
4. **Identify silent skips.** A condition that returns empty / no-op when state is missing is worse than a hard error — it produces a fake "0 results" that looks like a code bug.
5. **Predict the outcome.** Write down what you expect the smoke test to return. If you can't predict it, you haven't reviewed enough.
6. **Only then** deploy and test.

**Why:** A 35-minute GPU run + container restart cycle costs ~$1.50 and ~45 minutes. Three of those wasted on speculative deploys = 2+ hours and ~$5 that a 2-minute code review would have saved. The pattern "deploy → test → discover obvious gating bug → fix → redeploy" is forbidden.

**How to apply:** Before any `docker restart` / `sync_to_dev.sh` / fresh E2E launch that depends on a code change, write a one-paragraph review note: what the change does, what conditions it requires, and what the smoke test should return given current state. If the smoke test will fail for reasons unrelated to the bug being fixed (e.g., MemStorage wiped, state lost), DO NOT run it — fix the test setup first or run against a fresh state intentionally.

**Mandatory pre-sync test checklist:** Before running `scripts/sync_to_dev.sh`, run every step in `docs/PRE_SYNC_CHECKLIST.md`:
1. `cd frontend && npx tsc --noEmit -p .` — type check
2. `cd frontend && npx vitest run` — unit + integration suites (~7s)
3. For any modified `backend/lib/galaxy/**/*.py`: `cd backend && PYTHONPATH=lib python3.9 -c "import galaxy.webapps.galaxy.api.<module>"` — catches module-load failures (PEP 604 union syntax on Python 3.9, missing imports, etc.)
4. Domain integration test if relevant (e.g. `scripts/test_afterrun_comprehensive.py`)
5. Only then commit + push + sync

The 2026-06-03 Galaxy crash-loop was a Python module-load failure that step 3 would have caught in 3 seconds. Tests-after-sync is debugging in production; tests-before-sync is debugging on your laptop.

---

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

## Core Architectural Principle: BioMate Is the Execution Engine

**BioMate tasks should run through BioMate's production capabilities — not local workarounds that bypass the system.**

### Execution priority order for R/Bioconductor tasks

1. **Check indexed workflows first.** BioMate has 1,000+ Bioconductor workflows indexed in its AI tool DB (DESeq2, clusterProfiler/enrichGO, edgeR, limma, Seurat, etc.). Always search these first via BioMate's workflow routing. If a matching workflow exists, use it — it runs on AWS Batch workers with full R + Bioconductor installed.

2. **Generate a new workflow if no match.** If no indexed workflow matches the intent, generate a new Nextflow/R workflow stub, add it to the DB, and route through AWS Batch. This extends BioMate's coverage.

3. **Execute R directly via `run_code` as a last resort.** If the task is ad-hoc, short, or does not need a full pipeline (e.g., a single statistical test on a small dataset), BioMate's `run_code` tool can execute R or Python code directly in the backend. This is acceptable when the result feeds back insight about a capability gap, not as a permanent replacement for a proper workflow.

### What this means in practice

- **Do not install R packages locally** or run `Rscript` outside of BioMate's `run_code` tool or AWS Batch. Installing system-level R packages (apt-get, conda) bypasses BioMate entirely.
- **Do not use pydeseq2/pydeseq as substitutes.** Python reimplementations of R tools are not equivalent and do not prove BioMate's capability.
- **Benchmark work must feed back to BioMate production.** Scores achieved by bypassing BioMate (local subprocess hacks, direct file parsing outside BioMate) are worthless for improving the product. The correct loop:
  1. Benchmark reveals a capability gap
  2. Fix is applied via BioMate (indexed workflow, new workflow, or `run_code`)
  3. Re-run benchmark via `biomate_exec` mode to verify the fix is real
- **For pure Python analysis** (parsing text files, basic statistics with scipy/pandas), using BioMate's `run_code` Python path is fine and preferred over local subprocess workarounds in the benchmark adapter itself.

---

## Benchmark-Driven Development

**The purpose of all benchmarks is to improve BioMate's generalized capabilities for long-term use on rich real-world data — not to track a score for reporting.**

Every benchmark measures a specific BioMate capability. When a benchmark scores poorly, the correct response is:

1. **Diagnose the root cause** — is it a rule gap, a prompt gap, a data gap, or a benchmark design error?
2. **Fix BioMate** — add rules, improve prompts, fix schema bugs. Never fix the benchmark to match BioMate's current (wrong) behavior.
3. **Verify the fix improves the capability** — re-run the benchmark; the score improvement proves the fix is real.
4. **Exception: benchmark design errors** — if the expected answer doesn't match the actual workflow schema (e.g., param name mismatch), fix the benchmark to be accurate. Document why.

### Extraction approach: hybrid rule + LLM

For parameter extraction and context interpretation, always use **rule-based inference first, LLM as fallback**:

- **Rules** handle: unit conversions (ns→n_steps, fs→dt), negations (remove X → keep_x=false), boolean flags (single-end → single_end=true), canonical alias normalization (human → GRCh38, dUTP → reverse)
- **LLM** handles: free-text values (SMILES, PDB IDs, gene names), ambiguous enum selection, multi-param inference from prose
- **Validation (guardrail)**: after extraction, validate all values against schema allowed_values; drop or normalize values that violate constraints

**Why**: LLMs are unreliable at arithmetic (unit conversion, exponents), deterministic boolean mapping, and schema-constrained enums. Rules are exact, zero-cost, and testable.

### Benchmark coverage

| Benchmark | Capability tested | Target |
|---|---|---|
| `param_prefill` | Context → workflow parameter extraction | ≥70% |
| `routing` | Intent → correct workflow selection | ≥80% |
| `biomni_eval1` | Biomedical knowledge recall | ≥70% |
| `admet_benchmark` | ADMET prediction quality | ≥70% |
| `pbpk_benchmark` | PK modeling accuracy | ≥60% |
| `boin_benchmark` | Clinical dose escalation | ≥70% |
| `stability` | Cross-run consistency | ≥90% |

### Do not modify production workflow files for benchmark purposes

Never add params to `nextflow_nfcore/subworkflows/**/*.nf` to match benchmark expectations. Those files are executed by Nextflow — all params must be used by the Groovy code. Only the nfcore stub files under `biomni_workflows/nfcore/` are safe to edit for param extraction purposes.

---

## Documentation Rule

**All session documents, findings, plans, and technical notes MUST go into `docs/` or a subfolder of `docs/`.**

- Use date-prefixed filenames: `docs/20260318_TOPIC_NAME.md`
- Never create `.md` files in the repo root, backend root, or frontend root
- The `docs/` directory is the single source of truth for all written technical outputs

---

## Testing Rules

**NEVER mock API calls in E2E tests.** All E2E tests run against the live server with real backend responses. No `page.route()` interception, no `msw`, no `nock`, no stub responses. If a task requires data that depends on backend state, set it up through the real API or real UI actions.

Unit tests may use mocks only for external third-party services (e.g. AWS, Stripe) where real calls are impractical.

---

## UX E2E Completeness Standard

Every UX change must be verified to cover **all elements, all states, and all scenarios** from the Claude design reference at `http://localhost:7779`. A shallow "it renders" check is not acceptable.

### Required coverage for each component

**Workflow Panel (`nextflow-workflow-viewer.tsx`)**
- [ ] Pre-run state: param strip shows required params; missing required params → blocked alert with "Fix now" + "Confirm anyway"
- [ ] Running state: spinner, "Running…" footer button, phase cards show `running` status (spinner icon)
- [ ] Completed state: phase cards show `completed`; "Run again" footer button
- [ ] Failed state: phase cards show `failed`; "Restart" footer button
- [ ] QC gate: when gate is blocked (e.g. ADMET hERG > threshold), alert shows with red border; two-number display (measured vs threshold) in correct colors
- [ ] QC Settings section: threshold editor renders per-metric rows; each row has name, value, editable input; saving updates thresholds
- [ ] "Edit" button on QC gate row: opens QC settings section and scrolls to correct metric
- [ ] Parameter override: clicking "Edit params" opens GlobalParamsPanel; all param types render (boolean → toggle, select → dropdown, file → textarea, number → input with range hint)
- [ ] "View phase outputs" link: panel opens and scrolls to step outputs section
- [ ] Step file preview: image files render as `<img>`, tables render as HTML table, FASTA/VCF/text render as code block
- [ ] Auto-loop panel: remediation card shows was→now param diff (red strikethrough → green new value); gate table shows halt/advisory/pass with correct color coding
- [ ] Skip phase/step: commented out (no backend API) — verify buttons do NOT appear
- [ ] Watcher bar: commented out — verify it does NOT appear
- [ ] **Real-time status tracking** (CRITICAL): the panel must reflect live process state changes as they happen via SSE
  - Pre-run: `data-status="idle"` on overall badge, phase cards have `data-status="pending"`
  - After run clicked: footer button immediately shows "Running…" spinner; overall badge `data-status="running"`
  - As each phase starts: that phase's card `data-status` changes from `pending` → `running` (verified via Playwright `waitForFunction`)
  - As each step completes: step row `data-status` changes to `completed`
  - After all phases done: overall badge `data-status="completed"`, footer shows "Run again"
  - Failure path: any phase `data-status="failed"` → overall badge `data-status="failed"`, footer shows "Restart"
  - The test must observe at least one idle→running→terminal transition in real time (not mocked)

**Sidebar (`app-sidebar.tsx`)**
- [ ] "New Chat" → starts new chat session
- [ ] "Workflows" → opens StarredWorkflowsDialog
- [ ] "Runs" → navigates to `/dashboard`
- [ ] "CRO Library" → navigates to `/drug-discovery-cro`
- [ ] Chat history dots: blue=running, red=failed, green=completed (empty=no run)
- [ ] "Starred Workflows" → opens StarredWorkflowsDialog
- [ ] "Recent Tools" → opens RecentToolsDialog
- [ ] "Billing" → navigates to `/billing`
- [ ] "Settings" → opens SettingsDialog
- [ ] Collapse toggle: hides sidebar, icon-rail shows; expand restores

**Chat message (`chat-message.tsx`)**
- [ ] AI text-only message renders (markdown, code blocks)
- [ ] Workflow card appears AFTER AI text message when workflow is suggested
- [ ] wf-chip shows "In panel" badge when workflow is open in right panel
- [ ] DisambiguationCard renders when `workflow_type === 'disambiguation'`
- [ ] Alert banners: warn/error/info variants render with correct icon+color

**Use-case scenarios (must all pass end-to-end)**
1. **ADMET screening** — send SMILES list; get ADMET workflow; run; QC gate fires; auto-loop remediates; final report downloads
2. **RNA-seq** — upload FASTQ paths; get nf-core/rnaseq; run on AWS Batch; step updates via SSE; findings panel appears; methods report downloads
3. **WGS / variant calling** — genome param set; sarek pipeline; GATK steps complete; VCF output previews
4. **CryoEM** — MRC files; cryosparc_standard_spa; phases complete; 3D reconstruction output
5. **CRO compliance** — navigate to CRO Library; create campaign; attach ADMET results; export compliance package
6. **Drug discovery IND** — run PBPK + clinical trial; generate §2.6.1 LLM narrative; download DOCX

### Audit protocol after each E2E run

1. **Screenshot every state** — pre-run, running (with at least one phase card in running state), completed, QC-blocked
2. **Log assertions** — record pass/fail count per scenario
3. **Visual diff** — compare screenshots against reference design at `localhost:7779`; call out any pixel-level deviations
4. **Fix before marking done** — do not report "passing" if any visual element deviates from the reference or any scenario is skipped

This standard applies to every PR that touches the workflow panel, sidebar, chat message rendering, or auto-loop panel.

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
