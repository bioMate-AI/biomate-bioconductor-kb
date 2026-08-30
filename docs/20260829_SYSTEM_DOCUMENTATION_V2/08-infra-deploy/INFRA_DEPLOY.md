# 08 · Infrastructure & Deploy

**Verified 2026-08-29.**

---

## 1. `scripts/sync_to_dev.sh` (1,902 lines) — the only sanctioned dev deploy

Manual one-shot sync to `dev-public.biomate.ai` over **AWS SSM** (no open port 22). The auto-poll loop and auto-commit-before-sync were **removed** — commit yourself first. Four layers synced: **frontend** (Docker rebuild + restart), **backend Python** (`docker cp` into the running Galaxy container + gunicorn reload), **Galaxy DBs** (`galaxy_ai_tools.db`, `universe.sqlite`), **Nextflow `.nf`** files. The marketing site is **not** synced.

**Rollback model** — dev is an in-place file hot-patch + gunicorn HUP, not an image swap. Because the Galaxy container has **no mounts**, `snapshot_for_rollback()` (L1331) runs `docker commit … biomate-galaxy-dev:rollback` **before** the sync to capture all hot-patched code/DB/workflows.

**Health gate + auto-rollback:**
- `postsync_health_ok()` (L1499) probes Galaxy `localhost:8081/api/version` + frontend `localhost:3000/api/health`.
- A deeper functional gate hits `/api/ai_assistant/generate_workflow` (L1368) and the DB-query path (L1437).
- `do_sync()` (L1578): on pass → `SYNC_RESULT=healthy`; on fail → `rollback_sync()` (L1517) recreates containers from the `:rollback` snapshot and re-checks.
- Result state (`healthy | rolled_back | rollback_failed | failed`) is pushed via **SNS** so a failed sync is not silent. Also does an MCP liveness probe (`POST localhost:3000/mcp`) and Nextflow-version reconciliation.

> **Deploy discipline** (from CLAUDE.md + memory): commit → pull latest `integration/next-phase` → push feature branch (next-phase is PR-protected) → PR → merge → **sync only from the main repo `/Users/kky/biomate`, never from a worktree**. Never SSM-modify dev out-of-band (read-only diagnostics only). Run the [pre-sync checklist](../09-testing/TEST_PLAN.md#pre-sync-gate) first.

## 2. Docker topology & FROM chains

- **Frontend** (`frontend/Dockerfile`): `node:18-bookworm-slim` builder → runtime; bundles the `docker.io` CLI for sandbox spawn; `PORT=3000`, health `/api/health`.
- **Backend/Galaxy** (`backend/Dockerfile`): **`python:3.9-slim-bookworm`** (bookworm, not trixie — keeps JDK17 / glibc 2.36 to avoid an AWS-CRT JVM SIGSEGV). Pins `NF_VERSION=25.10.5`, pre-caches the Nextflow launcher + JAR under `/opt/nextflow/framework/25.10.5/`, AWS CLI v2 at `/opt/aws-cli/bin/aws`, pre-bakes HF sentence-transformer models; `galaxy` UID 1000; health `curl localhost:8080/api/version`.
- **Compose:** `docker-compose.yml` (dev: `biomate-galaxy` + `biomate-frontend`, bridge `biomate-network`); `docker-compose.ec2.yml` adds `postgres:15`; `deploy/docker-compose.deploy.yml` uses ECR refs, loads `/opt/biomate/.env`, sets `RUN_STATE_STORE=redis`; `deploy/docker-compose.sandbox.yml` adds gVisor `runsc` + `docker-socket-proxy` + `sandbox-launcher`.
- **Batch tool images** (`aws_infrastructure/configs/`): `Dockerfile.nextflow-base` = `python:3.11-slim` + AWS CLI + rdkit/scipy/biopython → `biomate-nextflow-base:latest`; bioconductor images FROM `biomate/bioc-domain-general:3.20-slim` (MOFA2) and `biomate/bioc-domain-genomics:3.20-slim` (clusterProfiler).

## 3. AWS resources

- **Account** `399683337364`, **region** `us-west-2`.
- **ECR** `399683337364.dkr.ecr.us-west-2.amazonaws.com`: `biomate/dev-backend`, `biomate/dev-frontend`, `biomate/ml-training`, `biomate/trl-training`, `biomate/sandbox-launcher`, `biomate-nextflow-base`, `biomate-nextflow-sandbox`, `biomate/bioc-domain-*`.
- **AWS Batch** (`nextflow_executor.py`): CPU queue `biomate-nextflow-queue` (L2589), GPU queue `biomate-gpu-spot-queue` (L2850); per-label `process_gpu` routing to avoid CPU starvation (2026-06-04 incident); default container `biomate-nextflow-base:latest`.
- **S3:** `biomate-nextflow-work` (default workdir/outputs), `biomate-cryo-data`, `biomate-test-data`; dev DB seed `s3://biomate-nextflow-work/dev-sync/galaxy_ai_tools.db`.
- **ElastiCache Redis** via `REDIS_URL` (billing-shared): run-state + billing ledger.
- **Lambda (billing):** `biomate-batch-billing-handler` (Python 3.12, EventBridge `biomate-batch-job-state-change`), `biomate-s3-billing-handler` (SQS `biomate-s3-billing-events` + DLQ).

## 4. Dev environment & gunicorn

- Containers: `biomate-dev-frontend` (net `biomate-dev-net`), `biomate-galaxy-dev` (rollback tag `:rollback`), remote-MCP on the same net.
- **Gunicorn** (`backend/config/galaxy.yml.docker:21–47`): bind `0.0.0.0:8080`, **`workers: 4`**, **`max_requests: 3000`**, **`max_requests_jitter: 300`**, **`preload: true`**, `timeout: 300`, `worker_class: sync`. Preload + copy-on-write fork was the fix for single-worker stale-UX blockers. (The old "1 worker / ~3-min recycle" era is over — don't cite it when diagnosing dev issues.)

## 5. Local service map

| Service | Port | Notes |
|---------|------|-------|
| Main app (Node + Vite) | 5000 | open in browser |
| Galaxy backend (gunicorn) | 8081 | `kill -HUP $(pgrep -f "gunicorn.*8081"\|head -1)` to reload Python |
| Reference design (static) | 7779 | UX parity target |
| Local Lago | 3010 | **do NOT use for billing tests** |

Container-internal ports differ (frontend 3000, Galaxy 8080); 5000/8081 are the host-local dev mappings.

## Key files / infra

| Area | Path / resource |
|------|-----------------|
| Deploy sync | `scripts/sync_to_dev.sh` (health gate L1499; rollback L1331/L1517) |
| Frontend image | `frontend/Dockerfile` (`node:18-bookworm-slim`) |
| Backend image | `backend/Dockerfile` (`python:3.9-slim-bookworm`, NF 25.10.5) |
| Compose (deploy/sandbox) | `deploy/docker-compose.deploy.yml`, `deploy/docker-compose.sandbox.yml` |
| Batch base image | `aws_infrastructure/configs/Dockerfile.nextflow-base` |
| Gunicorn config | `backend/config/galaxy.yml.docker:21-47` |
| Batch/S3/queues | `nextflow_executor.py:2589-2854` |
| Billing Lambdas | `ai/billing/lambda/{batch,s3}_event_handler.py` + `infrastructure/deploy_*.sh` |
