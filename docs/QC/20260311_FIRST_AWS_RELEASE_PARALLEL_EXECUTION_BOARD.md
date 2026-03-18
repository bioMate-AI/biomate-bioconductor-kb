# First AWS Release Parallel Execution Board (R1)

Date: 2026-03-11  
Release candidate: `aws-release-2026-03-11-r1`  
Goal: ship first AWS release now, while parallel improvements continue on separate branches.

---

## 1) What is already ready

- Core release gates are green on current candidate:
  - `npm --prefix frontend run check`
  - `npm --prefix frontend run test -- server/execution-env-policy.test.ts server/workflow-execution.test.ts`
  - `RUN_LIVE_EXECUTE_CONTRACT=1 REQUIRE_AWS_EXEC_200=1 ... test:live:execute-contract:strict`
- AWS infra readiness is now marked complete in release docs (Batch/IAM/S3).
- CI/CD workflows for release gate and release update are in place:
  - `.github/workflows/aws-release-gate.yml`
  - `.github/workflows/aws-release-update.yml`

---

## 2) Parallel tracks for first release

## Track A - Release control (start now)

Owner: release captain  
Status: in progress

Start tasks:

1. lock release candidate scope (`r1`) and freeze non-release merges
2. maintain approved cherry-pick list for release updates only
3. schedule go/no-go checkpoint with tracks B/C/D/E/F

Deliverables:

- release-scope lock note
- approved patch list
- final go/no-go record

## Track B - App/API validation (start now)

Owner: app maintainer  
Status: in progress

Start tasks:

1. run core gates on release candidate
2. run strict live contract against release target URL
3. attach command output summary to sign-off

Required command set:

```bash
npm --prefix frontend run check
npm --prefix frontend run test -- server/execution-env-policy.test.ts server/workflow-execution.test.ts
RUN_LIVE_EXECUTE_CONTRACT=1 REQUIRE_AWS_EXEC_200=1 BIOMATE_URL=<target_url> npm --prefix frontend run test:live:execute-contract:strict
```

## Track C - AWS infra validation (completed baseline, keep watch)

Owner: ops/cloud engineer  
Status: complete baseline / monitor during deploy

Focus now:

1. keep queue/role/bucket watch during rollout window
2. verify no account-level drift before prod deploy
3. keep rollback infra path ready

## Track D - Runtime dependency closure for day-0 scope (start now)

Owner: workflow/runtime maintainer  
Status: in progress

Start tasks:

1. verify runtime modules for day-0 release workflow allow-list
2. explicitly mark temporarily excluded domains (if any)
3. publish closure/exclusion note for release communication

Known risk to close:

- ADMET path dependency gaps (example: `DeepPurpose`)

## Track E - Deploy + smoke + rollback drill (start now)

Owner: QA + release captain  
Status: in progress

Start tasks:

1. deploy release candidate to target AWS environment
2. run smoke (`generate -> execute -> status -> outputs`)
3. run rollback drill to previous stable tag

Deliverables:

- smoke evidence pack
- rollback confirmation note
- execution runbook link for no-CI path:
  - `docs/QC/20260312_EC2_DOCKER_S3_RELEASE_RUNBOOK.md`

## Track F - CI/CD release update drill (start now)

Owner: platform/devops  
Status: in progress

Start tasks:

1. run `AWS Release Gate` workflow on release PR
2. run `AWS Release Update` workflow in dry run (`create_tag=false`)
3. run second pass with strict live contract enabled

Dry-run inputs:

- `source_ref`: release branch or selected commit
- `release_tag`: trial tag format (`aws-v...-rc`)
- `run_live_contract`: `true`
- `biomate_url`: staging URL
- `create_tag`: `false`

---

## 3) CI/CD test plan with new updates (next step after R1 starts)

Use this to validate release-update flow without risking production tags:

1. create small docs-only update on release branch (safe canary)
2. open PR to `release/**` and verify `AWS Release Gate` passes
3. run manual `AWS Release Update`:
   - pass with `create_tag=false` first
   - rerun with `create_tag=true` only after approval
4. verify generated tag points to expected release commit
5. run one post-tag smoke

Success criteria:

- both workflows pass in sequence
- strict live contract passes in update workflow
- no unrelated branch changes are pulled into release artifact

---

## 4) Go/No-Go checklist for R1

- [ ] Track A: scope lock + patch list done
- [ ] Track B: core gates + strict live contract green
- [ ] Track C: infra health reconfirmed during rollout window
- [ ] Track D: day-0 runtime dependency status published
- [ ] Track E: deploy smoke + rollback drill complete
- [ ] Track F: release update workflow dry-run completed

GO when all checks are complete, or with explicitly approved scope exclusions documented by owner/date.

---

## 5) CI/CD Drill Commands (for release update test)

Use these as the canonical dry-run sequence for testing release updates before tagging.

### 5.1 Prepare a safe canary update

1. create a tiny docs-only change on release branch
2. open PR to `release/**`
3. verify `AWS Release Gate` workflow is green

### 5.2 Trigger manual release update workflow (dry run)

GitHub UI:

1. Actions -> `AWS Release Update`
2. Run workflow with:
   - `source_ref=release/aws-2026-03-11-r1`
   - `release_tag=aws-v2026.03.11-r1-drill`
   - `run_live_contract=true`
   - `biomate_url=<staging_url>`
   - `create_tag=false`

CLI (`gh`) equivalent:

```bash
gh workflow run "AWS Release Update" \
  -f source_ref="release/aws-2026-03-11-r1" \
  -f release_tag="aws-v2026.03.11-r1-drill" \
  -f run_live_contract=true \
  -f biomate_url="https://<staging-host>" \
  -f create_tag=false
```

### 5.3 Promote to real patch tag after approval

After dry-run success and approval, rerun with:

- `release_tag=aws-v2026.03.11-r2` (or next patch tag)
- `create_tag=true`

```bash
gh workflow run "AWS Release Update" \
  -f source_ref="release/aws-2026-03-11-r1" \
  -f release_tag="aws-v2026.03.11-r2" \
  -f run_live_contract=true \
  -f biomate_url="https://<prod-or-staging-host>" \
  -f create_tag=true
```

### 5.4 Expected evidence to archive

For both dry-run and real tag runs, archive:

1. workflow run URL
2. pass/fail for `validate-core`
3. pass/fail for strict live contract step
4. created tag name and commit SHA (for real tag run)

---

## 6) Parallel execution progress snapshot (current)

Snapshot from active parallel track execution:

### Track B - App/API validation

Status: `green`

Completed:

1. `npm --prefix frontend run check` -> pass
2. `npm --prefix frontend run test -- server/execution-env-policy.test.ts server/workflow-execution.test.ts` -> pass (`73/73`)
3. `RUN_LIVE_EXECUTE_CONTRACT=1 REQUIRE_AWS_EXEC_200=1 BIOMATE_URL=http://127.0.0.1:5000 npm --prefix frontend run test:live:execute-contract:strict` -> pass (`1/1`)

### Track D - Runtime day-0 scope recommendation

Status: `amber` (scope-ready, dependency closure pending for excluded domain)

Recommended day-0 include:

- `biomni_nf/genomics/get_rna_seq_archs4/main.nf`

Recommended day-0 exclude (until dependency closure):

- pharmacology ADMET / DeepPurpose-dependent paths

### Track F - CI/CD update drill readiness

Status: `amber` (workflow files ready; platform billing gate blocks hosted runner execution)

Completed:

- new workflows exist and parse as valid YAML:
  - `.github/workflows/aws-release-gate.yml`
  - `.github/workflows/aws-release-update.yml`

Blocker:

- Hosted GitHub Actions jobs are blocked by account billing/spending limit status.
  - Run evidence:
    - `https://github.com/bioMate-AI/biomate/actions/runs/22986275465` (`AWS Release Gate`)
    - `https://github.com/bioMate-AI/biomate/actions/runs/22986277248` (`AWS Release Update`)
  - Failure annotation:
    - "The job was not started because recent account payments have failed or your spending limit needs to be increased."

Immediate unblock:

```bash
# 1) Fix GitHub billing/spending limit in org/repo settings.
# 2) Re-run the two workflow dispatches:
gh workflow run "AWS Release Gate" --ref "connection_formal" -f run_live_contract=false
gh workflow run "AWS Release Update" --ref "connection_formal" -f source_ref="connection_formal" -f release_tag="aws-v2026.03.11-r1-drill" -f run_live_contract=false -f create_tag=false
```

### Track A/E - control + operations

Status: `green` for schedule readiness

Completed:

- first 8-hour execution schedule, checkpoint gates, and artifact checklist prepared and ready for team kickoff.

### Track F - latest drill execution evidence

Completed:

1. Workflows are now registered and visible on remote:
   - `AWS Release Gate`
   - `AWS Release Update`
2. Both workflows were dispatched successfully via `gh workflow run`.
3. Both runs failed before job start due to billing/spending gate (not YAML or test failures).

### Track E/F - fallback implementation path (active)

When billing is not expected to be fixed, use:

- S3-first artifact staging + EC2 Docker deployment:
  - `docs/QC/20260312_EC2_DOCKER_S3_RELEASE_RUNBOOK.md`
- staging script:
  - `scripts/deployment/stage-release-to-s3.sh`
- EC2 deploy script:
  - `scripts/deployment/ec2-deploy-from-s3.sh`
- dev URL binding script:
  - `scripts/deployment/configure-ec2-dev-url.sh`

