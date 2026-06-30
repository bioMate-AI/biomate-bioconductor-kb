#!/bin/bash
# sync_to_dev.sh — MANUAL one-shot sync of ALL layers to dev-public.biomate.ai:
#   1. Frontend (React/Express) — Docker rebuild + restart
#   2. Backend Python files    — docker cp into running Galaxy container + restart
#   3. Galaxy databases        — galaxy_ai_tools.db (workflow search), universe.sqlite
#   4. Nextflow workflow files — .nf files in biomni_workflows/
#
# NOTE: Marketing website (webpage_design_v2/) is NOT synced here.
#       Use scripts/deploy_marketing.sh instead.
#
# Usage: bash scripts/sync_to_dev.sh
#
# As of 2026-05-15 this script is MANUAL-ONLY.
#   - The 10-minute auto-poll loop has been removed (caused orphan-process conflicts).
#   - The auto-commit-before-sync behavior has been removed (bypassed code review).
# Commit your work yourself, then run this script manually. It performs ONE sync
# pass and exits.
#
# This script is the supported fallback until the GitHub Actions CD pipeline is
# proven (see docs/20260514_CICD_REBUILD_PLAN.md). DO NOT re-introduce the polling
# loop or auto-commit — those are tracked as past-incident hard requirements.
#
# Prerequisites: AWS CLI configured with ec2-instance-connect permissions

set -euo pipefail

INSTANCE_ID="i-06696b0d91f4346e0"
AZ="us-west-2a"
EC2_USER="ubuntu"
EC2_HOST="52.42.49.175"
KEY_FILE="/tmp/biomate_ec2_key_sync"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Guard against accidentally running multiple syncs at once (per Lessons L7).
LOCK_FILE="/tmp/biomate_sync_to_dev.lock"
if [[ -e "$LOCK_FILE" ]] && kill -0 "$(cat "$LOCK_FILE" 2>/dev/null)" 2>/dev/null; then
  echo "ERROR: another sync_to_dev.sh is already running (pid $(cat "$LOCK_FILE"))." >&2
  echo "If you are sure no real sync is in progress: rm $LOCK_FILE" >&2
  exit 1
fi
echo $$ > "$LOCK_FILE"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

# --- Deploy notification (SNS) + consolidated cleanup -----------------------
# Previously the only EXIT trap removed the lock file — and resync_galaxy_env
# later REPLACED it with a LIVE_ENV cleanup (trap ... EXIT clobbers), silently
# dropping lock removal. Consolidate both into one handler and add an SNS
# notification so a failed dev sync is no longer silent.
#
# ROLLBACK: dev sync is in-place file hot-patch + gunicorn HUP, not an image-tag
# swap. The Galaxy container has NO mounts (verified), so `docker commit` BEFORE
# the sync captures all hot-patched code/db/workflows/config in one image; the
# frontend keeps its own image tags. A post-sync health gate (snapshot_for_rollback
# / postsync_health_ok / rollback_sync below) recreates both containers from those
# snapshots if dev is unhealthy after the sync.
AWS_REGION="${AWS_REGION:-us-west-2}"
SNS_TOPIC_ARN="${SNS_TOPIC_ARN:-arn:aws:sns:$AWS_REGION:399683337364:biomate-deploy-events}"
CLEANUP_FILES=""        # space-separated temp files to rm on exit (append, don't re-trap)
SYNC_STARTED=0          # set to 1 once we enter do_sync; gates the notification
CURRENT_COMMIT=""       # populated at the entry point; referenced by notify_sync
SYNC_RESULT=""          # healthy|rolled_back|rollback_failed|failed — set by do_sync, read by notify_sync
ROLLBACK_READY=0        # 1 once the pre-sync snapshot is taken
RB_SNAPSHOT_FRONTEND=0  # 1 if the frontend image was snapshotted this run
RB_GALAXY_IMAGE="biomate-galaxy-dev:rollback"   # snapshot tag (overwritten each run)

notify_sync() {
  local rc="$1" state subject note
  case "${SYNC_RESULT:-}" in
    healthy)         state="ok" ;;
    rolled_back)     state="ROLLED BACK" ;;
    rollback_failed) state="ROLLBACK FAILED" ;;
    "")              [[ "$rc" -eq 0 ]] && state="ok" || state="FAILED" ;;
    *)               state="FAILED" ;;
  esac
  case "$state" in
    "ROLLED BACK")     note="Sync failed health gate; dev auto-rolled back to the pre-sync snapshot and is healthy. Investigate the bad commit before re-syncing." ;;
    "ROLLBACK FAILED") note="Sync failed health gate AND rollback failed — dev may be DOWN. Manual intervention required." ;;
    "ok")              note="Dev healthy after sync." ;;
    *)                 note="Sync failed; inspect dev and re-sync a known-good commit." ;;
  esac
  subject="[dev-sync $state] dev -> ${CURRENT_COMMIT:0:8}"
  if aws sns publish --region "$AWS_REGION" --topic-arn "$SNS_TOPIC_ARN" \
       --subject "${subject:0:99}" \
       --message "BioMate dev sync: $state
Target:   https://dev-public.biomate.ai
Commit:   ${CURRENT_COMMIT:-unknown}
Instance: $INSTANCE_ID
Exit:     $rc
$note" \
       >/dev/null 2>&1; then
    log "[notify] SNS sent ($state) -> $SNS_TOPIC_ARN"
  else
    log "::warning:: [notify] SNS publish failed ($state) — check sns:Publish on local creds + a confirmed topic subscription"
  fi
}

on_exit() {
  local rc=$?
  rm -f "$LOCK_FILE" $CLEANUP_FILES 2>/dev/null || true
  [[ "$SYNC_STARTED" -eq 1 ]] && notify_sync "$rc"
  return 0
}
trap on_exit EXIT

# ---------------------------------------------------------------------------
# SSH helpers
# ---------------------------------------------------------------------------

inject_key() {
  [[ -f "${KEY_FILE}" ]] || ssh-keygen -t ed25519 -f "$KEY_FILE" -N "" -q
  aws ec2-instance-connect send-ssh-public-key \
    --instance-id "$INSTANCE_ID" --availability-zone "$AZ" \
    --instance-os-user "$EC2_USER" \
    --ssh-public-key "file://${KEY_FILE}.pub" \
    --region us-west-2 --output text --query 'Success' 2>/dev/null
}

ec2_ssh() {
  inject_key > /dev/null
  ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no -o ConnectTimeout=15 \
    "${EC2_USER}@${EC2_HOST}" "$@"
}

ec2_scp() {
  inject_key > /dev/null
  scp -i "$KEY_FILE" -o StrictHostKeyChecking=no "$@"
}

# ---------------------------------------------------------------------------
# Layer 1: Frontend (full Docker rebuild)
# ---------------------------------------------------------------------------

apply_postgres_migrations() {
  # Apply any new frontend/migrations/*.sql to biomate-dev-postgres.
  # Idempotent (each migration uses IF NOT EXISTS / IF EXISTS).
  # Runs BEFORE frontend deploy so schema is ready when the new bundle starts.
  log "[pg] Applying frontend/migrations/*.sql to biomate-dev-postgres..."
  local migrations_dir="$REPO_ROOT/frontend/migrations"
  if [[ ! -d "$migrations_dir" ]]; then
    log "[pg] No migrations dir at $migrations_dir — skipping"
    return 0
  fi
  local tar_file=/tmp/biomate_pg_migrations.tar.gz
  tar -czf "$tar_file" -C "$REPO_ROOT" frontend/migrations 2>/dev/null
  ec2_scp "$tar_file" "${EC2_USER}@${EC2_HOST}:/tmp/pg_migrations.tar.gz"
  ec2_ssh '
    set -e
    rm -rf /tmp/pg_migrations && mkdir -p /tmp/pg_migrations
    tar -xzf /tmp/pg_migrations.tar.gz -C /tmp/pg_migrations
    docker cp /tmp/pg_migrations/frontend/migrations biomate-dev-postgres:/tmp/migrations
    docker exec biomate-dev-postgres bash -c "
      set -e
      cd /tmp/migrations
      for f in \$(ls *.sql | sort); do
        echo \"[pg] applying \$f\"
        psql -U biomate -d biomate -v ON_ERROR_STOP=1 -f \$f >/dev/null
      done
    " 2>&1 | tail -20
  '
  log "[pg] Migrations applied"
}

deploy_frontend() {
  log "[frontend] Building archive..."
  local tar_file="/tmp/biomate_frontend_sync.tar.gz"
  tar -czf "$tar_file" \
    --exclude='frontend/data/uploads' \
    --exclude='frontend/e2e/screenshots' \
    --exclude='frontend/e2e/reports' \
    --exclude='frontend/node_modules' \
    -C "$REPO_ROOT" \
    frontend/client/ frontend/server/ frontend/shared/ frontend/attached_assets/ \
    frontend/migrations/ \
    frontend/package.json frontend/package-lock.json \
    frontend/tsconfig.json frontend/tsconfig.node.json frontend/vite.config.ts \
    frontend/tailwind.config.js frontend/postcss.config.js \
    frontend/Dockerfile frontend/Dockerfile.biotools 2>/dev/null
  log "[frontend] Archive: $(du -sh $tar_file | cut -f1)"

  ec2_scp "$tar_file" "${EC2_USER}@${EC2_HOST}:/tmp/frontend_sync.tar.gz"

  ec2_ssh '
    set -e
    rm -rf /opt/biomate/frontend_sync && mkdir -p /opt/biomate/frontend_sync
    tar -xzf /tmp/frontend_sync.tar.gz -C /opt/biomate/frontend_sync
    # Prune dangling images + build cache to prevent disk-full build failures
    docker image prune -f > /dev/null 2>&1 || true
    docker builder prune -f > /dev/null 2>&1 || true

    # ── Atomic swap pattern (no downtime) ────────────────────────────────
    # OLD pattern (caused dev-public outages 2026-05-18):
    #   docker stop && docker rm OLD → build new → docker run new
    #   ↳ Multi-minute 502 window while building. If build fails, the
    #     `keeping previous container running` branch did NOT restore
    #     reliably because the original image tag was overwritten.
    #
    # NEW pattern: build to a `:next` tag, only swap containers AFTER
    # the build succeeds. Failure path leaves the running container
    # untouched. Old container only goes down for the ~2 seconds of
    # the actual docker run, not the multi-minute build.

    # Ensure biotools base exists (built once, rarely rebuilt).
    if ! docker image inspect biomate-biotools:1 >/dev/null 2>&1; then
      echo "[frontend] Biotools base missing — building (this is slow, runs once)..."
      docker build -t biomate-biotools:1 \
        -f /opt/biomate/frontend_sync/frontend/Dockerfile.biotools \
        /opt/biomate/frontend_sync/frontend/ 2>&1 | tail -5
    fi

    echo "[frontend] Building app image (old container still serving)..."
    # Capture exit code BEFORE piping — `docker build | tail` always exits 0
    # because tail succeeds even when build fails. Without this guard, the
    # script swaps the OLD image into :latest as if the build succeeded
    # (observed live: silently shipped pre-fix code 2026-06-07).
    BUILD_RC=0
    set +e
    docker build -t biomate-dev-frontend:next \
        -f /opt/biomate/frontend_sync/frontend/Dockerfile \
        /opt/biomate/frontend_sync/frontend/ > /tmp/biomate_frontend_build.log 2>&1
    BUILD_RC=$?
    set -e
    tail -5 /tmp/biomate_frontend_build.log
    if [ "$BUILD_RC" -ne 0 ]; then
      echo "[frontend] ERROR: app image build failed (rc=$BUILD_RC) — old container still up, no swap"
      echo "[frontend] Full log: /tmp/biomate_frontend_build.log"
      exit 1
    fi

    # Promote :next → :latest; safe even if no previous :latest exists.
    docker tag biomate-dev-frontend:next biomate-dev-frontend:latest

    echo "[frontend] Swapping containers..."
    docker rm -f biomate-dev-frontend 2>/dev/null || true
    # /var/run/docker.sock + /tmp/biomate_code mount: run_code tool spawns
    # ephemeral biomate-biotools:1 sandboxes via host docker; the sandbox
    # bind-mounts /tmp/biomate_code/<session> which must resolve to the same
    # path inside the frontend container so paths match host-side.
    mkdir -p /tmp/biomate_code
    docker run -d --name biomate-dev-frontend --network biomate-dev-net \
      -p 3000:3000 --env-file /opt/biomate/.env \
      -e NODE_ENV=production -e PORT=3000 -e FORCE_HTTPS=0 \
      --restart unless-stopped \
      -v /var/run/docker.sock:/var/run/docker.sock \
      -v /tmp/biomate_code:/tmp/biomate_code \
      biomate-dev-frontend:latest
    sleep 5
    # Restore logo (not baked into image — uploaded separately)
    docker cp /tmp/logo_sync.png biomate-dev-frontend:/app/dist/public/logo.png 2>/dev/null || true
    docker ps --format "  {{.Names}}: {{.Status}}" | grep biomate-dev-frontend
  '
  log "[frontend] Done"
}

# ---------------------------------------------------------------------------
# Layer 2: Backend Python files (hot-patch into running Galaxy container)
# ---------------------------------------------------------------------------

deploy_galaxy_yml() {
  # Ship backend/config/galaxy.yml → /app/config/galaxy.yml inside the
  # Galaxy container. Image-baked galaxy.yml has had wrong values
  # (regressed bind port) that get re-applied on container restart;
  # an in-container patch is not durable. The local file is the
  # source of truth (committed in 26fef3ed4: bind: 0.0.0.0:8080).
  # Ship the .docker variant — has container-correct virtualenv, paths,
  # http port, etc. The plain galaxy.yml is the LOCAL dev config with
  # absolute paths under /home/yzhang/... that don't exist in the container.
  # Caught 2026-06-09: shipping galaxy.yml broke `import galaxy` because
  # tool_config_file pointed at host paths and gravity couldn't bootstrap.
  local src="$REPO_ROOT/backend/config/galaxy.yml.docker"
  if [[ ! -f "$src" ]]; then
    log "[galaxy.yml] source missing: $src — skipping"
    return 0
  fi
  log "[galaxy.yml] Shipping $(stat -c %s $src 2>/dev/null || echo ?) bytes..."
  ec2_scp "$src" "${EC2_USER}@${EC2_HOST}:/tmp/galaxy.yml"
  ec2_ssh '
    set -e
    docker cp /tmp/galaxy.yml biomate-galaxy-dev:/app/config/galaxy.yml
    # Verify the bind is correct (catch any future regression)
    BIND=$(docker exec biomate-galaxy-dev grep -E "^[[:space:]]+bind:" /app/config/galaxy.yml | head -1 | tr -d " ")
    echo "[galaxy.yml] applied; bind = ${BIND}"
    # Reload gunicorn so it picks up the new bind (no-op if unchanged)
    docker exec biomate-galaxy-dev galaxyctl restart gunicorn 2>&1 | tail -1
  '
  log "[galaxy.yml] Done"
}

deploy_backend_python() {
  log "[backend] Syncing Python files..."

  # Build list of Python files to sync (changed since Mar 31 container build + any new ones)
  local tmp_list="/tmp/backend_py_files.txt"
  cd "$REPO_ROOT"

  # Changed tracked files since container build date
  git diff --name-only "$(git log --before='2026-04-01' --format='%H' -- backend/ | head -1)" HEAD \
    -- 'backend/lib/**/*.py' 'backend/lib/**/*.py' 2>/dev/null > "$tmp_list" || true

  # Add untracked new Python files
  git ls-files --others --exclude-standard -- 'backend/lib/*.py' 'backend/lib/**/*.py' \
    2>/dev/null >> "$tmp_list" || true

  # Always include key files that might be missing
  echo "backend/lib/galaxy/jobs/qc_trace_monitor.py" >> "$tmp_list"

  # Also sync backend/scripts/ (indexer + utilities not under lib/)
  git diff --name-only "$(git log --before='2026-04-01' --format='%H' -- backend/scripts/ | head -1)" HEAD \
    -- 'backend/scripts/*.py' 2>/dev/null >> "$tmp_list" || true
  git ls-files --others --exclude-standard -- 'backend/scripts/*.py' \
    2>/dev/null >> "$tmp_list" || true
  # Always include the workflow indexer
  echo "backend/scripts/index_all_workflows.py" >> "$tmp_list"

  local count=$(sort -u "$tmp_list" | grep -c "\.py$" || true)
  log "[backend] $count Python files to sync"

  # Build tar of backend Python files using `git show HEAD:` instead of the
  # working tree. This prevents concurrent parallel sessions from deploying
  # a stale or wrong version of a file — only committed content is deployed.
  local tar_file="/tmp/biomate_backend_py.tar.gz"
  local tmp_tar_dir="/tmp/biomate_backend_py_staging"
  rm -rf "$tmp_tar_dir" && mkdir -p "$tmp_tar_dir"
  while IFS= read -r rel_path; do
    [[ "$rel_path" == *.py ]] || continue
    mkdir -p "$tmp_tar_dir/$(dirname "$rel_path")"
    # Export committed version; fall back to working tree for untracked files
    git show "HEAD:$rel_path" > "$tmp_tar_dir/$rel_path" 2>/dev/null \
      || cp "$REPO_ROOT/$rel_path" "$tmp_tar_dir/$rel_path" 2>/dev/null || true
  done < <(sort -u "$tmp_list")
  tar -czf "$tar_file" -C "$tmp_tar_dir" . 2>/dev/null || true

  # Hard-fail if the upload itself didn't land. Previously this was silent:
  # scp printed "Failure" but the script continued, then the next ec2_ssh
  # block extracted a STALE leftover tarball from /tmp/backend_py_extract/
  # (kept by `mkdir -p` not clearing the dir) and dispatched docker cp
  # for the wrong files. Caught 2026-06-06 when an autofix3 change
  # appeared to "sync OK" but the new code never reached the container.
  if ! ec2_scp "$tar_file" "${EC2_USER}@${EC2_HOST}:/tmp/backend_py_sync.tar.gz"; then
    log "[backend] FATAL: scp of $tar_file failed — aborting (was silently swallowed pre 2026-06-06)"
    return 1
  fi

  ec2_ssh '
    set -e
    # Nuke any leftover extract dir BEFORE tar so a missing/broken upload
    # cannot silently fall back to the previous sync content.
    rm -rf /tmp/backend_py_extract && mkdir -p /tmp/backend_py_extract
    # No `|| true`: a tar failure here means stale-or-corrupt input;
    # aborting is the only safe response.
    tar -xzf /tmp/backend_py_sync.tar.gz -C /tmp/backend_py_extract

    # Sanity check: confirm extract is non-empty before mass-copying.
    extracted=$(find /tmp/backend_py_extract/backend -name "*.py" 2>/dev/null | wc -l)
    if [[ "$extracted" -lt 1 ]]; then
      echo "[backend] FATAL: tarball extracted zero .py files — refusing to docker cp" >&2
      exit 1
    fi
    echo "[backend] extracted $extracted python files into /tmp/backend_py_extract/"

    # Copy each file into the Galaxy container at /app/ path
    find /tmp/backend_py_extract/backend -name "*.py" | while read src; do
      rel="${src#/tmp/backend_py_extract/backend/}"
      dest="/app/lib/galaxy/${rel#lib/galaxy/}"
      dir=$(dirname "$dest")
      # Create directory in container if needed
      docker exec biomate-galaxy-dev mkdir -p "$dir" 2>/dev/null || true
      docker cp "$src" "biomate-galaxy-dev:$dest" 2>/dev/null && echo "  cp: $dest" || echo "  SKIP: $dest"
    done

    # Also sync the biomni_workflows .nf files
    echo "[backend] Done Python sync"

    # Bootstrap runtime deps that the image was built without.
    # IMPORTANT: gunicorn runs with /usr/local/bin/python3.9 (system Python),
    # not /app/.venv. Installing to the venv silently fails to expose them.
    docker exec biomate-galaxy-dev /usr/local/bin/python3.9 -c "import boto3, redis, psycopg2" 2>/dev/null \
      || docker exec biomate-galaxy-dev /usr/local/bin/pip install -q boto3 redis psycopg2-binary 2>&1 | tail -3

    # Nextflow binary — required by /api/cryosparc/execute path. Image lacks it.
    # Nextflow VERSION PIN (2026-05-21): 25.10.5 is the latest pre-26 LTS.
    # Nextflow 26.04+ became stricter about DSL2 (e.g. rejects top-level
    # `def` statements with "Statements cannot be mixed with script
    # declarations", and is pickier about Groovy heredoc parsing). 21 of
    # our workflows had to be rewritten today to satisfy 26.04. Rather
    # than chase every future breaking change, pin to 25.10 LTS which
    # accepts the older syntax cleanly. Bump deliberately, not by curl.
    EXPECTED_NF_VER="25.10.5"
    INSTALLED_NF_VER=$(docker exec biomate-galaxy-dev /usr/local/bin/nextflow -v 2>/dev/null | grep -oE "[0-9]+\.[0-9]+\.[0-9]+" | head -1)
    if [[ "$INSTALLED_NF_VER" != "$EXPECTED_NF_VER" ]]; then
      echo "[galaxy] Nextflow version mismatch (installed=$INSTALLED_NF_VER, want=$EXPECTED_NF_VER) — reinstalling pinned version"
      docker exec biomate-galaxy-dev bash -c "NXF_VER=$EXPECTED_NF_VER curl -fsSL https://get.nextflow.io | bash && mv nextflow /usr/local/bin/nextflow && chmod +x /usr/local/bin/nextflow" 2>&1 | tail -3
    fi
  '
  log "[backend] Python files synced"
}

# ---------------------------------------------------------------------------
# Layer 3: Nextflow workflow files
# ---------------------------------------------------------------------------

deploy_workflows() {
  log "[workflows] Syncing .nf files..."
  local tar_file="/tmp/biomate_workflows.tar.gz"
  cd "$REPO_ROOT"
  tar -czf "$tar_file" \
    --exclude='*/.nextflow' \
    --exclude='*/.nextflow.log*' \
    backend/biomni_workflows/ 2>/dev/null
  log "[workflows] Archive: $(du -sh $tar_file | cut -f1)"

  ec2_scp "$tar_file" "${EC2_USER}@${EC2_HOST}:/tmp/workflows_sync.tar.gz"

  ec2_ssh '
    set -e
    mkdir -p /tmp/workflows_extract
    tar -xzf /tmp/workflows_sync.tar.gz -C /tmp/workflows_extract 2>/dev/null
    # Copy workflows into Galaxy container via in-container untar so symlinks
    # in the archive can replace pre-existing directories (the host docker cp
    # cannot overwrite a directory with a non-directory and silently leaves
    # stale content — caused the 2026-05-21 ADMET_pred regression where the
    # symlink drug_discovery/ADMET_pred → pharmacology/ADMET_pred could not
    # supersede an old standalone directory on dev).
    docker cp /tmp/workflows_sync.tar.gz biomate-galaxy-dev:/tmp/workflows_sync.tar.gz
    docker exec biomate-galaxy-dev bash -c "
      set -e
      cd /tmp && mkdir -p workflows_extract_in
      tar -xzf workflows_sync.tar.gz -C workflows_extract_in
      # Per-file replacement (handles symlink-vs-dir conflicts that defeat cp -r).
      # Walk the source, remove the dest entry whatever its type, then move new in.
      cd workflows_extract_in/backend/biomni_workflows
      find . -mindepth 1 \( -type f -o -type l \) | while read -r rel; do
        rel=\${rel#./}
        dest=/app/biomni_workflows/\$rel
        mkdir -p \"\$(dirname \"\$dest\")\"
        rm -rf \"\$dest\" 2>/dev/null
        cp -P \"\$rel\" \"\$dest\"
      done
    " 2>&1 | tail -3

    # Workflow-script cache invalidation: Nextflow caches compiled .nf
    # scripts by content hash, but stale per-run dirs can keep old plugin
    # state. We DO NOT delete entire ~/.nextflow (plugins are 100MB+ and
    # re-downloading on every sync would be slow); we clear only the
    # script-compile cache + tmp.
    docker exec biomate-galaxy-dev bash -c "
      rm -rf /home/galaxy/.nextflow/cache /home/galaxy/.nextflow/tmp 2>/dev/null
      rm -rf /root/.nextflow/cache /root/.nextflow/tmp 2>/dev/null
      # Also wipe completed/orphaned per-run dirs older than 1 hour so the
      # fallback status path will not latch onto a stale timing.json.
      find /tmp/nextflow_runs -maxdepth 1 -mindepth 1 -type d -mmin +60 -exec rm -rf {} + 2>/dev/null
      echo \"  ✓ nextflow caches cleared\"
    " 2>&1 | tail -3
    echo "[workflows] Done"
  '
  log "[workflows] Done"
}

# ---------------------------------------------------------------------------
# Layer 4: Galaxy databases
# ---------------------------------------------------------------------------

deploy_databases() {
  log "[db] Syncing Galaxy databases..."

  # galaxy_ai_tools.db — 270MB, sync via direct scp (NOT S3).
  #
  # WHY scp instead of S3 (2026-05-22):
  # The dev EC2 host has stale ~/.aws/credentials (Oct 2025) whose access
  # key has been deleted upstream. The `aws s3 cp` on the host returns
  # InvalidAccessKeyId and the previous code silently used a stale
  # `/tmp/galaxy_ai_tools_sync.db` from a prior run — leaving dev on a
  # stale workflow DB indefinitely. Same failure mode that hit
  # universe.sqlite. Direct scp avoids it. ~15-30 sec at LAN speed.
  #
  # Fixing the EC2 creds (move ~/.aws/credentials aside, let the
  # BioMateEc2DeployProfile instance role take over) would restore the
  # S3 path, but that's a separate hardening pass.
  local local_db="$REPO_ROOT/backend/database/galaxy_ai_tools.db"
  # Probe GNU stat first (see comment at L960). BSD `stat -f %m` returns
  # filesystem info on Linux *without* erroring, so the ||-fallback below
  # would never engage and the [[ -gt ]] check would die under set -u.
  local local_db_mtime=$(stat -c %Y "$local_db" 2>/dev/null \
    || stat -f %m "$local_db" 2>/dev/null \
    || echo 0)
  [[ "$local_db_mtime" =~ ^[0-9]+$ ]] || local_db_mtime=0

  if [[ "$local_db_mtime" -gt "${LAST_DB_SYNC:-0}" ]]; then
    log "[db] galaxy_ai_tools.db changed ($(du -sh $local_db | cut -f1)) — scp to EC2..."
    ec2_scp "$local_db" "${EC2_USER}@${EC2_HOST}:/tmp/galaxy_ai_tools_sync.db" \
      || { log "[db] scp failed — aborting galaxy_ai_tools.db sync"; return 1; }
    # Verify the transferred file is not empty/truncated before touching the container.
    # An scp that fails mid-transfer can leave a 0-byte or partial file even with exit 0.
    ec2_ssh '
      transferred_size=$(stat -c %s /tmp/galaxy_ai_tools_sync.db 2>/dev/null || echo 0)
      if [[ "$transferred_size" -lt 10485760 ]]; then
        echo "[db] FATAL: transferred file is only ${transferred_size} bytes (expected >10MB) — refusing docker cp to avoid corrupting dev DB" >&2
        rm -f /tmp/galaxy_ai_tools_sync.db
        exit 1
      fi
      echo "[db] transfer verified: ${transferred_size} bytes"
    ' || { log "[db] transfer size check failed — aborting"; return 1; }
    ec2_ssh '
      docker stop biomate-galaxy-dev 2>/dev/null || true
      docker cp /tmp/galaxy_ai_tools_sync.db \
        biomate-galaxy-dev:/app/database/galaxy_ai_tools.db
      docker start biomate-galaxy-dev
      docker network connect biomate-dev-net biomate-galaxy-dev 2>/dev/null || true
      sleep 3
      docker exec -u root biomate-galaxy-dev chown galaxy:galaxy /app/database/galaxy_ai_tools.db
      sleep 5
      # Verify the copy landed correctly — catch any docker cp corruption.
      dev_size=$(docker exec biomate-galaxy-dev stat -c %s /app/database/galaxy_ai_tools.db 2>/dev/null || echo 0)
      dev_md5=$(docker exec biomate-galaxy-dev md5sum /app/database/galaxy_ai_tools.db 2>/dev/null | cut -d" " -f1)
      if [[ "$dev_size" -lt 10485760 ]]; then
        echo "[db] ERROR: dev DB is only ${dev_size}B after copy — DB may be corrupt" >&2
      else
        echo "[db] galaxy_ai_tools.db replaced OK (size=${dev_size}B md5=${dev_md5})"
      fi
      rm -f /tmp/galaxy_ai_tools_sync.db
    '
    LAST_DB_SYNC="$local_db_mtime"
  else
    log "[db] galaxy_ai_tools.db unchanged — skipping"
  fi

  # universe.sqlite — 3.4MB, sync via direct scp (NOT S3).
  #
  # WHY scp instead of S3 (2026-05-21):
  # The dev EC2 host lacks S3 read credentials for biomate-nextflow-work
  # (HeadObject returns 403 Forbidden). The previous S3-path code silently
  # ran `aws s3 cp` on the host, failed, and continued using a STALE
  # `/tmp/universe_sync.sqlite` from a prior run — clobbering manual
  # migration fixes on every sync. Direct scp from the workstation avoids
  # that failure mode entirely. The file is small (3.4 MB ≈ 2 sec scp).
  #
  # Local DB must be at the same alembic head as the deployed code. If
  # the upgrade below fails with "Multiple head revisions are present",
  # update LATEST_GXY_HEAD to the new merge-revision filename in
  # backend/lib/galaxy/model/migrations/alembic/versions_gxy/.
  local universe_db="$REPO_ROOT/backend/database/universe.sqlite"
  local LATEST_GXY_HEAD="204367c6a604"  # merge_gxy_heads_autofix_sample_sheets
  if [[ -f "$universe_db" && $(stat -c %s "$universe_db") -gt 0 ]]; then
    log "[db] universe.sqlite — scp to EC2 (bypass S3)..."
    ec2_scp "$universe_db" "${EC2_USER}@${EC2_HOST}:/tmp/universe_sync.sqlite" \
      || { log "[db] scp failed — aborting universe.sqlite sync"; return 1; }
    # docker cp works on a RUNNING container — no need to stop. chown must
    # happen while the container runs (docker exec fails on a stopped one).
    # The restart at the end forces Galaxy workers to re-open the new DB
    # file (the open file handle from the pre-cp workers is now stale).
    ec2_ssh "
      docker cp /tmp/universe_sync.sqlite biomate-galaxy-dev:/app/database/universe.sqlite \
        && docker exec -u root biomate-galaxy-dev chown galaxy:galaxy /app/database/universe.sqlite \
        && echo '[db] file replaced — running alembic upgrade ${LATEST_GXY_HEAD}...' \
        && (docker exec biomate-galaxy-dev bash -c 'cd /app && ./manage_db.sh upgrade ${LATEST_GXY_HEAD} 2>&1' | tail -5 \
            || echo '[db] alembic upgrade returned non-zero — Galaxy may be unhealthy after restart') \
        && docker restart biomate-galaxy-dev >/dev/null \
        && echo '[db] universe.sqlite replaced + upgraded to ${LATEST_GXY_HEAD}'
    " || log "[db] universe.sqlite sync failed"
  fi

  log "[db] Done"
}

# ---------------------------------------------------------------------------
# Restart Galaxy after code changes
# ---------------------------------------------------------------------------

resync_galaxy_env() {
  # Recreate the Galaxy backend container with /opt/biomate/.env merged in,
  # preserving every existing env var (DB urls, API keys, etc.) that was set
  # inline at the container's original launch time.
  #
  # When to run: any time /opt/biomate/.env is edited (e.g. flipping
  # BIOMATE_RESPONSE_MODEL=gemini-3.1-pro-preview to move chat off Claude).
  # Trigger via: BIOMATE_RESYNC_GALAXY_ENV=1 bash scripts/sync_to_dev.sh
  #
  # Why this exists: the Galaxy container was originally launched with env
  # vars baked-in via `-e K=V` flags, NOT --env-file. Docker doesn't allow
  # changing a running container's env, so picking up new vars requires a
  # full stop/rm/run cycle. This function captures the live env, merges in
  # /opt/biomate/.env, and re-runs so every var stays in sync with one
  # canonical file going forward.
  #
  # Replaces the one-off scripts/enable_autofix3_on_dev.sh (deleted).
  log "[galaxy-env] Recreating Galaxy container with /opt/biomate/.env merged in..."
  ec2_ssh '
    set -euo pipefail
    CONTAINER=biomate-galaxy-dev
    ENV_FILE=/opt/biomate/.env

    if [[ ! -f "$ENV_FILE" ]]; then
      echo "[galaxy-env] FATAL: $ENV_FILE not present; aborting" >&2
      exit 1
    fi

    # Vars set in .env take precedence over the running container'\''s baked-in
    # values for the same key (last --env-file wins on docker run). Capture
    # the rest from the running container so we do not lose JWT_SECRET etc.
    LIVE_ENV=$(mktemp)
    CLEANUP_FILES="$CLEANUP_FILES $LIVE_ENV"   # cleaned by on_exit; do NOT re-trap (would drop lock removal)

    # Keys present in .env — we will let the file supply them
    NEW_KEYS=$(grep -v "^#\|^$" "$ENV_FILE" | awk -F= "{print \$1}" | sort -u)

    # Capture all other live container env vars (filter the keys .env will override)
    docker inspect "$CONTAINER" --format "{{range .Config.Env}}{{println .}}{{end}}" | \
      while IFS= read -r line; do
        k="${line%%=*}"
        # Skip PATH/HOME/TERM/HOSTNAME — Docker re-supplies these
        case "$k" in PATH|HOME|TERM|HOSTNAME|"") continue ;; esac
        # Skip keys present in the env file (file will supply them)
        if echo "$NEW_KEYS" | grep -qxF "$k"; then continue; fi
        echo "$line"
      done > "$LIVE_ENV"

    # Capture other container config we must preserve
    IMAGE=$(docker inspect "$CONTAINER" --format "{{.Config.Image}}")
    NETWORK=$(docker inspect "$CONTAINER" --format "{{.HostConfig.NetworkMode}}")
    PORTS=$(docker inspect "$CONTAINER" --format "{{range \$p, \$bs := .HostConfig.PortBindings}}{{range \$bs}}-p {{.HostPort}}:{{\$p}} {{end}}{{end}}" | sed "s|/tcp||g")
    MOUNTS=$(docker inspect "$CONTAINER" --format "{{range .Mounts}}-v {{.Source}}:{{.Destination}}{{if .RW}}{{else}}:ro{{end}} {{end}}")

    echo "  preserving image=$IMAGE network=$NETWORK ports=$PORTS"
    echo "  live env to preserve: $(wc -l < $LIVE_ENV) vars; env-file to apply: $(echo "$NEW_KEYS" | wc -l) keys"

    echo "[galaxy-env] Stopping + removing $CONTAINER..."
    docker stop "$CONTAINER" > /dev/null
    docker rm "$CONTAINER" > /dev/null

    echo "[galaxy-env] Re-running with --env-file + preserved env..."
    # --env-file applied first, then --env per captured var — file values win
    # because docker uses LAST occurrence per key. Order: file → live (live
    # keys are pre-filtered to NOT collide with file keys), so result = union.
    docker run -d --name "$CONTAINER" \
      --network "$NETWORK" \
      $PORTS \
      $MOUNTS \
      --restart unless-stopped \
      --env-file "$ENV_FILE" \
      $(awk "{print \"-e\", \$0}" "$LIVE_ENV" | tr "\n" " ") \
      "$IMAGE" > /dev/null

    echo "[galaxy-env] Waiting for container health..."
    for i in $(seq 1 30); do
      status=$(docker inspect "$CONTAINER" --format "{{.State.Status}}" 2>/dev/null || echo unknown)
      if [[ "$status" == "running" ]]; then
        echo "  ✓ container running"
        break
      fi
      sleep 1
    done
  '
  log "[galaxy-env] Done — env vars from /opt/biomate/.env are now active"
}

push_managed_env() {
  # Render the manifest-managed env locally and upsert it into the EC2's
  # /opt/biomate/.env via scp+ssh (no S3 needed — sync runs locally with SSH).
  #
  # Single source of variable NAMES: deploy/biomate.env.manifest.
  # Single source of VALUES:         $BIOMATE_ENV_SOURCE (default
  #                                  env-files/opt-biomate.env — the collected
  #                                  real env, gitignored).
  #
  # Per-key upsert: managed value overrides; host-only keys NOT in the manifest
  # (e.g. GALAXY_MASTER_API_KEY) are preserved. Required-but-missing vars fail
  # the render (fail-fast) before anything is pushed.
  #
  # Trigger via: BIOMATE_PUSH_ENV=1 [BIOMATE_ENV_SOURCE=path] bash scripts/sync_to_dev.sh
  # Pair with BIOMATE_RESYNC_GALAXY_ENV=1 to apply it to the Galaxy container.
  local manifest="$REPO_ROOT/deploy/biomate.env.manifest"
  local renderer="$REPO_ROOT/scripts/render_env_manifest.sh"
  local source_env="${BIOMATE_ENV_SOURCE:-$REPO_ROOT/env-files/opt-biomate.env}"

  [[ -f "$manifest"   ]] || { log "[push-env] FATAL: manifest missing: $manifest"; return 1; }
  [[ -f "$renderer"   ]] || { log "[push-env] FATAL: renderer missing: $renderer"; return 1; }
  [[ -f "$source_env" ]] || { log "[push-env] FATAL: value source missing: $source_env (set BIOMATE_ENV_SOURCE=<file>)"; return 1; }

  log "[push-env] Rendering managed env from manifest (values: $source_env)..."
  local managed; managed="$(mktemp)"
  # Render in a subshell: load source values WITHOUT \`source\` (values taken
  # literally via split-on-first-=, safe for spaces/specials), then render.
  if ! (
        while IFS= read -r line; do
          case "$line" in ''|\#*) continue ;; esac
          [[ "$line" == *=* ]] || continue
          export "${line%%=*}=${line#*=}"
        done < "$source_env"
        bash "$renderer" "$managed"
      ); then
    log "[push-env] FATAL: render failed (missing required vars? see error above)"
    rm -f "$managed"; return 1
  fi

  local n; n="$(grep -c '=' "$managed" 2>/dev/null || true)"
  if [[ "${n:-0}" -eq 0 ]]; then
    log "[push-env] Nothing to push (no managed vars rendered)"; rm -f "$managed"; return 0
  fi

  log "[push-env] Pushing $n managed var(s) → EC2 /opt/biomate/.env (host-only keys preserved)..."
  ec2_scp "$managed" "${EC2_USER}@${EC2_HOST}:/tmp/.env.managed"
  ec2_ssh '
    set -euo pipefail
    cd /opt/biomate
    touch .env
    cp .env ".env.backup.$(date +%Y%m%d_%H%M%S)"
    # Per-key upsert: drop each managed key, then append the managed block.
    while IFS="=" read -r k _; do
      [ -n "$k" ] && sed -i "/^${k}=/d" .env
    done < /tmp/.env.managed
    cat /tmp/.env.managed >> .env
    chmod 600 .env
    rm -f /tmp/.env.managed
    echo "[push-env] /opt/biomate/.env now has $(wc -l < .env) line(s)"
  '
  rm -f "$managed"
  log "[push-env] Done. Apply with BIOMATE_RESYNC_GALAXY_ENV=1 (frontend picks it up on next recreate)."
}

load_env_from_secrets() {
  # GitLab-style external config: pull runtime env from AWS Secrets Manager into
  # the EC2's /opt/biomate/.env, using the instance role (no static creds, no
  # GitHub, no workstation values). Values are configured in Secrets Manager
  # (see scripts/put_env_to_secret.sh); the repo holds only names (the manifest).
  #
  # Trigger via: BIOMATE_LOAD_ENV=1 [BIOMATE_ENV=test] bash scripts/sync_to_dev.sh
  # Pair with BIOMATE_RESYNC_GALAXY_ENV=1 to apply to the Galaxy container.
  local script="$REPO_ROOT/scripts/load_env_from_secrets.sh"
  [[ -f "$script" ]] || { log "[load-env] FATAL: $script missing"; return 1; }
  log "[load-env] Pulling env from Secrets Manager (${BIOMATE_ENV:-test}/biomate/galaxy-env) into EC2 /opt/biomate/.env..."
  ec2_scp "$script" "${EC2_USER}@${EC2_HOST}:/tmp/load_env_from_secrets.sh"
  # Runs as ubuntu (owns /opt/biomate/.env); the instance role supplies AWS creds.
  ec2_ssh "BIOMATE_ENV='${BIOMATE_ENV:-test}' bash /tmp/load_env_from_secrets.sh && rm -f /tmp/load_env_from_secrets.sh"
  log "[load-env] Done. Apply with BIOMATE_RESYNC_GALAXY_ENV=1."
}

# Dispatch the IND PI suite (workflow_dispatch) against the freshly-synced dev.
# A successful sync IS the dev deploy, so this is the one place that should fire
# the suite — it is dispatch-only because a git push does NOT deploy to dev.
# Non-fatal and skippable with BIOMATE_SKIP_PI_SUITE=1. Needs `gh` (authed) or a
# GITHUB_TOKEN/GH_TOKEN with the actions scope; otherwise prints a manual hint.
trigger_pi_suite() {
  if [[ "${BIOMATE_SKIP_PI_SUITE:-}" == "1" ]]; then
    log "[pi-suite] skipped (BIOMATE_SKIP_PI_SUITE=1)"
    return 0
  fi
  local ref repo
  ref="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo integration/next-phase)"
  repo="bioMate-AI/biomate"
  log "[pi-suite] dispatching ind-pi-suite.yml against dev (ref ${ref})..."
  if command -v gh >/dev/null 2>&1; then
    if gh workflow run ind-pi-suite.yml --ref "$ref" >/dev/null 2>&1; then
      log "[pi-suite] dispatched via gh — watch it in the GitHub Actions tab"
    else
      log "[pi-suite] gh dispatch failed — run it manually (Actions → Run workflow)"
    fi
  elif [[ -n "${GITHUB_TOKEN:-${GH_TOKEN:-}}" ]]; then
    if curl -fsS -X POST \
         -H "Authorization: Bearer ${GITHUB_TOKEN:-$GH_TOKEN}" \
         -H "Accept: application/vnd.github+json" \
         "https://api.github.com/repos/${repo}/actions/workflows/ind-pi-suite.yml/dispatches" \
         -d "{\"ref\":\"${ref}\"}" >/dev/null 2>&1; then
      log "[pi-suite] dispatched via API — watch it in the GitHub Actions tab"
    else
      log "[pi-suite] API dispatch failed — run it manually (Actions → Run workflow)"
    fi
  else
    log "[pi-suite] no gh CLI / GITHUB_TOKEN — run ind-pi-suite manually (Actions → Run workflow)"
  fi
  return 0
}

restart_galaxy() {
  log "[galaxy] Clearing stale caches + reloading Galaxy gunicorn workers (HUP)..."
  ec2_ssh '
    # Stale cache cleanup — addresses the class of "undetected issues" where
    # a code/workflow change ships but the runtime keeps serving the old
    # behaviour because:
    #   - .pyc bytecode under __pycache__/ wins over fresh .py
    #   - module-level singletons (e.g. _ai_assistant_instance) survive HUP
    #     when the master process is reused
    #   - Nextflow caches compiled workflow scripts in ~/.nextflow and the
    #     per-run directories under /tmp/nextflow_runs/<run_id>/.nextflow
    #   - Galaxy AI tool DB query caches inside the worker process
    # Cleaning these BEFORE the HUP guarantees the new code/workflow is what
    # serves the next request.
    echo "[galaxy] Clearing Python bytecode cache (__pycache__ under /app/lib/galaxy/ai)..."
    docker exec biomate-galaxy-dev bash -c "
      find /app/lib/galaxy/ai /app/lib/galaxy/webapps/galaxy/api -name __pycache__ -type d -exec rm -rf {} + 2>/dev/null
      find /app/lib/galaxy/ai /app/lib/galaxy/webapps/galaxy/api -name \"*.pyc\" -delete 2>/dev/null
      echo \"  ✓ pycache cleared\"
    " 2>&1 | tail -3

    echo "[galaxy] Clearing Nextflow workflow-script cache (preserves plugins)..."
    docker exec biomate-galaxy-dev bash -c "
      # Clear the cache directories Nextflow uses to memoise compiled workflow
      # bytecode + workflow trace state. /tmp/nextflow_runs/* is per-run and
      # safe to keep; the global ~/.nextflow/cache is what stores cross-run
      # script-compile artifacts that pin to stale .nf file hashes.
      rm -rf /home/galaxy/.nextflow/cache /home/galaxy/.nextflow/tmp 2>/dev/null
      rm -rf /root/.nextflow/cache /root/.nextflow/tmp 2>/dev/null
      echo \"  ✓ nextflow caches cleared\"
    " 2>&1 | tail -3

    # Prefer HUP (graceful reload, no 30-min cold start) over docker restart.
    # Use "docker kill -s HUP" from the host — the container has no kill binary.
    # Try pid file first; fall back to pgrep for the gunicorn master process.
    GPID=$(docker exec biomate-galaxy-dev cat /app/database/gravity/gunicorn.pid 2>/dev/null)
    if [[ -z "$GPID" ]]; then
      # pid file missing — find gunicorn master by looking for the process that
      # owns child workers (lowest PID among gunicorn processes is the master).
      GPID=$(docker exec biomate-galaxy-dev bash -c "pgrep -f 'gunicorn.*fast_factory' | sort -n | head -1" 2>/dev/null)
    fi
    if [[ -n "$GPID" ]]; then
      docker exec biomate-galaxy-dev sh -c "kill -HUP $GPID" 2>/dev/null && \
        echo "[galaxy] gunicorn HUP sent to PID $GPID" || \
        echo "[galaxy] HUP failed (non-fatal — workers will pick up files on next request)"
    else
      echo "[galaxy] gunicorn not found — Galaxy may still be starting up"
      echo "[galaxy] Python files copied; workers will use new code when Galaxy finishes loading"
    fi

    # Ensure Nextflow is installed (lost if container was recreated from image)
    if ! docker exec biomate-galaxy-dev which nextflow > /dev/null 2>&1; then
      echo "[galaxy] Nextflow missing — installing Java + Nextflow..."
      docker exec -u root biomate-galaxy-dev bash -c "
        apt-get update -q && apt-get install -y -q default-jre-headless 2>/dev/null
        curl -fsSL https://get.nextflow.io | bash
        mv nextflow /usr/local/bin/nextflow && chmod +x /usr/local/bin/nextflow
      " 2>&1 | tail -5
      echo "[galaxy] Nextflow installed: $(docker exec biomate-galaxy-dev nextflow -version 2>/dev/null | grep version)"
    else
      echo "[galaxy] Nextflow OK: $(docker exec biomate-galaxy-dev nextflow -version 2>/dev/null | grep version)"
    fi

    # Remove stale conda lock that blocks gunicorn worker startup after restart
    docker exec -u root biomate-galaxy-dev rm -f /app/database/dependencies/conda.lock 2>/dev/null || true

    # Ensure Galaxy is on the shared Docker network (lost if container was recreated)
    docker network connect biomate-dev-net biomate-galaxy-dev 2>/dev/null || true

    # Ensure Galaxy database files are owned by galaxy user (docker cp sets host uid)
    docker exec -u root biomate-galaxy-dev chown galaxy:galaxy \
      /app/database/universe.sqlite /app/database/galaxy_ai_tools.db 2>/dev/null || true
  '
}

# ---------------------------------------------------------------------------
# Main sync logic
# ---------------------------------------------------------------------------

sync_logo() {
  local logo="$REPO_ROOT/frontend/client/public/logo.png"
  [[ -f "$logo" ]] || return
  ec2_scp "$logo" "${EC2_USER}@${EC2_HOST}:/tmp/logo_sync.png"
  ec2_ssh '
    docker cp /tmp/logo_sync.png biomate-dev-frontend:/app/dist/public/logo.png 2>/dev/null || true
    sudo cp /tmp/logo_sync.png /var/www/biomate-marketing/images/logo.png 2>/dev/null || true
  '
}

# ---------------------------------------------------------------------------
# Layer 5: Marketing website (reference/claude_design/webpage_design_v2/ → /var/www/biomate-marketing/)

# ---------------------------------------------------------------------------
# Auto-rollback: snapshot pre-sync state, health-gate post-sync, restore on fail
# ---------------------------------------------------------------------------

snapshot_for_rollback() {
  # $1 = whether the frontend layer will run (true/false)
  local snap_frontend="$1"
  log "[rollback] Snapshotting pre-sync dev state (galaxy commit$( [[ "$snap_frontend" == true ]] && echo ' + frontend tag' ))..."
  # Galaxy has NO mounts -> docker commit captures all hot-patched
  # code/db/workflows/config in one image. Also persist its run-spec so the
  # container can be faithfully recreated from the snapshot on rollback.
  if ec2_ssh "
    set -e
    docker commit biomate-galaxy-dev $RB_GALAXY_IMAGE >/dev/null
    mkdir -p /opt/biomate/rollback
    docker inspect biomate-galaxy-dev --format '{{range .Config.Env}}{{println .}}{{end}}' > /opt/biomate/rollback/galaxy.env
    docker inspect biomate-galaxy-dev --format '{{.HostConfig.NetworkMode}}' > /opt/biomate/rollback/galaxy.net
    docker inspect biomate-galaxy-dev --format '{{range \$p,\$b := .HostConfig.PortBindings}}{{range \$b}}-p {{.HostPort}}:{{\$p}} {{end}}{{end}}' | sed 's#/tcp##g' > /opt/biomate/rollback/galaxy.ports
    echo '[rollback]   galaxy committed -> $RB_GALAXY_IMAGE'
    if [ '$snap_frontend' = true ] && docker image inspect biomate-dev-frontend:latest >/dev/null 2>&1; then
      docker tag biomate-dev-frontend:latest biomate-dev-frontend:rollback
      echo '[rollback]   frontend tagged :rollback'
    fi
  "; then
    ROLLBACK_READY=1
    [[ "$snap_frontend" == true ]] && RB_SNAPSHOT_FRONTEND=1
    log "[rollback] Snapshot ready"
  else
    ROLLBACK_READY=0
    log "[rollback] WARNING: snapshot failed — proceeding WITHOUT rollback safety"
  fi
}

postsync_health_ok() {
  # Probe the dev host's mapped ports; retry to ride out HUP / cold start.
  # $1 = number of 5s retries (default 24 = 120s).
  local tries="${1:-24}"
  ec2_ssh "
    for i in \$(seq 1 $tries); do
      if curl -fsS -o /dev/null --max-time 8 http://localhost:8081/api/version && curl -fsS -o /dev/null --max-time 8 http://localhost:3000/api/health; then exit 0; fi
      sleep 5
    done
    exit 1
  "
}

rollback_sync() {
  log "[rollback] Restoring pre-sync snapshot (galaxy$( [[ "$RB_SNAPSHOT_FRONTEND" == 1 ]] && echo ' + frontend' ))..."
  # Recreate Galaxy from the committed snapshot with its preserved run-spec
  # (no mounts to replay). This is a cold start (~60-90s) but fully reverts code.
  if ! ec2_ssh "
    set -e
    NET=\$(cat /opt/biomate/rollback/galaxy.net)
    PORTS=\$(cat /opt/biomate/rollback/galaxy.ports)
    docker rm -f biomate-galaxy-dev >/dev/null 2>&1 || true
    docker run -d --name biomate-galaxy-dev --network \"\$NET\" \$PORTS --restart unless-stopped \$(grep -vE '^(PATH|HOME|TERM|HOSTNAME)=' /opt/biomate/rollback/galaxy.env | awk '{print \"-e\", \$0}' | tr '\n' ' ') $RB_GALAXY_IMAGE >/dev/null
    docker network connect biomate-dev-net biomate-galaxy-dev 2>/dev/null || true
    echo '[rollback]   galaxy recreated from snapshot'
  "; then
    log "[rollback] galaxy recreate FAILED"
    SYNC_RESULT=rollback_failed
    return 1
  fi

  if [[ "$RB_SNAPSHOT_FRONTEND" == 1 ]]; then
    # Recreate frontend from the :rollback image using the SAME run args as
    # deploy_frontend (network/ports/env-file/mounts).
    if ! ec2_ssh '
      set -e
      if docker image inspect biomate-dev-frontend:rollback >/dev/null 2>&1; then
        docker tag biomate-dev-frontend:rollback biomate-dev-frontend:latest
        docker rm -f biomate-dev-frontend 2>/dev/null || true
        mkdir -p /tmp/biomate_code
        docker run -d --name biomate-dev-frontend --network biomate-dev-net \
          -p 3000:3000 --env-file /opt/biomate/.env \
          -e NODE_ENV=production -e PORT=3000 -e FORCE_HTTPS=0 \
          --restart unless-stopped \
          -v /var/run/docker.sock:/var/run/docker.sock \
          -v /tmp/biomate_code:/tmp/biomate_code \
          biomate-dev-frontend:latest >/dev/null
        docker cp /tmp/logo_sync.png biomate-dev-frontend:/app/dist/public/logo.png 2>/dev/null || true
        echo "[rollback]   frontend recreated from snapshot"
      fi
    '; then
      log "[rollback] frontend recreate FAILED"
      SYNC_RESULT=rollback_failed
      return 1
    fi
  fi

  # Confirm the rollback actually restored a healthy dev (longer budget: cold start).
  if postsync_health_ok 48; then
    log "[rollback] ✓ dev restored to pre-sync state and healthy"
    SYNC_RESULT=rolled_back
    return 0
  fi
  log "[rollback] ✗ dev still unhealthy after rollback"
  SYNC_RESULT=rollback_failed
  return 1
}

do_sync() {
  local commit="$1"
  local changed_paths="$2"

  log "=== Syncing commit ${commit:0:8} ==="

  local do_frontend=false do_backend=false do_workflows=false do_db=false

  # Determine what changed
  echo "$changed_paths" | grep -q "^frontend/" && do_frontend=true
  echo "$changed_paths" | grep -q "^backend/lib/" && do_backend=true
  echo "$changed_paths" | grep -q "^backend/biomni_workflows/" && do_workflows=true
  echo "$changed_paths" | grep -q "^backend/database/" && do_db=true

  # Always sync logo
  sync_logo 2>/dev/null || true

  # DB sync is also time-based (if local DB newer than last sync)
  # stat differs across platforms. GNU/Linux `stat -f %m` returns filesystem
  # info (multi-line, starts "  File: ..."), it does NOT error — so the
  # ||-fallback to `stat -c %Y` never runs, and the `[[ "$str" -gt 0 ]]`
  # below treats "File" as a variable name → set-u unbound-variable death.
  # Probe Linux first (stat -c) and fall back to BSD/macOS (stat -f).
  local local_db_mtime=$(stat -c %Y "$REPO_ROOT/backend/database/galaxy_ai_tools.db" 2>/dev/null \
    || stat -f %m "$REPO_ROOT/backend/database/galaxy_ai_tools.db" 2>/dev/null \
    || echo 0)
  # Defensive: if probing produced non-numeric output anyway, treat as 0.
  [[ "$local_db_mtime" =~ ^[0-9]+$ ]] || local_db_mtime=0
  [[ "$local_db_mtime" -gt "${LAST_DB_SYNC:-0}" ]] && do_db=true

  # Diagnostic: log which layers will run (makes silent skips visible in the log)
  log "Layers: frontend=$do_frontend backend=$do_backend workflows=$do_workflows db=$do_db"

  # Snapshot the pre-sync state BEFORE any mutation (and before the optional
  # resync_galaxy_env recreates the container) so we can roll back if the sync
  # leaves dev unhealthy.
  snapshot_for_rollback "$do_frontend"

  # Optional (RECOMMENDED): pull runtime env from AWS Secrets Manager into the
  # EC2's /opt/biomate/.env using the instance role. Values live in Secrets
  # Manager, repo holds only names — nothing through GitHub or local files.
  # Trigger via BIOMATE_LOAD_ENV=1 [BIOMATE_ENV=test].
  [[ "${BIOMATE_LOAD_ENV:-}" == "1" ]] && load_env_from_secrets

  # Optional (legacy/alternative): render the manifest-managed env from a LOCAL
  # source and push it into the EC2's /opt/biomate/.env (per-key upsert; host-only
  # keys preserved). Prefer BIOMATE_LOAD_ENV above (Secrets Manager) for secrets.
  # Trigger via BIOMATE_PUSH_ENV=1 [BIOMATE_ENV_SOURCE=path].
  [[ "${BIOMATE_PUSH_ENV:-}" == "1" ]] && push_managed_env

  # Optional: recreate Galaxy container with /opt/biomate/.env merged in.
  # Trigger via BIOMATE_RESYNC_GALAXY_ENV=1 when env vars in that file change
  # (e.g. flipping chat onto Gemini via BIOMATE_RESPONSE_MODEL). Has to come
  # BEFORE backend python sync so the docker cp lands in the recreated
  # container, not the now-removed old one.
  [[ "${BIOMATE_RESYNC_GALAXY_ENV:-}" == "1" ]] && resync_galaxy_env

  # ALWAYS sync backend/config/galaxy.yml. The container restart on dev wipes
  # any in-container patch back to the image-baked version, which has had wrong
  # values in the past (e.g. bind: 0.0.0.0:8081 vs the required 8080 in
  # `gunicorn` block — Docker maps host:8081 → container:8080, so 8081-bound
  # gunicorn never gets reached). Cheap to ship (single file) and idempotent.
  deploy_galaxy_yml || true

  $do_backend   && deploy_backend_python
  $do_workflows && deploy_workflows
  # HUP Galaxy when either backend Python OR workflow .nf files change.
  # Workflows used to skip the HUP on the theory that Nextflow reads .nf
  # from disk per-run, but Galaxy's in-process workflow_search keeps a
  # parsed step cache + tool DB cache that stays pinned to old file
  # contents until the worker process recycles. Skipping HUP caused the
  # 2026-05-21 class of "fix shipped but old behaviour persists" issues.
  ($do_backend || $do_workflows) && restart_galaxy
  $do_db        && deploy_databases
  # Apply PostgreSQL migrations BEFORE deploying the frontend so the new bundle's
  # storage layer never hits a missing column on the new schema.
  $do_frontend  && apply_postgres_migrations
  $do_frontend  && deploy_frontend

  # --- Post-sync health gate + auto-rollback -------------------------------
  if [[ "$ROLLBACK_READY" == 1 ]]; then
    log "[health] Verifying dev health after sync..."
    if postsync_health_ok 24; then
      log "[health] ✓ dev healthy after sync"
      SYNC_RESULT=healthy
    else
      log "[health] ✗ dev UNHEALTHY after sync — auto-rolling back"
      rollback_sync || true
    fi
  else
    # Snapshot wasn't taken — can't safely roll back. Still report real health.
    log "[health] No snapshot — health-gate without rollback safety"
    if postsync_health_ok 24; then SYNC_RESULT=healthy; else SYNC_RESULT=failed; fi
  fi

  log "=== Sync complete for ${commit:0:8} (result=${SYNC_RESULT:-unknown}) ==="
  [[ "$SYNC_RESULT" == healthy ]] && return 0 || return 1
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

log "BioMate dev sync starting (repo: $REPO_ROOT)"
log "Layers: frontend + backend Python + workflows + databases"
log "Mode: manual one-shot | Target: https://dev-public.biomate.ai"
# --- Pre-flight checks -----------------------------------------------------
# Refuse to run if there are uncommitted source changes. Caller must commit
# or stash first. Auto-commit-before-sync was removed (bypassed code review).
DIRTY_SOURCE=$(git -C "$REPO_ROOT" diff --name-only HEAD 2>/dev/null | \
  grep -E "^(frontend/client/|frontend/server/|frontend/shared/|backend/lib/|backend/biomni_workflows/)" || true)
if [[ -n "$DIRTY_SOURCE" ]]; then
  dirty_count=$(echo "$DIRTY_SOURCE" | wc -l)
  log "ERROR: ${dirty_count} uncommitted source file(s) in working tree:"
  echo "$DIRTY_SOURCE" | sed 's/^/  /' >&2
  log "Commit or stash them, then re-run. Auto-commit has been removed."
  exit 2
fi

CURRENT_COMMIT=$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || echo "")
if [[ -z "$CURRENT_COMMIT" ]]; then
  log "ERROR: not a git repo"
  exit 1
fi

# --- One-shot sync ---------------------------------------------------------
# Sync all tracked layers in one pass and exit. No polling, no retries.
#
# Layer detection strategy:
#   Code layers (frontend/, backend/lib/, backend/biomni_workflows/):
#     git diff against last-synced commit — only files in those trees
#     that actually changed get included.
#   DB layer (galaxy_ai_tools.db):
#     gitignored binary — use md5 of the local file vs. a stored
#     "last-synced md5" in .last_dev_sync_db_md5. Only syncs when
#     the file content has actually changed.
_PREV_COMMIT_FILE="$REPO_ROOT/.last_dev_sync_commit"
_DB_MD5_FILE="$REPO_ROOT/.last_dev_sync_db_md5"
_LOCAL_DB="$REPO_ROOT/backend/database/galaxy_ai_tools.db"

# Code layers — git diff
_PREV_COMMIT=""
[[ -f "$_PREV_COMMIT_FILE" ]] && _PREV_COMMIT="$(cat "$_PREV_COMMIT_FILE" | tr -d '[:space:]')"
if [[ -n "$_PREV_COMMIT" ]] && git -C "$REPO_ROOT" rev-parse --verify "$_PREV_COMMIT" &>/dev/null; then
  CHANGED="$(git -C "$REPO_ROOT" diff --name-only "${_PREV_COMMIT}...${CURRENT_COMMIT}" 2>/dev/null || \
             printf 'frontend/\nbackend/lib/\nbackend/biomni_workflows/')"
  log "Diff base: ${_PREV_COMMIT:0:8} → ${CURRENT_COMMIT:0:8} ($(echo "$CHANGED" | wc -l | tr -d ' ') code files)"
else
  CHANGED="$(printf 'frontend/\nbackend/lib/\nbackend/biomni_workflows/')"
  log "No previous sync commit — syncing all code layers"
fi

# DB layer — compare local md5 against the ACTUAL dev DB md5 (not a cached local md5).
# Comparing local→stored-local is wrong: if dev DB gets corrupted/truncated (e.g. a
# failed docker cp that wrote 0 bytes), the stored md5 still matches local and the DB
# is never re-synced. Root cause of the Jun-2026 "20K stub" incident.
_LOCAL_DB_MD5="$(md5 -q "$_LOCAL_DB" 2>/dev/null || md5sum "$_LOCAL_DB" 2>/dev/null | cut -d' ' -f1 || echo '')"
if [[ -n "$_LOCAL_DB_MD5" ]]; then
  # Fetch the actual dev DB md5 via SSH. One cheap round-trip saves 300MB transfer.
  _DEV_DB_MD5="$(inject_key > /dev/null 2>&1; \
    ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o IdentitiesOnly=yes \
      "${EC2_USER}@${EC2_HOST}" \
      'docker exec biomate-galaxy-dev md5sum /app/database/galaxy_ai_tools.db 2>/dev/null | cut -d" " -f1' 2>/dev/null || echo '')"
  _DEV_DB_SIZE="$(inject_key > /dev/null 2>&1; \
    ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o IdentitiesOnly=yes \
      "${EC2_USER}@${EC2_HOST}" \
      'docker exec biomate-galaxy-dev stat -c %s /app/database/galaxy_ai_tools.db 2>/dev/null || echo 0' 2>/dev/null || echo '0')"
  if [[ "$_LOCAL_DB_MD5" != "$_DEV_DB_MD5" ]]; then
    CHANGED="$CHANGED"$'\n'"backend/database/"
    log "DB out of sync (local=$_LOCAL_DB_MD5 dev=$_DEV_DB_MD5 dev_size=${_DEV_DB_SIZE}B) — will sync"
  elif [[ "${_DEV_DB_SIZE:-0}" -lt 1048576 ]]; then
    # Dev DB is < 1MB — corrupt/empty stub. Force sync even if md5 somehow matches.
    CHANGED="$CHANGED"$'\n'"backend/database/"
    log "Dev DB is too small (${_DEV_DB_SIZE}B) — forcing sync"
  else
    log "DB in sync on dev (${_DEV_DB_MD5}) — skipping 300MB transfer"
  fi
else
  log "WARNING: cannot compute local DB md5 (file missing?) — skipping DB sync"
fi

# From here on the run IS a deploy attempt — arm the SNS notification so its
# outcome (success OR failure) reaches the topic. Pre-flight refusals above
# (dirty tree, not-a-repo, lock contention) intentionally stay silent.
SYNC_STARTED=1

if do_sync "$CURRENT_COMMIT" "$CHANGED"; then
  # Record commit so next sync diffs only changed code layers.
  # Note: DB md5 is no longer cached locally — we fetch it from dev each run
  # to correctly detect dev-side corruption. See the DB layer detection comment above.
  echo "$CURRENT_COMMIT" > "$_PREV_COMMIT_FILE"
  log "=== Sync OK at ${CURRENT_COMMIT:0:8} ==="
  # Ensure all AWS Batch CEs are pinned to the latest Launch Template version.
  # The aws-cli libz regression (2026-04 → 2026-06) was caused by CEs being
  # left behind on old LT versions when the LT was updated. Auto-fix on every
  # sync so it can't survive across deploys. See
  # docs/20260607_BATCH_AMI_AWSCLI_NOT_SELF_CONTAINED.md.
  log "Ensuring Batch CE Launch-Template versions are current..."
  bash "$REPO_ROOT/scripts/audit_batch_ce_lt_versions.sh" --apply --quiet 2>&1 | sed 's/^/  /'
  log "Launching post-sync E2E tests in background..."
  bash "$REPO_ROOT/scripts/run_postsync_tests.sh" "$CURRENT_COMMIT" \
    >> /tmp/biomate_sync.log 2>&1 &
  # A successful sync IS the dev deploy — fire the IND PI suite against dev.
  trigger_pi_suite
  exit 0
else
  case "${SYNC_RESULT:-failed}" in
    rolled_back)
      log "ERROR: sync failed health gate — dev AUTO-ROLLED BACK to the pre-sync snapshot (service is UP on old code). Investigate ${CURRENT_COMMIT:0:8} before re-syncing." ;;
    rollback_failed)
      log "FATAL: sync failed health gate AND rollback failed — dev may be DOWN. Manual intervention required on $INSTANCE_ID." ;;
    *)
      log "ERROR: sync failed — see output above" ;;
  esac
  exit 1
fi
