# CI/CD test-env deploy validation — six layered fixes + Galaxy healthy

**Date:** 2026-05-21
**Scope:** Exercise the P3.1 CD pipeline against the test env now that the alembic block (Task #19, `f5c0401ad`) is cleared; fix every defect surfaced.
**Branch:** `integration/next-phase`
**Status:** **Galaxy backend boots HEALTHY end-to-end via the GHA pipeline for the first time.** Node frontend still needs its own config layer (see §6); that is a separate workstream.

---

## 1. Goal

Re-trigger `deploy.yml` against `test` and watch the previously-unverifiable success path: healthcheck green → tag commit → retention prune → SNS success. The P3.1 session report ended with deploy failing only because Galaxy couldn't boot due to alembic multi-head. With that fix merged, this session was supposed to be a confirmation run.

It was not. The first re-run failed, and each fix unmasked the next layer. Six real defects landed before Galaxy itself booted clean.

---

## 2. Defects fixed (in surfacing order)

| # | Symptom | Root cause | Fix | Commit |
|---|---|---|---|---|
| 1 | Pre-flight reported `DISK_FULL` (91%) and deploy continued anyway | `awk '...exit 1'` only exits awk, not the surrounding remote shell. No `set -e` in the SSM script body. | `set -e` + explicit shell test on disk %; aborts ssm_run cleanly. Also cleaned the test EC2 (5 GB reclaimed). | `90bae3905` |
| 2 | `compose pull` failed: `dev-frontend:sha-<X>: not found` after backend-only commit | Image-build workflows had `paths:` filters. A backend-only commit produced ONLY a backend image at `sha-<commit>`. `deploy.yml` workflow_run fired at that SHA → frontend image didn't exist there. | Dropped path filters from both image workflows so every commit rebuilds both images in lockstep. Per plan L1. | `57578fca5` |
| 3 | After (2), deploy still skipped silently — verify-images step said "not yet in ECR" even when images were present | `GitHubActionsDeploy` IAM role lacked `ecr:DescribeImages`. The verify-step's `aws ecr describe-images` returned AccessDenied; the script treated that as "not found". | Added `ecr:DescribeImages` for the two repos as a sixth statement on `DeployViaSsm` policy. | (out-of-band IAM put) |
| 4 | Galaxy boot: `NoVersionTableError: Your galaxy database has no version table` despite the alembic fix | A previous half-failed boot left RDS Postgres with tables but no `alembic_version`. Galaxy refuses to auto-recover from that state. | For the (ephemeral) test env, added step `[3b/5]` to `deploy.sh`: `DROP SCHEMA public CASCADE; CREATE SCHEMA public;` via `postgres:15-alpine` one-shot, then Galaxy boots into the "empty DB → bootstrap" path. Gated on `WIPE_GALAXY_DB=1` which is now `1` for test. Stage/prod retain durable schemas. | `3824a07ca` |
| 5 | Galaxy boot: `RuntimeError: LAGO_API_KEY not set and Secrets Manager fetch failed (AccessDenied on biomate/lago/api-key)` | `lago_client.py` fetches the Lago key from Secrets Manager at import time; the EC2 instance role only had access to `test/biomate/rds-galaxy`. | Extended `test-biomate-secrets-read` IAM policy via Terraform to also allow `biomate/lago/api-key-*` and a new consolidated `test/biomate/galaxy-env-*`. | `a7d47f933` |
| 6a | Galaxy boot: `BILLING_INTERNAL_KEY environment variable is required` (read directly from `os.environ`, not Secrets Manager) | The Lago secret only covered one variable. Many other Galaxy modules read env vars directly. | Created `test/biomate/galaxy-env` — a single KEY=VAL JSON secret. `deploy.sh` stage step fetches it once, iterates the JSON, idempotently appends every KEY=VAL to `/opt/biomate/.env`. New secrets added later don't need a deploy.sh change — just `aws secretsmanager update-secret`. | `a7d47f933` |
| 6b | Even after (6a), `BILLING_INTERNAL_KEY` was still empty inside the container | `docker compose` reads `/opt/biomate/.env` for `${VAR}` substitution but does NOT inject those vars as container env unless `env_file:` is declared. | Added `env_file: /opt/biomate/.env` to both services in `docker-compose.deploy.yml`. Pruned the per-var `environment:` entries that were duplicating it. | `a7d47f933` |
| 7 | Galaxy boot: `RuntimeError: JWT_SECRET environment variable is required` | Same env-var pattern, new variable. | Added `JWT_SECRET` (generated via `openssl rand -base64 32`) to `test/biomate/galaxy-env`. | (secret update only) |
| 8 | Frontend Node service: `DATABASE_URL environment variable is required` | The Node frontend reads its own Postgres connection from `DATABASE_URL` (Galaxy reads `GALAXY_CONFIG_OVERRIDE_DATABASE_CONNECTION`). | Added `DATABASE_URL` (same Postgres) to `test/biomate/galaxy-env`. | (secret update only) |

After fix #8, **Galaxy backend reached `Up X minutes (healthy)`** — first time the full Postgres + alembic + billing + JWT path booted clean via the CD pipeline.

---

## 3. The cascade rationale

Each fix unmasked the next layer because the previous layers were short-circuiting the failure. The pattern was instructive:

1. **Pipeline mechanics** (defects 1–3): the CD primitives themselves had race conditions and silent failures. Fixed once, then stable.
2. **Data state** (defect 4): the RDS schema was an orphan from before alembic was merged. One-time wipe step buys us a clean slate per test deploy.
3. **Secrets architecture** (defects 5–7): Phase 2.3 was partially done — RDS connection moved to Secrets Manager, but billing/auth/Lago env vars were never wired. The consolidated `test/biomate/galaxy-env` JSON secret + `env_file:` on the compose services solves this generically; adding new secrets is now a one-line update.
4. **Service config inventory** (defect 8 + ongoing): each service has its own env-var contract. Galaxy uses `GALAXY_CONFIG_OVERRIDE_DATABASE_CONNECTION`, Node uses `DATABASE_URL`; both point at the same Postgres but neither inherits from the other.

---

## 4. Files touched

```
.github/workflows/deploy.yml                            # verify-both-images guard + verify step
.github/workflows/backend-image.yml                     # drop paths: filter
.github/workflows/frontend-image.yml                    # drop paths: filter
scripts/deploy.sh                                       # DISK_FULL hard-fail; [3b/5] schema wipe; ENV_SECRET fetch+merge
deploy/docker-compose.deploy.yml                        # env_file: /opt/biomate/.env on both services
infra/terraform/envs/test/secrets_access.tf             # add lago + galaxy-env ARNs to read policy
docs/20260521_CICD_TEST_DEPLOY_VALIDATION_AND_FIXES.md  # this file
```

AWS resource changes:

```
iam::role-policy GitHubActionsDeploy/DeployViaSsm       # added ecr:DescribeImages on the two repos
iam::role-policy BioMateEc2DeployRole/test-biomate-secrets-read  # via Terraform
secretsmanager::test/biomate/galaxy-env                 # NEW: 8 keys
  BILLING_INTERNAL_KEY, LAGO_API_URL, LAGO_WEBHOOK_SECRET,
  JAVA_BILLING_SERVICE_URL, JAVA_BILLING_ENABLED,
  REDIS_URL, JWT_SECRET, DATABASE_URL
```

---

## 5. Past-incident lessons satisfied

This session validated several lessons from the rebuild plan:

- **L1** (every push rebuilds images) — now true; path filters removed.
- **L3** (no `prune -af` in production code) — preserved; ad-hoc disk cleanup used `-af` deliberately, but `deploy.sh` still uses `--filter=until=24h`.
- **L9** (no hardcoded secrets) — preserved; everything sourced from Secrets Manager. Old `35.86.137.71` Lago box config + RDS DSN both come from secrets.
- **L13** (boto3 adaptive retry) — preserved.
- **L17** (auto-rollback to previous tag) — exercised; rollback correctly skipped when there was no prior healthy tag.
- **L21** (HTTP healthcheck gates promotion) — confirmed; deploy fails closed when frontend healthcheck red.

---

## 6. What still gates "deploy.yml green end-to-end"

The Node frontend now needs its own config layer:

| Blocker | Note |
|---|---|
| `frontend/server/s3-client.ts:42-44` hard-throws when `AWS_ACCESS_KEY_ID` + `AWS_SECRET_ACCESS_KEY` are absent | This is anti-pattern on EC2 — the AWS SDK should fall back to the instance profile via IMDS. Either fix the code to use the default credential chain, or inject keys (less clean). |
| `S3_BUCKET_NAME` | Not yet in `galaxy-env`. |
| `GALAXY_URL`, `GALAXY_API_KEY` | Currently logged as "WARNING: GALAXY_URL not set" — needs `http://galaxy-backend-deploy:8080` and the matching API key. |
| `FIELD_ENCRYPTION_SECRET` | Frontend warns and uses insecure default. |
| `STRIPE_*`, `EMAIL_*`, `GEMINI_API_KEY`, `OPENAI_API_KEY` | Lazy-checked (inside method bodies). Won't block boot but will break specific endpoints. |

Per user direction: the frontend will be re-released with proper config in a future cycle. **Not in scope for this session.**

---

## 7. Demonstration state

Most recent dispatched deploy was `26265493737`. Container state at that time:

```
biomate-galaxy-deploy     Up 4 minutes (healthy)
biomate-frontend-deploy   Restarting (1) 48 seconds ago  ← see §6
```

So the deploy.yml job still ended in `failure` because the external healthcheck targets the frontend. But the CD pipeline itself + Galaxy's full boot path are proven working.

---

## 8. Recommended next steps (any session, not blocking)

1. **P4.2** branch protection on `integration/next-phase` requiring image-build + ECR-verify checks to pass.
2. **P2.4** stage env — clone `infra/terraform/envs/test` into `envs/stage` + add a `stage` GitHub Environment + extend `deploy.yml` choice list.
3. **Frontend config layer** — fix `s3-client.ts` to use the AWS SDK default credential chain; add the remaining frontend env vars to `test/biomate/galaxy-env`; rebuild frontend image.
4. SNS subscription on `biomate-deploy-events` for `xiaoni5122@gmail.com` — currently `PendingConfirmation` per the P3.1 doc.
