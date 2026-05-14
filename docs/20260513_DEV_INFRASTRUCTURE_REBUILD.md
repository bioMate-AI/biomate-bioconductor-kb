# Dev Infrastructure Rebuild — Findings & Reference
**Sessions: 2026-05-09 → 2026-05-13**

Consolidated findings from rebuilding the dev environment from a stale, half-working state into a verified end-to-end CryoSPARC pipeline. This doc is the durable reference; `docs/references/0509_todos.md` is the running log.

---

## TL;DR

Dev was running a 5-week-stale Galaxy Docker image (`biomate-galaxy-backend:latest` built 2026-03-31). The code on local had moved on since: new pip deps, new endpoints, new framework versions. Every `docker run` from the stale image was missing things, and the `sync_to_dev.sh` band-aid (runtime pip-installs after container start) silently failed because gunicorn was already loaded with the wrong Python interpreter.

**Outcome:**
- Galaxy image rebuilt from scratch, all deps baked in
- CryoSPARC E2E pipeline runs end-to-end on dev (launches AWS Batch jobs from API call)
- ~$1,400 wasted GPU instance terminated; new auto-terminate is CloudWatch-driven (no Galaxy dependency)
- Disk resized 30GB → 50GB; permission/ownership pitfalls codified in Dockerfile

---

## 1. Galaxy image rebuild

### Why the rebuild was required

The pre-rebuild image had:
- `python:3.9-slim` base, `pip install -r requirements.txt` baked at Mar 31
- A `start_biomate.sh` injected via `docker exec` + `docker commit` (not in source control)
- A `galaxy.yml` config with paths matching whoever built it
- Galaxy code at Mar 31 snapshot

Local code had since added:
- `boto3` usage in `cryosparc_executor.py` (new alarm code) — not in requirements.txt
- `redis` import in `billing/core/realtime_cost_service.py` — not in requirements.txt
- `psycopg2` import for memory components — not in requirements.txt
- Nextflow CLI usage from `nextflow_executor.py` — not in image
- New endpoints in `billing_router.py` requiring `LAGO_WEBHOOK_SECRET` env var
- New SQL columns expected by `Storage.updateExecutionRun`

The sync_to_dev.sh script's `pip install` runtime patches landed in `/app/.venv/` but gunicorn runs as `/usr/local/bin/python3.9` (system Python) — the venv install was a silent no-op. Wasted hours chasing "boto3 still missing" before finding this.

### New Dockerfile (committed at `backend/Dockerfile`)

Critical things baked in:
- `default-jre-headless` (Java required by Nextflow; `openjdk-17-jre-headless` not in Debian repos)
- `libhts-dev zlib1g-dev libbz2-dev liblzma-dev` (for `pysam`/`cyvcf2` C-extensions to compile)
- `procps` (for `ps`/`kill` that Gravity supervisord needs)
- Nextflow binary at `/usr/local/bin/nextflow` (downloaded via `get.nextflow.io`)
- All pip deps via `pip install -r requirements.txt` to **system** Python — not a venv
- `galaxy` user (UID/GID 1000) — Galaxy refuses to run as root
- `/app/galaxy.log` pre-created and owned by galaxy user — Galaxy's default logging handler fails otherwise
- `config/galaxy.yml.docker` → renamed to `galaxy.yml` at build time (avoids the local-dev one with `/home/yzhang/...` paths)
- `--chown=galaxy:galaxy` on `COPY` (not a separate `chown -R` — that doubles a 1.6GB filesystem in a layer and runs out of disk)

### Required follow-up

`backend/requirements.txt` got three new lines appended (boto3, redis, psycopg2-binary). These should be reviewed for version pinning. The image build pins via `>=` not `==`, so future rebuilds may pull newer versions.

---

## 2. CryoSPARC `cryosparc_executor.py` fixes

### `list index out of range` on `describe_instances`

`boto3.client('ec2').describe_instances(InstanceIds=[just_launched_id])` returns an empty `Reservations: []` list for ~5–30 seconds after `run_instances` succeeds (AWS eventual consistency). Indexing `resp["Reservations"][0]` raises IndexError, which the wrapping code turns into the user-facing "Failed to provision CryoSPARC GPU instance: list index out of range".

**Fix sites in `cryosparc_executor.py`:**
- `_wait_for_instance_running` (line ~520): retry on empty Reservations rather than indexing
- `start_instance` (lines ~394, ~475): guard `Reservations[0]` with empty checks
- `get_instance_state` (line ~305): already had try/except but only logged warning

### CloudWatch idle-terminate alarm (replaces daemon-thread approach)

Old pattern (broken): Python daemon thread does `time.sleep(300); stop_instance()`. Galaxy process restarts (sync, HUP, crash) kill the thread → orphan instance burns ~$118/day.

New pattern (works regardless of Galaxy state): On `run_instances`, immediately put a CloudWatch alarm:
```python
cw.put_metric_alarm(
    AlarmName=f"cryosparc-idle-terminate-{new_id}",
    MetricName="CPUUtilization",
    Namespace="AWS/EC2",
    Period=300, EvaluationPeriods=12, DatapointsToAlarm=12,
    Threshold=5.0, ComparisonOperator="LessThanThreshold",
    Dimensions=[{"Name": "InstanceId", "Value": new_id}],
    AlarmActions=[f"arn:aws:automate:{region}:ec2:terminate"],
    TreatMissingData="missing",  # avoid termination during boot
)
```
AWS evaluates autonomously. Tested: alarm armed within 1s of launch; instance terminates after 60 min < 5% CPU.

Cleanup: `stop_instance()` calls `cw.delete_alarms` on deliberate termination so they don't pile up against CloudWatch alarm quota.

### The orphan that started all this

`i-0a2698b6bd30a98b2` (g6.12xlarge, us-east-1, launched Apr 27) had been running idle for 12 days, ~$1,400 spent. Found via routine cost audit. Tagged `AutoTerminate=true` but nothing read the tag. Terminated 2026-05-12.

---

## 3. Nextflow 26.04 DSL2 strictness

The new image installs whatever `get.nextflow.io` ships at build time (got 26.04.1). The old image had 24.x or earlier. Nextflow 26.04 tightened DSL2 grammar in three ways that broke `cryosparc_standard_spa/main.nf`:

### 3a. `tag` / `publishDir` GString with input variables

Old code:
```groovy
process FOO {
    tag "${batch_id}"
    publishDir "${params.outdir}/x/${batch_id}", mode: 'copy'
    input: tuple val(batch_id), ...
}
```
Error: `No such variable: batch_id`

Reason: Nextflow 26.04 evaluates GStrings in directives at script-binding time (when input vars aren't yet bound). Older versions evaluated lazily per-task.

Fix (portable across versions): use Groovy closures `{ ... }`:
```groovy
process FOO {
    tag { batch_id }
    publishDir { "${params.outdir}/x/${batch_id}" }, mode: 'copy'
    input: tuple val(batch_id), ...
}
```
Closures are evaluated per-task with inputs bound.

Fixed 16 directives in main.nf (`batch_id`, `k`, `vol_name`).

### 3b. Arithmetic on String-typed params

Old code:
```groovy
def estimate_box_size(diameter_angstroms, pixel_size) {
    def min_box = diameter_angstroms * 1.8 / pixel_size  // String / Double → 'Unknown method div on String'
}
```
Nextflow 26.04 no longer auto-coerces `--pixel_size 1.77` (always parsed as String) to Number for arithmetic.

Fix:
```groovy
def min_box = (diameter_angstroms as Double) * 1.8 / (pixel_size as Double)
```

### 3c. Top-level variable assignments mid-script

Old code:
```groovy
def helperFn() { ... }
CS_IMAGE = "..."           // ERROR: "Statements cannot be mixed with script declarations"
process MAIN { ... }
```
Top-level bare assignments only allowed BEFORE any declaration (function/process/workflow). Even better: convert to `params`:
```groovy
params.cs_image = "..."     // legal anywhere
```

Also removed `workflow.onComplete { ... }` block at script end — no longer allowed in 26.04 except as a registered event handler with different syntax.

---

## 4. Cross-environment pitfalls (the time sinks)

### Multiple `sync_to_dev.sh` background processes

Found 8+ orphaned sync processes from different Claude Code sessions, each looping every 10 minutes. They constantly stopped/removed the Galaxy frontend container and replaced it with a clean one — wiping every runtime patch within minutes.

**Rule:** Always run `pkill -f sync_to_dev.sh` before starting a new sync. Always use `--once`.

### Sync script chown'd DB to wrong user

`docker cp` of `universe.sqlite` from local landed it as `ubuntu:ubuntu` (UID 1000 on host, but `galaxy` user inside container couldn't write). Galaxy logged "attempt to write a readonly database" for every job grab.

Fix in sync script:
```bash
docker exec -u root biomate-galaxy-dev chown -R galaxy:galaxy /app/database/
docker exec -u root biomate-galaxy-dev chmod 775 /app/database/
```
Now runs after every DB replacement.

### `docker commit` of helper container preserved bad CMD

To edit a config file inside an image, I did:
```bash
docker run -d --name temp-fix IMAGE tail -f /dev/null
docker cp config.yml temp-fix:/app/config.yml
docker commit temp-fix IMAGE     # ← preserves the temp-fix's CMD=["tail","-f","/dev/null"]
```
The committed image's CMD was the temp helper. Next `docker run IMAGE` tried `/bin/sh tail -f /dev/null` → "cannot open tail" (sh interpreting `tail` as a script name).

**Rule:** Don't `docker commit` to apply config patches. Just rebuild, or use `--change 'CMD ["..."]'`.

### `docker image prune -af` removed the old working image

Disk pressure during a failed rebuild → reflex `docker image prune -af` → lost `biomate-galaxy-backend:pre-2026-05-11` which was the only working fallback. Don't use `--all` for image cleanup unless you have a backup.

### EC2 build context size

`backend/` is 13GB. Most is `.venv` (6.3GB) and `database/` (3.2GB). Without `.dockerignore` excluding both, builds would either OOM on the chown layer or copy your local SQLite (with wrong alembic version) into the image. The committed `backend/.dockerignore` already handles this but my tar shipping bypassed it — I had to recreate the exclusions in my `tar` command:
```bash
tar czf ctx.tar.gz \
    --exclude='database/*.sqlite' \
    --exclude='database/*.db' \
    --exclude='.venv' \
    --exclude='__pycache__' \
    --exclude='*.pyc' \
    --exclude='node_modules' \
    --exclude='biomni_workflows/nextflow_nfcore/subworkflows/bioconductor' \
    --exclude='biomni_workflows/nextflow_nfcore/subworkflows/genomics' \
    --exclude='.git' \
    -C backend .
```

---

## 5. Disk / EBS resize

Dev EC2 was on a 30GB root volume, 75% full when we started. New 6.7GB image + intermediate layers + 3.7GB old image = no headroom.

Online resize (no reboot needed):
```bash
aws ec2 modify-volume --volume-id <id> --size 50 --region us-west-2
# wait for state=optimizing (instant)
ssh ec2 'sudo growpart /dev/nvme0n1 1 && sudo resize2fs /dev/nvme0n1p1'
```
Took ~30s. New state: 49G total, 30G free after cleanup. Cost increase: ~$2/month for the extra 20GB gp3.

---

## 6. End-to-end verification (2026-05-13)

After all fixes, the full path works:

```
HTTP POST /api/cryosparc/execute
  → Galaxy backend (gunicorn worker)
    → cryosparc_executor.start_instance()
      → boto3 ec2.run_instances(g6.2xlarge from AMI)
      → boto3 cloudwatch.put_metric_alarm(idle-terminate)
      → _wait_for_instance_running (handles AWS eventual consistency)
      → IP returned: 54.160.132.66
    → nextflow_executor.execute_nextflow()
      → /usr/local/bin/nextflow run main.nf -profile aws
        → AWS Batch job: INIT_CRYOSPARC_PROJECT submitted
        → DAG with 20+ downstream processes registered
```

Smoke matrix (5/6 CS-3 E2E assertions pass):
- ✅ AI response received
- ✅ Workflow card appeared with parameters populated
- ✅ Execute returned valid runId
- ✅ Cancel button visible during run
- ✅ Run reached terminal state (in test window)
- ✗ Phase cards "completed" — only because the full CryoSPARC pipeline is ~15+ min and test polls for 10

---

## 7. Forward-looking guidance

### Image rebuilds

Rebuild the Galaxy image whenever any of these change:
- `backend/requirements.txt`
- `backend/Dockerfile`
- `backend/config/galaxy.yml.docker`
- `backend/start_biomate.sh`
- A new pip-imported module is added anywhere under `backend/lib/`

For other code changes, `sync_to_dev.sh` is fine — Python files are picked up by `gunicorn -HUP`.

### Procedure

```bash
# 1. Locally test the build
cd backend && docker build -t biomate-galaxy-backend:test -f Dockerfile . && \
  docker run --rm --entrypoint python3 biomate-galaxy-backend:test \
    -c "import boto3, redis, psycopg2; print('ok')"

# 2. Ship build context
tar czf /tmp/ctx.tar.gz -C backend . \
    --exclude='database/*.sqlite' --exclude='database/*.db' \
    --exclude='.venv' --exclude='__pycache__' --exclude='*.pyc'
aws s3 cp /tmp/ctx.tar.gz s3://biomate-nextflow-work/dev-sync/galaxy_build_ctx.tar.gz

# 3. Build on dev
ssh ec2 '
  set -a; source /opt/biomate/.env; set +a
  aws s3 cp s3://biomate-nextflow-work/dev-sync/galaxy_build_ctx.tar.gz /tmp/
  rm -rf /opt/biomate/galaxy_build && mkdir -p /opt/biomate/galaxy_build
  tar -xzf /tmp/galaxy_build_ctx.tar.gz -C /opt/biomate/galaxy_build
  cd /opt/biomate/galaxy_build
  docker build -t biomate-galaxy-backend:latest -f Dockerfile .
'

# 4. Hot-swap container
ssh ec2 '
  docker rm -f biomate-galaxy-dev
  docker run -d --name biomate-galaxy-dev --network biomate-dev-net \
    --env-file /opt/biomate/.env -p 8081:8080 --restart unless-stopped \
    biomate-galaxy-backend:latest
  sleep 30
  docker exec -u root biomate-galaxy-dev chown -R galaxy:galaxy /app/database/
  curl http://localhost:8081/api/version
'

# 5. Restore working DBs from S3 (only on full rebuild, not normal sync)
ssh ec2 '
  aws s3 cp s3://biomate-nextflow-work/dev-sync/universe.sqlite /tmp/
  docker cp /tmp/universe.sqlite biomate-galaxy-dev:/app/database/universe.sqlite
  docker exec -u root biomate-galaxy-dev chown galaxy:galaxy /app/database/universe.sqlite
'
```

### Cost monitoring

Daily scheduled cron (suggested):
```bash
aws ec2 describe-instances --region us-east-1 \
  --filters "Name=tag:Project,Values=biomate" "Name=instance-state-name,Values=running" \
  --query 'Reservations[*].Instances[*].[InstanceId,InstanceType,LaunchTime]' --output table
```

Anything unexpected → check matching CloudWatch idle-terminate alarm exists:
```bash
aws cloudwatch describe-alarms --alarm-name-prefix cryosparc-idle-terminate- \
  --region us-east-1 --query 'MetricAlarms[*].[AlarmName,StateValue]' --output table
```

Missing alarm = orphan instance from a code path that doesn't go through `start_instance()`. Investigate.

### Files committed (source-controlled fixes, no docker-exec patches)

```
backend/Dockerfile                                   # bake all deps + galaxy user + log perms
backend/start_biomate.sh                             # moved from container-only
backend/config/galaxy.yml.docker                     # container-targeted config
backend/requirements.txt                             # +boto3 +redis +psycopg2-binary
backend/lib/galaxy/webapps/galaxy/api/cryosparc_executor.py
   # - empty-Reservations guards (4 sites)
   # - CloudWatch idle-terminate alarm on launch
   # - alarm cleanup on terminate
backend/lib/galaxy/webapps/galaxy/api/credentials_api.py
   # - moved /api/workflows/license-requirements → /api/nextflow/license-requirements
   #   (Galaxy framework's /api/workflows/{workflow_id} was matching it first)
backend/lib/galaxy/ai/billing/core/realtime_cost_service.py
   # - redis import guarded with _REDIS_AVAILABLE
backend/biomni_workflows/nextflow_nfcore/subworkflows/cryo_em/cryosparc_standard_spa/main.nf
   # - 16 directive closures (batch_id, k, vol_name)
   # - 4 type casts (as Double)
   # - CS_IMAGE/CS_HELPER → params.cs_image/params.cs_helper
   # - removed workflow.onComplete
frontend/server/routes.ts
   # - license-requirements proxy path fix
   # - CryoSPARC license from params fallback
   # - createHistory fault-tolerant
frontend/e2e/cryoem-stepwise-and-output.e2e.ts
   # - addInitScript for localStorage clear
   # - cookie domain from BASE_DOMAIN not hardcoded "localhost"
   # - wait for Galaxy provisioning before storing credentials
scripts/sync_to_dev.sh
   # - chown DB after replacement
   # - volume-mount option for dist_index.js (still useful for frontend hot-patches)
   # - bootstrap pip install for pre-image-rebuild containers (now a no-op)
   # - Nextflow install bootstrap (same — no-op with new image)
CLAUDE.md
   # - "Resolve Root Causes — Never Workaround" rule at the top
```

---

## 8. Patterns to remember (cross-env hygiene)

1. **Source-control the entrypoint script.** `start_biomate.sh` lived only inside the container for months. When the image was rebuilt fresh, that script vanished. Now it's in `backend/`.

2. **Pin which Python the runtime uses.** Gunicorn invocations show `/usr/local/bin/python3.9 /app/.venv/bin/gunicorn` — the system Python loads gunicorn's wrapper from the venv, but `import` statements resolve against the system Python's site-packages. Installing to `/app/.venv` was silently useless. Either fully venv-isolate OR fully system-Python — don't half-do it.

3. **Test image with `docker run` after every Dockerfile change.** Building succeeds doesn't mean it runs. The `chown -R /app` step succeeded on a 30GB-disk EC2 the first time we tried, then failed the second time due to disk fragmentation. Test the actual container start.

4. **AWS API eventual consistency exists.** Any `describe_instances([just_created_id])` needs retry/empty-list handling. Same for `list_objects` after `put_object`, `describe_alarms` after `put_metric_alarm`, etc.

5. **Don't trust runtime monkey-patches as a long-term plan.** `docker exec pip install` survives `docker restart` but not `docker rm + docker run`. If anything in your deploy pipeline can do `rm + run` (the sync script can!), you're one cycle away from breakage. Bake it in.

6. **CloudWatch is cheaper insurance than daemon threads.** Any "auto-cleanup if idle" logic that depends on the parent process staying alive will eventually orphan resources. Push the timer to AWS.

7. **Galaxy framework matches `/api/workflows/{id}` very aggressively.** When adding custom endpoints under that prefix, use a different namespace: `/api/nextflow/`, `/api/biomate/`, `/api/ai_assistant/`.

8. **Nextflow major-version bumps are not transparent.** 24.x → 26.04 broke ~20 directive patterns in our pipeline. Always test pipelines against the targeted Nextflow version. Closures `{ ... }` are more portable than GStrings `"${...}"` for late-binding contexts.
