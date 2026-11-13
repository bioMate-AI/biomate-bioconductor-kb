# E2E base URL precedence — class close (2026-11-13)

## Gap

Commit `a0d9191c17` fixed `_fixture-login.ts` + `playwright.config.ts` so
`BASE_URL > PLAYWRIGHT_BASE_URL > BIOMATE_URL > default`. Many other paths still
resolved target as `BIOMATE_URL || localhost` only — so a shell that set only
`BASE_URL=https://dev-public.biomate.ai` still logged into localhost for those
suites / helpers / configs / harness scripts.

## Fix

- New shared module: `frontend/e2e/_e2e-base-url.ts` (`resolveE2eBaseUrl` /
  `BASE_URL`). `_fixture-login` re-exports it; helpers and configs import it.
- Specs that redefined `BIOMATE_URL || localhost` (or hardcoded localhost) now
  import the shared resolver. Live-default suites call
  `resolveE2eBaseUrl("https://dev-public.biomate.ai")`.
- Custom login clones in `after-run-audit`, `ui-interaction-flows`,
  `intent-clarification`, `param-clarification` → `loginAsFixture`.
- Harness scripts (`run_live_journeys`, `run_postsync_tests`, `run_ux_audit`,
  `run_real_workflows`, `e2e_*.sh`, …) accept either var:
  `BIOMATE_URL="${BASE_URL:-${BIOMATE_URL:-…}}"` and export both.
- `.mjs` probes cannot import the TS module; they inline the same precedence
  with a comment pointing at `_e2e-base-url.ts`.

## Remaining (non-blocking)

One-off root demos / debug scripts (`frontend/debug-*.mjs`,
`frontend/biomate-audit*.mjs`, recording captures under `scripts/recording/`,
hardcoded local ports) are not Playwright harness paths; left alone.

## Sanity

`BASE_URL=https://dev-public.biomate.ai` with `BIOMATE_URL` / `PLAYWRIGHT_BASE_URL`
unset → shared resolver + Playwright `baseURL` resolve to live;
`folder-attach-all-files.e2e.ts` login hits `dev-public.biomate.ai`.

Re-run 2026-11-13 (only `BASE_URL` set): **PASS** (1.2m) — Analysis chips=5,
Models `folder:pairs`, samplesheet chip persisted. Live build tip observed in
test log was independent of this e2e-only class close (no product sync needed).
