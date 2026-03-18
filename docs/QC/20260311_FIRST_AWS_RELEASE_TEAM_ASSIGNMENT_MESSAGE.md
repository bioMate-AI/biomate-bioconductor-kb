# Team Assignment Message - First AWS Release (R1)

Copy/paste template for release kickoff.

---

Team, we are starting **first AWS release R1** now with parallel execution.

Release candidate: `aws-release-2026-03-11-r1`  
Execution board: `docs/QC/20260311_FIRST_AWS_RELEASE_PARALLEL_EXECUTION_BOARD.md`  
Runbook: `docs/QC/20260311_AWS_RELEASE_EXECUTION_GATE_AND_VALIDATION_RUNBOOK.md`

## Track assignments (parallel)

### Track A - Release Control (Owner: Release Captain)
- Lock release scope and freeze non-release merges.
- Maintain approved cherry-pick list.
- Run final go/no-go.

### Track B - App/API Validation (Owner: App Maintainer)
- Run:
  - `npm --prefix frontend run check`
  - `npm --prefix frontend run test -- server/execution-env-policy.test.ts server/workflow-execution.test.ts`
  - `RUN_LIVE_EXECUTE_CONTRACT=1 REQUIRE_AWS_EXEC_200=1 BIOMATE_URL=<target_url> npm --prefix frontend run test:live:execute-contract:strict`
- Attach concise result summary in sign-off.

### Track C - AWS Infra Watch (Owner: Ops/Cloud)
- Confirm queue/role/bucket health during rollout window.
- Watch for drift and keep rollback infra path ready.

### Track D - Runtime Dependencies (Owner: Runtime Maintainer)
- Validate day-0 workflow allow-list runtime completeness.
- Publish exclusions with owner/date if needed.

### Track E - Deploy + Smoke + Rollback (Owner: QA + Release Captain)
- Deploy candidate.
- Run smoke: `generate -> execute -> status -> outputs`.
- Execute rollback drill and record result.

### Track F - CI/CD Update Drill (Owner: Platform/DevOps)
- Run `AWS Release Gate` on release PR.
- Run `AWS Release Update` dry-run (`create_tag=false`) with strict live contract.
- After approval, rerun with real patch tag (`create_tag=true`).

## Reporting format (each track)

Post updates with:

1. Status: `green` / `amber` / `red`
2. Completed items
3. Blockers (with owner + ETA)
4. Evidence links (run URLs / command outputs / doc path)

## Exit criteria for GO

- All tracks complete, or approved scope exclusions documented.
- CI/CD dry-run complete.
- Strict live contract green on target URL.
- Rollback drill confirmed.

