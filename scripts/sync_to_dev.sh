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
    docker stop biomate-dev-frontend 2>/dev/null || true
    docker rm -f biomate-dev-frontend 2>/dev/null || true
    # Ensure biotools base exists (built once, rarely rebuilt).
    if ! docker image inspect biomate-biotools:1 >/dev/null 2>&1; then
      echo "[frontend] Biotools base missing — building (this is slow, runs once)..."
      docker build -t biomate-biotools:1 \
        -f /opt/biomate/frontend_sync/frontend/Dockerfile.biotools \
        /opt/biomate/frontend_sync/frontend/ 2>&1 | tail -5
    fi
    echo "[frontend] Building app image..."
    if ! docker build -t biomate-dev-frontend:latest \
        -f /opt/biomate/frontend_sync/frontend/Dockerfile \
        /opt/biomate/frontend_sync/frontend/ 2>&1 | tail -5; then
      echo "[frontend] ERROR: app image build failed — keeping previous container running"
      docker run -d --name biomate-dev-frontend --network biomate-dev-net \
        -p 3000:3000 --env-file /opt/biomate/.env \
        -e NODE_ENV=production -e PORT=3000 -e FORCE_HTTPS=0 \
        --restart unless-stopped \
        biomate-dev-frontend:latest 2>/dev/null || true
      exit 1
    fi
    echo "[frontend] Restarting container..."
    sleep 1
    # Note: removed the /opt/biomate/dist_index.js volume mount + post-start docker cp.
    # That was a workaround from when image rebuilds were flaky and would override the
    # freshly-built bundle with a stale host file. Now that Dockerfile.biotools is split
    # and the app image rebuilds reliably, we use only the baked-in dist/.
    #
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
    docker exec biomate-galaxy-dev test -x /usr/local/bin/nextflow 2>/dev/null \
      || docker exec biomate-galaxy-dev bash -c "curl -fsSL https://get.nextflow.io | bash && mv nextflow /usr/local/bin/nextflow && chmod +x /usr/local/bin/nextflow" 2>&1 | tail -3
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
    # Copy workflows into Galaxy container
    docker cp /tmp/workflows_extract/backend/biomni_workflows \
      biomate-galaxy-dev:/app/biomni_workflows 2>/dev/null || \
    docker exec biomate-galaxy-dev mkdir -p /app/biomni_workflows && \
      docker cp /tmp/workflows_extract/backend/biomni_workflows/. \
        biomate-galaxy-dev:/app/biomni_workflows/ 2>/dev/null
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

  # universe.sqlite — 3.4MB, same pattern
  local universe_db="$REPO_ROOT/backend/database/universe.sqlite"
  if [[ -f "$universe_db" && $(stat -c %s "$universe_db") -gt 0 ]]; then
    log "[db] universe.sqlite — uploading to S3..."
    aws s3 cp "$universe_db" "${S3_PREFIX}/universe.sqlite" --no-progress
    ec2_ssh '
      docker stop biomate-galaxy-dev 2>/dev/null || true
      aws s3 cp s3://biomate-nextflow-work/dev-sync/universe.sqlite \
        /tmp/universe_sync.sqlite --no-progress
      docker cp /tmp/universe_sync.sqlite biomate-galaxy-dev:/app/database/universe.sqlite
      docker exec -u root biomate-galaxy-dev chown -R galaxy:galaxy /app/database/
      docker exec -u root biomate-galaxy-dev chmod 775 /app/database/
      docker start biomate-galaxy-dev
      sleep 5
      echo "[db] universe.sqlite replaced"
    ' || log "[db] universe.sqlite sync failed"
  fi

  log "[db] Done"
}

# ---------------------------------------------------------------------------
# Restart Galaxy after code changes
# ---------------------------------------------------------------------------

restart_galaxy() {
  log "[galaxy] Reloading Galaxy gunicorn workers (HUP)..."
  ec2_ssh '
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
  # Only restart Galaxy when backend Python changes — .nf files don't require Galaxy restart
  $do_backend && restart_galaxy
  $do_db        && deploy_databases
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
