# PM Wire Handoff (QC / Research / Test Harness)

Date: 2026-03-02
Owner: AI agent handoff to teammate

## Scope completed in this session

1. Ran comprehensive PM-wire style validation across:
   - Frontend type safety + targeted QC runtime tests
   - Research routing and live research E2E suite
   - Model test harness (live Anthropic-backed run)
   - Backend QC pytest suite
2. Hardened PM wire script behavior for better operational reliability.

## Code changes made

### `frontend/scripts/run-pm-test-wire.sh`

Implemented wire hardening:

- Auto-load `frontend/.env` if present (to pick up `DATABASE_URL`, keys, etc.).
- Added bounded timeout for research E2E:
  - `PM_WIRE_RESEARCH_E2E_TIMEOUT` (default `12m`)
  - Uses `timeout` when available.
- Added configurable Python executable:
  - `PM_WIRE_PYTHON_BIN` (default `python3`)
- Strengthened backend QC dependency check:
  - from `import pulsar`
  - to `import pulsar, sqlalchemy`
- Updated skip message to explicitly mention both required Python modules.

## Test execution evidence and current status

## 1) Frontend PM wire gates

Command pattern used:

`set -a && source ./.env && set +a && PATH="/home/yzhang/biomate/.venv_pm_wire/bin:$PATH" TEST_BASE_URL="http://localhost:5000" npm run pm:wire:full`

Observed:

- Type Safety Gate: passed (`tsc`)
- QC Runtime Gate: passed (`89/89` vitest tests)
- Research Routing Gate: passed (`75/75`)
- Harness Gate: skipped in `pm:wire:full` unless `PM_WIRE_RUN_HARNESS=1`
- Research E2E Gate: started and progressed; later isolated run used for full detail (below)

## 2) Research E2E (isolated run for full diagnostics)

Command:

`set -a && source ./.env && set +a && TEST_BASE_URL="http://localhost:5000" timeout 12m npx tsx server/test-e2e-flexible-intents.ts`

Observed:

- E2E-1 intent classification: passed (`8/8`, 100%)
- E2E-2 fact extraction/state persistence: passed
- E2E-3 tool search: **quality failures** (SHOULD)
  - "variant calling tools: 0 tools returned"
  - "DE with DESeq2: 0 tools returned"
  - "peak calling tools: 0 tools returned"
- E2E-4 workflow generation: **quality failures** (SHOULD)
  - workflow present/success true, but `0 steps` in generated workflow for tested prompts
- Run ended by timeout (`exit 124`) during later section, so this needs a longer window for full pass/fail completion.

## 3) Backend QC regression pytest

Command:

`PATH="/home/yzhang/biomate/.venv_pm_wire/bin:$PATH" pytest backend/tests/test_qc_e2e_domains.py backend/tests/test_qc_edge_cases.py -q`

Observed:

- Failed during collection (0 tests run):
  - `ModuleNotFoundError: No module named 'sqlalchemy'`
- This directly motivated the script hardening to check for both `pulsar` and `sqlalchemy` before running backend QC gate.

## 4) Model test harness (live run)

Command:

`set -a && source ./.env && set +a && timeout 15m npx tsx server/model-test-harness.ts`

Observed:

- Harness completed successfully (`exit 0`)
- Intent classification:
  - Sonnet: `16/17` (94.1%)
  - Haiku: `16/17` (94.1%)
- Notable miss: metabolomics domain keyword coverage test (`1/3`) for both models.
- Artifacts generated:
  - `frontend/server/__tests__/results/model_test_results_2026-03-02T17-32-17.json`
  - `frontend/server/__tests__/results/model_response_comparison_2026-03-02T17-32-17.md`

## Environment work performed

- Created local venv for PM-wire/backend test dependencies:
  - `/home/yzhang/biomate/.venv_pm_wire`
- Installed (in venv): `pytest`, `pulsar-app` (+ transitive deps)
- Note: system Python was PEP 668 managed; direct global `pip install --user` failed, so venv path was required.

## Remaining issues for teammate

1. Research E2E quality regressions:
   - Tool search returns zero tools for benchmark prompts.
   - Workflow generation returns zero steps despite success flag.
2. Research E2E runtime budget:
   - Current `12m` may be too short for full suite completion in this environment.
3. Backend QC gate dependency parity:
   - Ensure the Python env used by PM wire has both `pulsar` and `sqlalchemy` (or install full backend test requirements).

## Priority order for continuation

### P0 (must do first)

1. Rotate Anthropic key and update `frontend/.env`.
2. Install missing backend dependency in the PM-wire venv:
   - `"/home/yzhang/biomate/.venv_pm_wire/bin/pip" install sqlalchemy`
3. Verify local services are up:
   - frontend/api reachable at `http://localhost:5000/api/health`
   - backend reachable at `http://localhost:8081`

### P1 (release-gate stability)

1. Run strict PM wire with longer research timeout:
   - `cd /home/yzhang/biomate/frontend`
   - `set -a && source ./.env && set +a`
   - `export TEST_BASE_URL="http://localhost:5000"`
   - `export PATH="/home/yzhang/biomate/.venv_pm_wire/bin:$PATH"`
   - `PM_WIRE_RUN_HARNESS=1 PM_WIRE_STRICT=1 PM_WIRE_RESEARCH_E2E_TIMEOUT=20m bash scripts/run-pm-test-wire.sh full`
2. Capture output in `frontend/test-results/pm-wire-report.txt` and note first failing gate.

### P2 (quality regressions)

1. Fix research E2E SHOULD failures:
   - tool-search path returning `0 tools`
   - workflow generation returning success with `0 steps`
2. Re-run:
   - `npx tsx server/test-e2e-flexible-intents.ts` (with timeout >= 20m)
   - strict PM wire again after fixes.

## Recommended next commands (teammate)

1. Ensure venv deps:
   - `"/home/yzhang/biomate/.venv_pm_wire/bin/pip" install sqlalchemy`
2. Re-run full wire with explicit env:
   - `cd /home/yzhang/biomate/frontend`
   - `set -a && source ./.env && set +a`
   - `export TEST_BASE_URL="http://localhost:5000"`
   - `export PATH="/home/yzhang/biomate/.venv_pm_wire/bin:$PATH"`
   - `PM_WIRE_RESEARCH_E2E_TIMEOUT=20m npm run pm:wire:full`
3. Re-run strict+live harness:
   - `PM_WIRE_RUN_HARNESS=1 PM_WIRE_STRICT=1 PM_WIRE_RESEARCH_E2E_TIMEOUT=20m bash scripts/run-pm-test-wire.sh full`

## Security note

- A raw Anthropic key was previously posted in chat history. Treat it as exposed:
  - Rotate/revoke key at provider side.
  - Update local `.env` to use a fresh replacement key.
