# BioMate Parallel QC Integration Test Plan (Quick + Comprehensive)

Date: 2026-03-04
Goal: Fast, high-confidence validation of QC integration across multiple workflows with parallel execution.

## Why this plan

`docs/20260303_1914_TESTER_PLAN.md` is a strong manual checklist. This plan turns it into:

- a parallelized execution model
- a <30-minute "quick confidence" path
- a deeper follow-up path with explicit ownership and pass/fail gates

## Parallel team lanes

## Lane A - Backend QC contract validation (Python)

Owner: Backend tester/agent

Scope:
- Domain QC gates still enforce expected thresholds and profile logic.
- Focus on newest/high-risk domains: ADMET, PopPK, NCA, profile coverage.

Commands:

```bash
cd /home/yzhang/biomate
PATH="/home/yzhang/biomate/.venv_pm_wire/bin:$PATH" \
pytest backend/tests/test_qc_e2e_domains.py -q -k "PopulationPKQCGates or AmesStructuralAlerts or NamedProfilesCoverage"
```

Pass:
- All selected tests pass.

Fail signals:
- Import/runtime dependency failures (`sqlalchemy`, `pulsar`).
- Any regression in profile behavior or gold/silver gate logic.

---

## Lane B - Frontend deterministic QC UX (Playwright, low-flake)

Owner: Frontend tester/agent

Scope:
- Deterministic UX behavior around QC-related guidance and gate flows.

Commands:

```bash
cd /home/yzhang/biomate/frontend
npx playwright test \
  e2e/ux-autofix-gate.e2e.ts \
  e2e/ux-artifact-readiness-silent.e2e.ts \
  e2e/ux-prereq-checklist.e2e.ts \
  e2e/run-triage-hierarchy.e2e.ts \
  --project chromium
```

Pass:
- All selected tests pass and artifacts are generated.

Fail signals:
- Regressions in retry/report-issue UX, readiness indicators, triage hierarchy.

---

## Lane C - Real workflow integration sentinel (UI + API)

Owner: E2E integrator

Scope:
- Real API + real workflow execution sentinel for end-to-end confidence.

Precondition:
- Frontend/API live and reachable.

Commands:

```bash
cd /home/yzhang/biomate/frontend
BIOMATE_URL=http://localhost:5310 npx playwright test \
  e2e/complete-workflow.e2e.ts \
  --project chromium --retries=1
```

Optional expansion:

```bash
npx playwright test \
  e2e/real-workflow-execution.e2e.ts \
  e2e/real-api-integration.e2e.ts \
  --project chromium
```

Pass:
- End-to-end run completes and key checkpoints are visible.

Fail signals:
- Workflow executes but no QC semantics surface; modal/content mismatch; stalled runs.

---

## Lane D - PM wire orchestration + research + harness gatekeeper

Owner: Release/test lead

Scope:
- Unified gate execution and reporting (`pm-wire-report.txt`).

Commands:

```bash
cd /home/yzhang/biomate/frontend
npm run pm:wire:deps
npm run pm:wire:quick
```

Strict full gate (when env ready):

```bash
set -a && source ./.env && set +a
export TEST_BASE_URL="http://localhost:5000"
export PATH="/home/yzhang/biomate/.venv_pm_wire/bin:$PATH"
PM_WIRE_RUN_HARNESS=1 PM_WIRE_STRICT=1 PM_WIRE_RESEARCH_E2E_TIMEOUT=20m \
  bash scripts/run-pm-test-wire.sh full
```

Pass:
- Quick wire passes.
- Full strict wire passes with zero skips.

Fail signals:
- Skipped critical gates in strict mode.
- Research E2E quality regressions (`0 tools`, `0 steps`).

## 30-minute execution schedule

Minute 0-5:
- Lane D runs `pm:wire:deps` + `pm:wire:quick`
- Lane A verifies backend env and starts targeted pytest
- Lane B starts deterministic Playwright set
- Lane C verifies live endpoints and warms browser

Minute 5-20:
- Lanes A/B execute and report failures with first error lines + artifacts
- Lane C runs `complete-workflow.e2e.ts`
- Lane D triages wire report and flags blockers

Minute 20-30:
- Merge findings into one report:
  - status per lane (Pass/Fail/Partial)
  - top 3 blockers
  - go/no-go for deeper full strict run

## Fast checks completed now (current baseline)

Automated smoke executed in parallel during planning:

- `npm run check`: pass
- `npm run test -- server/workflow-execution.test.ts shared/schema.test.ts`: pass (`77 passed`)
- `npx tsx server/test-information-needs.ts`: pass (`75/75`)
- `curl http://localhost:5000/api/health`: fail (endpoint not reachable at execution time)

Implication:
- code-level fast gates are healthy
- live stack must be started/restarted before real integration lanes (C/D full mode)

## High-risk areas to target first

1. Profile propagation from UI to backend execution path.
2. Process-name humanization and modal wording consistency.
3. Two-click proceed confirmation + retry/diff panel behavior.
4. Research E2E quality issues previously seen (`0 tools`, `workflow success with 0 steps`).

## Required artifacts from each lane

- Command list + exit status
- Key failure lines (first actionable error)
- Screenshot/video path for UI failures
- Final lane verdict: Pass / Fail / Partial

## Done criteria

- All four lanes complete with artifacts.
- No blocker in Lane A or Lane C.
- Lane D quick wire passes; strict full wire either passes or has documented blocker with owner and fix ETA.

## Latest execution snapshot (this run)

### Lane D (PM wire quick) - PASS with expected skips

- `npm run pm:wire:deps` completed.
- `npm run pm:wire:quick` completed:
  - Type safety passed.
  - QC runtime tests passed (`89/89`).
  - Research routing passed (`75/75`).
  - Harness gate skipped (key not set in shell env for this run).

### Lane B (deterministic frontend QC UX) - PASS after targeting active app URL

Initial attempt failed because tests default to `http://localhost:5000` and local service was unavailable.

Re-run command:

```bash
cd /home/yzhang/biomate/frontend
BIOMATE_URL="http://localhost:5310" npx playwright test \
  e2e/ux-autofix-gate.e2e.ts \
  e2e/ux-artifact-readiness-silent.e2e.ts \
  e2e/ux-prereq-checklist.e2e.ts \
  e2e/run-triage-hierarchy.e2e.ts \
  --project chromium
```

Result:
- `6 passed (15.5s)`.

### Lane A (backend targeted QC pytest) - BLOCKED by backend Python dependency chain

Even after adding multiple dependencies to `.venv_pm_wire`, collection still fails.

Observed missing modules in sequence:
- `sqlalchemy`
- `social_core`
- `Cheetah`
- `fissix`
- `past`
- `numpy` (current blocker)

Current status:
- lane remains blocked at import-time dependency resolution for `backend/tests/test_qc_e2e_domains.py`.

### Lane C (real integration sentinel) - pending in this cycle

- Not executed in this pass to keep turnaround short while resolving Lane A dependency churn.
- Run next after confirming stable target URL and desired environment (`5000` or `5310`).

## Update: continuation run

### Lane C (real integration sentinel) - PASS

Command:

```bash
cd /home/yzhang/biomate/frontend
BIOMATE_URL="http://localhost:5310" npx playwright test \
  e2e/complete-workflow.e2e.ts \
  --project chromium --retries=1 --trace=off
```

Result:
- `1 passed (2.6m)`
- Verified workflow generation, run, terminal completion, and output panel availability.

### Lane A (backend targeted QC pytest) - still blocked by full backend dependency stack

Installed during continuation:
- `numpy`
- `email-validator`

Current blocker:
- `ModuleNotFoundError: No module named 'Crypto'`

Note:
- This confirms Lane A requires a fuller backend Python environment (likely project-level requirements), not ad-hoc package additions.

### Lane A continuation details (latest)

Additional dependencies installed while iterating:
- `pycryptodome` (resolved `Crypto`)
- `python-magic` (resolved `magic`)
- plus earlier: `sqlalchemy`, `social-auth-core`, `Cheetah3`, `fissix`, `future`, `numpy`, `email-validator`

Current blocker after latest rerun:
- `ModuleNotFoundError: No module named 'bdbag'`

Implication:
- Backend lane is still failing at import/collection phase because the local Python venv does not yet match the full Galaxy/backend dependency graph.
- Recommended to bootstrap from the backend’s full dependency set in one step, then rerun targeted QC tests.
