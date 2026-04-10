#!/bin/bash
# sync_to_dev.sh — Watches for local commits and syncs ALL layers to dev-public.biomate.ai:
#   1. Frontend (React/Express) — Docker rebuild + restart
#   2. Backend Python files    — docker cp into running Galaxy container + restart
#   3. Galaxy databases        — galaxy_ai_tools.db (workflow search), universe.sqlite
#   4. Nextflow workflow files — .nf files in biomni_workflows/
#
# Usage: bash scripts/sync_to_dev.sh [--once]
# --once: run a single sync cycle then exit (useful for CI)
#
# Prerequisites: AWS CLI configured with ec2-instance-connect permissions

set -euo pipefail

INSTANCE_ID="i-06696b0d91f4346e0"
AZ="us-west-2a"
EC2_USER="ubuntu"
EC2_HOST="52.42.49.175"
KEY_FILE="/tmp/biomate_ec2_key_sync"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK_INTERVAL=600  # 10 minutes
RUN_ONCE="${1:-}"

LAST_DEPLOYED_COMMIT=""
LAST_DB_SYNC=""

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
    echo "[frontend] Building image..."
    docker build -t biomate-dev-frontend:latest \
      -f /opt/biomate/frontend_sync/frontend/Dockerfile \
      /opt/biomate/frontend_sync/frontend/ 2>&1 | tail -3
    echo "[frontend] Restarting container..."
    docker rm -f biomate-dev-frontend 2>/dev/null || true
    sleep 1
    docker run -d --name biomate-dev-frontend --network biomate-dev-net \
      -p 3000:3000 --env-file /opt/biomate/.env \
      -e NODE_ENV=production -e PORT=3000 -e FORCE_HTTPS=0 \
      --restart unless-stopped \
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
      docker exec -u root biomate-galaxy-dev chown galaxy:galaxy /app/database/universe.sqlite
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
  local local_db_mtime=$(stat -c %Y "$REPO_ROOT/backend/database/galaxy_ai_tools.db" 2>/dev/null || echo 0)
  [[ "$local_db_mtime" -gt "${LAST_DB_SYNC:-0}" ]] && do_db=true

  $do_backend   && deploy_backend_python
  $do_workflows && deploy_workflows
  # Only restart Galaxy when backend Python changes — .nf files don't require Galaxy restart
  $do_backend && restart_galaxy
  $do_db        && deploy_databases
  $do_frontend  && deploy_frontend

  log "=== Sync complete for ${commit:0:8} ==="
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

log "BioMate dev sync starting (repo: $REPO_ROOT)"
log "Layers: frontend + backend Python + workflows + databases"
log "Interval: ${CHECK_INTERVAL}s | Target: https://dev-public.biomate.ai"

# First run: sync everything regardless
FORCE_FULL=true

while true; do
  CURRENT_COMMIT=$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || echo "")

  if [[ -z "$CURRENT_COMMIT" ]]; then
    log "ERROR: not a git repo"
    sleep "$CHECK_INTERVAL"
    continue
  fi

  if $FORCE_FULL || [[ "$CURRENT_COMMIT" != "$LAST_DEPLOYED_COMMIT" ]]; then
    if $FORCE_FULL; then
      CHANGED="$(printf 'frontend/\nbackend/lib/\nbackend/biomni_workflows/\nbackend/database/')"
      FORCE_FULL=false
    else
      CHANGED=$(git -C "$REPO_ROOT" diff --name-only \
        "$LAST_DEPLOYED_COMMIT" "$CURRENT_COMMIT" 2>/dev/null || echo "frontend/ backend/")
      log "Changes since last deploy: $(echo "$CHANGED" | wc -l) files"
    fi

    if do_sync "$CURRENT_COMMIT" "$CHANGED"; then
      LAST_DEPLOYED_COMMIT="$CURRENT_COMMIT"
      log "Running post-sync E2E tests..."
      bash "$REPO_ROOT/scripts/run_postsync_tests.sh" "$CURRENT_COMMIT" \
        >> /tmp/biomate_sync.log 2>&1 &
    else
      log "Sync failed — will retry next cycle"
    fi
  else
    # Check if DB changed even without a new commit
    local_db_mtime=$(stat -c %Y "$REPO_ROOT/backend/database/galaxy_ai_tools.db" 2>/dev/null || echo 0)
    if [[ "$local_db_mtime" -gt "${LAST_DB_SYNC:-0}" ]]; then
      log "DB changed outside git — syncing..."
      deploy_databases
      LAST_DB_SYNC="$local_db_mtime"
    fi

    # Also sync uncommitted edits (dirty working tree) so live testing sees latest code
    DIRTY=$(git -C "$REPO_ROOT" diff --name-only HEAD 2>/dev/null | grep -E "^(frontend/|backend/lib/|backend/biomni_workflows/)" || true)
    if [[ -n "$DIRTY" ]]; then
      dirty_count=$(echo "$DIRTY" | wc -l)
      log "Dirty working tree: ${dirty_count} file(s) — syncing uncommitted edits..."
      if do_sync "$CURRENT_COMMIT-dirty" "$DIRTY"; then
        log "Running post-sync E2E tests (dirty)..."
        bash "$REPO_ROOT/scripts/run_postsync_tests.sh" "${CURRENT_COMMIT}-dirty" \
          >> /tmp/biomate_sync.log 2>&1 &
      else
        log "Dirty sync failed — will retry next cycle"
      fi
    else
      log "No changes (${CURRENT_COMMIT:0:8}) — sleeping ${CHECK_INTERVAL}s"
    fi
  fi

  [[ "$RUN_ONCE" == "--once" ]] && exit 0
  sleep "$CHECK_INTERVAL"
done
