#!/bin/bash
# sync_to_dev.sh — MANUAL one-shot sync of ALL layers to dev-public.biomate.ai:
#   1. Frontend (React/Express) — Docker rebuild + restart
#   2. Backend Python files    — docker cp into running Galaxy container + restart
#   3. Galaxy databases        — galaxy_ai_tools.db (workflow search), universe.sqlite
#   4. Nextflow workflow files — .nf files in biomni_workflows/
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
trap 'rm -f "$LOCK_FILE"' EXIT

log() { echo "[$(date '+%H:%M:%S')] $*"; }

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
    frontend/package.json frontend/package-lock.json \
    frontend/tsconfig.json frontend/tsconfig.node.json frontend/vite.config.ts \
    frontend/tailwind.config.js frontend/postcss.config.js \
    frontend/Dockerfile 2>/dev/null
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
    if ! docker build -t biomate-dev-frontend:next \
        -f /opt/biomate/frontend_sync/frontend/Dockerfile \
        /opt/biomate/frontend_sync/frontend/ 2>&1 | tail -5; then
      echo "[frontend] ERROR: app image build failed — old container still up, no swap"
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

  local count=$(sort -u "$tmp_list" | grep -c "\.py$" || true)
  log "[backend] $count Python files to sync"

  # Build tar of backend Python files
  local tar_file="/tmp/biomate_backend_py.tar.gz"
  sort -u "$tmp_list" | grep "\.py$" | \
    xargs tar -czf "$tar_file" -C "$REPO_ROOT" 2>/dev/null || true

  ec2_scp "$tar_file" "${EC2_USER}@${EC2_HOST}:/tmp/backend_py_sync.tar.gz"

  ec2_ssh '
    set -e
    mkdir -p /tmp/backend_py_extract
    tar -xzf /tmp/backend_py_sync.tar.gz -C /tmp/backend_py_extract 2>/dev/null || true

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
    # Nextflow VERSION PIN (2026-05-21): 25.10.0 is the latest pre-26 LTS.
    # Nextflow 26.04+ became stricter about DSL2 (e.g. rejects top-level
    # `def` statements with "Statements cannot be mixed with script
    # declarations", and is pickier about Groovy heredoc parsing). 21 of
    # our workflows had to be rewritten today to satisfy 26.04. Rather
    # than chase every future breaking change, pin to 25.10 LTS which
    # accepts the older syntax cleanly. Bump deliberately, not by curl.
    EXPECTED_NF_VER="25.10.0"
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
  log "[db] Syncing Galaxy databases via S3..."
  local S3_PREFIX="s3://biomate-nextflow-work/dev-sync"

  # galaxy_ai_tools.db — 259MB, upload local→S3, EC2 pulls from S3
  local local_db="$REPO_ROOT/backend/database/galaxy_ai_tools.db"
  local local_db_mtime=$(stat -c %Y "$local_db" 2>/dev/null || echo 0)

  if [[ "$local_db_mtime" -gt "${LAST_DB_SYNC:-0}" ]]; then
    log "[db] galaxy_ai_tools.db changed ($(du -sh $local_db | cut -f1)) — uploading to S3..."
    aws s3 cp "$local_db" "${S3_PREFIX}/galaxy_ai_tools.db" --no-progress
    log "[db] S3 upload done — EC2 pulling..."

    ec2_ssh '
      docker stop biomate-galaxy-dev 2>/dev/null || true
      aws s3 cp s3://biomate-nextflow-work/dev-sync/galaxy_ai_tools.db \
        /tmp/galaxy_ai_tools_sync.db --no-progress
      docker cp /tmp/galaxy_ai_tools_sync.db \
        biomate-galaxy-dev:/app/database/galaxy_ai_tools.db
      docker exec -u root biomate-galaxy-dev chown galaxy:galaxy /app/database/galaxy_ai_tools.db
      docker start biomate-galaxy-dev
      sleep 5
      echo "[db] galaxy_ai_tools.db replaced"
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
    GPID=$(docker exec biomate-galaxy-dev cat /app/database/gravity/gunicorn.pid 2>/dev/null)
    if [[ -n "$GPID" ]]; then
      docker exec biomate-galaxy-dev sh -c "kill -HUP $GPID" 2>/dev/null && \
        echo "[galaxy] gunicorn HUP sent to PID $GPID" || \
        echo "[galaxy] HUP failed (non-fatal — workers will pick up files on next request)"
    else
      echo "[galaxy] gunicorn.pid not found — Galaxy may still be starting up"
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
# Layer 5: Marketing website (webpage_design/ → /var/www/biomate-marketing/)
# ---------------------------------------------------------------------------

deploy_marketing() {
  log "[marketing] Syncing webpage_design/ to /var/www/biomate-marketing/..."
  local tar_file="/tmp/biomate_marketing.tar.gz"
  tar -czf "$tar_file" -C "$REPO_ROOT" webpage_design/ 2>/dev/null
  log "[marketing] Archive: $(du -sh $tar_file | cut -f1)"

  ec2_scp "$tar_file" "${EC2_USER}@${EC2_HOST}:/tmp/marketing_sync.tar.gz"

  ec2_ssh '
    set -e
    sudo mkdir -p /var/www/biomate-marketing
    sudo tar -xzf /tmp/marketing_sync.tar.gz -C /tmp/marketing_extract --strip-components=1 2>/dev/null || \
      (mkdir -p /tmp/marketing_extract && tar -xzf /tmp/marketing_sync.tar.gz -C /tmp/marketing_extract)
    sudo rsync -a --delete /tmp/marketing_extract/webpage_design/ /var/www/biomate-marketing/ 2>/dev/null || \
      sudo cp -r /tmp/marketing_extract/webpage_design/. /var/www/biomate-marketing/
    sudo chown -R www-data:www-data /var/www/biomate-marketing/ 2>/dev/null || true
    rm -rf /tmp/marketing_extract
    echo "[marketing] Done — $(ls /var/www/biomate-marketing/*.html 2>/dev/null | wc -l) HTML files"
  '
  log "[marketing] Done"
}

do_sync() {
  local commit="$1"
  local changed_paths="$2"

  log "=== Syncing commit ${commit:0:8} ==="

  local do_frontend=false do_backend=false do_workflows=false do_db=false do_marketing=false

  # Determine what changed
  echo "$changed_paths" | grep -q "^frontend/" && do_frontend=true
  echo "$changed_paths" | grep -q "^backend/lib/" && do_backend=true
  echo "$changed_paths" | grep -q "^backend/biomni_workflows/" && do_workflows=true
  echo "$changed_paths" | grep -q "^backend/database/" && do_db=true
  echo "$changed_paths" | grep -q "^webpage_design/" && do_marketing=true

  # Always sync logo
  sync_logo 2>/dev/null || true

  # DB sync is also time-based (if local DB newer than last sync)
  local local_db_mtime=$(stat -c %Y "$REPO_ROOT/backend/database/galaxy_ai_tools.db" 2>/dev/null || echo 0)
  [[ "$local_db_mtime" -gt "${LAST_DB_SYNC:-0}" ]] && do_db=true

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
  $do_marketing && deploy_marketing

  log "=== Sync complete for ${commit:0:8} ==="
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
CHANGED="$(printf 'frontend/\nbackend/lib/\nbackend/biomni_workflows/\nbackend/database/\nwebpage_design/')"

if do_sync "$CURRENT_COMMIT" "$CHANGED"; then
  log "=== Sync OK at ${CURRENT_COMMIT:0:8} ==="
  log "Launching post-sync E2E tests in background..."
  bash "$REPO_ROOT/scripts/run_postsync_tests.sh" "$CURRENT_COMMIT" \
    >> /tmp/biomate_sync.log 2>&1 &
  exit 0
else
  log "ERROR: sync failed — see output above"
  exit 1
fi
