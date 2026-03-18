# PM Wire Strict + Backend Addendum Results (2026-03-04)

## Scope

This handoff records the latest validated results for:
- PM wire strict execution (QC + research + harness + backend regression)
- Colleague addendum backend command (`551 passed` expectation)

Branch context: `connection_formal`

---

## 1) PM Wire strict run (complete)

### Command used

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

- PM wire completed successfully.
- `frontend/test-results/pm-wire-report.txt` shows:
  - `[PASS] Type Safety Gate`
  - `[PASS] QC Runtime Gate`
  - `[PASS] Research Routing Gate`
  - `[PASS] Harness Wiring Gate`
  - `[PASS] Research E2E Gate`
  - `[PASS] Backend QC Regression Gate (docker)`

### Key notes from strict run

- All **MUST** checks in Research E2E passed (`73/73`).
- Some **SHOULD** checks remain open (`33/41`), mainly:
  - tool-search queries returning `0 tools`
  - workflow generation returning success with `0 steps` for two prompts
  - missing structured research/benchmark agent evidence flags
  - one latency case slightly over 60s (`61.7s`)

These SHOULD gaps do not fail the strict PM wire currently; they are quality follow-ups.

---

## 2) Backend addendum command verification (exact)

Reference: `docs/20260304_TESTER_ADDENDUM.md`

### Command used

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

- **`551 passed`**, `0 failed` (matches addendum expected outcome exactly).

---

## 3) Backend QC execution path hardening completed

To avoid local Python dependency drift, backend QC regression is now runnable via Galaxy backend docker image:

- Helper script:
  - `backend/scripts/run_qc_regression_in_galaxy_backend.sh`
- PM wire supports mode selection:
  - `PM_WIRE_BACKEND_GATE_MODE=auto|docker|local`

Recommended default for consistency: `docker`.

---

## 4) Quick rerun commands for teammate

### Fast confidence check

```bash
cd /home/yzhang/biomate/frontend
npm run pm:wire:quick
```

### Full strict (same as validated run)

```bash
cd /home/yzhang/biomate/frontend
set -a && source ./.env && set +a
export TEST_BASE_URL="http://localhost:5310"
export PM_WIRE_BACKEND_GATE_MODE=docker
export PM_WIRE_RUN_HARNESS=1
export PM_WIRE_STRICT=1
export PM_WIRE_RESEARCH_E2E_TIMEOUT=30m
bash scripts/run-pm-test-wire.sh full
```

### Backend-only addendum verification

```bash
cd /home/yzhang/biomate/backend
.venv/bin/python -m pytest \
  tests/test_qc_e2e_domains.py \
  tests/test_qc_edge_cases.py \
  tests/test_gap3_complete_integration.py \
  tests/test_gap3_standalone.py \
  -q --tb=short
```

