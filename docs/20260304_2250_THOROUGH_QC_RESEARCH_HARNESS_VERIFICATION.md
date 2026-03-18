# Thorough QC / Research / Harness Verification (2026-03-04)

## Scope

This pass validates the PM wire end-to-end plus addendum-specific QC behavior with focused backend and frontend tests.

---

## 1) PM wire strict (all gates enabled) — PASS

### Command

From `frontend/`:

```bash
set -a && source ./.env && set +a
export TEST_BASE_URL="http://localhost:5310"
export PM_WIRE_BACKEND_GATE_MODE=docker
export PM_WIRE_RUN_HARNESS=1
export PM_WIRE_STRICT=1
export PM_WIRE_RESEARCH_E2E_TIMEOUT=30m
bash scripts/run-pm-test-wire.sh full
```

### Result

- Completed successfully with all gates marked pass in `frontend/test-results/pm-wire-report.txt`:
  - Type Safety
  - QC Runtime
  - Research Routing
  - Harness Wiring
  - Research E2E
  - Backend QC Regression (docker)

---

## 2) Colleague addendum backend command — PASS (`551 passed`)

### Command (exact from addendum)

From `backend/`:

```bash
.venv/bin/python -m pytest \
  tests/test_qc_e2e_domains.py \
  tests/test_qc_edge_cases.py \
  tests/test_gap3_complete_integration.py \
  tests/test_gap3_standalone.py \
  -q --tb=short
```

### Result

- `551 passed` (matches expected exactly).

---

## 3) Addendum-mapped backend QC classes — PASS

### Command

```bash
cd /home/yzhang/biomate/backend
.venv/bin/python -m pytest -q --tb=short \
  tests/test_qc_edge_cases.py::TestTierOneChanges \
  tests/test_qc_e2e_domains.py::TestCryoEM2DClassificationQCGates \
  tests/test_qc_e2e_domains.py::TestVoltaPhasePlateCTFGates \
  tests/test_qc_e2e_domains.py::TestChemoproteomicsPulldownGate
```

### Result

- `20 passed`

### Coverage against addendum

- CTF defocus out-of-range directional failures: covered (`TestTierOneChanges`)
- Two-tier RNA-seq severity split (<25 critical vs 25–70 warning): covered
- Near-threshold warning emits `qc_warning` not blocking gate: covered
- 2D classification junk-fraction routing (`CLASSIFY_2D_R1/R2`): covered
- VPP advisory behavior + phase-plate profile threshold relaxation: covered
- Chemoproteomics / ABPP pulldown enrichment gate + routing: covered

---

## 4) Parser/workflow alignment regression set — PASS

### Command

```bash
cd /home/yzhang/biomate/backend
.venv/bin/python -m pytest -q --tb=short \
  tests/test_gap3_complete_integration.py \
  tests/test_gap3_standalone.py
```

### Result

- `24 passed`

---

## 5) Run manager validation — PASS (targeted)

### Backend API unit tests

```bash
cd /home/yzhang/biomate/frontend
npm run test -- server/run-overview.test.ts
```

- Result: `3 passed`

### Frontend run-manager UI flows (Playwright)

```bash
cd /home/yzhang/biomate/frontend
BIOMATE_URL="http://localhost:5310" npx playwright test \
  e2e/run-manager-multi-chat-scope.e2e.ts \
  e2e/run-manager-scope-race-guard.e2e.ts \
  --project chromium --trace=off
```

- Result: `2 passed`

---

## 6) Remaining quality gaps (from strict Research E2E SHOULD checks)

MUST checks passed; SHOULD checks still indicate quality debt:

1. Tool-search responses returning `0 tools` for multiple queries.
2. Workflow generation reports success with `0 steps` for two prompts.
3. Research/benchmark structured evidence flags missing:
   - `researchResponse`/`researchAgentUsed`
   - `benchmarkEvidence`/`benchmarkAgentUsed`
4. One response-time SHOULD miss (`61.7s > 60s`).

These are product-quality follow-ups, not blocker failures in current strict gate behavior.

---

## 7) Recommended next fix order

1. **Tool search return content** (highest user-visible impact).
2. **Workflow step construction integrity** (`workflow.success` must imply non-zero steps).
3. **Agent evidence metadata wiring** (research/benchmark provenance flags).
4. **Latency tuning for FASTQC query path**.

