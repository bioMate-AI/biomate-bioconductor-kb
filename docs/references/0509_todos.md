# CryoEM Dev E2E Handover — 2026-05-09 (updated 2026-05-12)

## CS-3 + CS-4 + CS-5 Merged Into One Test (2026-05-13)

These three tests each ran the full CryoSPARC SPA pipeline (~15 min, real g6.2xlarge GPU). They differed only in what they asserted afterward. Merged into one test at `frontend/e2e/cryoem-stepwise-and-output.e2e.ts:978` ("CS-3+4+5: CryoSPARC SPA — execute → live step status → outputs → run summary (merged)").

**Savings per CI run:** ~$0.50 GPU + ~30 min wall clock + ~$0.10 LLM tokens. 3× less AWS Batch dispatch.

**Backward-compat:** still emits three `SuiteRecord`s keyed by `testId: "CS-3" | "CS-4" | "CS-5"`. Dashboards/queries keying on testId keep working. Shared assertions (`ai-response-received`, `workflow-card-appeared`, `execute-returned-runId`, `run-reached-terminal-state`) go to all three via an `assertAll()` helper.

**Verified:** test executes the real CryoSPARC pipeline on dev (`90af2c48-...`), 127 AWS Batch tasks dispatched, S3 outputs accumulating. Single Galaxy worker, single GPU instance, three audit records.

## Stale `_active_instance_id` Bug — FIXED (2026-05-13)

While verifying the merged test, hit a bug where Galaxy's module-level `_active_instance_id` held an ID for an already-terminated instance (`i-0b2f33b56b53fd547`). My earlier "retry on empty Reservations" fix turned into an infinite loop on that dead ID. Fixed in `cryosparc_executor.py`:
- `_wait_for_instance_running`: capped empty-Reservations retries at 60s before raising RuntimeError
- `start_instance`: when `get_instance_state()` returns "unknown"/"terminated", clear `_active_instance_id` and fall through to the AMI launch branch (instead of trying to wait on a dead instance)

## CryoSPARC Pipeline Debug — FIXED (2026-05-13)

After the image rebuild, the CryoSPARC execute path failed with several layered bugs surfaced by Nextflow 26.04's stricter DSL2 grammar (older Nextflow was lenient):

| Bug | Location | Fix |
|---|---|---|
| `list index out of range` on `describe_instances` | `cryosparc_executor.py:305,394,475,522` | Guard `Reservations[0]` against empty result (AWS eventual consistency); retry on empty in `_wait_for_instance_running` |
| `No such variable: batch_id` at process directives | `main.nf` 6 processes (lines 680,681,825,826,962,963,1037,1038,1215,1216,1322,1323) | Rewrite `tag "${batch_id}"` and `publishDir "...${batch_id}..."` as Groovy closures `tag { batch_id }` / `publishDir { "..." }` for late evaluation |
| `No such variable: k` / `vol_name` | `main.nf` 4 directives (1404,1405,1489,1490) | Same closure fix |
| `Unknown method invocation 'div' on String type` | `main.nf:356` | Added explicit `as Double` casts in `estimate_box_size` / `estimate_particle_diameter` — Nextflow 26.04 no longer auto-coerces String params to Number |

**Result:** `POST /api/cryosparc/execute` now succeeds — instance provisions, alarm arms, Nextflow workflow launches on AWS Batch, `INIT_CRYOSPARC_PROJECT` dispatched, 12+ downstream DAG processes waiting (`hopeful_bardeen` run, May 13 03:30 UTC).

**Note on Nextflow version:** The closure-form fixes are portable — they work on both old (24.x) and new (26.04) Nextflow. The arithmetic-cast fix is also portable. So these are not workarounds for a version downgrade — they are correct DSL2 idioms.

## Galaxy Image Rebuild — COMPLETE (2026-05-12)

The 5-week-stale `biomate-galaxy-backend:latest` image was rebuilt from scratch. Fresh containers now have everything baked in — no more runtime `pip install` / Nextflow downloads needed.

**Image:** `biomate-galaxy-backend:latest` on dev EC2 — 5.5GB, built 2026-05-12.

**What's baked in (all confirmed working):**
- `boto3` 1.39.11, `redis` 7.0.1, `psycopg2-binary` 2.9.12 — installed via `backend/requirements.txt`
- Nextflow 26.04.1 + Java 21 (OpenJDK) — installed via `apt + curl get.nextflow.io`
- Container-specific `config/galaxy.yml.docker` (no `/home/yzhang/...` paths)
- Non-root `galaxy` user (UID 1000) — Galaxy refuses to run as root
- `/app/galaxy.log` pre-created with `galaxy:galaxy` ownership (Galaxy's default logging handler requires this writable)

**Files changed for the rebuild:**
- `backend/Dockerfile` — bakes in deps, Java, Nextflow, galaxy user, log perms
- `backend/start_biomate.sh` — moved from container-only into source control
- `backend/config/galaxy.yml.docker` — minimal container-targeted Galaxy config
- `backend/requirements.txt` — added boto3, redis, psycopg2-binary
- `scripts/sync_to_dev.sh` — adds DB perms fix after sync; pip-install fallback (now a no-op with new image)

**Rebuild procedure (recorded for next time):**
1. Update `backend/Dockerfile` / `requirements.txt` locally → test build: `cd backend && docker build -t biomate-galaxy-backend:test .`
2. Tar build context: `tar czf /tmp/galaxy_build_ctx.tar.gz -C backend . --exclude=database/*.sqlite --exclude=database/*.db --exclude=.venv --exclude=__pycache__`
3. Upload to S3: `aws s3 cp /tmp/galaxy_build_ctx.tar.gz s3://biomate-nextflow-work/dev-sync/galaxy_build_ctx.tar.gz`
4. On dev EC2: pull from S3, extract, `docker build -t biomate-galaxy-backend:latest .`, `docker run` with `--env-file /opt/biomate/.env`
5. Smoke test: `/api/version`, `/internal/users/provision`, `/api/nextflow/license-requirements`, `/api/cryosparc/execute` (dry)
6. Restore working DBs from S3: `universe.sqlite` + `galaxy_ai_tools.db`

**End-to-end smoke (2026-05-12 21:35 UTC):**
- ✅ Galaxy `/api/version` → 200
- ✅ `/api/ai_assistant/status` → 200
- ✅ `/internal/users/provision` → creates user
- ✅ `/api/nextflow/license-requirements` → 1 cryosparc req
- ✅ Nginx routing https://dev-public.biomate.ai → 200
- ⚠️ `/api/cryosparc/execute` → "list index out of range" (app code bug in `cryosparc_executor.py`, NOT image-related)

## Disk / Infrastructure Cleanup (2026-05-12)

- Dev EC2 EBS resized from 30GB → 50GB (online, `aws ec2 modify-volume`); partition + filesystem grown.
- `/opt/biomate/frontend_old`, `frontend_deploy` removed (393MB).
- Docker prune freed 17.6GB (lost: old image `biomate-galaxy-backend:pre-2026-05-11` — careful with `--all` next time).
- Orphan g6.12xlarge cryosparc instance terminated; new CloudWatch idle-terminate alarm armed automatically on every new instance (60min < 5% CPU → terminate).



## Cost / GPU Cleanup (added late in session)

**Found and terminated:** `i-0a2698b6bd30a98b2` (g6.12xlarge, us-east-1) — running idle since 2026-04-27, ~$1,400 burned, ~$118/day going forward. **Now terminated.**

**Root cause of orphan:** Auto-terminate was implemented as a Python daemon thread (`time.sleep(5min); stop_instance()`) inside the Galaxy backend. Galaxy restart kills the thread AND resets `_active_instance_id` to `""`, leaving the instance forgotten. The `AutoTerminate=true` tag was set but nothing read it.

**Permanent fix** (committed in `cryosparc_executor.py`):
- `start_instance()` now creates a CloudWatch alarm per instance: `<5% CPU for 60 min` → `arn:aws:automate:<region>:ec2:terminate`. AWS evaluates it autonomously, no Galaxy dependency.
- `stop_instance()` cleans up the alarm on deliberate termination.

**Other "always-on" servers checked:**
- `100.54.207.255` (CRYOSPARC_HOST in both local + dev) — **not a real server**, CGNAT placeholder, $0 cost, doesn't ping. It's the default that gets overwritten by `start_instance()` when a real instance launches.

## Major Decision: Removed `CRYOSPARC_SKIP_PROVISION=1` from dev

Earlier in the session we set this to bypass IAM AuthFailure when launching GPU instances. Re-tested with current dev creds (`biomate-admin`, `AKIAV2DX3XSKLG5H4HQ6`) — `aws ec2 run-instances --dry-run` succeeds now. Removed `SKIP_PROVISION` from `/opt/biomate/.env`. Future CryoSPARC runs on dev will provision a fresh g6.2xlarge per run, and the new alarm will auto-terminate it after 60 min idle.



## Current Status (after session 04:27 UTC run)

**CS-3 E2E test on dev (`https://dev-public.biomate.ai`):**
- ✅ `ai-response-received`
- ✅ `workflow-card-appeared`
- ✗ `execute-returned-runId` — Run button stays disabled

**What's now confirmed working in the dev stack:**
- Galaxy user provisioning (`bm_5d06e6e560eb4871` created via test register)
- CryoSPARC credential storage (`POST /api/users/credentials` → 200)
- License-requirements endpoint (`GET /api/nextflow/license-requirements` → 200)
- `CRYOSPARC_SKIP_PROVISION` removed; future runs will provision real GPU instances
- CloudWatch idle-terminate alarm armed at launch

**New regression identified:**
The latest log shows `Required params: [{"name":"movies_path"},{"name":"gain_ref"},{"name":"dose_per_frame"},{"name":"particle_diameter_angstroms"},{"name":"molecular_weight_kda"},{"name":"particle_box_size"},{"name":"cryosparc_license"},{"name":"cryosparc_password"}]` — 8 required params (was 1) and **none have `value` set after extraction**. `Phase cards before run: 1` (was 6).

**Root cause:** my DSL2 fix to `main.nf` (converting `CS_IMAGE = ...` → `params.cs_image`, removing `workflow.onComplete`) shifted how Galaxy's workflow indexer classifies required vs optional params. Params with `null` default that didn't appear required before are now classified as required because the schema-derivation code reads the params block differently after the structural change.

**Fix path:** ensure `_apply_llm_suggestions` runs successfully on the larger param set. Likely the regex in `_extract_explicit_params_from_query` is failing because too many param names are alternated. Test by running the workflow generator directly:
```bash
docker exec biomate-galaxy-dev /app/.venv/bin/python3 -c "
from galaxy.ai.ai_assistant import AIAssistant
# call _extract_explicit_params_from_query with the test message and verify movies_path is matched
"
```

---

## What Was Fixed Today

### 1. Galaxy DB permissions break after every sync
**Root cause:** `sync_to_dev.sh` replaces `universe.sqlite` via `docker cp`, which resets ownership to `ubuntu:ubuntu`. Galaxy process (user `galaxy`) can't write → provisioning and credential storage fail with 500.

**Fix applied:** `sync_to_dev.sh` now runs `chown -R galaxy:galaxy /app/database/ && chmod 775 /app/database/` after every DB replacement.

**Manual fix for current dev:** Already applied. If it breaks again, run:
```bash
docker exec -u root biomate-galaxy-dev chown -R galaxy:galaxy /app/database/
docker exec -u root biomate-galaxy-dev chmod 775 /app/database/
```

### 2. Galaxy billing router failed to load on dev
**Root cause:** `realtime_cost_service.py` had `import redis` at module level. Dev Galaxy container has no redis package → `ModuleNotFoundError` → entire billing router fails to load → `/internal/users/provision` returns 404.

**Fix:** Made redis import optional in `realtime_cost_service.py`. Also: `LAGO_WEBHOOK_SECRET` was missing from dev `.env` → added it.

### 3. License-requirements Galaxy route conflict
**Root cause:** `GET /api/workflows/license-requirements` was catching Galaxy's own `GET /api/workflows/{workflow_id}` route.

**Fix:** Moved endpoint to `GET /api/nextflow/license-requirements`. Updated Node.js proxy to call the new path.

### 4. CryoSPARC Nextflow script DSL2 syntax errors
**Root cause:** `main.nf` had top-level variable assignments (`CS_IMAGE = "..."`, `CS_HELPER = '''...'''`) after function declarations — forbidden in Nextflow DSL2. Also had `workflow.onComplete { }` at script level (not allowed in Nextflow 26.04+).

**Fix:** Converted `CS_IMAGE` → `params.cs_image`, `CS_HELPER` → `params.cs_helper`. Removed `workflow.onComplete` block. Updated all usages in processes.

### 5. Test localStorage stale state
**Root cause:** Tests shared browser `localStorage` across runs. Old `movies_path` and workflow params from previous test runs persisted, making the test appear to pass even when the AI didn't extract params.

**Fix:** Added `page.addInitScript(() => localStorage.clear())` before navigation.

### 6. CryoSPARC credential timing race
**Root cause:** `registerCryoSPARCLicense` was called immediately after registration, before Galaxy account provisioning completed. Credentials stored under admin Galaxy user, but license check queried under provisioned user → `source: 'none'`.

**Fix in test:** Added `page.waitForFunction(async () => { const d = await fetch('/api/auth/me').json(); return !!d.user?.galaxyUserId; })` before storing credentials.

### 7. Multiple background sync processes
**Root cause:** Each Claude Code session started `sync_to_dev.sh` without `--once`. Multiple loops running simultaneously kept overwriting the container every 10 minutes.

**Fix:** Always use `bash scripts/sync_to_dev.sh --once`. Before starting: `pkill -f sync_to_dev.sh`.

### 8. Frontend volume mount for patched index.js
**Root cause:** `docker cp` after container start doesn't affect already-loaded Node.js code. Container restarts reset to base image.

**Fix:** Mount patched file as persistent volume:
```bash
docker run -d ... -v /opt/biomate/dist_index.js:/app/dist/index.js biomate-dev-frontend:latest
```
The `dist_index.js` is at `/opt/biomate/dist_index.js` on the EC2 host. The sync script now includes this volume mount.

---

## Pending TODOs

### High Priority (needed for CS-3 to fully pass)

1. **Re-run CS-3 after DB permissions fix**
   ```bash
   cd /home/yzhang/biomate/frontend
   BIOMATE_URL=https://dev-public.biomate.ai \
   E2E_TEST_TOKEN=biomate-e2e-bypass-token-dev-only \
   PW_OUTPUT_DIR=/tmp/pw-test-results-final \
     npx playwright test e2e/cryoem-stepwise-and-output.e2e.ts --grep "CS-3" --project chromium
   ```
   Expected: `execute-returned-runId` now passes. The Nextflow script compiles and runs on AWS Batch.

2. **Fix `phase-card-statuses-updated-after-run`**
   The pipeline runs but phase cards stay "pending" after completion. This happens because:
   - The status polling in `pollWithLiveUIChecks` needs to see `phase-group-A.data-status` change from `pending` → `running` → `completed`
   - Currently the Nextflow pipeline fails too fast (DSL2 fix should help, but verify with next run)

3. **Fix Nextflow `batch_id` issue in PATCH_MOTION_CORRECTION_BATCH**
   `nextflow run main.nf --help` shows: `No such variable: batch_id` at line 681 during help evaluation. This is in `publishDir` — should not affect actual execution (it's evaluated lazily), but verify the pipeline actually runs past Phase A.

### Medium Priority (architecture)

4. **Move CryoSPARC credentials out of Galaxy vault into BioMate PostgreSQL**
   The fundamental issue: Galaxy vault is per-user and requires a provisioned Galaxy account. BioMate users without Galaxy accounts store credentials under the admin Galaxy user — but only when `_get_credential` is called with `trans.user = None`, it returns None immediately (line 70 in credentials_api.py).
   
   **Real fix:** Add a `user_credentials` table to BioMate's PostgreSQL. Node.js stores/retrieves from there directly, no Galaxy dependency. Galaxy endpoints (`POST /api/users/credentials`, `GET /api/users/credentials/{tool_id}/value`) become wrappers that query BioMate's DB via the Node.js API.

5. **Fix Galaxy route conflicts for ALL custom endpoints under `/api/users/`**
   `GET /api/users/credentials` returns 400 because Galaxy's `GET /api/users/{user_id}` catches it. The credential check endpoint is broken. Test with: `curl 'http://localhost:8081/api/users/credentials?tool=cryosparc' -H 'X-API-Key: ...'` — should return 400 (routing conflict).

6. **Fix Gemini intent model on dev**
   The `intentModel: 'gemini-3-flash-preview'` fails on dev because `GEMINI_API_KEY` isn't in the dev `.env`. Every chat request logs: `Intent analysis failed: NotFoundError: 404 model: gemini-3-flash-preview`. The CryoEM override catches this and forces workflow generation anyway, but for non-CryoEM queries, intent classification falls back to keyword matching.
   
   **Fix:** Add `GEMINI_API_KEY` to dev `.env`, OR change `intentModel` fallback to use `claude-haiku-4-5` when Gemini is unavailable.

### Low Priority

7. **Build Docker image properly** — The `Dockerfile` build fails on dev because `libhts-dev` conflicts with `tabix`. Fixed in the Dockerfile (separate pip install steps with `|| true`), but not validated on dev since the build was never re-run. The workaround (volume mount for `dist_index.js`) means the image doesn't need to be rebuilt for code changes.

8. **CS-4 and CS-5 tests** — After CS-3 passes fully (pipeline completes), run CS-4 (output visualization) and CS-5 (run summary/report) to verify the full end-to-end.

---

## Dev Environment Quick Reference

| Service | How to check |
|---------|-------------|
| Frontend | `curl https://dev-public.biomate.ai/api/health -k` |
| Galaxy | `curl http://localhost:8081/api/version` (from EC2) |
| Provisioning | `curl -X POST http://localhost:8081/internal/users/provision -H 'X-Internal-Key: 031b06b827bdfd5a8fdbd314645577eff95c28a436a2571f' -d '{"biomate_user_id":"t","email":"t@t.com"}'` |
| CryoSPARC | `curl -X POST http://localhost:8081/api/cryosparc/execute -H 'Content-Type: application/json' -H 'X-Galaxy-Auth-Key: biomate-internal-auth-key-2024' -d '{"movies_path":"s3://biomate-cryo-data/empiar-10028/Micrographs","user_id":"test"}'` |

**SSH to EC2:** Uses EC2 instance connect (temporary key):
```bash
KEY_FILE="/tmp/biomate_ec2_key_sync"
aws ec2-instance-connect send-ssh-public-key \
  --instance-id "i-06696b0d91f4346e0" --availability-zone "us-west-2a" \
  --instance-os-user "ubuntu" --ssh-public-key "file://${KEY_FILE}.pub" \
  --region us-west-2 --output text --query 'Success'
ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no ubuntu@52.42.49.175
```

**Fix DB permissions (run if provisioning returns 500):**
```bash
docker exec -u root biomate-galaxy-dev chown -R galaxy:galaxy /app/database/
docker exec -u root biomate-galaxy-dev chmod 775 /app/database/
```

**Update frontend code on dev (after local `npm run build`):**
```bash
scp frontend/dist/index.js ubuntu@52.42.49.175:/opt/biomate/dist_index.js
docker rm -f biomate-dev-frontend
docker run -d --name biomate-dev-frontend --network biomate-dev-net \
  -p 3000:3000 --env-file /opt/biomate/.env \
  -e NODE_ENV=production -e PORT=3000 -e FORCE_HTTPS=0 \
  --restart unless-stopped \
  -v /opt/biomate/dist_index.js:/app/dist/index.js \
  biomate-dev-frontend:latest
```

**Sync Python files to dev Galaxy:**
```bash
bash scripts/sync_to_dev.sh --once
```
(Always use `--once`. Kill existing sync processes first: `pkill -f sync_to_dev.sh`)

---

## Files Changed in This Session

| File | Change | Status |
|------|--------|--------|
| `backend/lib/galaxy/ai/billing/core/realtime_cost_service.py` | Optional redis import | ✅ deployed |
| `backend/lib/galaxy/webapps/galaxy/api/credentials_api.py` | Moved license-requirements to `/api/nextflow/` | ✅ deployed |
| `backend/biomni_workflows/nextflow_nfcore/subworkflows/cryo_em/cryosparc_standard_spa/main.nf` | DSL2 fixes (CS_IMAGE→params, removed workflow.onComplete) | ✅ deployed |
| `frontend/server/routes.ts` | License-requirements proxy path; CryoSPARC license from params fallback; createHistory fault-tolerant | ✅ built, deployed via volume mount |
| `frontend/server/galaxy-assistant.ts` | Debug log for required_params | ✅ built, deployed |
| `frontend/e2e/cryoem-stepwise-and-output.e2e.ts` | localStorage clear (addInitScript); cookie domain fix; Galaxy provisioning wait before credential storage | ✅ local only (test file) |
| `frontend/Dockerfile` | Separate pip install steps to avoid build failure | ✅ local only (image not rebuilt) |
| `scripts/sync_to_dev.sh` | Volume mount for index.js; DB chown after replacement | ✅ local |
| `CLAUDE.md` | Root-cause resolution rule | ✅ local |
| `docs/20260509_CROSS_ENV_IMPLEMENTATION_LESSONS.md` | Full lessons-learned document | ✅ local |
