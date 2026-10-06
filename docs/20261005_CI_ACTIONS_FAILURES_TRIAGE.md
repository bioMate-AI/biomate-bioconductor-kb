# CI triage — all GitHub Actions workflows red (2026-10-05)

**For:** the team. **Author:** automated triage during the agent-eng committee-fix session.
**TL;DR:** the recent all-red CI is **two independent problems**, and **neither is caused by the
agent-engineering committee fixes** (PR #270). (1) The `ind-pi-suite` workflow invokes Playwright test
files that were **deleted three months ago** → `No tests found` → exit 1. (2) Since ~20:32Z today,
jobs across multiple workflows are **cancelled after ~15 min with zero steps executed** — the signature
of hosted-runner unavailability / Actions minutes exhaustion (not confirmable without `admin:org`).

---

## How this was diagnosed (not a guess)
Every claim below is from `gh run view --log` / `--json jobs` and `git` on this checkout. Exit codes
were read, not inferred — a cancelled job and an assertion failure look the same in the run list but are
different causes.

---

## Problem A — `ind-pi-suite` runs deleted test files (real, long-standing)

**Symptom.** Runs that *did* acquire a runner fail fast (~2 min) at step #7
"Run PI suite (PI-1..PI-13) against dev":
```
npx playwright test e2e/ind-report-production.e2e.ts --reporter=list --output=/tmp/pi-suite-output
Error: No tests found.
Make sure that arguments are regular expressions matching test files.
##[error]Process completed with exit code 1.
```
Step #6 "Wait for dev backend healthy" **succeeded** first, so this is NOT a dev-reachability problem —
the backend was up. The decisive error is `No tests found`.

**Root cause.** The two files the workflow invokes do not exist:
- `.github/workflows/ind-pi-suite.yml:88` → `e2e/ind-report-production.e2e.ts`
- `.github/workflows/ind-pi-suite.yml:95` → `e2e/ind-design-audit.e2e.ts`

Both were deleted in commit **`1a12b4e8c`** ("chore: remove redundant bioconductor_skill MCP tool;
clean up 161 stale E2E files", **2026-07-06**) — `-364` and `-299` lines respectively. The workflow was
never updated to match.

**Scope.** The deletion commit is in the ancestry of `integration/next-phase` **and** the `cursor/tutorial-*`
branches; the files are **ABSENT on `integration/next-phase` (main) too**. So the PI suite is broken
repo-wide, not just on a feature branch. It only *surfaces* when `sync_to_dev.sh` dispatches it (it is
`workflow_dispatch`-only), which is why multiple syncs today produced a cluster of identical failures.

**Surviving `ind-*` e2e files** (candidate replacements / evidence the suite content moved):
`frontend/e2e/demo-11-ind-assembly.demo.ts`, `frontend/e2e/index-query-input.e2e.ts`. Neither is the
PI-1..PI-13 report-production suite.

**Fix options (team decision — not applied here, since the deletion was deliberate):**
1. **Retire the workflow** if the PI suite was intentionally removed (simplest; delete/disable
   `ind-pi-suite.yml`, and drop its dispatch from `sync_to_dev.sh`).
2. **Repoint** the workflow at the current IND tests if the coverage moved (update lines 88/95).
3. **Restore** `ind-report-production.e2e.ts` + `ind-design-audit.e2e.ts` from `1a12b4e8c^` if that
   coverage is still wanted.
   Also: `sync_to_dev.sh` auto-dispatches this suite after every sync — whichever option is chosen,
   update the dispatch so a sync doesn't keep spawning a known-red run.

**Affected runs (executed, real failure):** `37357459746` (18:38Z), `37361578555` (19:11Z),
`37363433871` (19:32Z) — each 13 steps, ~2 min, step #7 failure.

---

## Problem B — jobs cancelled after ~15 min with zero steps (runner/minutes)

**Symptom.** Since ~20:32Z (2026-10-05), jobs across **multiple** workflows end as `cancelled` having
run **no steps at all**, each sitting ~15 min first:
- `CI Tests` `37370365524` (20:32Z): `Security Scan`, `Backend Tests (Full Suite)`,
  `Frontend Tests (Full Suite)`, `Test Summary` all **cancelled, steps=0**; `Smoke Tests` skipped.
- `IND PI Suite` `37372081023` (20:49Z, the sync-dispatched one): `pi-suite` **cancelled, steps=0**,
  20:49:08→21:04:09 (~15 min).
- `PM Test Wire` `37370365525` (20:32Z): failure, same window.

**Interpretation.** Zero steps + a ~15-min wall + `cancelled` on `runs-on: ubuntu-latest` is the
signature of jobs that **never acquired a hosted runner** and were then cancelled. For an org-owned
private repo (`bioMate-AI/biomate`), the usual cause is **Actions minutes / spending-limit exhaustion**
(or Actions temporarily disabled / a budget cap). It is NOT a code or test failure — nothing ran.

**Could not confirm directly.** The org Actions billing endpoint now requires `admin:org`
(`GET /orgs/bioMate-AI/settings/billing/actions` → HTTP 410 "endpoint moved" + scope error), so the
spending-limit cause is **strongly indicated but not verified from here**. A maintainer with org admin
should check **Org → Settings → Billing → Actions** (minutes used vs. included, spending limit, payment
method) and that Actions is enabled for the repo.

**Timeline anchor.** Last green before the streak: `Sample Workflow Execution Smoke` (schedule) at
**16:44Z**. The `CI Tests` "success" at 12:30Z today was a `push` run that executed **only** the Smoke
job (full-suite jobs skipped on that trigger), so it is not evidence the full suite was healthy today.

**Action (account-level, cannot be fixed from code or out-of-band):** restore Actions minutes / raise
the spending limit / confirm Actions is enabled, then re-dispatch. Do **not** mass-re-run — that burns
more of whatever budget remains and the cause is identified.

---

## Why this is not the committee fixes (PR #270)
- The committee fixes are server middleware (`quota-middleware.ts`, `routes.ts`) + a backend search
  index migration. They touch no e2e test file, no `ind-*` test, and no workflow YAML.
- Problem A predates the work by 3 months (file deletion 2026-07-06).
- Problem B ran zero steps — nothing from any branch executed.
- Independent verification of the committee fixes was done **directly against live dev** (healthy +
  smoke PASS, both DB indexes live and EXPLAIN-confirmed, fixture quota path OK) and the **full local
  vitest/tsc** (1639 passed) — see `docs/20261005_AGENT_ENG_FIXES.md`. CI being down does not leave the
  change unverified; it leaves CI without signal until the account/runner issue is resolved.

## Evidence index (run IDs)
| Run | Workflow | Time (UTC) | Outcome | Steps |
|---|---|---|---|---|
| 37343162004 | Sample Workflow Execution Smoke | 16:44Z | success | (last green) |
| 37357459746 | IND PI Suite | 18:38Z | failure | 13 (step #7 "No tests found") |
| 37361578555 | IND PI Suite | 19:11Z | failure | 13 (same) |
| 37363433871 | IND PI Suite | 19:32Z | failure | 13 (same) |
| 37370365524 | CI Tests | 20:32Z | failure | jobs cancelled, steps=0 |
| 37372081023 | IND PI Suite | 20:49Z | failure | cancelled, steps=0 |
