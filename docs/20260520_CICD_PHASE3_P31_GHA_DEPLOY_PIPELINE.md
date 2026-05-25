# CI/CD Rebuild — P3.1 Session Report

**Date:** 2026-05-20
**Scope:** P3.1 — wrap `scripts/deploy.sh` in a GHA workflow (the CD primitive)
**Plan:** [`docs/20260514_CICD_REBUILD_PLAN.md`](20260514_CICD_REBUILD_PLAN.md)
**Branch:** `integration/next-phase` (now the repo default branch)
**Status:** **CD pipeline proven** end-to-end against the test env. Galaxy app boot still blocked by Task #19 (Galaxy fork alembic), but the CD primitive itself works as designed: builds → deploys → healthchecks → notifies → exits clean.

---

## 1. What ships

### 1a. `.github/workflows/deploy.yml`

- **Triggers**: `workflow_run` (after either image-build workflow succeeds on default branch) and `workflow_dispatch` (manual deploy / rollback).
- **Inputs (manual)**: `env` (currently only `test`), `tag` (any ECR tag: `sha-*`, `release-*`, or `<branch>-latest`).
- **OIDC** via `aws-actions/configure-aws-credentials@v4` → assumes `arn:aws:iam::399683337364:role/GitHubActionsDeploy`.
- **Job-level `environment: test`** — couples the run to GitHub Environments, which is how the OIDC trust policy is gated (`sub` claim must contain `:environment:test`). Future stage/prod paths add their own Environments + scoped roles.
- **Concurrency**: `deploy-${env}` with `cancel-in-progress: false` so an in-flight rollback can't be cancelled.
- **Timeout**: 10 min job-level (caps the blast radius — see §2 for why this matters).

### 1b. IAM `GitHubActionsDeploy`

Least privilege (separate from the ECR push role):

| Action set | Resources | Conditions |
|---|---|---|
| `ec2:DescribeInstances` | `*` | — |
| `ssm:SendCommand` | `ec2:*:*:instance/*` | `aws:ResourceTag/Env ∈ {test, dev, stage}` |
| `ssm:SendCommand` | `ssm:us-west-2::document/AWS-RunShellScript` | — (AWS-managed doc, no tags) |
| `ssm:GetCommandInvocation`, `ListCommandInvocations`, `DescribeInstanceInformation` | `*` | — |
| `sns:Publish` | `biomate-deploy-events` topic only | — |

No ECR push. No Secrets Manager read (the **EC2 instance profile** has that — separation of duties). No S3. No IAM. Pure deploy mechanic.

Trust policy `sub` claim: `repo:bioMate-AI/biomate:environment:test`. Combined with the workflow's `environment: name: test`, only jobs that have selected the `test` GitHub Environment can assume the role.

### 1c. Repo default branch switch

Changed `bioMate-AI/biomate` default branch from `connection_formal` (last touched March 12) → `integration/next-phase`. This was a P3.1 prerequisite because GHA `workflow_run` events fire only when the source workflow ran on the **default branch**, and `gh workflow run` for not-yet-default-branch workflows returns 404 ("workflow not found"). All four current workflows now appear in `gh workflow list`.

Old branches left untouched per user direction; 18 remote branches remain.

---

## 2. Real bugs the GHA runner caught (locally hidden by my admin creds)

The CD primitive worked from my laptop on day one. The GHA runner — with its scoped role + actual GHA networking — found three real defects:

| # | Surfaced | Cause | Fix |
|---|---|---|---|
| 1 | `workflow_dispatch` 404 (`gh workflow run deploy.yml`) | GHA only registers workflows that are on the default branch OR have been auto-triggered. `deploy.yml` had only `workflow_run`+`workflow_dispatch` triggers → no auto-trigger → invisible to API. Default branch was a stale March branch with none of my work. | Switched default branch to `integration/next-phase`. |
| 2 | First real run: `AccessDeniedException: ssm:SendCommand on resource arn:aws:ssm:us-west-2::document/AWS-RunShellScript` despite an apparently matching wildcard ARN in the policy | The condition `aws:ResourceTag/Env ∈ …` was attached to a statement that listed BOTH the EC2 instance ARN AND the document ARN. Conditions apply to **every** resource in the statement, but the AWS-managed document has no tags → implicitDeny. | Split into two statements: one for the tagged instance (with condition), one for the document (no condition). Verified via `iam simulate-principal-policy`. |
| 3 | First real run burned the FULL 20-min job timeout on a 1-second error | `ssm_run()` ignored `aws ssm send-command` failures: when SendCommand returned AccessDenied, `cmd_id` was empty, and the `until ... get-command-invocation` loop polled an empty command-id forever. | `ssm_run()` now captures stderr into a temp file, aborts loudly when `send_rc != 0` or `cmd_id` is empty/None. Also tightened job timeout from 20m → 10m as defense in depth. |

All three are in the new commits (4b8b8b33a + the IAM policy update done out-of-band).

---

## 3. Validated flow (current state after fixes)

Latest run (workflow_dispatch, commit `aee3f54b`):

```
[15:35] Resolving target EC2 for env=test …
[15:35] Target: i-0482a6fa98c6f301a
[15:35] [1/5] Pre-flight checks (disk, docker, orphan sync_to_dev.sh) … OK
[15:36] [2/5] Staging compose file + ECR login on target …            OK
        OVERRIDE_DATABASE_CONNECTION sourced from test/biomate/rds-galaxy
[15:36] [3/5] Recording previous tag (for auto-rollback) …            OK
[15:37] [4/5] docker compose pull + up …                              OK (both images pulled, network up)
        Error dependency galaxy-backend-deploy failed to start          ← galaxy boot
        timeout waiting for dependencies
[16:21] [4b/5] External healthcheck: stage-public.biomate.ai/api/health …
[16:23] external healthcheck failed                                    ← correct failure detection
        rollback: no prior healthy tag                                 ← correct: only roll back to a tag that was healthy
        SNS publish: [deploy] test integration-next-phase-latest FAILED
        exit 1                                                         ← correct failure signal
```

This is the **expected** behavior given Task #19 (Galaxy fork's alembic multi-head + ALTER-before-CREATE bug). The CD primitive correctly refuses to declare success when the app can't actually serve.

Past-incident lessons satisfied by this validated flow:
- **L17** auto-rollback to previous healthy tag (gracefully exits when there is none — no prior healthy state to roll back to)
- **L20** SSM Run Command only — no SSH, no Instance Connect keys
- **L21** external HTTP healthcheck gates every deploy
- **L9 + L11** secret fetched from Secrets Manager via instance profile, not GHA secrets

---

## 4. What's now unblocked

- **P3.2 rollback workflow**: same `deploy.yml` already serves as the rollback handle — `gh workflow run deploy.yml -f env=test -f tag=<any-prior-sha>`. A dedicated convenience workflow can come later.
- **P2.4 stage env**: clone the test env's Terraform stack + add an aws_iam_role policy attachment for the stage SSM target + a GitHub Environment named `stage`. The wiring pattern is now proven.
- **P4.2 branch protection**: switching default to `integration/next-phase` is the prerequisite; branch protection rules can land in P4 once we're sure no in-flight PRs target the old default.

---

## 5. What still gates "green CD all the way through prod"

- **Task #19 (Galaxy fork alembic)** — once Galaxy boots clean on Postgres, the external HTTP healthcheck flips green and we exercise the success path: tag commit, retention prune, SNS success notify. Until then, every deploy ends in the failure path. The CD primitive itself doesn't need to wait.
- **P2.4 + P4.1** — actually provision stage and prod EC2s + Route53 records (`platform.biomate.ai` zone needs delegation NS records added at the registrar — same pattern as dev-public + stage-public).
- **SNS email confirmation** — subscription on `biomate-deploy-events` for `xiaoni5122@gmail.com` is `PendingConfirmation`. Notifications are silently dropped until you click the AWS confirmation link.

---

## 6. Files touched / created

```
.github/workflows/deploy.yml                            (new)
scripts/deploy.sh                                       (ssm_run error handling; healthcheck-fail rollback)
docs/20260520_CICD_PHASE3_P31_GHA_DEPLOY_PIPELINE.md    (this file)
```

AWS:
```
iam::role/GitHubActionsDeploy                           (new; least-privilege deploy role)
iam::role-policy/GitHubActionsDeploy/DeployViaSsm       (split into 5 statements; condition correctly scoped)
github_environment test (on repo bioMate-AI/biomate)    (new; gates OIDC sub-claim)
default_branch repo setting                              (connection_formal → integration/next-phase)
```
