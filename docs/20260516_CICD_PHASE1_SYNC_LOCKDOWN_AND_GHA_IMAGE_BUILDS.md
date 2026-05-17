# CI/CD Rebuild — Phase 1 Session Report

**Sessions:** 2026-05-14 → 2026-05-17
**Scope:** P0 (plan), P1.1 (sync_to_dev.sh lockdown), P1.2 (GHA image builds)
**Plan document:** [`docs/20260514_CICD_REBUILD_PLAN.md`](20260514_CICD_REBUILD_PLAN.md)
**Branch:** `integration/next-phase`
**Status:** P0 done · P1.1 done · P1.2 infrastructure live & validating; surfacing real source-tree issues

---

## 1. What was decided

The current dev infrastructure has one environment plus a hand-rolled `scripts/sync_to_dev.sh` polling loop. We are building a proper four-environment CI/CD pipeline:

| Env | URL | Approval |
|---|---|---|
| local | `localhost:5000` | — |
| dev | `dev-public.biomate.ai` | auto |
| stage | `stage-public.biomate.ai` (new) | auto after dev green |
| **prod** | **`platform.biomate.ai`** (new) | **manual GH Environments approval** |

Locked decisions (revised after team review on 2026-05-15):

- **Compute:** EC2 + docker-compose (no ECS migration). Image-tag-based deploys via AWS SSM Run Command.
- **No blue/green** on single-instance hosts — replaced with `compose pull && up -d --wait` + healthcheck + automatic rollback.
- **Two-track promotion:** *minor* changes auto-deploy through dev → stage → prod (with approval gate). *Major* changes (DB migrations, S3 layout) get an additional approval gate and auto-snapshot RDS + affected S3 prefixes before deploying.
- **Branching:** single `main` branch (small team). Release markers are tags `release-x.y.z` that match ECR image tags exactly. Initial version `release-0.0.1`. No `release/*` branches.
- **Database:** migrate Galaxy `database_connection` SQLite → RDS Postgres (Phase 2).
- **Approval gate:** manual GH Environments approval before any prod deploy; additional approval for major-track changes.
- **IaC:** Terraform.
- **Retention:** ECR lifecycle keeps last K=10 release tags + K=10 sha tags; on-host container prune keeps last K=3 stopped.
- **Notifications:** SES email on every deploy success/failure.

Two items explicitly out of scope (documented in plan §6):

1. **Lago + Java billing on `35.86.137.71`** — stays standalone; fold into prod VPC after Phase 4.
2. **GPU / AWS Batch / CryoSPARC remote** — unchanged. Phase 1–4 must not break the Batch submission interface (S3 paths, IAM role names, queue ARNs).

---

## 2. Past-incident register (§6.3 of plan)

Before writing any code, we audited every documented incident in `docs/` and project memory that touched config, DB, env, or sync. **22 lessons (L1–L22)** were converted into hard requirements that the new pipeline must satisfy. The most load-bearing five:

- **L1.** Stale `latest` tag masked 5-week image drift → every image must carry `sha-<commit>` tag + `/image-build-info` provenance file.
- **L5.** Nextflow auto-installed (unpinned) broke 16+ workflow directives when 26.04 landed → version must be pinned via `ARG NF_VERSION` and bumped only in a dedicated PR.
- **L8.** Galaxy `Storage.updateExecutionRun` expected columns absent from 2-week-old SQLite → every deploy runs `alembic upgrade head` before container swap; healthcheck only flips green after migration succeeds.
- **L9.** `LAGO_API_KEY` and other secrets hardcoded in scripts and docs → pre-cutover lint must catch any `(API_KEY|SECRET|TOKEN)=<value>` outside `.example` files; every leaked key gets rotated during Phase 2.3.
- **L18.** AWS CLI symlink to `/usr/bin/aws` broke when Nextflow bind-mounted `/opt/aws-cli` into Batch task containers → CLI installed self-contained at `/opt/aws-cli/bin/aws` and verified at image-build time.

Full register: plan doc §6.3.

---

## 3. P1.1 — `sync_to_dev.sh` lockdown (commit `8e8775e07`)

**Goal:** stop the two recurring failure modes without disabling manual fallback.

Removed:
- 10-minute `while true; do … sleep 600; done` polling loop.
- Auto-commit-before-sync block (lines 389–423 in old script) that bypassed code review by silently committing dirty source files.

Added:
- PID lockfile guard (`/tmp/biomate_sync_to_dev.lock`) — prevents concurrent runs (incident L7: 8+ orphan loops from prior Claude sessions fighting over the container).
- Pre-flight refusal: script errors out if working tree has uncommitted source files. User must commit or stash explicitly.
- Single-shot exit. No retries, no polling.

Manual `bash scripts/sync_to_dev.sh` still works and remains the supported fallback until the GHA pipeline is proven (per plan §P4.3 exit criteria: 2 weeks of green deploys + 1 auto-rollback drill + 1 major-track deploy).

Verified no orphan sync processes locally or on dev EC2 `i-06696b0d91f4346e0` at time of change.

---

## 4. P1.2 — GHA image builds (commits `88bee5af8`, `9b41d87bd`, `8809ed97b`, `c078d06aa`, `f6ddaf431`, `6076611a9`)

### 4.1 AWS infrastructure (one-time, out-of-band)

| Resource | ARN / value |
|---|---|
| OIDC provider | `arn:aws:iam::399683337364:oidc-provider/token.actions.githubusercontent.com` |
| IAM role | `arn:aws:iam::399683337364:role/GitHubActionsECRPush` |
| Trust policy scope | `repo:bioMate-AI/biomate:*` (any branch/tag/PR from this repo) |
| Permissions | `ecr:GetAuthorizationToken`, push to `biomate/dev-backend` + `biomate/dev-frontend` only |
| ECR lifecycle (both repos) | K=10 release tags, K=10 sha tags, untagged dropped after 7d |
| Org-level Actions | `bioMate-AI` org has Actions in "selected repositories" mode; this repo added to the allow-list |

No long-lived AWS credentials in GitHub secrets. Reversible (deletable) with no side effects.

### 4.2 Workflows

`.github/workflows/backend-image.yml` and `.github/workflows/frontend-image.yml`. Triggers:

- `push` on `main` or `integration/next-phase` (active dev branch).
- `push` of `release-*` tags.
- `workflow_dispatch` for manual runs.
- Path-filtered: backend workflow only fires on `backend/**` changes; frontend on `frontend/**`.

Tag scheme per build:
- `sha-<12char-commit>` — pinned forever, used by deploys.
- `<branch>-latest` (slash → dash, e.g. `integration-next-phase-latest`) — moving pointer per branch.
- `release-x.y.z` — pushed only when triggered by a release tag.

Concurrency group `<workflow>-<ref>` with `cancel-in-progress: true` — prevents two simultaneous builds racing on the same branch.

### 4.3 Build-time guardrails

Each build runs as smoke tests against the actually-built image (not the source). Failure of any guardrail aborts the push to ECR. Coverage:

| Lesson | Guard |
|---|---|
| L22 | `.dockerignore` presence + `.venv` + `database/*.sqlite` exclusions asserted before build |
| L1 | `/image-build-info` file baked with `git_sha`, `build_date`, `nf_version`; smoke step `cat`s it from the image |
| L18 | `/opt/aws-cli/bin/aws --version` runs inside the image |
| L5 | `/usr/local/bin/nextflow -version` runs inside the image (verifies the pinned download landed) |
| L2 | `python -c "import boto3, redis, psycopg2, requests, yaml, sqlalchemy, alembic"` — failed import → failed build |
| L4 | grep image for `/home/<user>/` in first-party `*.py *.yml *.yaml *.conf *.cfg *.json` files; excludes `node_modules`, `site-packages`, `.venv` |

### 4.4 Backend Dockerfile fixes

Bugs the dry-runs surfaced and the fixes applied:

| # | Surfaced as | Cause | Fix |
|---|---|---|---|
| 1 | Build log: `mv: cannot stat 'config/galaxy.yml.docker'` | `galaxy.yml.docker` contains plaintext `ai_llm_api_key: sk-ant-…` and is correctly `.gitignore`d (L9) — never reaches CI build context. `|| true` was masking the failure. | Switched to `cp config/galaxy.yml.template config/galaxy.yml`. Template is checked in, uses `${ANTHROPIC_API_KEY}` placeholder; Galaxy interpolates at runtime. Removed the `2>/dev/null \|\| true` mask. Image is now secret-free at build time. |
| 2 | Smoke step: `mkdir: cannot create directory '/app/.nextflow': Permission denied` (despite USER=galaxy and useradd `-d /app`) | Docker does not auto-populate `HOME` from `/etc/passwd` when `USER` is set. `HOME` defaulted to `/`. Nextflow tried `mkdir $HOME/.nextflow`. | `ENV HOME=/app` and `ENV NXF_HOME=/app/.nextflow` in the image. |
| 3 | Smoke step: same `EACCES` even after fix #2 | `/app` itself was created by `WORKDIR` before `useradd` and was root-owned 755. `COPY --chown=galaxy` only chowns copied files, not the parent dir. Subdirs created by later `mkdir` are also root-owned. | Pre-create `/app/.nextflow` in the build step; `chown galaxy:galaxy /app /app/galaxy.log /app/.nextflow` and recursive chown over `database/`, `logs/`, `config/plugins/`. |
| 4 | L4 lint: `/home/yzhang/biomate/backend/...` paths in `workflow_summary_mqc.yaml` files | 432 MB / 1705 files of Nextflow runtime artifacts under `backend/work/` were accidentally committed and contain absolute launching-machine paths. | Added `work/` to `backend/.dockerignore`. Follow-up filed to `git rm -r --cached backend/work/` proper. |

Pinned `ARG NF_VERSION=24.10.5` and installed Nextflow from the explicit GitHub release URL (no more `curl | bash` from `get.nextflow.io`).

### 4.5 Workflow-side fixes during dry-runs

- **L4 lint scope** — initial version caught `/home/nate/` and `/home/playwright/` strings inside vendored npm package docstrings. Tightened to scan first-party only via `--exclude-dir={node_modules,site-packages,.venv,dist,.cache}`.
- **Tag scheme** — original `main-latest` shared between `main` and `integration/next-phase` would have collided. Replaced with branch-scoped `<branch>-latest` so each branch has its own moving pointer.

### 4.6 Validation status as of end of session

| Run | Branch SHA | Result |
|---|---|---|
| Frontend `25968494181` | `c078d06a` | ✅ green — image pushed to `biomate/dev-frontend:sha-c078d06aab84` |
| Frontend `25968731703` | `f6ddaf43` | ✅ green — second confirmation, `integration-next-phase-latest` set |
| Backend `25968731704` | `f6ddaf43` | ❌ L4 — `backend/work/` artifacts (fixed in next push) |
| Backend `25968980525` | `6076611a` | ❌ L4 — caught two **real** first-party hits (see §4.7) |

ECR state after the green frontend runs:
```
biomate/dev-frontend: sha-f6ddaf431130, integration-next-phase-latest
biomate/dev-backend:  (no green tag yet)
```

### 4.7 Real L4 violations the workflow surfaced (handed off for cleanup)

Both are now tracked as follow-up tasks; they are not P1.2 infrastructure bugs but pre-existing source-tree leaks the workflow correctly identified:

1. `BIOMNI_FUNCTIONS_ANALYSIS_2025-10-13.json` — contains `/home/appuser/input` and `/home/appuser/output` paths in container-template strings. Probably reference docs for a Docker-based tool; either parametrize or move out of `/app`.
2. `experiments/cryo_em_autoloop/tests/test_truth_based_qc.py` — has `/home/yzhang/biomate/` literal in a docstring. Real dev-path leak.

The pipeline is doing what it should: refusing to push an image with these leaks. The right resolution is to fix the source, not relax the lint.

---

## 5. Follow-ups created this session

- **Task #17:** `git rm -r --cached backend/work/` + ensure entry in `backend/.gitignore` (currently `.dockerignore` only). Shrinks repo by ~432 MB.
- **Task (new):** Remove `/home/yzhang/biomate/` and `/home/appuser/` literals from `BIOMNI_FUNCTIONS_ANALYSIS_2025-10-13.json` and `experiments/cryo_em_autoloop/tests/test_truth_based_qc.py`. Either parametrize via env var, gitignore from image scope, or whitelist with explicit justification.

---

## 6. What ships next (P1.3 → P1.4)

- **P1.3** — `scripts/deploy.sh <env> <release-tag>` using AWS SSM Run Command (no SSH, no Instance Connect). Includes pre-flight disk check, `alembic upgrade head`, HTTP healthcheck (90s/5s), automatic rollback to prior tag on failure, ECR + on-host retention pruning (with `--filter=until=24h` — **never** `prune -af`), boto3 `Config(retries={'mode': 'adaptive'})`, SES success/failure email.
- **P1.4** — CloudWatch idle alarm on every EC2 (Terraform-managed, not in-app daemon thread — L14 made that mistake cost $1,400). Dev = notify-only. Ephemeral GPU = auto-terminate.

The plan retains the `sync_to_dev.sh` fallback until P4.3 exit criteria are met (≥2 weeks of green GHA deploys, ≥1 auto-rollback drill, ≥1 major-track DB-migration deploy).

---

## 7. Files touched / created

```
docs/20260514_CICD_REBUILD_PLAN.md                          (new, plan + register)
docs/20260516_CICD_PHASE1_SYNC_LOCKDOWN_AND_GHA_IMAGE_BUILDS.md (this file)
scripts/sync_to_dev.sh                                       (auto-poll + auto-commit removed; lockfile added)
backend/Dockerfile                                           (Nextflow pin, AWS CLI v2, /image-build-info, HOME/NXF_HOME, chown /app)
backend/.dockerignore                                        (+ work/)
.github/workflows/backend-image.yml                          (new)
.github/workflows/frontend-image.yml                         (new)
```

AWS:
```
iam::oidc-provider/token.actions.githubusercontent.com       (created)
iam::role/GitHubActionsECRPush                               (created)
ecr lifecycle policies on biomate/dev-{backend,frontend}     (set, K=10/K=10/7d)
org bioMate-AI Actions allow-list                            (this repo added)
```
