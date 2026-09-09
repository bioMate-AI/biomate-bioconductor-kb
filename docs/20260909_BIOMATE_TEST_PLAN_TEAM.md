# BioMate — Test Plan (Team Reference)

**Date:** 2026-09-09
**Purpose:** one shared reference for how BioMate is tested — the layers, the suites, how to run each, what they cover, and the current pass/gap status. Applies to the data-centric platform, the drug-development capabilities, and the hospital/omics analysis surfaces.
**Golden rules (non-negotiable):**
- **E2E tests hit the live stack — never mock API calls** (no `page.route()`, `msw`, `nock`, stub responses). Data is set up through the real API/UI.
- **One canonical fixture account**, reused across tests (no per-test users → rate-limit/quota debt).
- **Pre-sync gate before every deploy** — type-check + unit + backend module-load *before* `sync_to_dev.sh`, never debug in production.
- **Integrity over green** — a workflow must fail honestly, never emit fabricated results to make a test pass.

---

## 1. Environments & credentials

| | Value |
|---|---|
| **Dev (all E2E run here)** | `https://dev-public.biomate.ai` |
| Local app (dev only) | `http://localhost:5000` (Node) · Galaxy backend `:8081` |
| **Fixture account** | `lifeifei163361@163.com` (real, deliverable inbox) |
| Fixture password | env `E2E_FIXTURE_PASSWORD` (do not commit) |
| Dev auth bypass header | `x-e2e-test-token: <E2E_TEST_TOKEN on dev>` |
| Pattern | register-or-login once → cache JWT → `page.context().addCookies({ biomate_token })` |

Never point billing tests at the local Lago container — use the AWS billing stack (or the internal quota pipeline).

---

## 2. Test layers (fastest → slowest)

### Layer 0 — Pre-merge / pre-sync gate (mandatory, ~30–60s)
Run **before** any `scripts/sync_to_dev.sh`:
1. `cd frontend && npx tsc --noEmit -p .` — type check
2. `cd frontend && npx vitest run` — unit + integration (~15s; currently **1,166 pass / 6 skip**)
3. For any modified `backend/lib/galaxy/**/*.py`: real module-load via the venv (Py3.9-safe check that caught the 2026-06 crash-loop):
   `cd backend && PYTHONPATH=lib /Users/kky/biomate/backend/.venv/bin/python -c "import galaxy.webapps.galaxy.api.<module>"`
4. Domain unit tests for touched areas (below).

### Layer 1 — Unit & component
- **Frontend:** `npx vitest run` — 89 files, 1,166 tests (components, hooks, lib, server routes incl. `project-routes.test.ts`).
- **Backend (Python):** `pytest` per area, e.g.
  - ACMG variant interpretation: `backend/.../genomics/acmg_variant_interpretation/test_acmg_criteria.py` — **40 tests** (deterministic criteria: BA1/BS1/PM2/PP3/BP4 thresholds).
  - QC auto-loop: `backend/experiments/admet_autoloop/…` — **109 tests** (gate evaluation, remediation).
  - Data-source registry drift guard: `backend/tests/test_data_source_registry.py`.
  - Project auth/ownership: `frontend/server/project-routes.test.ts` (404-not-403, cross-user isolation).

### Layer 2 — Deploy health gate (automatic in `sync_to_dev.sh`)
Every sync runs, after deploy, and auto-rolls-back on failure:
- Galaxy + frontend health probes.
- **Workflow-generation smoke** (`localhost:8081/api/ai_assistant/generate_workflow`, prompt "run RNA-seq differential expression analysis") — accepts a single workflow **or a curated chain**.
- DB-search routing smoke · connector-contract smoke.
- On failure → docker-commit rollback to the pre-sync snapshot (dev stays up on old code).

### Layer 3 — E2E on dev (the canonical suites)
Run against `BIOMATE_URL=https://dev-public.biomate.ai` with the fixture:
- **`scripts/e2e_use_cases.sh`** — the canonical consolidated journey: **Flow A** (login → create project → chat-stream → workflow routing across microarray/RNA-seq/proteomics/microbiome/cryoEM → 32-dataset cap → compression UUID preservation) + **Flow B** (auth-gate probes 401/404). Single fixture, single project, 90s LLM timeouts. *(latest: 16/17; the 1 "fail" is a branch-name guard.)*
- **`scripts/run_postsync_tests.sh`** — billing-smoke (8/8) + auth-flows smoke.
- **Key `frontend/e2e/*` specs** (Playwright, Chromium): `api-smoke`, `auth-flows-smoke`, `after-run-audit`, `autoloop-full-arc`, `chat-multiturn-research`, `chain-suggestion`, `billing-smoke`, `cryoem-capstone`.

### Layer 4 — Capability / dimension validation audits
Deeper audits vs the claude-design reference + the CLAUDE.md UX-completeness standard (harnesses on the `test/*` branches):
- **UX completeness** — every element/state of the workflow panel, sidebar, chat, Models module, cold-start dashboard, dataset object, full step deep-view.
- **Multi-round interaction** — multi-turn context carry (a preference in turn 1 applied in turn 3), panel↔chat sync, SSE pills.
- **Parallel execution** — concurrent runs get distinct run-ids, each polls its own record, no cross-worker 404 (RunStateStore).
- **Memory** — session carry, byte-cap dataset preservation, summarization UUID survival, episodic recall, cross-session recall, org-rule.

### Layer 5 — Integrity checks (drug-dev / workflows)
- **No fabricated results:** no `random.*`/`np.random.*` produces scientific output values in `.nf` workflows; stubs honest-fail (exit 1) with a clear message. Verify with a repo grep + a spot honest-fail run.
- **QC gate reflects a real evaluation** (never a faked gate); ACMG never emits a black-box clinical verdict; research agent verifies citations or abstains (0 mismatched cites).

### Layer 6 — Real end-to-end execution evidence (AWS Batch)
For a domain to count as "green," a real run must produce real output on S3 (not indexed-only). Track `workflows.real_exec_status` / `real_exec_produced` in the workflow DB. **Do not launch speculative Batch/GPU runs** — review the patch and predict the outcome first (a GPU run is ~$1.50 + ~45 min).

---

## 3. Coverage matrix (capability → primary test → current status)

| Capability | Primary test(s) | Status |
|---|---|---|
| Chat → workflow routing (RNA-seq, proteomics, cryoEM, microbiome…) | `e2e_use_cases.sh` Flow A | 🟢 pass |
| Multi-turn context / panel sync | `chat-multiturn-research.e2e.ts` + multi-round audit | 🟢 backend / 🟡 in-browser render (harness timing) |
| Parallel execution (cross-worker) | parallel-execution audit | 🟢 pass |
| Memory (session/byte-cap/summarization/episodic) | memory audit | 🟢 4/6 (cross-session-chat + org-rule = documented gaps) |
| Workflow panel states (idle/running/completed/failed/QC-blocked) | UX audit + `after-run-audit.e2e.ts` | 🟢 core / 🟡 full step deep-view (orphan — wiring pending) |
| **ADMET QC auto-loop (hERG gate → halt → remediate)** | `autoloop-full-arc.e2e.ts` + admet_autoloop unit (109) | 🟢 unit; **live-fire proof pending** (SSE Batch fix just deployed) |
| **Clinical variant interpretation (ACMG)** | `test_acmg_criteria.py` (40) + workflow fixture run | 🟢 unit + local run (BRCA1→VUS correct) |
| MPO/DMTA optimize (propose next round) | `models.test.tsx` (DMTA loop + honest-empty) + `/propose` | 🟢 |
| Billing / quota | `billing-smoke.e2e.ts` | 🟢 8/8 |
| Auth / project ownership / isolation | `auth-flows-smoke`, `project-routes.test.ts` | 🟢 |
| `/api/projects` (dataset surface) | authenticated GET probe + `project-routes.test.ts` | 🟢 fixed (was 500; verified 200) |
| Integrity (no fabricated `.nf` output) | fabrication grep + honest-fail spot run | 🟢 33 fabricators remediated |
| Proteomics / metabolomics / single-cell / spatial | real Batch run (Layer 6) | 🔴 near-zero produced-output — **priority execution gap** |

---

## 4. How to run (quick commands)

```bash
# Pre-sync gate
cd frontend && npx tsc --noEmit -p . && npx vitest run
cd backend && PYTHONPATH=lib .venv/bin/python -c "import galaxy.webapps.galaxy.api.nextflow_executor"

# Canonical E2E on dev
BIOMATE_URL=https://dev-public.biomate.ai scripts/e2e_use_cases.sh
scripts/run_postsync_tests.sh

# A single Playwright spec on dev
cd frontend && BIOMATE_URL=https://dev-public.biomate.ai npx playwright test e2e/chat-multiturn-research.e2e.ts --project=chromium

# ACMG + auto-loop unit
pytest backend/biomni_workflows/nextflow_nfcore/subworkflows/genomics/acmg_variant_interpretation/test_acmg_criteria.py
pytest backend/experiments/admet_autoloop/

# Deploy (runs the health gate + smoke automatically)
scripts/sync_to_dev.sh
```

---

## 5. Audit protocol (after each E2E run)
1. **Screenshot every state** — pre-run, running (≥1 phase card running), completed, QC-blocked, failed.
2. **Log pass/fail per scenario.**
3. **Visual-diff vs the reference design** (`localhost:7779`) — call out any pixel/text deviation; no "undefined", no stuck "Analysis in progress…" on a failed run.
4. **Fix before marking done** — chat panel and workflow panel must agree (same workflow name, same state).

---

## 6. Known gaps / open items (as of 2026-09-09)
- **Live-fire the QC auto-loop** end-to-end now that the Batch SSE fix is deployed (`autoloop-full-arc.e2e.ts`).
- **Full step deep-view** — `steps/step-detail.tsx` exists but isn't mounted; wiring pending.
- **Cross-session chat recall (M-4)** + **org-rule memory (M-6)** — documented not-wired.
- **Real produced-output runs** for proteomics/metabolomics/single-cell/spatial — the top credibility gap.
- **In-browser workflow-panel render** — widen the harness wait to ≥45s and seed the fixture with one run + dataset to unlock the data-dependent UX elements.
- Firefox binary not installed locally → run `--project=chromium` or `npx playwright install firefox`.

---

## 7. Ownership & cadence (proposed)
- **Every PR:** Layer 0 gate (author).
- **Every deploy:** Layers 0 + 2 (automatic health gate).
- **Weekly / pre-demo:** Layers 3 + 4 (canonical E2E + the four dimension audits) on dev.
- **Per new domain/capability:** Layers 1 + 5 + one Layer-6 real run before it's called "green."
- Record each significant run as a date-prefixed doc under `docs/` (what changed, what was tested, screenshots/logs, open issues).
