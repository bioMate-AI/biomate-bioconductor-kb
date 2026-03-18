# AWS Immediate Release Parallel Plan (2026-03-11)

Purpose: release one stable AWS version now, while parallel workers continue non-blocking improvements.

---

## 1) Current System Check (fresh)

Validated immediately before this plan update:

- `npm --prefix frontend run test -- server/execution-env-policy.test.ts server/workflow-execution.test.ts`
  - pass: `73/73`
- `npm --prefix frontend run check`
  - pass (`tsc`)
- `RUN_LIVE_EXECUTE_CONTRACT=1 REQUIRE_AWS_EXEC_200=1 BIOMATE_URL=http://127.0.0.1:5000 npm --prefix frontend run test:live:execute-contract:strict`
  - pass: `1/1` (strict AWS `200` contract)

Interpretation:

- AWS-default execution gate behavior is healthy on current app path.
- Core server workflow execution tests are stable.
- Immediate cut is technically feasible with operational controls below.

---

## 2) Release Strategy (now, with active parallel development)

Use a controlled cut model:

1. Create a release branch from current stable head (or from selected tested commit set).
2. Freeze release-branch scope to AWS execution gate + validated workflow run path.
3. Keep ongoing improvement work on separate branches; no direct merges into release branch without re-gating.
4. Promote only after preflight + smoke + rollback readiness are complete.

Recommended release label:

- `aws-release-2026-03-11-r1`

Execution board for this first cut:

- `docs/QC/20260311_FIRST_AWS_RELEASE_PARALLEL_EXECUTION_BOARD.md`

---

## 3) Parallel Team Split for Release Week

## Track A - Release Captain / Branch Control

Owner: release manager (single accountable owner)

Scope:

- define cut commit/branch
- enforce change freeze on release branch
- approve only critical cherry-picks
- run go/no-go checkpoint

Done when:

- release tag/branch created
- approved patch list locked
- go/no-go record signed

## Track B - App/API Gate Validation

Owner: app backend/frontend maintainer

Scope:

- rerun required server and live contract suites on release branch
- verify `generate_workflow -> /api/workflows/execute` AWS path behavior
- verify no local false-block on AWS default

Required checks:

- `execution-env-policy.test.ts`
- `workflow-execution.test.ts`
- `workflows-execute.live.test.ts` (strict mode)

Done when:

- all checks green on release branch and evidence captured

## Track C - AWS Infra Readiness

Owner: ops/cloud engineer

Scope:

- AWS Batch queue health
- IAM role permissions (Batch submit + S3 read/write)
- S3 output bucket/prefix write checks
- runtime environment parity for deployed worker images

Done when:

- all infra checks pass in target release account

## Track D - Runtime Dependency Completeness

Owner: workflow/runtime maintainer

Scope:

- verify release-target domains for missing runtime modules (known example: `DeepPurpose`)
- run import and execution preflight in target runtime image/env
- produce allow-list of workflows valid for day-0 release

Done when:

- no blocker dependency gap in declared day-0 scope
- exclusions (if any) documented with follow-up owner/date

## Track E - Post-Deploy Smoke + Rollback Drill

Owner: QA + release captain

Scope:

- deploy to target AWS env
- run post-deploy smoke (generate, execute, status, outputs)
- confirm run IDs and output materialization
- execute rollback drill checklist

Done when:

- smoke passes and rollback procedure is verified executable

## Track F - CI/CD Release Automation

Owner: platform/devops engineer

Scope:

- release-branch gating in GitHub Actions
- manual patch/hotfix release update workflow
- optional strict live contract check and tag creation on approved updates

Workflows:

- `.github/workflows/aws-release-gate.yml`
- `.github/workflows/aws-release-update.yml`

Done when:

- release branches are protected by required checks (`check`, core server tests)
- patch release update can be run via manual dispatch with optional strict live contract
- release tag creation is controlled by explicit manual input

---

## 4) Go/No-Go Gates (Blocking)

All must be true for GO:

1. strict live contract test passes (`REQUIRE_AWS_EXEC_200=1`)
2. app tests and typecheck pass on release branch
3. AWS Batch/IAM/S3 checks pass in target account
4. runtime dependency preflight passes for day-0 workflow scope
5. rollback owner and script/checklist are confirmed

Any false item => NO-GO until resolved or explicitly scope-reduced and approved.

---

## 5) Known Gaps Right Now

1. **Runtime dependency completeness is not fully closed**
   - prior real runs showed `DeepPurpose` missing for some ADMET paths.
2. **Hardware metadata memory coverage remains partial by strict evidence policy**
   - `0` unresolved refs, `0` missing execution_info, but memory evidence still missing for many tools.
   - This is non-blocking for release if execution gate behavior remains correct and day-0 scope is explicit.
3. **Parallel branch activity risk**
   - many active in-flight changes increase merge/regression risk without a strict release branch freeze.

---

## 6) 24-Hour Execution Timeline (parallelized)

Hour 0-2:

- Track A creates release branch and freeze policy.
- Track B reruns mandatory tests on release branch.
- Track C begins AWS account preflight.
- Track D runs runtime dependency preflight for day-0 workflows.

Hour 2-6:

- Track B executes live generate/execute smoke on release env.
- Track C closes IAM/queue/S3 validation evidence.
- Track D finalizes day-0 workflow allow-list and exclusions.

Hour 6-8:

- Track E performs deploy + post-deploy smoke and rollback drill.
- Track A runs go/no-go review.

Hour 8+:

- GO: tag and publish release notes.
- NO-GO: hold and route blockers by track owner.

---

## 7) Day-0 Scope Control (recommended)

If runtime gaps remain, release with explicit scope:

- include only workflows verified in AWS runtime preflight
- exclude high-risk domain paths with unresolved runtime modules
- publish known limitations and owner-target date for closure

This allows release now without hiding known operational risks.

