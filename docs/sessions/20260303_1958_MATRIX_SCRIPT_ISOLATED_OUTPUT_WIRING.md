# Matrix Script Isolated Output Wiring

## Change completed

- Updated `frontend/scripts/run-feedback-e2e-matrix.sh` to use isolated Playwright output paths by default.

## Details

- New env control:
  - `E2E_ISOLATED_OUTPUTS` (default: `true`)
- Behavior:
  - when `true`:
    - each matrix test invokes `scripts/run-e2e-isolated.sh`
    - Playwright artifacts go to timestamped isolated directories
  - when `false`:
    - falls back to direct `npx playwright test` behavior

## Why this matters

- Prevents recurring cross-run artifact file collisions that produced false negatives (`ENOENT`) during trace/video packaging.
- Keeps matrix auditing reliable without changing test semantics.

## Validation

1) Script syntax checks
- `bash -n scripts/run-feedback-e2e-matrix.sh`
- `bash -n scripts/run-e2e-isolated.sh`
- Result: pass

2) Isolated-runner smoke test
- `BIOMATE_URL=http://localhost:5310 bash scripts/run-e2e-isolated.sh e2e/run-manager-multi-chat-scope.e2e.ts --project chromium`
- Result: pass (1/1)

## Notes

- Existing matrix metadata and attachment capture remain unchanged.
- This is backward compatible and can be disabled per run by setting:
  - `E2E_ISOLATED_OUTPUTS=false`
