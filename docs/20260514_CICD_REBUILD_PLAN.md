# BioMate CI/CD Rebuild Plan

**Date:** 2026-05-14
**Author:** Engineering
**Status:** Approved — implementation starting Phase 1

---

## 1. Goal

Replace the hand-rolled `scripts/sync_to_dev.sh` polling loop with a professional, auditable CI/CD pipeline covering four environments:

| Env | URL | Purpose | Approval |
|---|---|---|---|
| **local** | `http://localhost:5000` | developer laptop | — |
| **dev** | `https://dev-public.biomate.ai` | shared dev EC2; auto-deploy on push to `main` | none (auto) |
| **stage** | `https://stage-public.biomate.ai` | mirror of prod; full E2E + billing-smoke gate | auto after dev green |
| **prod** | `https://platform.biomate.ai` | customer-facing | **manual GH Environments approval** |

Locked architectural decisions (2026-05-14, revised 2026-05-15 per team review):

- **Compute:** EC2 + `docker-compose` (no ECS migration). Replace `docker cp` patching with image-tag-based deploys driven by AWS SSM Run Command.
- **Deploy strategy:** `docker compose pull && up -d --wait` with healthcheck + **automatic rollback on failure**. **No blue/green while we're on a single instance per env** — too much friction for too little benefit. Revisit blue/green only after we go multi-instance.
- **Two-track promotion by change type:**
  - **Minor** (code only, no schema/data change): fully automatic dev → stage → prod after green CI.
  - **Major** (DB migration, data shape change, S3 layout change): mandatory manual approval **and** automatic S3 snapshot of RDS + affected S3 prefixes before deploy. Detection: any commit touching `alembic/versions/*`, or commit message tagged `[major]`, or schema-detecting CI step flags it.
- **Branching/versioning (small-team):** single working branch `main`. Release markers are tags only — `release-0.0.1`, `release-0.0.2`, … — matching the ECR image tag exactly. No `release/*` branches. Initial version `release-0.0.1`.
- **Rollback:** redeploy any prior `release-x.y.z` tag in <5 min. Also automatic on healthcheck failure during deploy.
- **Database:** migrate Galaxy `database_connection` from SQLite → AWS RDS Postgres (Multi-AZ in prod).
- **Approval gate:** manual GH Environments approval before any prod deploy; **additional** approval required for any major-track change in any env.
- **IaC:** Terraform (no CloudFormation). State in S3 + DynamoDB lock.
- **Notifications:** email on every deploy (success + failure) to engineering list via SES.
- **Retention:** ECR lifecycle keeps last **K=10** images per repo; on-host container prune keeps last **K=3** stopped containers for emergency manual rollback.

---

## 2. Current State (the problems we are fixing)

Audited from `scripts/sync_to_dev.sh`, `docs/20260513_DEV_INFRASTRUCTURE_REBUILD.md`, `docs/20260422_BIOMATE_INFRASTRUCTURE_AND_INFORMATION_FLOW.md`, `docs/20260331_INFRASTRUCTURE_AND_AUDIT_REPORT.md`, and `.github/workflows/`.

### 2.1 Brittleness in `sync_to_dev.sh`

| # | Issue | Where | Consequence |
|---|---|---|---|
| 1 | Auto-commits dirty working tree before sync | `sync_to_dev.sh:389-402` | Unreviewed code reaches dev; bypasses any CI gate. |
| 2 | Hot-patches Python into running Galaxy container via `docker cp` | `sync_to_dev.sh:116-173` | Image drifts vs. source; runtime pip-installs silently fail; root cause of the 2026-03-31 → 2026-05-13 image-staleness crisis. |
| 3 | EC2 Instance Connect keys expire after 60s | `sync_to_dev.sh:795-801` | Race on large tar transfers; intermittent failures. |
| 4 | Galaxy container restart kills in-flight Nextflow subprocesses | infrastructure doc §10 | Manual resume needed; user-visible run failures. |
| 5 | `.nextflow/` cache copy uses `locals()` hack | infrastructure doc §2570-2574 | Silent failure → full pipeline re-run on resume. |
| 6 | No rollback mechanism; partial-state failure | `sync_to_dev.sh:422-429` | Half-synced systems with no clean recovery. |
| 7 | No health gate between sync layers | throughout | Downstream layers run even when upstream times out. |
| 8 | No idle-instance alarm | AWS | Orphan `i-0a2698b6bd30a98b2` (g6.12xlarge) burned **$1,400 over 12 days** before manual termination. |
| 9 | Multiple stale `sync_to_dev.sh` loops from prior sessions | rebuild doc §161-165 | Concurrent loops fight, container churn, unpredictable state. |
| 10 | Secrets hardcoded in script + docs | `sync_to_dev.sh:19,212`; CLAUDE.md billing section | No rotation; leaked credentials cannot be revoked without code change. |

### 2.2 GitHub Actions today (cosmetic, not real CI/CD)

| Workflow | Trigger | What it does | Gap |
|---|---|---|---|
| `aws-release-gate.yml` | PR to `release/**` | Frontend typecheck + lint | No backend tests; no image build. |
| `aws-release-update.yml` | Manual dispatch | Tag creation | No automation. |
| `feedback-e2e-matrix.yml` | PR + push to main | Playwright UX E2E | Runs against local-mocked stack, not AWS. |
| `pm-test-wire.yml` | PR + push to main | PM test harness | Internal only. |
| `reindex-workflows.yml` | Weekly cron | Workflow catalog index | No deploy hook. |

**Missing entirely:** backend lint/unit tests, image build+push, deploy job, migration check, smoke test against real AWS env.

### 2.3 Building blocks already present (we keep these)

- Dockerfiles: `backend/Dockerfile`, `frontend/Dockerfile`, `billing_system/Dockerfile`, `aws_infrastructure/configs/Dockerfile.nextflow-base`.
- `docker-compose.yml` (local) and `docker-compose.ec2.yml` (dev).
- ECR push (frontend only, today).
- Route53 hosted zones: `dev-public.biomate.ai` (live), `stage-public.biomate.ai` (zone exists, no A record yet).

---

## 3. Target Architecture

### 3.1 Deploy primitive

```
GitHub Actions
   └─ build image → push ECR
        tags: sha-<commit>, main-latest, and (on tag push) release-x.y.z
   └─ aws ssm send-command  (no SSH, no Instance Connect)
        └─ on target EC2:
             docker compose pull
             docker compose up -d --wait              (compose-level healthcheck)
             external HTTP probe (e.g. GET /health)   (90s budget, 5s interval)
        └─ on failure: docker compose up -d with previous successful tag (auto-rollback)
        └─ on success:
             docker image prune (keep last K=10 by tag)
             docker container prune --filter=until=24h  (keep last K=3 stopped)
             SES email: "[deploy] <env> <release-tag> success — <duration>"
        └─ on failure (after rollback):
             SES email: "[deploy] <env> <release-tag> FAILED — rolled back to <prev>"
```

No `docker cp`. No SSH. No auto-commit. One source of truth: the ECR image tag.

### 3.1.1 Minor vs major change routing

Every push to `main` is classified at the start of the pipeline:

```
classify-change job:
  if commit touches alembic/versions/** OR commit msg contains "[major]"
       OR schema-diff step detects DB shape change
    → label: major
  else
    → label: minor

minor → auto-deploy dev → smoke → auto stage → auto prod (after standard approval gate)
major → auto-deploy dev → smoke → auto stage → full E2E + billing-smoke
        → snapshot RDS (manual snapshot) + sync affected S3 prefixes to s3://biomate-deploy-backups/<release-tag>/
        → SECOND manual approval (data-change confirmation) ✋✋
        → prod deploy
```

### 3.2 Environment topology

```
local           dev                  stage                 prod
─────  ─────────────────────  ─────────────────────  ─────────────────────
laptop  EC2 i-06696b0d91...   EC2 (new, t3.xlarge)   EC2 (new, m6i.2xlarge)
        ALB+ACM               ALB+ACM                ALB+ACM
        RDS Postgres (small)  RDS Postgres (small)   RDS Postgres (Multi-AZ)
        S3 bucket             S3 bucket              S3 bucket
        Secrets Manager       Secrets Manager        Secrets Manager
        CW idle alarm         CW idle alarm          CW idle alarm + budget
```

### 3.3 GHA CD pipeline (Phase 3 final shape)

```
push to main
  ├─ classify-change (minor | major)                 [~10s]
  ├─ lint + pytest (backend) + tsc (frontend)        [required, ~5min]
  ├─ build & push images                              [required, ~8min]
  │    tags: sha-<commit>, main-latest, release-x.y.z (if tag pushed)
  ├─ deploy to DEV via SSM                           [auto]
  │    └─ alembic upgrade head → compose pull/up → HTTP healthcheck
  │    └─ prune old images/containers; SES notify
  ├─ smoke E2E against dev URL                       [required, ~10min]
  ├─ deploy to STAGE via SSM                         [auto if green]
  ├─ full E2E + billing-smoke against stage          [required, ~30min]
  ├─ [if major] snapshot RDS + S3 backup             [required, ~5min]
  ├─ [if major] data-change approval ✋✋             [GH Environments]
  └─ deploy to PROD                                  [GH Environments approval ✋]
       └─ alembic upgrade head → compose pull/up → HTTP healthcheck
       └─ auto-rollback to previous release tag on healthcheck fail
       └─ SES notify
```

Rollback (manual): `gh workflow run deploy.yml -f env=prod -f release_tag=release-0.0.4` — under 5 minutes to restore any prior tag.

Rollback (automatic): triggered by healthcheck failure during deploy; no human action needed.

---

## 4. Phases & Deliverables

### Phase 1 — Stop the bleeding (week 1)

- [ ] **P1.1** Disable **only** the auto-commit and 10-min auto-poll behaviors in `sync_to_dev.sh`. Manual invocation (`bash scripts/sync_to_dev.sh`) MUST keep working as a fallback. Kill orphan auto-loops on dev EC2. The script stays in active use until the GHA pipeline is proven end-to-end (see P4.3 exit criteria).
- [ ] **P1.2** New GHA workflows `backend-image.yml` + `frontend-image.yml`: lint, smoke test, `docker build`, push to ECR with tags `sha-<commit>` and `main-latest`.
- [ ] **P1.3** New `scripts/deploy.sh <env> <sha>` using AWS SSM Run Command. Includes healthcheck wait + auto-rollback to previous sha.
- [ ] **P1.4** CloudWatch idle alarm on every EC2 (CPU<5% for 1hr → SNS).

**Exit criteria:** dev can be deployed by running `gh workflow run deploy.yml -f env=dev -f sha=<sha>`. No `docker cp`. No SSH. No auto-commit.

### Phase 2 — Postgres + stage env (week 2)

- [ ] **P2.1** `infra/terraform/{modules,envs/{dev,stage,prod}}` skeleton. `terraform import` existing dev EC2, Route53 zones, ECR repos.
- [ ] **P2.2** Migrate Galaxy DB SQLite → RDS Postgres. `pgloader` one-shot from `universe.sqlite`. Adopt Alembic for our additive schema.
- [ ] **P2.3** Move all secrets from `.env` and hardcoded strings → AWS Secrets Manager. Containers fetch via instance-profile IAM role.
- [ ] **P2.4** Provision **stage** end-to-end on `stage-public.biomate.ai` via Terraform. Deploy `main-latest`. Verify smoke + billing-smoke E2E.

**Exit criteria:** `stage-public.biomate.ai` is live, mirrors prod config exactly, and passes the same E2E suite as dev.

### Phase 3 — Full CD pipeline (week 3)

- [ ] **P3.1** Single `deploy.yml` GHA: build → deploy dev → smoke → deploy stage → full E2E + billing-smoke → **GH Environments approval** → blue/green prod deploy. Concurrency group per env.
- [ ] **P3.2** Rollback `workflow_dispatch` accepting `env` + `sha` inputs.

**Exit criteria:** every push to `main` reaches stage automatically with green checks. Prod deploy requires one click.

### Phase 4 — Prod cutover + hygiene (week 4)

- [ ] **P4.1** Create Route53 hosted zone `platform.biomate.ai`. Add the 4 AWS-assigned NS records as a delegation record at the registrar where `biomate.ai` is registered (same pattern used for `dev-public` and `stage-public`). Request ACM cert (DNS validation) in us-west-2. Provision prod EC2 m6i.2xlarge + RDS Multi-AZ + ALB via Terraform. Daily EBS snapshot policy + RDS automated backups.
- [ ] **P4.2** Branch protection on `main`: required checks = classify-change + lint + unit + image-build + dev-smoke. Release tags `release-x.y.z` for every cut (initial = `release-0.0.1`). Per-env AWS budget alarms. Runbooks at `docs/runbooks/{deploy,rollback,hotfix,incident}.md`. SES email distribution list configured.
- [ ] **P4.3** Retire `sync_to_dev.sh` **only after** the new GHA pipeline has proven itself: at least 2 weeks of successful dev + stage + prod deploys via GHA, including at least one successful auto-rollback drill and one major-track (DB migration) deploy. Until that bar is met, manual `sync_to_dev.sh` remains a supported fallback. Once retired, move to `scripts/legacy/` with a README pointing at the new flow; confirm no cron/systemd still invokes it.

**Exit criteria:** `platform.biomate.ai` serves prod traffic. `sync_to_dev.sh` is retired. CI/CD is the only path to any environment.

---

## 5. Fix matrix — every brittleness gets a specific remedy

| Today's issue | Remedy | Phase |
|---|---|---|
| `docker cp` patches drift image vs source | Source of truth = ECR image tag. No live patching. | P1.3 |
| EC2 Instance Connect 60s key races | AWS SSM Run Command. | P1.3 |
| Galaxy restart kills Nextflow children | Nextflow runner in its own container w/ `restart: unless-stopped` and SIGTERM handler that snapshots `.nextflow/`. App restarts don't touch it. | P2 |
| `.nextflow/` cache `locals()` hack | Cache dir = named docker volume mounted into runner. No copy needed. | P2 |
| Auto-commit unreviewed code | Removed entirely; all changes go PR → main → CI → deploy. | P1.1 |
| Orphan instance burned $1,400 | CloudWatch idle alarm + per-env AWS budget. | P1.4 + P4.2 |
| Multiple sync loops fight | One GHA deploy job per env, GH concurrency group serialises. | P1.3 |
| No rollback | `deploy.sh <env> <sha>` accepts any prior sha. | P1.3 + P3.2 |
| Secrets in plaintext | AWS Secrets Manager + instance-profile IAM. | P2.3 |
| No backend tests in CI | pytest smoke gate added in image-build workflow. | P1.2 |
| SQLite blocks blue/green | RDS Postgres + Alembic. | P2.2 |
| No staging env | Stage on `stage-public.biomate.ai` via TF. | P2.4 |

---

## 6. Deferred / Out of Scope (revisit after Phase 4)

These are explicitly left alone for this rebuild. Documented here so future-us doesn't forget they exist.

### 6.1 Lago + Java billing service on `35.86.137.71`

**Current state:**
- Lago (SaaS metering) on EC2 `35.86.137.71:3000`. API key `01b71711-...` (rotate during Phase 2.3 secrets work).
- Java billing service on `35.86.137.71:8080`. Returns 503 intermittently (`docs/20260331_INFRASTRUCTURE_AND_AUDIT_REPORT.md:36,306`).
- AWS ElastiCache Redis at `biomate-billing-redis.xzhevl.0001.usw2.cache.amazonaws.com:6379`.
- AWS Lambda `biomate-batch-billing` triggered by EventBridge on Batch state changes.

**Why deferred:** billing is a separate concern from the app deploy pipeline; folding it in now expands scope significantly. The current standalone box works for metering and is read-only from the app's perspective via the `JAVA_BILLING_SERVICE_URL` env var.

**Future work (post-Phase 4):**
- Move Lago + Java billing into the prod VPC.
- Manage via Terraform.
- Auto-restart the Java service via systemd + CW alarm on the 503 condition.
- Unified ops/observability surface with the app tier.

### 6.2 GPU / AWS Batch / CryoSPARC remote

**Current state:**
- AWS Batch job queues + compute environments (GPU + CPU).
- CryoSPARC remote on `3.88.225.107` (us-east-1).
- Nextflow runner submits Batch jobs from inside the Galaxy container.
- IAM role `ecsInstanceRole` with `biomate-cryo-data` bucket policy.

**Why deferred:** Batch infra is functionally separate from the app deploy pipeline. The app tier only needs IAM credentials + queue names (which live in Secrets Manager after P2.3).

**Future work (post-Phase 4):**
- Terraform the Batch compute environments + job queues.
- Document the GPU AMI rebuild flow (per `project_gpu_infrastructure_issue.md` memory — `galaxy-cloud-compute-gpu-industrial` currently missing ECS GPU AMI).
- Health-check CryoSPARC remote in CW and page on outage.

**Hard constraint while deferred:** Phase 1–4 changes must not break the Batch submission interface. Specifically: S3 bucket names, IAM role names, job queue ARNs, and the `nextflow_executor.py` submission logic stay exactly as-is.

---

## 6.3 Lessons Learned Register — past incidents that shape this plan

Sourced from `docs/20260513_DEV_INFRASTRUCTURE_REBUILD.md`, `docs/20260422_BIOMATE_INFRASTRUCTURE_AND_INFORMATION_FLOW.md`, `docs/20260331_INFRASTRUCTURE_AND_AUDIT_REPORT.md`, and project memory files. Every item below is a hard requirement on the new pipeline.

### Config

| # | Past incident | Hard requirement on the rebuild |
|---|---|---|
| L1 | Dev ran a 5-week-stale Galaxy image because `latest` tag masked drift | Every push to `main` rebuilds images. **Never** use bare `latest`; always `sha-<commit>` + `main-latest` + `release-x.y.z`. Bake `cat /image-build-info` into the image for forensic auditing. |
| L2 | Runtime `pip install` from `sync_to_dev.sh` landed in `/app/.venv/` but gunicorn ran system Python — silent no-op | No runtime pip-installs, ever. All deps in image at build time. CI step: image build must execute `python -c "import <every-top-level-pkg>"` to fail loudly on missing deps. |
| L3 | `docker image prune -af` during disk pressure deleted the only working fallback image | Pipeline NEVER uses `prune -af`. ECR lifecycle keeps last K=10; on-host prune uses `--filter=until=24h` only. K=10 in ECR is non-negotiable. |
| L4 | `galaxy.yml` hardcoded `/home/yzhang/...` paths from local dev | Container images must contain NO host-specific paths. All paths come from env vars resolved from Secrets Manager at boot. Lint step: grep image for `/home/` literals → fail build. |
| L5 | Nextflow 26.04 broke 16+ directives because version was auto-installed (not pinned) | `Dockerfile` pins `ARG NF_VERSION=<exact-version>`. Bumping NF version requires its own PR + full E2E run, never a silent transitive upgrade. |

### Database

| # | Past incident | Hard requirement on the rebuild |
|---|---|---|
| L6 | `docker cp universe.sqlite` landed as `ubuntu:ubuntu`; Galaxy's `galaxy` user got read-only DB errors | After P2.2 (Postgres) this class of bug is gone. Until then, any `docker cp` must be followed by `docker exec -u root … chown galaxy:galaxy`. Add this check to a pre-deploy sanity script. |
| L7 | 8+ orphan `sync_to_dev.sh` loops from prior sessions wiped each other's container patches | GHA `concurrency: group: deploy-${env}` serializes deploys per env. Runbook step before any manual sync_to_dev.sh invocation: `pkill -f sync_to_dev.sh \|\| true`. |
| L8 | `Storage.updateExecutionRun` expected columns absent from a 2-week-old `universe.sqlite` | P2.2 Alembic. **Every** deploy runs `alembic upgrade head` BEFORE `docker compose up`; healthcheck only flips green AFTER migrations applied. Migration failure → automatic rollback. |
| L8b | No DB backup before destructive schema changes | Major-track gate (§3.1.1) takes RDS manual snapshot named `pre-<release-tag>` AND copies affected S3 prefixes to `s3://biomate-deploy-backups/<release-tag>/` BEFORE deploy. Snapshots retained 30 days. |

### Env vars / secrets

| # | Past incident | Hard requirement on the rebuild |
|---|---|---|
| L9 | `LAGO_API_KEY` and other secrets hardcoded in script + docs; no rotation path | P2.3 — Secrets Manager. Pre-cutover lint: `git grep -E "(API_KEY\|SECRET\|TOKEN)\s*=\s*['\"][A-Za-z0-9]{8,}"` must return zero outside `.example` files. Rotate ALL leaked keys (Lago, billing internal, JWT) during P2.3. |
| L10 | `JAVA_BILLING_ENABLED=true` not synced; dev container missing it; smoke test misled | Env state per env lives in Secrets Manager. Deploy fetches at boot. No `.env` editing on hosts. Smoke test asserts all expected env vars are present and prints their names (not values). |
| L11 | `REDIS_URL` pointed at `localhost:6379` locally but ElastiCache on dev → two caches, billing drift | Per-env config in Terraform + Secrets Manager. No hardcoded `localhost` strings in code paths that run in containers. CI grep guard. |
| L12 | `redis` Python pkg missing from image until 2026-05-13 rebuild | Image-build smoke: `python -c "from billing_router import *"` must succeed. Failing import = failing build. |

### Cross-cutting

| # | Past incident | Hard requirement on the rebuild |
|---|---|---|
| L13 | `boto3.describe_instances` returned empty Reservations for 5–30s after `run_instances` (AWS eventual consistency); IndexError | All AWS API calls in deploy scripts wrap in exponential backoff (max 5 retries, 2^n seconds). Use `botocore.config.Config(retries={'mode': 'adaptive'})`. |
| L14 | Orphan g6.12xlarge `i-0a2698b6bd30a98b2` burned $1,400 in 12 days — daemon-thread idle-killer died with gunicorn | P1.4 CloudWatch alarm is autonomous (not in-app). Alarm created on every EC2 launch via Terraform; deletion only via TF destroy. Idle threshold: CPU <5% for 1h → SNS → manual ack required (don't auto-terminate dev by mistake). |
| L15 | Galaxy restart SIGKILLed in-flight Nextflow subprocesses | P2: Nextflow runner = separate container, `restart: unless-stopped`, SIGTERM handler that snapshots `.nextflow/` to named volume. App tier deploys don't restart the runner. |
| L16 | `.nextflow/` cache copy used `locals()` hack — silently failed → full pipeline re-run | Named docker volume mounted at `/work/.nextflow`; no copy logic. Volume retained across deploys. |
| L17 | No rollback path; partial failures = unknown state | Every deploy = ECR image tag swap. Rollback = redeploy any prior `release-x.y.z` tag, <5 min. Auto-rollback on healthcheck failure. |
| L18 | AWS Batch `cliPath` symlink to `/usr/bin/aws` broke when bind-mounted into containers (exit 127 on ALL Batch jobs) | Self-contained AWS CLI at `/opt/aws-cli/bin/aws` via official installer. Verify in Dockerfile (CI assertion: `test -f /opt/aws-cli/bin/aws && /opt/aws-cli/bin/aws --version`). Already fixed across 2,102 workflows; preserve. |
| L19 | GPU compute env `galaxy-cloud-compute-gpu-industrial` used default ECS AMI (no NVIDIA toolkit) → silent CPU fallback | OUT OF SCOPE for this rebuild (§6.2 deferred). But the Terraform module skeleton (P2.1) reserves a `gpu_compute_env` resource block with explicit `image_id = <ECS-GPU-AMI>` placeholder + TODO comment so future-us can't forget. |
| L20 | EC2 Instance Connect 60s key races on large tar transfers | SSM Run Command (P1.3). No SSH. IAM-authenticated. |
| L21 | No health gate between sync layers — half-synced systems | Each GHA job is a hard gate. Failure halts downstream. Healthcheck is HTTP probe + container `healthy` status, both required. |
| L22 | Disk pressure during build; `.venv` (6.3GB) + `database/*.sqlite` (3.2GB) bloated build context | `.dockerignore` excludes both (already committed — verify still present). EBS root volume ≥50GB on every env. Pre-build disk check in SSM script: `df -h / \| awk 'NR==2 {if ($5+0 > 80) exit 1}'`. |

---

## 7. Open Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Postgres migration corrupts dev data | `pgloader` runs against an EBS snapshot of current SQLite; original `universe.sqlite` preserved for 30 days. Cut-over happens in dev first; stage and prod start fresh on Postgres. |
| Blue/green ALB swap drops in-flight Nextflow runs | Nextflow runner moved to its own long-lived container outside the app blue/green pair (see Phase 2 §`.nextflow/` cache fix). |
| `platform.biomate.ai` delegation NS record requires registrar access | Confirm registrar access before starting Phase 4. If blocked, fall back to `prod-public.biomate.ai` (same delegation pattern as dev/stage — works immediately). |
| Secrets Manager fetch failure at boot bricks containers | Local `.env` fallback retained for the first two weeks post-cutover; remove in P4.2. |
| Stage env unused → becomes drift source | Stage is part of the auto-deploy chain; every push to `main` exercises it. CW alarm if no deploy in 7 days. |

---

## 8. Tracking

Tasks are tracked in the Claude Code task list under prefixes **P1.x** through **P4.x**, plus two **Deferred** entries (§6). See `TaskList` for live status.
