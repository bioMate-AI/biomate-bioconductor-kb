#!/bin/bash
# sync_to_dev.sh — MANUAL one-shot sync of ALL layers to dev-public.biomate.ai:
#   1. Frontend (React/Express) — Docker rebuild + restart
#   2. Backend Python files    — docker cp into running Galaxy container + restart
#   3. Galaxy databases        — galaxy_ai_tools.db (workflow search); universe.sqlite (dev's live
#                                Galaxy DB) only with BIOMATE_REPLACE_GALAXY_DB=1, backed up first
#   4. Nextflow workflow files — .nf files in biomni_workflows/ + nf-core-workflows/modules/biomate-ai-tools/
#
# NOTE: Marketing website (webpage_design_v2/) is NOT synced here.
#       Use scripts/deploy_marketing.sh instead.
#
# NOTE: Marketing website (webpage_design_v2/) is NOT synced here.
#       Use scripts/deploy_marketing.sh instead.
#
# Usage: bash scripts/sync_to_dev.sh
#        BIOMATE_SYNC_FORCE=frontend,backend bash scripts/sync_to_dev.sh   (re-deploy layers with no change)
#        BIOMATE_SYNC_DB=0 bash scripts/sync_to_dev.sh   (code/workflows only — never upload galaxy_ai_tools.db)
#
# HOT-PATCH FORBIDDEN: do not docker cp / S3-drop files onto DEV outside this script
# unless immediately followed by a ledger-correcting sync_to_dev.sh run. Ad-hoc
# hot-patches leave /opt/biomate/.deploy-ledger.jsonl lying (2026-11-13). See
# docs/20261113_COMMIT_PR_SYNC_PROCESS.md (one-writer rule + recovery).
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

# Ensure session-manager-plugin is in PATH (installed to ~/bin on this machine)
export PATH="/Users/kky/bin:$PATH"

INSTANCE_ID="i-06696b0d91f4346e0"
AZ="us-west-2a"
EC2_USER="ubuntu"
EC2_HOST="52.42.49.175"
KEY_FILE="/tmp/biomate_ec2_key_sync"

# SSM session-manager-plugin — needed by ProxyCommand below.
# We install it user-local so no sudo is required.
export PATH="$HOME/bin:$PATH"
if ! command -v session-manager-plugin &>/dev/null; then
  _ARCH=$(uname -m)
  _SSM_URL="https://s3.amazonaws.com/session-manager-downloads/plugin/latest/mac_arm64/sessionmanager-bundle.zip"
  [[ "$_ARCH" != "arm64" ]] && _SSM_URL="https://s3.amazonaws.com/session-manager-downloads/plugin/latest/mac/sessionmanager-bundle.zip"
  curl -sSL "$_SSM_URL" -o /tmp/ssm-bundle.zip 2>/dev/null && \
    unzip -qo /tmp/ssm-bundle.zip -d /tmp/ssm-bundle/ 2>/dev/null && \
    cp /tmp/ssm-bundle/sessionmanager-bundle/bin/session-manager-plugin "$HOME/bin/" && \
    chmod +x "$HOME/bin/session-manager-plugin" && \
    log "[ssm] session-manager-plugin installed to ~/bin"
fi

# SSH/SCP ProxyCommand — routes all connections through AWS SSM so that
# port 22 does not need to be open in the security group.
_SSM_PROXY="aws ssm start-session --target ${INSTANCE_ID} --document-name AWS-StartSSHSession --parameters portNumber=%p --region us-west-2"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Guard helpers (proxy / local lock / DB decision / receipt) — unit-tested in
# scripts/tests/test_sync_guards.sh
# shellcheck source=lib/sync_guards.sh
source "$REPO_ROOT/scripts/lib/sync_guards.sh"

# Cursor sandbox (and some corporate MITM setups) inject HTTP_PROXY=http://127.0.0.1:…
# which breaks AWS SSM Session Manager. Clear loopback proxies before any aws/ssm call.
# Set BIOMATE_STRICT_PROXY=1 to refuse instead of auto-unsetting.
if ! biomate_guard_loopback_proxy; then
  exit 2
fi

# Guard against accidentally running multiple syncs at once (per Lessons L7).
# Multi-worktree: panelfix / nextphase / review / coldstart share this lock path
# on one machine; remote lease covers cross-machine writers.
LOCK_FILE="/tmp/biomate_sync_to_dev.lock"
biomate_acquire_local_sync_lock "$LOCK_FILE" || exit 1

log() { echo "[$(date '+%H:%M:%S')] $*"; }

# --- Deploy notification (SNS) + consolidated cleanup -----------------------
# Previously the only EXIT trap removed the lock file — and resync_galaxy_env
# later REPLACED it with a LIVE_ENV cleanup (trap ... EXIT clobbers), silently
# dropping lock removal. Consolidate both into one handler and add an SNS
# notification so a failed dev sync is no longer silent.
#
# ROLLBACK: dev sync is in-place file hot-patch + gunicorn HUP, not an image-tag
# swap. Galaxy persists /app/database via the galaxy_db host bind; `docker commit`
# captures hot-patched code/workflows/config, while rollback preserves that bind. The
# frontend keeps its own image tags. A post-sync health gate (snapshot_for_rollback
# / postsync_health_ok / rollback_sync below) recreates both containers from those
# snapshots if dev is unhealthy after the sync.
AWS_REGION="${AWS_REGION:-us-west-2}"
SNS_TOPIC_ARN="${SNS_TOPIC_ARN:-arn:aws:sns:$AWS_REGION:399683337364:biomate-deploy-events}"
CLEANUP_FILES=""        # space-separated temp files to rm on exit (append, don't re-trap)
REMOTE_SYNC_LEASE=""
REMOTE_SYNC_LEASE_ACQUIRED=0
SYNC_STARTED=0          # set to 1 once we enter do_sync; gates the notification
CURRENT_COMMIT=""       # populated at the entry point; referenced by notify_sync
SYNC_RESULT=""          # healthy|rolled_back|rollback_failed|failed — set by do_sync, read by notify_sync
ROLLBACK_READY=0        # 1 once the pre-sync snapshot is taken
RB_SNAPSHOT_FRONTEND=0  # 1 if the frontend image was snapshotted this run
RB_GALAXY_IMAGE="biomate-galaxy-dev:rollback"   # snapshot tag (overwritten each run)

# Persistent host directory that survives container recreation.
# Mounted at /app/database inside every Galaxy container so the DB is never
# wiped when the container is recreated from an older image.
GALAXY_DB_HOST_PATH="/opt/biomate/galaxy_db"

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
  if [[ "$REMOTE_SYNC_LEASE_ACQUIRED" == "1" ]]; then
    ec2_ssh "test \$(cat /opt/biomate/.dev-deploy.lock/owner) = '$REMOTE_SYNC_LEASE' && rm /opt/biomate/.dev-deploy.lock/owner && rmdir /opt/biomate/.dev-deploy.lock" >/dev/null 2>&1 || true
  fi
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
  ssh -i "$KEY_FILE" \
    -o ProxyCommand="$_SSM_PROXY" \
    -o StrictHostKeyChecking=no -o ConnectTimeout=30 -o IdentitiesOnly=yes \
    -o ServerAliveInterval=30 -o ServerAliveCountMax=4 \
    "${EC2_USER}@${INSTANCE_ID}" "$@"
}

ec2_scp() {
  inject_key > /dev/null
  scp -i "$KEY_FILE" \
    -o ProxyCommand="$_SSM_PROXY" \
    -o StrictHostKeyChecking=no -o ConnectTimeout=30 -o IdentitiesOnly=yes \
    -o ServerAliveInterval=30 -o ServerAliveCountMax=100 "$@"
}

# ---------------------------------------------------------------------------
# Layer 1: Frontend (full Docker rebuild)
# ---------------------------------------------------------------------------

# PostgreSQL migrations have one owner: the frontend startup runner applies
# pending SQL and ledger updates transactionally before routes register. The
# existing post-start health/rollback gate rejects a failed migration startup.

deploy_frontend() {
  log "[frontend] Building archive..."
  local tar_file="/tmp/biomate_frontend_sync.tar.gz"
  # COPYFILE_DISABLE=1 suppresses macOS ._* resource-fork files from the archive.
  # Without it, tar on macOS silently includes binary ._0018_*.sql files in
  # migrations/, which the boot-time migration runner picks up and sends to PG
  # as SQL — PG rejects with "invalid message format" and the container crashes.
  COPYFILE_DISABLE=1 tar -czf "$tar_file" \
    --exclude='frontend/data/uploads' \
    --exclude='frontend/e2e/screenshots' \
    --exclude='frontend/e2e/reports' \
    --exclude='frontend/node_modules' \
    --exclude='._*' \
    -C "$REPO_ROOT" \
    frontend/client/ frontend/server/ frontend/shared/ frontend/attached_assets/ \
    frontend/migrations/ \
    frontend/package.json frontend/package-lock.json \
    frontend/tsconfig.json frontend/tsconfig.node.json frontend/vite.config.ts \
    frontend/tailwind.config.js frontend/postcss.config.js \
    frontend/Dockerfile frontend/Dockerfile.biotools frontend/Dockerfile.runcode frontend/sandbox/ 2>/dev/null
  log "[frontend] Archive: $(du -sh $tar_file | cut -f1)"

  # NOTE: deploy_frontend runs with set -e DISABLED — do_sync is invoked as
  # `if do_sync ...` (bottom of file), which suppresses errexit for the entire
  # call tree. So every remote step here MUST check its own exit code; a bare
  # command that fails will otherwise be swallowed and the sync will falsely
  # report "healthy" on the OLD container (2026-09-13 silent-fail incident:
  # the archive scp dropped on a flaky SSM link, nothing deployed, yet
  # [frontend] Done printed and the last-synced marker advanced).
  if ! ec2_scp "$tar_file" "${EC2_USER}@${EC2_HOST}:/tmp/frontend_sync.tar.gz"; then
    log "[frontend] ERROR: archive upload (scp) failed — remote link down; aborting frontend deploy (old container still serving, marker NOT advanced)"
    return 1
  fi

  if ! ec2_ssh '
    set -e
    # Use sudo for the staging-dir wipe: a prior sync (or a root docker step)
    # can leave root-owned files under /opt/biomate/frontend_sync (observed
    # 2026-10-11: research_agent_v2/* owned by root -> `rm` Permission denied
    # -> tar "Cannot open: File exists" -> frontend build aborted). sudo rm
    # guarantees a clean staging dir; the fresh mkdir is then owned by $USER.
    sudo rm -rf /opt/biomate/frontend_sync 2>/dev/null || rm -rf /opt/biomate/frontend_sync
    mkdir -p /opt/biomate/frontend_sync
    tar -xzf /tmp/frontend_sync.tar.gz -C /opt/biomate/frontend_sync
    # Prune dangling images, and cap (not wipe) the build cache, to prevent disk-full build failures.
    # A full `docker builder prune -f` here threw away the npm ci + apt layers before every build:
    # ~234 s of a ~6.7 min frontend deploy re-installed unchanged dependencies (sync of 2026-11-04).
    # With the cache capped at 6 GB those layers are reused while package-lock.json is unchanged.
    docker image prune -f > /dev/null 2>&1 || true
    docker builder prune -f --max-used-space 6gb > /dev/null 2>&1 || docker builder prune -f > /dev/null 2>&1 || true

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
    # run_code sandbox = biotools + CJK fonts + matplotlib defaults (thin layer, fast).
    if ! docker image inspect biomate-runcode:3 >/dev/null 2>&1; then
      echo "[frontend] run_code sandbox image missing — building biomate-runcode:3..."
      docker build -t biomate-runcode:3 \
        -f /opt/biomate/frontend_sync/frontend/Dockerfile.runcode \
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
        --build-arg BUILD_COMMIT='"${CURRENT_COMMIT}"' \
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
    # Interactive Tools (Jupyter/RStudio/CellxGene) are launchable ONLY when the
    # Galaxy container actually has the host docker socket (ITs spawn docker child
    # containers). Derive INTERACTIVE_TOOLS_ENABLED from the LIVE Galaxy container so
    # the UI advertises the IT buttons exactly when they will work: set to 1 once the
    # socket is enabled, and auto-cleared to 0 on the next frontend deploy if a
    # rollback (or any recreate) ever drops the socket — no manual flag to keep in
    # sync. /api/interactive/available gates on this; see routes.ts.
    if docker inspect biomate-galaxy-dev --format "{{range .Mounts}}{{.Destination}} {{end}}" 2>/dev/null | grep -q "/var/run/docker.sock"; then
      IT_ENABLED=1
    else
      IT_ENABLED=0
    fi
    echo "[frontend] INTERACTIVE_TOOLS_ENABLED=$IT_ENABLED (derived from Galaxy docker-socket mount)"
    docker run -d --name biomate-dev-frontend --network biomate-dev-net \
      -p 3000:3000 --env-file /opt/biomate/.env \
      -e NODE_ENV=production -e PORT=3000 -e FORCE_HTTPS=0 \
      -e MCP_UPSTREAM_URL=http://biomate-remote-mcp:8848 \
      -e BIOMATE_RESPONSE_MODEL=gpt-5.6-luna \
      -e INTERACTIVE_TOOLS_ENABLED="$IT_ENABLED" \
      --restart unless-stopped \
      -v /var/run/docker.sock:/var/run/docker.sock \
      -v /tmp/biomate_code:/tmp/biomate_code \
      biomate-dev-frontend:latest
    sleep 5
    # Restore logo (not baked into image — uploaded separately)
    docker cp /tmp/logo_sync.png biomate-dev-frontend:/app/dist/public/logo.png 2>/dev/null || true
    docker ps --format "  {{.Names}}: {{.Status}}" | grep biomate-dev-frontend
  '; then
    log "[frontend] ERROR: remote build/swap step failed or SSH connection dropped mid-deploy — aborting frontend deploy (marker NOT advanced)"
    return 1
  fi

  # Post-swap freshness verification. The steps above can each fail; the
  # rc checks catch a hard failure, but a dropped/re-established SSM tunnel
  # can also leave the OLD container in place while every command appears to
  # have "run". So independently confirm the container now serving was created
  # by THIS deploy: its creation time must be recent. A stale image means the
  # fresh code did NOT go live — fail loudly rather than record a false success.
  local _age
  _age=$(ec2_ssh 'c=$(docker inspect biomate-dev-frontend --format "{{.Created}}" 2>/dev/null); if [ -n "$c" ]; then echo $(( $(date +%s) - $(date -d "$c" +%s) )); else echo missing; fi' 2>/dev/null | tr -d "[:space:]")
  if ! [[ "$_age" =~ ^[0-9]+$ ]] || [[ "$_age" -gt 900 ]]; then
    log "[frontend] ERROR: post-deploy verification failed — running container image age='${_age:-?}'s (expected < 900s). Fresh code is NOT live; aborting (marker NOT advanced)."
    return 1
  fi
  # Verify the actual public bundle, not only a newly-created container.
  # Worktrees may contain different branches while all produce healthy images.
  local _served_commit
  if ! _served_commit="$(curl --fail --silent --show-error --retry 10 --retry-all-errors --retry-delay 2 --retry-max-time 60 --max-time 10 \
      "https://dev-public.biomate.ai/build-info.json?commit=${CURRENT_COMMIT}" | \
      python3 -c 'import json,sys; print(json.load(sys.stdin).get("commit", ""))')" \
      || [[ "$_served_commit" != "$CURRENT_COMMIT" ]]; then
    log "[frontend] ERROR: public build commit '${_served_commit:-missing}' does not match ${CURRENT_COMMIT}; marker NOT advanced"
    return 1
  fi
  log "[frontend] verified public build commit ${_served_commit}"
  log "[frontend] verified fresh container (image age ${_age}s)"
  log "[frontend] Done"
}

# ---------------------------------------------------------------------------
# Layer 1b: remote_mcp — the Streamable-HTTP MCP transport, as its OWN
# supervised container (restart=always) on biomate-dev-net, reachable by the
# frontend /mcp proxy via Docker DNS (biomate-remote-mcp:8848). This is the
# root-cause fix for "/mcp keeps 502-ing": the service was never deployed or
# supervised — not in this script, not a systemd unit, and it could not run in
# the Node-only frontend container the proxy's 127.0.0.1:8848 pointed at.
# Lives in the separate biomate-connector repo (set CONNECTOR_REPO to override).
# See docs/20260723_CONNECTOR_CONTRACT_TEST_AND_STABILITY.md.
# ---------------------------------------------------------------------------

deploy_remote_mcp() {
  local connrepo="${CONNECTOR_REPO:-$(cd "$REPO_ROOT/.." && pwd)/biomate-connector}"
  if [[ ! -f "$connrepo/Dockerfile.remote_mcp" ]]; then
    log "[remote_mcp] connector repo / Dockerfile.remote_mcp not found at $connrepo — SKIPPING (set CONNECTOR_REPO). /mcp stays down until deployed."
    return 0
  fi
  log "[remote_mcp] Packaging remote_mcp from $connrepo ..."
  local tar_file="/tmp/biomate_remote_mcp_sync.tar.gz"
  COPYFILE_DISABLE=1 tar -czf "$tar_file" -C "$connrepo" \
    --exclude '.git' --exclude '__pycache__' --exclude '*.pyc' --exclude 'node_modules' \
    Dockerfile.remote_mcp remote_mcp mcp oauth_server biomate_connector
  log "[remote_mcp] Archive: $(du -sh "$tar_file" | cut -f1)"
  ec2_scp "$tar_file" "${EC2_USER}@${EC2_HOST}:/tmp/remote_mcp_sync.tar.gz"
  ec2_ssh '
    set -e
    rm -rf /opt/biomate/remote_mcp_sync && mkdir -p /opt/biomate/remote_mcp_sync
    tar -xzf /tmp/remote_mcp_sync.tar.gz -C /opt/biomate/remote_mcp_sync
    cd /opt/biomate/remote_mcp_sync
    # Persist a signing key ONCE (not committed) so OAuth tokens + stored API keys
    # survive container/host restarts. Only consumed at runtime, never at import.
    KEYFILE=/opt/biomate/remote_mcp_signing.key
    [ -s "$KEYFILE" ] || python3 -c "import secrets;print(secrets.token_urlsafe(64))" > "$KEYFILE"
    SIGNING_KEY=$(cat "$KEYFILE")
    mkdir -p /opt/biomate/remote_mcp_data
    echo "[remote_mcp] building image (build-time import guard runs here)..."
    if ! docker build -t biomate-remote-mcp:latest -f Dockerfile.remote_mcp . 2>&1 | tail -8; then
      echo "[remote_mcp] BUILD FAILED"; exit 1
    fi
    docker rm -f biomate-remote-mcp 2>/dev/null || true
    docker run -d --name biomate-remote-mcp --network biomate-dev-net \
      --restart unless-stopped \
      -e BIOMATE_MCP_HOST=0.0.0.0 -e BIOMATE_MCP_PORT=8848 \
      -e BIOMATE_API_URL=http://biomate-dev-frontend:3000 \
      -e BIOMATE_MCP_PUBLIC_URL=https://dev-public.biomate.ai \
      -e BIOMATE_OAUTH_ISSUER=https://dev-public.biomate.ai \
      -e BIOMATE_MCP_REQUIRE_AUTH=1 \
      -e BIOMATE_OAUTH_SIGNING_KEY="$SIGNING_KEY" \
      -e BIOMATE_OAUTH_DB=/var/lib/biomate/oauth.db \
      -v /opt/biomate/remote_mcp_data:/var/lib/biomate \
      biomate-remote-mcp:latest
    # Startup check — the container must reach "healthy" (uvicorn bound :8848),
    # not crash-loop. Dump logs (ground truth) on failure so we see the reason.
    ok=0; st=""; hs=""
    for i in $(seq 1 15); do
      sleep 3
      st=$(docker inspect -f "{{.State.Status}}" biomate-remote-mcp 2>/dev/null)
      hs=$(docker inspect -f "{{if .State.Health}}{{.State.Health.Status}}{{end}}" biomate-remote-mcp 2>/dev/null)
      [ "$st" != "running" ] && break
      [ "$hs" = "healthy" ] && { ok=1; break; }
    done
    if [ "$ok" != 1 ]; then
      echo "[remote_mcp] STARTUP CHECK FAILED (status=$st health=$hs) — container logs:"
      docker logs --tail 40 biomate-remote-mcp 2>&1 || true
      exit 1
    fi
    # End-to-end: the frontend /mcp proxy must now reach the container (not 502).
    code=$(curl -s -o /dev/null -w "%{http_code}" -m 8 -X POST http://localhost:3000/mcp \
      -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" \
      -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\"}" 2>/dev/null || echo "000")
    echo "[remote_mcp] frontend /mcp -> HTTP $code (container status=$st health=$hs)"
    docker ps --format "  {{.Names}}: {{.Status}}" | grep biomate-remote-mcp || true
  '
  log "[remote_mcp] Done"
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
  log "[galaxy.yml] Shipping $(stat -c %s $src 2>/dev/null || stat -f %z $src 2>/dev/null || echo ?) bytes..."
  ec2_scp "$src" "${EC2_USER}@${EC2_HOST}:/tmp/galaxy.yml"

  # Sync interactivetools_conf.xml BEFORE the gunicorn restart below.
  # galaxy.yml.docker references interactivetools_conf.xml in tool_config_file;
  # Galaxy reads tool_config_file at startup — if the file is missing when gunicorn
  # restarts, Galaxy crashes. Copy it first so both files land before the restart.
  # (Registers Jupyter, RStudio, CellxGene in Galaxy's tool panel; not covered by
  # the Python file diff sync.)
  local it_src="$REPO_ROOT/backend/config/interactivetools_conf.xml"
  if [[ -f "$it_src" ]]; then
    ec2_scp "$it_src" "${EC2_USER}@${EC2_HOST}:/tmp/interactivetools_conf.xml"
    ec2_ssh 'GC=$(docker ps --filter "name=biomate-galaxy" --format "{{.Names}}" | grep -Ev "rollback|chatgpt" | head -1); GC="${GC:-biomate-galaxy-dev}"; docker cp /tmp/interactivetools_conf.xml "$GC:/app/config/interactivetools_conf.xml"'
    log "[galaxy.yml] interactivetools_conf.xml staged"
  fi

  # Sync llm_providers.yml BEFORE the gunicorn restart too. The LLM fallback
  # chain (FallbackChainManager) reads /app/config/llm_providers.yml at import;
  # it controls per-provider retry_attempts + timeout_seconds. NOT covered by
  # the Python file diff sync (it is a .yml under backend/config/, not backend/lib/),
  # so without this the container keeps the image-baked config and latency fixes
  # (retry 2->1, timeout 120->30) never reach dev. Caught 2026-07-10: workflow
  # generation hung >120s on dev while the fix sat only in llm_providers.yml.
  local llm_src="$REPO_ROOT/backend/config/llm_providers.yml"
  if [[ -f "$llm_src" ]]; then
    ec2_scp "$llm_src" "${EC2_USER}@${EC2_HOST}:/tmp/llm_providers.yml"
    ec2_ssh 'GC=$(docker ps --filter "name=biomate-galaxy" --format "{{.Names}}" | grep -Ev "rollback|chatgpt" | head -1); GC="${GC:-biomate-galaxy-dev}"; docker cp /tmp/llm_providers.yml "$GC:/app/config/llm_providers.yml"'
    log "[galaxy.yml] llm_providers.yml staged"
  fi

  # Sync job_conf.yml BEFORE the gunicorn restart too. galaxy.yml sets
  # job_config_file: config/job_conf.yml — it controls tool→destination routing.
  # NOT covered by the Python file diff sync (a .yml under backend/config/), so
  # without this the container keeps the image-baked job_conf and routing changes
  # never reach dev. Caught 2026-08-11: upload1/__DATA_FETCH__ defaulted to a docker
  # destination the Galaxy container can't run ("docker: command not found"), so
  # every uploaded/fetched dataset landed in state=error, size=0 (empty HDA).
  local jc_src="$REPO_ROOT/backend/config/job_conf.yml"
  if [[ -f "$jc_src" ]]; then
    ec2_scp "$jc_src" "${EC2_USER}@${EC2_HOST}:/tmp/job_conf.yml"
    ec2_ssh 'GC=$(docker ps --filter "name=biomate-galaxy" --format "{{.Names}}" | grep -Ev "rollback|chatgpt" | head -1); GC="${GC:-biomate-galaxy-dev}"; docker cp /tmp/job_conf.yml "$GC:/app/config/job_conf.yml"'
    log "[galaxy.yml] job_conf.yml staged"
  fi

  ec2_ssh '
    set -e
    GC=$(docker ps --filter "name=biomate-galaxy" --format "{{.Names}}" | grep -Ev "rollback|chatgpt" | head -1)
    GC="${GC:-biomate-galaxy-dev}"
    docker cp /tmp/galaxy.yml "$GC:/app/config/galaxy.yml"
    # Verify the bind is correct (catch any future regression)
    BIND=$(docker exec "$GC" grep -E "^[[:space:]]+bind:" /app/config/galaxy.yml | head -1 | tr -d " ")
    echo "[galaxy.yml] applied; bind = ${BIND}"
    # Reload gunicorn so it picks up the new config (both galaxy.yml + interactivetools_conf.xml are now in place)
    docker exec "$GC" galaxyctl restart gunicorn 2>&1 | tail -1
  '
  log "[galaxy.yml] Done"
}

# ---------------------------------------------------------------------------
# Real nf-core pipelines (backend/nf-core-workflows/<name>/main.nf)
# ---------------------------------------------------------------------------
# The downloaded pipelines are git-ignored (only modules/ is tracked) and are not part of any synced
# layer, and the running Galaxy image is a docker-commit chain of containers that lacked them — so on
# 2026-11-04 the container had 0 of the 137 real pipelines present on the host, every catalog
# nf-core/* run failed at submit ("Could not resolve Nextflow script 'nfcore/<name>/main.nf'"), and
# the resolver fell back to display-only stubs. Every sync now restores any that are missing from the
# host copy (additive; nothing in the container is removed). Cheap no-op when all are present.
NFCORE_PIPELINES_HOST_DIR="/opt/biomate/galaxy_build/nf-core-workflows"
NFCORE_MODULES_HOST_DIR="/opt/biomate/galaxy_build/nf-core-modules"
validate_sync_inputs() {
  # Validate the current checkout before snapshots, container copies or env changes.
  if $do_backend || $do_workflows; then
    [[ -d "$REPO_ROOT/infra/nfcore-patches" ]] || { log "[preflight] FATAL: infra/nfcore-patches missing from checkout"; return 1; }
    [[ -f "$REPO_ROOT/infra/nfcore-patches/dualrnaseq/1.0.0.patch" ]] || { log "[preflight] FATAL: required dualrnaseq patch is missing"; return 1; }
  fi
  if $do_workflows; then
    local required
    for required in backend/biomni_workflows backend/nf-core-workflows/modules/biomate-ai-tools backend/nf-core-modules; do
      [[ -d "$REPO_ROOT/$required" ]] || { log "[preflight] FATAL: workflow source directory missing: $required"; return 1; }
    done
  fi
}

ensure_nfcore_pipelines() {
  log "[nfcore] Checking real nf-core pipelines in the Galaxy container..."
  # BioMate patches to pinned nf-core releases (infra/nfcore-patches/<pipeline>/<version>.patch):
  # shipped to the host and applied to the host source below, so the container copy carries them.
  local patch_tgz remote_patch_tgz patch_sha
  patch_tgz=$(mktemp /tmp/biomate_nfcore_patches.XXXXXX) || return 1
  remote_patch_tgz="/tmp/${patch_tgz##*/}.tar.gz"
  if ! tar -czf "$patch_tgz" -C "$REPO_ROOT/infra" nfcore-patches; then
    rm -f "$patch_tgz"; log "[nfcore] FATAL: could not create patch archive"; return 1
  fi
  patch_sha=$(shasum -a 256 "$patch_tgz" | cut -d ' ' -f 1)
  if ! ec2_scp "$patch_tgz" "${EC2_USER}@${EC2_HOST}:$remote_patch_tgz"; then
    rm -f "$patch_tgz"; log "[nfcore] FATAL: could not upload current patch archive"; return 1
  fi
  rm -f "$patch_tgz"
  ec2_ssh "NFCORE_SRC=${NFCORE_PIPELINES_HOST_DIR} NFCORE_PATCH_TGZ=$remote_patch_tgz NFCORE_PATCH_SHA=$patch_sha bash -s" <<'REMOTE'
set -e
# Verify this exact invocation's archive before modifying any pipeline source.
[ -n "$NFCORE_PATCH_TGZ" ] && [ -f "$NFCORE_PATCH_TGZ" ] || { echo "[nfcore] FATAL: current patch archive missing" >&2; exit 1; }
[ "$(sha256sum "$NFCORE_PATCH_TGZ" | cut -d ' ' -f 1)" = "$NFCORE_PATCH_SHA" ] || { echo "[nfcore] FATAL: patch archive checksum mismatch" >&2; exit 1; }
PD=$(mktemp -d /tmp/nfcore_patches.XXXXXX)
trap 'rm -f "$NFCORE_PATCH_TGZ"; rm -rf "$PD"' EXIT
tar -xzf "$NFCORE_PATCH_TGZ" -C "$PD"
[ -f "$PD/nfcore-patches/dualrnaseq/1.0.0.patch" ] || { echo "[nfcore] FATAL: required patch missing from archive" >&2; exit 1; }
GC=$(docker ps --filter "name=biomate-galaxy" --format "{{.Names}}" | grep -Ev "rollback|chatgpt" | head -1)
GC="${GC:-biomate-galaxy-dev}"
if [ ! -d "$NFCORE_SRC" ]; then echo "[nfcore] FATAL: host copy $NFCORE_SRC missing — cannot restore pipelines" >&2; exit 1; fi
# A pipeline is INCOMPLETE when its nextflow.config includes conf/base.config (the unconditional include every
# nf-core pipeline loads) and that file does not exist. 125 of 137 host copies held only top-level files
# (main.nf, nextflow.config, README — no conf/, modules/, workflows/), so every run failed at config parse
# ("Config file does not exist: …/conf/base.config", 2026-11-05). Only base.config is checked: profile-scoped
# includes may legitimately be absent upstream (eager test_bam, viralrecon test_full_sispa, …).
incomplete() {  # $1 = pipeline dir
  local c="$1/nextflow.config"
  [ -f "$c" ] || return 1
  grep -qE "includeConfig +['\"]conf/base\.config['\"]" "$c" && [ ! -f "$1/conf/base.config" ]
}
# 1) complete the host source from nf-core's own repositories, PINNED to the version the catalog was built
#    against (manifest.version of the original 2025-10-30 download). The default branch is the latest release —
#    on 2026-11-05 that moved 53 pipelines to other versions (ampliseq 2.16→3.1, pixelator 3→6, …), many needing
#    Nextflow ≥ 26.04 while the container runs 25.10.x. The pins file records the intended version once.
mver() { grep -oE "^\s*version\s*=\s*['\"][^'\"]+['\"]" "$1/nextflow.config" 2>/dev/null | head -1 | sed -E "s/.*['\"]([^'\"]+)['\"].*/\1/"; }
nfreq() { grep -oE "nextflowVersion\s*=\s*['\"][^'\"]+['\"]" "$1/nextflow.config" 2>/dev/null | head -1 | grep -oE "[0-9]+\.[0-9]+(\.[0-9]+)?"; }
NF_HAVE=$(docker exec "$GC" sh -c 'nextflow -version 2>/dev/null' | grep -oE "version [0-9]+\.[0-9]+\.[0-9]+" | head -1 | cut -d" " -f2)
ver_le() { [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" = "$1" ]; }   # $1 <= $2
PINS="$NFCORE_SRC/.pinned_versions"
if [ ! -f "$PINS" ]; then   # first run: original versions — from the backup of a replaced copy, else the copy itself
  for d in "$NFCORE_SRC"/*/; do
    n=$(basename "$d"); case "$n" in modules|*.incomplete_*|.fetch_*) continue ;; esac; [ -f "$d/main.nf" ] || continue
    b=$(ls -d "$NFCORE_SRC/$n".incomplete_* 2>/dev/null | head -1)
    v=$(mver "${b:-$d}"); [ -n "$v" ] && echo "$n $v"
  done > "$PINS"
fi
refetched=0; refetch_failed=""
for d in "$NFCORE_SRC"/*/; do
  n=$(basename "$d"); [ "$n" = modules ] && continue; [ -f "$d/main.nf" ] || continue
  case "$n" in *.incomplete_*|.fetch_*) continue ;; esac   # backups of replaced copies, not pipelines
  pin=$(awk -v n="$n" '$1==n{print $2}' "$PINS")
  cur=$(mver "$d")
  if incomplete "$d" || { [ -n "$pin" ] && [ "$cur" != "$pin" ]; }; then
    tmp="$NFCORE_SRC/.fetch_$n"; rm -rf "$tmp"; ok=0
    if [ -n "$pin" ] && timeout 300 git clone -q --depth 1 --branch "$pin" "https://github.com/nf-core/$n.git" "$tmp" 2>/dev/null; then ok=1
    elif [ -n "$pin" ] && grep -q dev <<<"$pin" && timeout 300 git clone -q --depth 1 "https://github.com/nf-core/$n.git" "$tmp" 2>/dev/null; then
      req=$(nfreq "$tmp"); { [ -z "$req" ] || [ -z "$NF_HAVE" ] || ver_le "$req" "$NF_HAVE"; } && ok=1   # dev snapshot: no tag
      # A "<x>dev" pin names no fetchable version, so the clone never matches it and every sync re-cloned
      # (7 pipelines, 2026-11-06). Record the version actually fetched as the pin — fetched once, then stable.
      fv=$(mver "$tmp")
      if [ $ok = 1 ] && [ -n "$fv" ]; then
        awk -v n="$n" -v v="$fv" '$1==n{$2=v} {print}' "$PINS" > "$PINS.tmp" && mv "$PINS.tmp" "$PINS"
      fi
    fi
    if [ $ok = 1 ] && [ -f "$tmp/main.nf" ] && ! incomplete "$tmp"; then
      [ -d "$NFCORE_SRC/$n.incomplete_$(date +%Y%m%d)" ] && rm -rf "$NFCORE_SRC/$n" || mv "$NFCORE_SRC/$n" "$NFCORE_SRC/$n.incomplete_$(date +%Y%m%d)"
      mv "$tmp" "$NFCORE_SRC/$n" && refetched=$((refetched+1))
    else
      rm -rf "$tmp"; refetch_failed="$refetch_failed $n(pin=${pin:-?})"
    fi
  fi
done
[ "$refetched" -gt 0 ] && echo "[nfcore] fetched $refetched host pipelines at their pinned versions from github.com/nf-core (container Nextflow ${NF_HAVE:-?})"
[ -n "$refetch_failed" ] && echo "[nfcore] WARNING: not fetched (kept as is):$refetch_failed"
# 1b) apply BioMate patches for the pinned version. .biomate_patches in the pipeline dir lists the
#     sha256 of each applied patch; a fresh re-fetch has none, so its patches are re-applied.
#     Patches are applied by `patch -p1 -N` to the host source only (the container is replaced below).
for pf in "$PD"/nfcore-patches/*/*.patch; do
  [ -f "$pf" ] || continue
  n=$(basename "$(dirname "$pf")"); ver=$(basename "$pf" .patch); d="$NFCORE_SRC/$n"
  [ -f "$d/main.nf" ] || continue
  [ "$(mver "$d")" = "$ver" ] || { echo "[nfcore] patch $n/$ver.patch skipped: host has $(mver "$d")"; continue; }
  sha=$(sha256sum "$pf" | cut -c1-16)
  grep -q "^$sha " "$d/.biomate_patches" 2>/dev/null && continue
  if patch -p1 -N -s -d "$d" < "$pf"; then
    echo "$sha $n/$ver.patch" >> "$d/.biomate_patches"; echo "[nfcore] applied patch $n/$ver.patch"
  else
    echo "[nfcore] WARNING: patch $n/$ver.patch did not apply cleanly — left unpatched"
  fi
done
pstate() { cat "$1/.biomate_patches" 2>/dev/null | cut -c1-16 | sort | tr -d '\n'; }
host_n=$(ls "$NFCORE_SRC"/*/main.nf 2>/dev/null | grep -vcE "\.incomplete_|/\.fetch_")
# 2) restore into the container every pipeline that is missing there OR incomplete there
# complete container copies as "name@version" (an incomplete copy is not listed, so it is replaced). Versions are
# parsed on the host with the same mver() as the source, from the container's file — one parser for both sides.
container_state=""
for n in $(docker exec "$GC" sh -c 'for d in /app/nf-core-workflows/*/; do [ -f "$d/main.nf" ] || continue; if grep -qE "includeConfig +.conf/base.config" "$d/nextflow.config" 2>/dev/null && [ ! -f "$d/conf/base.config" ]; then continue; fi; basename "$d"; done'); do
  cv=$(docker exec "$GC" cat "/app/nf-core-workflows/$n/nextflow.config" 2>/dev/null | { t=$(mktemp -d); cat > "$t/nextflow.config"; mver "$t"; rm -rf "$t"; })
  cp_=$(docker exec "$GC" cat "/app/nf-core-workflows/$n/.biomate_patches" 2>/dev/null | cut -c1-16 | sort | tr -d '\n')
  container_state="$container_state $n@$cv+$cp_"
done
present=" $container_state "   # complete pipelines, with their versions
missing=""
for d in "$NFCORE_SRC"/*/; do
  n=$(basename "$d"); [ "$n" = modules ] && continue; [ -f "$d/main.nf" ] || continue
  case "$n" in *.incomplete_*|.fetch_*) continue ;; esac
  incomplete "$d" && continue   # do not copy a source that is still incomplete
  case "$present" in *" $n@$(mver "$d")+$(pstate "$d") "*) ;; *) missing="$missing $n" ;; esac   # missing, incomplete, other version or other patches
done
if [ -z "$missing" ]; then echo "[nfcore] all $host_n real pipelines present in $GC"; exit 0; fi
ST=/tmp/nfcore_pipelines_stage
sudo rm -rf "$ST"; mkdir -p "$ST"
for n in $missing; do rsync -a --exclude=.github --exclude="._*" --exclude=.git "$NFCORE_SRC/$n/" "$ST/$n/"; done
# replace (not merge into) an incomplete container copy
for n in $missing; do docker exec -u root "$GC" rm -rf "/app/nf-core-workflows/$n"; done
docker cp "$ST/." "$GC:/app/nf-core-workflows/"
docker exec -u root "$GC" chown -R galaxy:galaxy /app/nf-core-workflows 2>/dev/null || true
echo "[nfcore] restored/replaced $(echo $missing | wc -w) of $host_n real pipelines into $GC (missing or incomplete)"
REMOTE
  # Same gap for the nf-core community library (also git-ignored except BioMate's own files): the
  # catalog's nfcore/subworkflows/<name> entries resolve to nf-core-modules/subworkflows/nf-core/<name>
  # and include ../../../modules/nf-core/<tool> — the container had 0 of the host's 94 / 755.
  ec2_ssh "NFMOD_SRC=${NFCORE_MODULES_HOST_DIR} bash -s" <<'REMOTE'
set -e
GC=$(docker ps --filter "name=biomate-galaxy" --format "{{.Names}}" | grep -Ev "rollback|chatgpt" | head -1)
GC="${GC:-biomate-galaxy-dev}"
if [ ! -d "$NFMOD_SRC/subworkflows/nf-core" ]; then echo "[nfcore] WARNING: host copy $NFMOD_SRC missing — cannot restore subworkflows"; exit 0; fi
host_sw=$(ls "$NFMOD_SRC"/subworkflows/nf-core/*/main.nf 2>/dev/null | wc -l)
host_mod=$(find "$NFMOD_SRC/modules/nf-core" -name main.nf 2>/dev/null | wc -l)
have_sw=$(docker exec "$GC" sh -c 'ls /app/nf-core-modules/subworkflows/nf-core/*/main.nf 2>/dev/null | wc -l')
have_mod=$(docker exec "$GC" sh -c 'find /app/nf-core-modules/modules/nf-core -name main.nf 2>/dev/null | wc -l')
if [ "$have_sw" -ge "$host_sw" ] && [ "$have_mod" -ge "$host_mod" ]; then echo "[nfcore] nf-core library present ($have_sw subworkflows, $have_mod modules)"; exit 0; fi
ST=/tmp/nfcore_modules_stage
sudo rm -rf "$ST"; mkdir -p "$ST/subworkflows" "$ST/modules"
rsync -a --exclude=.github --exclude="._*" --exclude=.git "$NFMOD_SRC/subworkflows/nf-core" "$ST/subworkflows/"
rsync -a --exclude=.github --exclude="._*" --exclude=.git "$NFMOD_SRC/modules/nf-core" "$ST/modules/"
docker cp "$ST/." "$GC:/app/nf-core-modules/"
docker exec -u root "$GC" chown -R galaxy:galaxy /app/nf-core-modules 2>/dev/null || true
echo "[nfcore] restored nf-core library into $GC ($host_sw subworkflows, $host_mod modules; had $have_sw / $have_mod)"
REMOTE
  # Extra Nextflow frameworks: the executor launches DSL1 pipelines on 22.10.8 and pipelines whose manifest
  # requires a newer release on that release (_pipeline_nextflow_version). Pre-fetch each framework and its
  # nf-amazon plugin into the runtime NXF_HOME so the first run does not download them mid-launch (concurrent
  # first runs would race on the same jar). The version→plugin map is read from the executor — one source.
  local nxf_map
  nxf_map=$(python3 -c 'import re,ast,sys; s=open(sys.argv[1]).read(); m=re.search(r"^_NFAMAZON_FOR_NXF_VER = (\{.*\})", s, re.M); print(" ".join(f"{k}:{v}" for k,v in ast.literal_eval(m.group(1)).items()))' \
    "$REPO_ROOT/backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py" 2>/dev/null)
  [[ -z "$nxf_map" ]] && { log "[nfcore] ⚠ could not read _NFAMAZON_FOR_NXF_VER from the executor — extra frameworks not pre-fetched"; return 0; }
  ec2_ssh "NXF_MAP='${nxf_map}' bash -s" <<'REMOTE'
GC=$(docker ps --filter "name=biomate-galaxy" --format "{{.Names}}" | grep -Ev "rollback|chatgpt" | head -1)
GC="${GC:-biomate-galaxy-dev}"
H=$(docker exec "$GC" sh -c 'if [ -d /opt/nextflow ]; then echo /opt/nextflow; else echo $HOME/.nextflow; fi')
for vp in $NXF_MAP; do
  v=${vp%%:*}; p=${vp##*:}
  if docker exec "$GC" sh -c "[ -d $H/framework/$v ] && [ -d $H/plugins/nf-amazon-$p ]"; then echo "[nfcore] Nextflow $v + nf-amazon@$p present in $H"; continue; fi
  if docker exec -e NXF_HOME="$H" -e NXF_VER="$v" -e NXF_OFFLINE=false "$GC" sh -c "timeout 600 nextflow -version >/dev/null 2>&1 && timeout 300 nextflow plugin install nf-amazon@$p >/dev/null 2>&1"; then
    echo "[nfcore] fetched Nextflow $v + nf-amazon@$p into $H"
  else
    echo "[nfcore] WARNING: could not fetch Nextflow $v / nf-amazon@$p into $H — those pipelines will download it at launch"
  fi
done
REMOTE
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

  # Also sync backend/experiments/ — the executor imports `experiments.autoloop_bridge`
  # (+ per-domain QC evaluators) for the completion-time auto-loop emit. This tree was
  # previously omitted from the sync, so on dev the import raised ModuleNotFoundError and
  # the auto-loop remediation SSE silently no-op'd. Ship the whole package.
  git ls-files -- 'backend/experiments/**/*.py' 'backend/experiments/*.py' 2>/dev/null >> "$tmp_list" || true
  git ls-files --others --exclude-standard -- 'backend/experiments/**/*.py' 2>/dev/null >> "$tmp_list" || true

  # Built-in SKILLS are Markdown (YAML frontmatter + body), not .py. Include them so a new or updated
  # skill under backend/lib/galaxy/ai/skills/ actually deploys — the py-only tar filter below silently
  # dropped them otherwise (caught 2026-11-06: biomate-universe.md never reached dev despite "Sync OK").
  git ls-files -- 'backend/lib/galaxy/ai/skills/*.md' 2>/dev/null >> "$tmp_list" || true
  git ls-files --others --exclude-standard -- 'backend/lib/galaxy/ai/skills/*.md' 2>/dev/null >> "$tmp_list" || true

  local count=$(sort -u "$tmp_list" | grep -cE "\.(py|md)$" || true)
  log "[backend] $count backend files to sync (Python + skill .md)"

  # Build tar of backend Python files using `git show HEAD:` instead of the
  # working tree. This prevents concurrent parallel sessions from deploying
  # a stale or wrong version of a file — only committed content is deployed.
  local tar_file="/tmp/biomate_backend_py.tar.gz"
  local tmp_tar_dir="/tmp/biomate_backend_py_staging"
  rm -rf "$tmp_tar_dir" && mkdir -p "$tmp_tar_dir"
  while IFS= read -r rel_path; do
    # .py anywhere in the backend tree, plus built-in skill .md files (scoped to the skills dir so
    # this never pulls in unrelated Markdown like docs).
    [[ "$rel_path" == *.py || "$rel_path" == backend/lib/galaxy/ai/skills/*.md ]] || continue
    mkdir -p "$tmp_tar_dir/$(dirname "$rel_path")"
    # Export committed version; fall back to working tree for untracked files
    git show "HEAD:$rel_path" > "$tmp_tar_dir/$rel_path" 2>/dev/null \
      || cp "$REPO_ROOT/$rel_path" "$tmp_tar_dir/$rel_path" 2>/dev/null || true
  done < <(sort -u "$tmp_list")
  # COPYFILE_DISABLE=1 suppresses macOS ._* Apple Double resource-fork files from
  # entering the archive. Without this, macOS tar bundles a ._<name>.py companion
  # for every .py file; Linux extracts them as real files; alembic finds them,
  # tries to compile them (binary → null bytes) → ValueError → gunicorn crash.
  # Sync 8 root cause: this flag was present on the frontend tar but not here.
  COPYFILE_DISABLE=1 tar -czf "$tar_file" -C "$tmp_tar_dir" --exclude='._*' . 2>/dev/null || true

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
    # Auto-detect Galaxy container name (handles biomate-galaxy-dev OR biomate-galaxy-deploy)
    GC=$(docker ps --filter "name=biomate-galaxy" --format "{{.Names}}" | grep -Ev "rollback|chatgpt" | head -1)
    GC="${GC:-biomate-galaxy-dev}"
    echo "[backend] Using Galaxy container: $GC"

    # Nuke any leftover extract dir BEFORE tar so a missing/broken upload
    # cannot silently fall back to the previous sync content.
    rm -rf /tmp/backend_py_extract && mkdir -p /tmp/backend_py_extract
    # No `|| true`: a tar failure here means stale-or-corrupt input;
    # aborting is the only safe response.
    tar -xzf /tmp/backend_py_sync.tar.gz -C /tmp/backend_py_extract

    # Sanity check: confirm extract is non-empty before mass-copying.
    # Exclude ._* Apple Double resource-fork files (defense-in-depth; primary fix is
    # COPYFILE_DISABLE=1 on the macOS tar creation side above).
    extracted=$(find /tmp/backend_py_extract/backend -name "*.py" ! -name "._*" 2>/dev/null | wc -l)
    if [[ "$extracted" -lt 1 ]]; then
      echo "[backend] FATAL: tarball extracted zero .py files — refusing to docker cp" >&2
      exit 1
    fi
    echo "[backend] extracted $extracted python files into /tmp/backend_py_extract/"

    # Copy each file into the Galaxy container at /app/ path.
    # ! -name "._*" excludes any Apple Double resource-fork files that macOS tar may
    # have bundled; copying them into the alembic versions_gxy/ dir causes a
    # null-byte ValueError that crash-loops gunicorn (sync 8 root cause, 2026-07-03).
    # Lay the files out as the container sees them, then copy the tree in with ONE docker cp
    # (merges into /app; existing files elsewhere are untouched). The per-file loop it replaces ran
    # docker exec mkdir + docker cp for every file: ~2m47s for 632 files (sync of 2026-11-04).
    LAYOUT=/tmp/backend_py_layout
    rm -rf "$LAYOUT" && mkdir -p "$LAYOUT/app"
    find /tmp/backend_py_extract/backend -type f ! -name "._*" \( -name "*.py" -o -path "/tmp/backend_py_extract/backend/lib/galaxy/ai/skills/*.md" \) | while IFS= read -r src; do
      rel="${src#/tmp/backend_py_extract/backend/}"
      # experiments/ is a top-level package at /app/experiments (importable as `experiments`);
      # everything else lands under /app/lib/galaxy/.
      case "$rel" in
        experiments/*) dest="/app/$rel" ;;
        *)             dest="/app/lib/galaxy/${rel#lib/galaxy/}" ;;
      esac
      mkdir -p "$LAYOUT$(dirname "$dest")"
      cp "$src" "$LAYOUT$dest"
    done
    staged=$(find "$LAYOUT/app" -name "*.py" | wc -l)
    # set -e: a failed copy aborts the sync instead of leaving a half-updated container.
    docker cp "$LAYOUT/app/." "$GC:/app/"
    echo "[backend] copied $staged python files into $GC:/app in one docker cp"
    # Verify Markdown skills too: a successful Python copy does not prove these shipped.
    if [[ -d "$LAYOUT/app/lib/galaxy/ai/skills" ]]; then
      find "$LAYOUT/app/lib/galaxy/ai/skills" -type f -name "*.md" | while IFS= read -r src; do
        dest="${src#"$LAYOUT"}"
        expected=$(sha256sum "$src" | cut -d " " -f 1)
        actual=$(docker exec "$GC" sha256sum "$dest" | cut -d " " -f 1)
        if [[ "$expected" != "$actual" ]]; then
          echo "[backend] FATAL: deployed skill hash mismatch: $dest" >&2
          exit 1
        fi
      done
    fi

    # Also sync the biomni_workflows .nf files
    echo "[backend] Done Python sync"

    # Bootstrap runtime deps that the image was built without.
    # IMPORTANT: gunicorn runs with /usr/local/bin/python3.9 (system Python),
    # not /app/.venv. Installing to the venv silently fails to expose them.
    docker exec "$GC" /usr/local/bin/python3.9 -c "import boto3, redis, psycopg2" 2>/dev/null \
      || docker exec "$GC" /usr/local/bin/pip install -q boto3 redis psycopg2-binary 2>&1 | tail -3

    # RDKit — required in-process by the Design & generate module (BRICS generator,
    # backend/lib/galaxy/ai/drug_discovery/generators.py). gunicorn runs system
    # python3.9 (see note above), so it must be installed there or /design returns
    # "rdkit_unavailable" and generates 0 candidates. Pin rdkit>=2024.3 to avoid a
    # numpy-2 segfault in rdkit.ML.InfoTheory (see backend/Dockerfile:134-137).
    docker exec "$GC" /usr/local/bin/python3.9 -c "import rdkit" 2>/dev/null \
      || docker exec "$GC" /usr/local/bin/pip install -q "rdkit==2024.3.5" 2>&1 | tail -3

    # Nextflow binary — required by /api/cryosparc/execute path. Image lacks it.
    # Nextflow VERSION PIN (2026-05-21): 25.10.5 is the latest pre-26 LTS.
    # Nextflow 26.04+ became stricter about DSL2 (e.g. rejects top-level
    # `def` statements with "Statements cannot be mixed with script
    # declarations", and is pickier about Groovy heredoc parsing). 21 of
    # our workflows had to be rewritten today to satisfy 26.04. Rather
    # than chase every future breaking change, pin to 25.10 LTS which
    # accepts the older syntax cleanly. Bump deliberately, not by curl.
    EXPECTED_NF_VER="25.10.5"
    INSTALLED_NF_VER=$(docker exec "$GC" /usr/local/bin/nextflow -v 2>/dev/null | grep -oE "[0-9]+\.[0-9]+\.[0-9]+" | head -1)
    if [[ "$INSTALLED_NF_VER" != "$EXPECTED_NF_VER" ]]; then
      echo "[galaxy] Nextflow version mismatch (installed=$INSTALLED_NF_VER, want=$EXPECTED_NF_VER) — reinstalling pinned version"
      docker exec "$GC" bash -c "NXF_VER=$EXPECTED_NF_VER curl -fsSL https://get.nextflow.io | bash && mv nextflow /usr/local/bin/nextflow && chmod +x /usr/local/bin/nextflow" 2>&1 | tail -3
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
  # GUARD: never ship git conflict markers to dev. deploy_workflows tars the WORKING TREE
  # (unlike deploy_backend_python, which uses `git show HEAD:`), so a concurrent session's
  # unresolved `git stash apply` can leave `<<<<<<<` / `>>>>>>>` in a .nf and this would
  # hot-ship a broken file that dies at parse time (SyntaxError) on every Batch run —
  # observed 2026-10-01 on merfish_spatial_analysis/main.nf (3 marker blocks reached dev).
  # Same class as CLAUDE.md's merge-conflict-marker trap. Abort before tarring if any
  # workflow source file carries an unambiguous conflict marker.
  local _cm_hits
  _cm_hits=$(grep -rlE '^(<<<<<<< |>>>>>>> )' \
      backend/biomni_workflows backend/nf-core-workflows/modules/biomate-ai-tools backend/nf-core-modules \
      --include='*.nf' --include='*.py' --include='*.R' --include='*.config' 2>/dev/null || true)
  if [[ -n "$_cm_hits" ]]; then
    log "[workflows] FATAL: git conflict markers in workflow source — refusing to deploy corrupted files:"
    echo "$_cm_hits" | sed 's/^/      /' >&2
    log "[workflows] Resolve them (likely a stray 'git stash apply') then re-run. ABORTING sync."
    return 1
  fi
  # Ship the COMMITTED tree (HEAD), NOT the working tree. A sparse or stale
  # worktree shipped an OLD .nf for a commit the ledger recorded as deployed
  # (2026-11-11 boltz_structure_prediction: dev's commit contained the fix but
  # /app still ran the old file). The ancestry gate verifies the COMMIT while
  # deploy_workflows ships FILES, so a working-tree tar let the two diverge.
  # git archive is content-addressed to HEAD — same guarantee deploy_backend_python
  # gets from `git show HEAD:`. All workflow source is committed (0 untracked .nf),
  # and .nextflow/.nextflow.log are gitignored so HEAD never carries them.
  git archive --format=tar.gz -o "$tar_file" HEAD -- \
    backend/biomni_workflows \
    backend/nf-core-workflows/modules/biomate-ai-tools \
    backend/nf-core-modules \
    scripts/regen_stub_runcopies.sh 2>/dev/null \
    || { log "[workflows] FATAL: git archive HEAD failed (detached/corrupt HEAD?). ABORTING."; return 1; }
  log "[workflows] Archive (git HEAD ${CURRENT_COMMIT:0:8}): $(du -sh $tar_file | cut -f1)"

  ec2_scp "$tar_file" "${EC2_USER}@${EC2_HOST}:/tmp/workflows_sync.tar.gz"

  ec2_ssh '
    set -e
    GC=$(docker ps --filter "name=biomate-galaxy" --format "{{.Names}}" | grep -Ev "rollback|chatgpt" | head -1)
    GC="${GC:-biomate-galaxy-dev}"
    mkdir -p /tmp/workflows_extract
    tar -xzf /tmp/workflows_sync.tar.gz -C /tmp/workflows_extract 2>/dev/null
    # Copy workflows into Galaxy container via in-container untar so symlinks
    # in the archive can replace pre-existing directories (the host docker cp
    # cannot overwrite a directory with a non-directory and silently leaves
    # stale content — caused the 2026-05-21 ADMET_pred regression where the
    # symlink drug_discovery/ADMET_pred → pharmacology/ADMET_pred could not
    # supersede an old standalone directory on dev).
    docker cp /tmp/workflows_sync.tar.gz "$GC:/tmp/workflows_sync.tar.gz"
    docker exec "$GC" bash -c "
      set -e
      cd /tmp && mkdir -p workflows_extract_in
      tar -xzf workflows_sync.tar.gz -C workflows_extract_in

      # Per-file replacement for biomni_workflows (handles symlink-vs-dir conflicts).
      cd workflows_extract_in/backend/biomni_workflows
      find . -mindepth 1 \( -type f -o -type l \) | while read -r rel; do
        rel=\${rel#./}
        dest=/app/biomni_workflows/\$rel
        mkdir -p \"\$(dirname \"\$dest\")\"
        rm -rf \"\$dest\" 2>/dev/null
        cp -P \"\$rel\" \"\$dest\"
      done

      # Per-file replacement for nf-core-workflows/modules/biomate-ai-tools.
      # New custom BioMate wrappers (magma, scgwas, ldsc, etc.) are added here
      # and must reach dev EC2 — previously this directory was never synced.
      cd /tmp/workflows_extract_in/backend/nf-core-workflows/modules/biomate-ai-tools
      find . -mindepth 1 \( -type f -o -type l \) | while read -r rel; do
        rel=\${rel#./}
        dest=/app/nf-core-workflows/modules/biomate-ai-tools/\$rel
        mkdir -p \"\$(dirname \"\$dest\")\"
        rm -rf \"\$dest\" 2>/dev/null
        cp -P \"\$rel\" \"\$dest\"
      done

      # Per-file replacement for nf-core-modules/. The executor resolves workflows
      # from backend_root/nf-core-modules (nextflow_executor _candidate_bases), but
      # this directory was NEVER synced — so any workflow placed there (e.g. the
      # proteomics DDA/EncyclopeDIA DIA workflows from PR #217) could not run on dev.
      if [ -d /tmp/workflows_extract_in/backend/nf-core-modules ]; then
        cd /tmp/workflows_extract_in/backend/nf-core-modules
        find . -mindepth 1 \( -type f -o -type l \) | while read -r rel; do
          rel=\${rel#./}
          dest=/app/nf-core-modules/\$rel
          mkdir -p \"\$(dirname \"\$dest\")\"
          rm -rf \"\$dest\" 2>/dev/null
          cp -P \"\$rel\" \"\$dest\"
        done
      fi
    " 2>&1 | tail -3

    # -----------------------------------------------------------------------
    # Regenerate stub-sourced nf-core RUN-copies (root-cause fix 2026-11-17).
    # (No single quotes in this comment: it lives inside the ec2_ssh payload.)
    #
    # backend/nf-core-workflows/<wf>/ holds REAL nf-core pipeline downloads; it
    # is gitignored + container-only, so the deploy never ships it. The executor
    # resolver (_resolve_nextflow_path in nextflow_executor.py) searches that
    # REAL run-copy BEFORE the biomni_workflows/nfcore/<wf> stub, so for
    # workflows where OUR stub is the functional source of truth (declared
    # // Input: contract + gate self-correction, e.g. differentialabundance) the
    # stale run-copy main.nf shadowed the stub and stub edits had ZERO runtime
    # effect — the Stream-6 saga.
    #
    # Canonical logic = scripts/regen_stub_runcopies.sh (single source of truth,
    # unit-tested by scripts/test_regen_stub_runcopies.sh). It is shipped inside
    # the workflows tarball and extracted in-container at
    # /tmp/workflows_extract_in/scripts/, so we exec it there directly. It
    # overwrites ONLY main.nf of stubs carrying the // Input: marker (real
    # nf-core downloads for other workflows are untouched) and hard-fails on any
    # stub/run-copy marker divergence.
    #
    # Run as its OWN docker exec with NO masking tail pipe: the remote shell is
    # set -e but NOT pipefail, so a tail-piped failure would be swallowed. Bare,
    # a nonzero exit propagates (docker exec -> remote set -e -> ec2_ssh nonzero
    # -> top-level set -euo pipefail aborts the sync). That is what makes the
    # guard real: a deploy CANNOT silently ship a stale run-copy.
    docker exec "$GC" bash /tmp/workflows_extract_in/scripts/regen_stub_runcopies.sh

    # Workflow-script cache invalidation: Nextflow caches compiled .nf
    # scripts by content hash, but stale per-run dirs can keep old plugin
    # state. We DO NOT delete entire ~/.nextflow (plugins are 100MB+ and
    # re-downloading on every sync would be slow); we clear only the
    # script-compile cache + tmp.
    docker exec "$GC" bash -c "
      rm -rf /home/galaxy/.nextflow/cache /home/galaxy/.nextflow/tmp 2>/dev/null
      rm -rf /root/.nextflow/cache /root/.nextflow/tmp 2>/dev/null
      # Per-run directories contain resume caches, status evidence, logs and
      # local outputs. Deployment must preserve active and historical runs.
      # Retention belongs to a separate owner-aware lifecycle policy.
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

  # galaxy_ai_tools.db — 310MB, sync via S3 presigned URL (NOT direct scp).
  #
  # WHY S3 instead of scp (2026-07-17):
  # Direct scp over the SSM WebSocket proxy corrupts data with "Bad packet
  # length" at ~17-21 min regardless of file size or ServerAliveInterval.
  # The SSM session has a hard rotation interval that corrupts the SSH stream.
  # Fix: local uploads to S3; EC2 pulls via presigned HTTPS URL (bypasses SSM;
  # in-region download is ~1 Gbps vs ~150 KB/s through SSM).
  # EC2 stale ~/.aws/credentials (Oct 2025 key deleted upstream) is moved to
  # .bak in-flight so the BioMateEc2DeployProfile instance role takes over.
  local local_db="$REPO_ROOT/backend/database/galaxy_ai_tools.db"
  # Probe GNU stat first (see comment at L960). BSD `stat -f %m` returns
  # filesystem info on Linux *without* erroring, so the ||-fallback below
  # would never engage and the [[ -gt ]] check would die under set -u.
  local local_db_mtime=$(stat -c %Y "$local_db" 2>/dev/null \
    || stat -f %m "$local_db" 2>/dev/null \
    || echo 0)
  [[ "$local_db_mtime" =~ ^[0-9]+$ ]] || local_db_mtime=0

  if [[ "$local_db_mtime" -gt "${LAST_DB_SYNC:-0}" ]]; then
    # MD5 short-circuit: mtime fires on every run (LAST_DB_SYNC is not persisted
    # across shell invocations). Skip the 300MB S3 upload if local and dev are
    # already byte-for-byte identical. _DEV_DB_MD5 was fetched during pre-flight.
    local _cur_local_md5
    _cur_local_md5=$(md5 -q "$local_db" 2>/dev/null \
      || md5sum "$local_db" 2>/dev/null | cut -d' ' -f1 \
      || echo '')
    # Never ship a catalog whose external-content FTS index disagrees with the workflows table: search
    # then ranks on stale text and the update triggers fail mid-write (2026-11-05, docs/20261103 §13).
    # 2026-11-13: soft-skip was treated as "DB aside" and still left operators thinking DEV got the
    # intended catalog — refuse hard when an upload was about to happen.
    local _db_decision _db_local_wf _db_dev_wf
    _db_local_wf="$(biomate_db_workflow_count "$local_db")"
    _db_dev_wf="${_DEV_DB_WF_COUNT:--1}"
    _db_decision="$(biomate_db_upload_decision "$local_db" "$_db_dev_wf")"
    if [[ "$_db_decision" != "allow" ]]; then
      log "::error:: [db] $(biomate_db_decision_message "$_db_decision" "$local_db" "$_db_local_wf" "$_db_dev_wf")"
      log "::error:: [db] refusing upload — set BIOMATE_SYNC_DB=0 for code-only, or fix the local catalog first"
      return 1
    fi
    if [[ -n "$_cur_local_md5" && "$_cur_local_md5" == "${_DEV_DB_MD5:-}" ]]; then
      log "[db] galaxy_ai_tools.db MD5 matches dev (${_cur_local_md5}) — skipping upload"
      LAST_DB_SYNC="$local_db_mtime"
    else
    # Transfer via S3 presigned URL: avoids SSM tunnel "Bad packet length"
    # corruption that hits at ~17 min for any file >~60MB over the SSM proxy.
    # Local uploads to S3 (user's internet); EC2 pulls from S3 via HTTPS
    # (in-region, ~1 Gbps) — SSM tunnel carries only the curl command, not data.
    # EC2 stale ~/.aws/credentials: rename to .bak so the instance role takes over.
    # Backup the current dev DB before overwriting it.
    ec2_ssh '
      SRC=/opt/biomate/galaxy_db/galaxy_ai_tools.db
      if [[ -f "$SRC" ]]; then
        TS=$(date +%Y%m%d_%H%M%S)
        cp "$SRC" "${SRC}.bak_${TS}" && echo "[db] pre-sync backup: ${SRC}.bak_${TS} ($(stat -c %s ${SRC}.bak_${TS}) bytes)"
        # Keep only the 3 most recent backups to avoid filling the disk.
        ls -t /opt/biomate/galaxy_db/galaxy_ai_tools.db.bak_* 2>/dev/null | tail -n +4 | xargs rm -f
      fi
    ' || log "[db] WARNING: pre-sync backup failed — continuing anyway"
    local S3_STAGE="s3://biomate-nextflow-outputs/tmp/db-sync/galaxy_ai_tools.db"
    log "[db] galaxy_ai_tools.db changed ($(du -sh $local_db | cut -f1)) — uploading to S3 staging..."
    aws s3 cp "$local_db" "$S3_STAGE" \
      || { log "[db] S3 upload failed — aborting"; return 1; }
    log "[db] S3 upload complete — generating presigned URL for EC2 pull..."
    local presigned
    presigned=$(aws s3 presign "$S3_STAGE" --expires-in 3600)
    # Disable stale per-user creds so instance role (BioMateEc2DeployProfile) is active
    ec2_ssh '[[ -f ~/.aws/credentials ]] && mv ~/.aws/credentials ~/.aws/credentials.bak && echo "[db] stale creds moved to .bak"' || true
    ec2_ssh "curl -fsSL -o /tmp/galaxy_ai_tools_sync.db '${presigned}'"
    local pull_rc=$?
    aws s3 rm "$S3_STAGE" 2>/dev/null || true
    if [[ "$pull_rc" -ne 0 ]]; then
      log "[db] EC2 pull from S3 failed — aborting"
      return 1
    fi
    log "[db] EC2 pull complete"
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
    ec2_ssh "
      # Write to the host volume path directly — persists across container restarts.
      mkdir -p $GALAXY_DB_HOST_PATH
      mv /tmp/galaxy_ai_tools_sync.db $GALAXY_DB_HOST_PATH/galaxy_ai_tools.db
      chown \$(id -u):\$(id -g) $GALAXY_DB_HOST_PATH/galaxy_ai_tools.db 2>/dev/null || true
      # Verify the file landed correctly.
      dev_size=\$(stat -c %s $GALAXY_DB_HOST_PATH/galaxy_ai_tools.db 2>/dev/null || echo 0)
      dev_md5=\$(md5sum $GALAXY_DB_HOST_PATH/galaxy_ai_tools.db 2>/dev/null | cut -d' ' -f1)
      if [[ \"\$dev_size\" -lt 10485760 ]]; then
        echo '[db] ERROR: host-volume DB is only '\${dev_size}'B after copy — DB may be corrupt' >&2
        exit 1
      fi
      echo \"[db] galaxy_ai_tools.db written to host volume (size=\${dev_size}B md5=\${dev_md5})\"
      # Also update the live container's in-process copy so Galaxy picks it up
      # without a restart (the volume mount will serve it on next restart anyway).
      GC=\$(docker ps --filter \"name=biomate-galaxy\" --format \"{{.Names}}\" | grep -Ev \"rollback|chatgpt\" | head -1)
      GC=\"\${GC:-biomate-galaxy-dev}\"
      docker exec -u root \"\$GC\" cp $GALAXY_DB_HOST_PATH/galaxy_ai_tools.db \
        /app/database/galaxy_ai_tools.db 2>/dev/null \
        && docker exec -u root \"\$GC\" chown galaxy:galaxy \
             /app/database/galaxy_ai_tools.db 2>/dev/null || true
    "
    # Rebuild the workflow embedding NPZ inside the container so the next
    # Galaxy startup finds a fresh index and never blocks at request time.
    # The Python command uses only double quotes (no apostrophes) so the
    # outer single-quoted ec2_ssh block is not broken.
    log "[embed] Rebuilding workflow embeddings to match new DB (may take 60-120 s)..."
    # Call _build_workflow_embeddings() directly — bypasses the runtime
    # staleness gate (which now refuses to rebuild in the request path).
    # No apostrophes in this block (see sync 9 root cause in CLAUDE.md).
    # timeout 1200: kills the SSH+docker-exec if embedding hangs (no-timeout bug caused
    # a 30+ min hang when the container stalled). Raised from 660s on 2026-11-09: the catalog
    # grew to ~4226 workflows and BGE encoding on dev CPU now exceeds 660s, so the 660 cap
    # false-positived (sync f1b390df: embeddings left stale, server fell back to FTS-only).
    # 1200s = 20 min covers the grown catalog with margin; still well under the old hang.
    ec2_ssh '
      GC=$(docker ps --filter "name=biomate-galaxy" --format "{{.Names}}" | grep -Ev "rollback|chatgpt" | head -1)
      GC="${GC:-biomate-galaxy-dev}"
      timeout 1200 docker exec -u galaxy "$GC" python3.9 -c "
import sys, time
sys.path.insert(0, \"/app/lib\")
t0 = time.time()
import pathlib
import galaxy.ai.unified_workflow_search as _m
_m._WORKFLOW_EMBED_NPZ = pathlib.Path(\"/app/database/galaxy_ai_workflow_embeddings.npz\")
if _m._WF_EMBED_MODEL is None:
    print(\"[embed] Loading BGE model...\")
    from sentence_transformers import SentenceTransformer as _ST
    _m._WF_EMBED_MODEL = _ST(\"BAAI/bge-small-en-v1.5\", device=\"cpu\", local_files_only=True)
from galaxy.ai.unified_workflow_search import UnifiedWorkflowSearch
wfs = UnifiedWorkflowSearch(\"/app/database/galaxy_ai_tools.db\")
print(\"[embed] Encoding all workflows...\")
wfs._build_workflow_embeddings()
ok = _m._WF_EMBED_MATRIX is not None and len(_m._WF_EMBED_IDS) > 0
label = \"ready\" if ok else \"FAILED\"
print(\"[embed] %s elapsed=%.1fs\" % (label, time.time()-t0))
sys.exit(0 if ok else 1)
" && echo "[embed] Embedding rebuild OK" || echo "[embed] WARNING: embedding rebuild failed — server will use FTS-only on first request"
    ' || log "[embed] WARNING: embedding rebuild ssh step failed"
    LAST_DB_SYNC="$local_db_mtime"
    fi  # end MD5 short-circuit else
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
  # universe.sqlite IS dev's live Galaxy database (users, API keys, histories, workflows).
  # Replacing it with a workstation copy resets all of that to the copy's state — e.g. a sync
  # from a checkout holding a months-old universe.sqlite rolls dev's Galaxy users and every
  # per-user API key back to that date. So it is replaced ONLY on explicit opt-in
  # (BIOMATE_REPLACE_GALAXY_DB=1), and dev's current file is backed up first (2026-11-04).
  if [[ -f "$universe_db" && "${BIOMATE_REPLACE_GALAXY_DB:-}" != "1" ]]; then
    log "[db] universe.sqlite present locally but NOT replacing dev's live Galaxy DB (set BIOMATE_REPLACE_GALAXY_DB=1 to replace; dev's copy is backed up first)"
  fi
  if [[ "${BIOMATE_REPLACE_GALAXY_DB:-}" == "1" && -f "$universe_db" && $(stat -c %s "$universe_db" 2>/dev/null || stat -f %z "$universe_db" 2>/dev/null || echo 0) -gt 0 ]]; then
    log "[db] universe.sqlite — BIOMATE_REPLACE_GALAXY_DB=1: backing up dev's live Galaxy DB, then replacing..."
    ec2_ssh '
      SRC=/opt/biomate/galaxy_db/universe.sqlite
      if [[ -f "$SRC" ]]; then
        TS=$(date +%Y%m%d_%H%M%S)
        cp "$SRC" "${SRC}.bak_${TS}" && echo "[db] pre-replace backup: ${SRC}.bak_${TS} ($(stat -c %s ${SRC}.bak_${TS}) bytes)"
        ls -t /opt/biomate/galaxy_db/universe.sqlite.bak_* 2>/dev/null | tail -n +4 | xargs rm -f
      else
        echo "[db] WARNING: $SRC not found on host — no backup taken"
      fi
    ' || { log "[db] backup of dev's Galaxy DB failed — NOT replacing it"; return 1; }
    log "[db] universe.sqlite — scp to EC2 (bypass S3)..."
    ec2_scp "$universe_db" "${EC2_USER}@${EC2_HOST}:/tmp/universe_sync.sqlite" \
      || { log "[db] scp failed — aborting universe.sqlite sync"; return 1; }
    # docker cp works on a RUNNING container — no need to stop. chown must
    # happen while the container runs (docker exec fails on a stopped one).
    # The restart at the end forces Galaxy workers to re-open the new DB
    # file (the open file handle from the pre-cp workers is now stale).
    ec2_ssh "
      GC=\$(docker ps --filter 'name=biomate-galaxy' --format '{{.Names}}' | grep -Ev 'rollback|chatgpt' | head -1)
      GC=\"\${GC:-biomate-galaxy-dev}\"
      docker cp /tmp/universe_sync.sqlite \"\$GC:/app/database/universe.sqlite\" \
        && docker exec -u root \"\$GC\" chown galaxy:galaxy /app/database/universe.sqlite \
        && echo '[db] file replaced — running alembic upgrade ${LATEST_GXY_HEAD}...' \
        && (docker exec \"\$GC\" bash -c 'cd /app && ./manage_db.sh upgrade ${LATEST_GXY_HEAD} 2>&1' | tail -5 \
            || echo '[db] alembic upgrade returned non-zero — Galaxy may be unhealthy after restart') \
        && docker restart \"\$GC\" >/dev/null \
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
    CONTAINER=$(docker ps --filter "name=biomate-galaxy" --format "{{.Names}}" | grep -Ev "rollback|chatgpt" | head -1)
    CONTAINER="${CONTAINER:-biomate-galaxy-dev}"
    ENV_FILE=/opt/biomate/.env

    if [[ ! -f "$ENV_FILE" ]]; then
      echo "[galaxy-env] FATAL: $ENV_FILE not present; aborting" >&2
      exit 1
    fi

    # Vars set in .env take precedence over the running container'\''s baked-in
    # values for the same key (last --env-file wins on docker run). Capture
    # the rest from the running container so we do not lose JWT_SECRET etc.
    LIVE_ENV=$(mktemp)
    # NOTE: CLEANUP_FILES is a LOCAL-side var (outer on_exit trap). This block runs
    # REMOTELY under set -u, where referencing it is an "unbound variable" fatal that
    # aborts the recreate before docker stop/rm/run — a silent no-op that still prints
    # "Done" and passes the health gate on the OLD container. Clean the temp file
    # remotely instead (trap fires even on the early-exit paths above).
    trap '"'"'rm -f "$LIVE_ENV"'"'"' EXIT

    # Keys present in .env — we will let the file supply them
    NEW_KEYS=$(grep -v "^#\|^$" "$ENV_FILE" | awk -F= "{print \$1}" | sort -u)

    # Capture all other live container env vars (filter the keys .env will override)
    docker inspect "$CONTAINER" --format "{{range .Config.Env}}{{println .}}{{end}}" | \
      while IFS= read -r line; do
        k="${line%%=*}"
        # Skip PATH/HOME/TERM/HOSTNAME — Docker re-supplies these
        case "$k" in PATH|HOME|TERM|HOSTNAME|"") continue ;; esac
        # Skip keys present in the env file (file will supply them)
        if grep -qxF "$k" <<<"$NEW_KEYS"; then continue; fi
        echo "$line"
      done > "$LIVE_ENV"

    # Capture other container config we must preserve
    IMAGE=$(docker inspect "$CONTAINER" --format "{{.Config.Image}}")
    NETWORK=$(docker inspect "$CONTAINER" --format "{{.HostConfig.NetworkMode}}")
    PORTS=$(docker inspect "$CONTAINER" --format "{{range \$p, \$bs := .HostConfig.PortBindings}}{{range \$bs}}-p {{.HostPort}}:{{\$p}} {{end}}{{end}}" | sed "s|/tcp||g")
    MOUNTS=$(docker inspect "$CONTAINER" --format "{{range .Mounts}}-v {{.Source}}:{{.Destination}}{{if .RW}}{{else}}:ro{{end}} {{end}}")

    # The Galaxy DB bind mount is already captured by MOUNTS for a normally-launched
    # container. Adding it a SECOND time here makes docker run fail with "Duplicate
    # mount point: /app/database" — and that failure lands AFTER docker rm, taking dev
    # down. So add the explicit mount ONLY if MOUNTS somehow lacks it.
    DB_MOUNT=""
    case "$MOUNTS" in
      *:/app/database*|*:/app/database:ro*) : ;;   # already preserved
      *) DB_MOUNT="-v '"$GALAXY_DB_HOST_PATH"':/app/database" ;;
    esac

    echo "  preserving image=$IMAGE network=$NETWORK ports=$PORTS db_mount_extra=${DB_MOUNT:-none}"
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
      $DB_MOUNT \
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

# ---------------------------------------------------------------------------
# Enable Galaxy Interactive Tools on dev (Stage C+D from
# docs/20260617_RSTUDIO_IT_PROGRESS.md). The Galaxy container must be able to
# `docker run` child containers (RStudio/Jupyter/CellxGene). It needs (1) the
# host docker socket mounted — requires a container recreate — and (2) a docker
# trusted Docker CLI inside the container, with validated shared libraries. The
# existing proxy remains untouched. Health-guarded:
# if Galaxy does not come back after the recreate, it is restored WITHOUT the
# socket so dev is never left down. Gated behind BIOMATE_ENABLE_IT=1.
# NOTE: mounting the host docker socket gives the Galaxy container effective
# root on the host — acceptable on DEV only; production needs a real IT job
# destination (k8s/ECS), not this.
enable_interactive_tools() {
  local stage helper sha apply_args=""
  stage="$(ec2_ssh 'umask 077; mktemp -d /tmp/biomate-it-review.XXXXXXXX')"
  [[ "$stage" =~ ^/tmp/biomate-it-review\.[A-Za-z0-9]+$ ]] || return 1
  for helper in interactive_runtime_recovery.py interactive_recreate_plan.py interactive_state_migration.py; do
    sha="$(shasum -a 256 "$REPO_ROOT/scripts/$helper" | awk '{print $1}')"
    ec2_scp "$REPO_ROOT/scripts/$helper" "${EC2_USER}@${EC2_HOST}:$stage/$helper" || return 1
    ec2_ssh "chmod 600 '$stage/$helper'; test \$(sha256sum '$stage/$helper' | cut -d' ' -f1) = '$sha'" || return 1
  done
  if [[ "${BIOMATE_IT_APPLY:-0}" == "1" ]]; then
    [[ "${BIOMATE_IT_SOCKET_APPROVED:-}" == "1" && "${BIOMATE_IT_APPROVED_PLAN_SHA:-}" =~ ^[a-f0-9]{64}$ ]] || { log "IT apply requires explicit socket approval and reviewed plan SHA"; return 1; }
    apply_args="--apply --approved-plan-sha $BIOMATE_IT_APPROVED_PLAN_SHA"
  fi
  # Default is review-only: no stop, recreate, CLI installation or socket grant.
  # Private root-owned journals retain inspect/config and rollback evidence.
  ec2_ssh "sudo env PYTHONDONTWRITEBYTECODE=1 BIOMATE_IT_SOCKET_APPROVED='${BIOMATE_IT_SOCKET_APPROVED:-0}' python3 '$stage/interactive_runtime_recovery.py' --deploy-lease '$REMOTE_SYNC_LEASE' --cli-sha256 2c0c7085014dab521228f90fc5fc714184cbba3ab1dd8d526840dd000ed478b5 $apply_args"
  local result=$?
  ec2_ssh "rm -f '$stage/interactive_runtime_recovery.py' '$stage/interactive_recreate_plan.py' '$stage/interactive_state_migration.py'; rmdir '$stage'" || true
  # After a successful socket APPLY, the frontend must learn ITs are now launchable.
  # This BIOMATE_ENABLE_IT path exits before the normal deploy_frontend runs, so the
  # frontend would otherwise keep INTERACTIVE_TOOLS_ENABLED unset and hide the buttons
  # even though ITs now work. Recreate the frontend from its current :latest image
  # (no rebuild) with the flag DERIVED from the live Galaxy docker-socket mount — so
  # /api/interactive/available flips to available and the IT buttons appear with no
  # second sync. Non-fatal: a failure just means "run one normal sync to pick it up".
  if [[ "$result" == "0" && "${BIOMATE_IT_APPLY:-0}" == "1" ]]; then
    ec2_ssh '
      if docker inspect biomate-galaxy-dev --format "{{range .Mounts}}{{.Destination}} {{end}}" 2>/dev/null | grep -q "/var/run/docker.sock"; then IT_ENABLED=1; else IT_ENABLED=0; fi
      if docker image inspect biomate-dev-frontend:latest >/dev/null 2>&1; then
        mkdir -p /tmp/biomate_code
        docker rm -f biomate-dev-frontend 2>/dev/null || true
        docker run -d --name biomate-dev-frontend --network biomate-dev-net \
          -p 3000:3000 --env-file /opt/biomate/.env \
          -e NODE_ENV=production -e PORT=3000 -e FORCE_HTTPS=0 \
          -e MCP_UPSTREAM_URL=http://biomate-remote-mcp:8848 \
          -e BIOMATE_RESPONSE_MODEL=gpt-5.6-luna \
          -e INTERACTIVE_TOOLS_ENABLED="$IT_ENABLED" \
          --restart unless-stopped \
          -v /var/run/docker.sock:/var/run/docker.sock \
          -v /tmp/biomate_code:/tmp/biomate_code \
          biomate-dev-frontend:latest >/dev/null
        docker cp /tmp/logo_sync.png biomate-dev-frontend:/app/dist/public/logo.png 2>/dev/null || true
        echo "[galaxy-it] frontend refreshed: INTERACTIVE_TOOLS_ENABLED=$IT_ENABLED"
      fi
    ' || log "[galaxy-it] frontend IT-flag refresh failed (non-fatal; run a normal sync to pick it up)"
  fi
  return "$result"
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
  # Self-healing guard: the PI suite's test files (e2e/ind-report-production.e2e.ts,
  # e2e/ind-design-audit.e2e.ts) were removed in the "161 stale E2E files" cleanup
  # (1a12b4e8c), so dispatching the workflow produced a guaranteed-red run on every
  # sync ("No tests found"). Skip the dispatch while the tests are absent; it
  # auto-resumes once they're restored. See docs/20261005_CI_ACTIONS_FAILURES_TRIAGE.md.
  if [[ ! -f "$REPO_ROOT/frontend/e2e/ind-report-production.e2e.ts" ]]; then
    log "[pi-suite] skipped — e2e/ind-report-production.e2e.ts absent (removed in 1a12b4e8c); not dispatching a testless suite. Restore the PI tests to re-enable."
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
  log "[galaxy] Clearing stale caches + reloading Galaxy gunicorn (full master restart)..."
  ec2_ssh '
    # Auto-detect Galaxy container name (handles biomate-galaxy-dev OR biomate-galaxy-deploy)
    GC=$(docker ps --filter "name=biomate-galaxy" --format "{{.Names}}" | grep -Ev "rollback|chatgpt" | head -1)
    GC="${GC:-biomate-galaxy-dev}"
    echo "[galaxy] Using Galaxy container: $GC"

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
    docker exec "$GC" bash -c "
      find /app/lib/galaxy/ai /app/lib/galaxy/webapps/galaxy/api -name __pycache__ -type d -exec rm -rf {} + 2>/dev/null
      find /app/lib/galaxy/ai /app/lib/galaxy/webapps/galaxy/api -name \"*.pyc\" -delete 2>/dev/null
      echo \"  ✓ pycache cleared\"
    " 2>&1 | tail -3

    echo "[galaxy] Clearing Nextflow workflow-script cache (preserves plugins)..."
    docker exec "$GC" bash -c "
      # Clear the cache directories Nextflow uses to memoise compiled workflow
      # bytecode + workflow trace state. /tmp/nextflow_runs/* is per-run and
      # safe to keep; the global ~/.nextflow/cache is what stores cross-run
      # script-compile artifacts that pin to stale .nf file hashes.
      rm -rf /home/galaxy/.nextflow/cache /home/galaxy/.nextflow/tmp 2>/dev/null
      rm -rf /root/.nextflow/cache /root/.nextflow/tmp 2>/dev/null
      echo \"  ✓ nextflow caches cleared\"
    " 2>&1 | tail -3

    # Use galaxyctl restart (full master reload) — NOT kill -HUP.
    #
    # WHY: galaxy.yml.docker sets gunicorn preload=true. With --preload the
    # application is loaded in the gunicorn MASTER process; workers are
    # fork()ed from it. A SIGHUP only recycles workers, which inherit the
    # master stale in-memory module state. Fresh .py files on disk are
    # ignored until the master itself restarts.
    #
    # deploy_galaxy_yml() already does a galaxyctl restart early in the sync
    # to apply config changes — but that runs BEFORE Python files are copied
    # (backend sync happens after). By the time restart_galaxy() runs, all
    # .py files are on disk and the master must be restarted to load them.
    #
    # galaxyctl restart gunicorn is a graceful master restart (~5-15s) that
    # re-imports all Python modules from the freshly synced .py files.
    # Stray gunicorn holding :8080. Supervisord stops its gunicorn as a group, but a gunicorn
    # started outside supervisord (parent = PID 1) keeps the listening socket: the supervised
    # gunicorn then logs "Connection in use: (0.0.0.0, 8080)" and crash-loops — dev was down
    # 2026-11-04 18:00-18:06 (CST) with two such orphans (started 17:31/17:34, not in gunicorn.log).
    # Kill them before the restart and say so loudly (PIDs + start times) so the source is traceable.
    kill_orphan_gunicorn() {
      _orph=$(docker exec "$GC" ps -eo pid,ppid,lstart,args | awk "\$2==1 && /gunicorn galaxy.webapps.galaxy.fast_factory/" )
      if [ -n "$_orph" ]; then
        echo "[galaxy] WARNING: gunicorn outside supervisord (ppid 1) — would block :8080; killing:"
        echo "$_orph" | cut -c1-140 | sed "s/^/[galaxy]   /"
        docker exec -u root "$GC" kill -KILL $(echo "$_orph" | awk "{print \$1}") 2>/dev/null || true
      fi
    }
    kill_orphan_gunicorn
    # Galaxy (user galaxy) creates /tmp/nextflow_runs/<run_id> for EVERY Nextflow launch.
    # Anything run as root in the container (docker exec -u root …) can leave it root-owned,
    # and a snapshot/rollback preserves that — then every workflow launch fails with
    # "Permission denied: /tmp/nextflow_runs/<id>" (dev, 2026-11-11 03:03 → 04:52).
    docker exec -u root "$GC" sh -c "mkdir -p /tmp/nextflow_runs && chown -R galaxy:galaxy /tmp/nextflow_runs" 2>/dev/null && \
      echo "[galaxy] /tmp/nextflow_runs owned by galaxy" || \
      echo "[galaxy] WARNING: could not fix /tmp/nextflow_runs ownership"
    docker exec "$GC" galaxyctl restart gunicorn 2>&1 | tail -2 && \
      echo "[galaxy] gunicorn master restarted (fresh module load)" || \
      echo "[galaxy] galaxyctl restart failed — Galaxy may serve stale code"

    # Ensure Nextflow is installed (lost if container was recreated from image)
    if ! docker exec "$GC" which nextflow > /dev/null 2>&1; then
      echo "[galaxy] Nextflow missing — installing Java + Nextflow..."
      docker exec -u root "$GC" bash -c "
        apt-get update -q && apt-get install -y -q default-jre-headless 2>/dev/null
        curl -fsSL https://get.nextflow.io | bash
        mv nextflow /usr/local/bin/nextflow && chmod +x /usr/local/bin/nextflow
      " 2>&1 | tail -5
      echo "[galaxy] Nextflow installed: $(docker exec "$GC" nextflow -version 2>/dev/null | grep version)"
    else
      echo "[galaxy] Nextflow OK: $(docker exec "$GC" nextflow -version 2>/dev/null | grep version)"
    fi

    # Remove stale conda lock that blocks gunicorn worker startup after restart
    docker exec -u root "$GC" rm -f /app/database/dependencies/conda.lock 2>/dev/null || true

    # Ensure Galaxy is on the shared Docker network (lost if container was recreated)
    docker network connect biomate-dev-net "$GC" 2>/dev/null || true

    # Ensure Galaxy database files are owned by galaxy user (docker cp sets host uid)
    docker exec -u root "$GC" chown galaxy:galaxy \
      /app/database/universe.sqlite /app/database/galaxy_ai_tools.db 2>/dev/null || true

    # Wait for Galaxy to be healthy after restart (up to 120s).
    # Without this, a warm Docker layer cache lets the frontend build finish in
    # ~30s — the health gate then starts before gunicorn workers have restarted
    # their Python AI stack, causing every probe to fail with TCP-RST (workers
    # not ready to recv()) and triggering a false-positive auto-rollback.
    echo "[galaxy] Waiting for Galaxy (8081) to be healthy after HUP (up to 120s)..."
    _galaxy_ok=0
    for _gi in $(seq 1 24); do
      if curl -fsS -o /dev/null --max-time 8 http://localhost:8081/api/version 2>/dev/null; then
        echo "[galaxy] ✓ Galaxy healthy (attempt ${_gi}/24, ~$(((_gi - 1) * 5))s)"
        _galaxy_ok=1
        break
      fi
      sleep 5
    done
    if [ "$_galaxy_ok" -eq 0 ] && docker exec "$GC" sh -c "tail -50 /app/database/gravity/log/gunicorn.log" 2>/dev/null | grep -q "Connection in use"; then
      echo "[galaxy] gunicorn cannot bind :8080 (Connection in use) — clearing strays; supervisord will retry"
      kill_orphan_gunicorn
      for _gi in $(seq 1 24); do
        if curl -fsS -o /dev/null --max-time 8 http://localhost:8081/api/version 2>/dev/null; then
          echo "[galaxy] ✓ Galaxy healthy after clearing strays"; _galaxy_ok=1; break
        fi
        sleep 5
      done
    fi
    if [ "$_galaxy_ok" -eq 0 ]; then
      echo "[galaxy] WARNING: Galaxy did not respond within 120s after HUP — proceeding anyway (health gate will catch it)"
    fi
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
    GC=\$(docker ps --filter 'name=biomate-galaxy' --format '{{.Names}}' | grep -Ev 'rollback|chatgpt' | head -1)
    GC=\"\${GC:-biomate-galaxy-dev}\"
    docker commit \"\$GC\" $RB_GALAXY_IMAGE >/dev/null
    mkdir -p /opt/biomate/rollback
    docker inspect \"\$GC\" --format '{{range .Config.Env}}{{println .}}{{end}}' > /opt/biomate/rollback/galaxy.env
    docker inspect \"\$GC\" --format '{{.HostConfig.NetworkMode}}' > /opt/biomate/rollback/galaxy.net
    docker inspect \"\$GC\" --format '{{range \$p,\$b := .HostConfig.PortBindings}}{{range \$b}}-p {{.HostPort}}:{{\$p}} {{end}}{{end}}' | sed 's#/tcp##g' > /opt/biomate/rollback/galaxy.ports
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

smoke_test_workflow() {
  # Call workflow generation directly on Galaxy — validates the DB schema and
  # AI stack are functional, not just that the HTTP server is up.
  # Returns 0 (pass) or 1 (fail). Called after postsync_health_ok passes.
  log "[smoke] Testing workflow generation (Galaxy localhost:8081)..."
  ec2_ssh '
    result=$(curl -s --max-time 90 http://localhost:8081/api/ai_assistant/generate_workflow \
      -X POST -H "Content-Type: application/json" \
      -d "{\"request_text\":\"run RNA-seq differential expression analysis\",\"user_id\":\"1\"}" 2>/dev/null)
    if [[ -z "$result" ]]; then
      echo "[smoke] FAIL — no response from Galaxy workflow endpoint" >&2
      exit 1
    fi
    ok=$(echo "$result" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    err = d.get(\"error\", \"\")
    success = d.get(\"success\", False)
    # A valid generation result is EITHER a single workflow (workflow_ga/nextflow_path)
    # OR a curated multi-step chain (workflow_type=chain with real steps). Both prove the
    # DB schema + AI stack are functional; a chain IS a runnable pipeline, not 'no workflow'.
    is_chain = d.get(\"workflow_type\") == \"chain\" and bool(d.get(\"chain_steps\"))
    wf = bool(d.get(\"workflow_ga\") or d.get(\"nextflow_path\") or is_chain)
    if err == \"db_unavailable\":
        print(\"FAIL db_unavailable\"); sys.exit(1)
    if err == \"clarification_needed\":
        print(\"CLARIFY\"); sys.exit(2)
    if err:
        print(f\"FAIL error={err}\"); sys.exit(1)
    if not success or not wf:
        print(f\"FAIL success={success} wf={wf}\"); sys.exit(1)
    name = (d.get(\"workflow_ga\") or {}).get(\"name\") or d.get(\"chain_name\") or \"?\"
    print(\"PASS workflow=\" + str(name)); sys.exit(0)
except Exception as e:
    print(f\"FAIL parse_error={e}\"); sys.exit(1)
" 2>&1)
    if grep -q "^CLARIFY" <<<"$ok"; then
      echo "[smoke] clarification_needed — retrying with specific query..."
      result=$(curl -s --max-time 90 http://localhost:8081/api/ai_assistant/generate_workflow \
        -X POST -H "Content-Type: application/json" \
        -d "{\"request_text\":\"run DESeq2 differential expression on human RNA-seq FASTQ files, control vs treatment\",\"user_id\":\"1\"}" 2>/dev/null)
      ok=$(echo "$result" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    err = d.get(\"error\", \"\")
    success = d.get(\"success\", False)
    is_chain = d.get(\"workflow_type\") == \"chain\" and bool(d.get(\"chain_steps\"))
    wf = bool(d.get(\"workflow_ga\") or d.get(\"nextflow_path\") or is_chain)
    if err:
        print(f\"FAIL error={err}\"); sys.exit(1)
    if not success or not wf:
        print(f\"FAIL success={success} wf={wf}\"); sys.exit(1)
    name = (d.get(\"workflow_ga\") or {}).get(\"name\") or d.get(\"chain_name\") or \"?\"
    print(\"PASS workflow=\" + str(name)); sys.exit(0)
except Exception as e:
    print(f\"FAIL parse_error={e}\"); sys.exit(1)
" 2>&1)
    fi
    echo "[smoke] $ok"
    grep -q "^PASS" <<<"$ok" && exit 0 || exit 1
  '
}

smoke_test_db_search() {
  # Behavioral gate: assert the intent-driven `operation` param is honored
  # end-to-end through the FRONTEND PROXY (localhost:3000 -> Galaxy) — the exact
  # path where routes.ts:8135 silently dropped `operation` on 2026-07-19.
  # DETERMINISTIC: the similarity code path sets its `search` tag even when the
  # upstream API (ChEMBL/RCSB) returns zero hits, so this never flakes on an
  # external outage. CONSERVATIVE: an empty/unreachable response is treated as
  # inconclusive (exit 0) — unreachability is postsync_health_ok's job — so a
  # transient blip cannot trigger a false rollback. Only a REACHABLE-but-WRONG
  # response fails the gate. See docs/20260719_INTENT_DRIVEN_DB_SEARCH_AND_DEPLOY_ROOT_CAUSE.md
  log "[smoke] Testing intent-driven DB-search routing (frontend proxy -> Galaxy)..."
  # Decide on the OUTPUT, not the exit code: roll back ONLY when the remote check
  # printed a definitive "[smoke] FAIL" line. An ec2_ssh transient error (SSH
  # blip, timeout) yields no FAIL line -> return 0 -> never a false rollback.
  local _dbs_out
  _dbs_out="$(ec2_ssh '
    UBIQ="MQIFVKTLTGKTITLEVEPSDTIENVKAKIQDKEGIPPDQQRLIFAGKQLEDGRTLSDYNIQKESTLHLVLRLRGG"
    q() { curl -s --max-time 45 -X POST http://localhost:3000/api/databases/query \
            -H "Content-Type: application/json" \
            -H "x-e2e-test-token: biomate-e2e-bypass-token-dev-only" -d "$1"; }
    # A response is WELL-FORMED only if it carries the source tag; {"error":...},
    # empty, or a cold-start 5xx are transient -> retry, never fail the gate.
    cs=""; ps=""
    for try in 1 2 3 4 5; do
      cs=$(q "{\"database\":\"chembl\",\"query\":\"CC(=O)Oc1ccccc1C(=O)O\",\"operation\":\"similarity\"}")
      ps=$(q "{\"database\":\"pdb\",\"query\":\"$UBIQ\",\"operation\":\"similarity\"}")
      if grep -q "\"source\": *\"chembl\"" <<<"$cs" && grep -q "\"source\": *\"pdb\"" <<<"$ps"; then break; fi
      sleep 8
    done
    if ! grep -q "\"source\": *\"chembl\"" <<<"$cs" || ! grep -q "\"source\": *\"pdb\"" <<<"$ps"; then
      echo "[smoke] db-search INCONCLUSIVE — no well-formed response after retries (transient); not failing the gate"
      exit 0
    fi
    # Well-formed responses in hand: a MISSING search tag now means the operation
    # param was dropped/ignored (proxy drop or stale code) — a real regression.
    fail=0
    grep -q "\"search\": *\"tanimoto_similarity\"" <<<"$cs" || { echo "[smoke] FAIL chembl operation=similarity not routed (proxy drop / stale code)"; fail=1; }
    grep -q "\"search\": *\"sequence_similarity\"" <<<"$ps" || { echo "[smoke] FAIL pdb operation=similarity not routed"; fail=1; }
    pt=$(q "{\"database\":\"pdb\",\"query\":\"$UBIQ\",\"operation\":\"text\"}")
    if grep -q "\"source\": *\"pdb\"" <<<"$pt"; then
      grep -q "\"search\": *\"sequence_similarity\"" <<<"$pt" && { echo "[smoke] FAIL pdb operation=text wrongly ran similarity (operation ignored)"; fail=1; }
    fi
    [ "$fail" -eq 1 ] && exit 1
    echo "[smoke] db-search operation routing OK (similarity != text)"
    exit 0
  ' 2>&1)"
  echo "$_dbs_out"
  # Roll back ONLY on a definitive regression signal; anything else is safe.
  if grep -q '\[smoke\] FAIL' <<<"$_dbs_out"; then
    return 1
  fi
  return 0
}

smoke_test_connector() {
  # Contract gate for the MCP/connector surface: assert every tool declared in
  # the canonical manifest resolves to a live endpoint with the declared verb,
  # and that the ChatGPT /tools/{name} adapter handles each one. This catches the
  # exact class of bugs fixed 2026-07-21/22 that the STATIC drift test cannot —
  # a manifest verb/path that 404s on the running server, a tool missing from an
  # adapter switch, a Phase-2 stub, or the /mcp remote transport being down.
  # Runs LOCALLY (needs node) against the public dev URL — the real client path.
  # WARN-ONLY: transient 502/timeout are reported as inconclusive, never a FAIL,
  # so a blip can't trigger a rollback. Only a definitive contract violation FAILs.
  local url="${CONNECTOR_TEST_URL:-https://dev-public.biomate.ai}"
  if ! command -v node >/dev/null 2>&1; then
    log "[smoke] connector contract SKIPPED (node not on PATH)"
    return 0
  fi
  log "[smoke] Testing connector tool contract ($url)..."
  local _out
  _out="$(node "$REPO_ROOT/scripts/connector_contract_test.mjs" "$url" 2>&1)"
  echo "$_out" | grep -E '\[smoke\] (FAIL|.*inconclusive|.*summary|.*reachability|.*drift)'
  if grep -q '\[smoke\] FAIL' <<<"$_out"; then
    return 1
  fi
  return 0
}

postsync_health_ok() {
  # Probe the dev host's mapped ports; retry to ride out HUP / cold start.
  # $1 = number of 5s retries (default 24 = 120s).
  # Prints which port is failing so we can distinguish Galaxy vs Frontend issues.
  # Returns 0 healthy, 1 unhealthy (probes ran and failed), 2 UNVERIFIED (could not reach the host).
  # ec2_ssh exits 255 on a transport failure (SSM "TargetNotConnected", dropped SSH): that is not a
  # health verdict. On 2026-11-04 a healthy deploy was rolled back because the first probe's SSM
  # session failed ("i-06696b0d91f4346e0 is not connected"); transport failures are now retried.
  local attempt rc
  for attempt in 1 2 3 4 5; do
    _postsync_probe "$@"; rc=$?
    [[ $rc -ne 255 ]] && return $rc
    log "[health] cannot reach the dev host (ssh/SSM exit 255) — retrying in $((attempt * 15))s; not a health verdict"
    sleep $((attempt * 15))
  done
  log "[health] dev host unreachable after 5 attempts — health UNVERIFIED"
  return 2
}

_postsync_probe() {
  local tries="${1:-24}"
  ec2_ssh "
    for i in \$(seq 1 $tries); do
      gx=0; fe=0
      curl -fsS -o /dev/null --max-time 8 http://localhost:8081/api/version 2>/dev/null && gx=1
      curl -fsS -o /dev/null --max-time 8 http://localhost:3000/api/health 2>/dev/null && fe=1
      if [ \$gx -eq 1 ] && [ \$fe -eq 1 ]; then
        # Launch-path check: the galaxy user must be able to create a Nextflow run dir,
        # or every workflow launch fails with Permission denied on /tmp/nextflow_runs.
        # (No double quotes or angle brackets in these comments: this text is inside the
        # double-quoted ec2_ssh string, and a quote here broke the probe on 2026-11-11.)
        if docker exec -u galaxy biomate-galaxy-dev sh -c 'd=/tmp/nextflow_runs/.writecheck-\$\$; mkdir -p \$d && rmdir \$d' 2>/dev/null; then exit 0; fi
        echo \"[probe \$i/$tries] galaxy cannot create a run dir in /tmp/nextflow_runs — workflow launches would fail\"
      fi
      echo \"[probe \$i/$tries] galaxy=\$gx frontend=\$fe\"
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
    # Write a filtered env file (drop shell-only vars that docker --env-file rejects)
    grep -vE '^(PATH|HOME|TERM|HOSTNAME|SHELL|SHLVL|LOGNAME|USER|_)=' /opt/biomate/rollback/galaxy.env > /tmp/galaxy_rollback.env
    docker rm -f biomate-galaxy-dev >/dev/null 2>&1 || true
    # Use --env-file instead of per-var -e flags: avoids word-splitting bugs when
    # env values contain spaces or shell-special chars.
    docker run -d --name biomate-galaxy-dev --network \"\$NET\" \$PORTS \
      -v $GALAXY_DB_HOST_PATH:/app/database \
      --restart unless-stopped --env-file /tmp/galaxy_rollback.env $RB_GALAXY_IMAGE >/dev/null
    docker network connect biomate-dev-net biomate-galaxy-dev 2>/dev/null || true
    # The snapshot preserves file ownership; make sure Galaxy can create run dirs again.
    docker exec -u root biomate-galaxy-dev sh -c 'mkdir -p /tmp/nextflow_runs && chown -R galaxy:galaxy /tmp/nextflow_runs' 2>/dev/null || true
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
        # Keep INTERACTIVE_TOOLS_ENABLED in sync with the live Galaxy docker-socket
        # mount even on a frontend rollback (same rule as deploy_frontend).
        if docker inspect biomate-galaxy-dev --format "{{range .Mounts}}{{.Destination}} {{end}}" 2>/dev/null | grep -q "/var/run/docker.sock"; then
          IT_ENABLED=1
        else
          IT_ENABLED=0
        fi
        docker run -d --name biomate-dev-frontend --network biomate-dev-net \
          -p 3000:3000 --env-file /opt/biomate/.env \
          -e NODE_ENV=production -e PORT=3000 -e FORCE_HTTPS=0 \
          -e INTERACTIVE_TOOLS_ENABLED="$IT_ENABLED" \
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

  # Determine what changed.
  # Test/spec files and e2e fixtures don't affect the production Docker image —
  # exclude them so a test-only commit doesn't force an expensive full rebuild.
  # Membership tests read here-strings, not `echo | grep -q`: under pipefail, grep -q exits at its
  # first match, echo then dies of SIGPIPE on a large list, and the test reads as "no match" — a
  # 2,300-file change list silently skipped the backend + workflows layers (2026-11-08).
  _runtime_frontend="$(echo "$changed_paths" | grep "^frontend/" | \
    grep -vE '\.(test|spec)\.(ts|tsx|js)$|^frontend/e2e/' || true)"
  [[ -n "$_runtime_frontend" ]] && do_frontend=true
  grep -q "^backend/lib/" <<<"$changed_paths" && do_backend=true
  # The workflows layer also runs when the stub→run-copy regeneration script itself
  # changes (e.g. the first deploy of the Stream-6 fix), so a scripts-only diff still
  # executes deploy_workflows and regenerates stale run-copies instead of lying dormant.
  grep -qE "^backend/biomni_workflows/|^backend/nf-core-workflows/modules/biomate-ai-tools/|^backend/nf-core-modules/|^infra/nfcore-patches/|^scripts/regen_stub_runcopies\.sh$" <<<"$changed_paths" && do_workflows=true
  grep -q "^backend/database/" <<<"$changed_paths" && do_db=true
  # BIOMATE_SYNC_FORCE=frontend,backend,workflows re-deploys those layers even with no matching
  # change, e.g. to exercise a change to this script itself.
  [[ ",${BIOMATE_SYNC_FORCE:-}," == *",frontend,"* ]] && do_frontend=true
  [[ ",${BIOMATE_SYNC_FORCE:-}," == *",backend,"* ]] && do_backend=true
  [[ ",${BIOMATE_SYNC_FORCE:-}," == *",workflows,"* ]] && do_workflows=true

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
  if [[ "$local_db_mtime" -gt "${LAST_DB_SYNC:-0}" ]]; then
    # Only set do_db when local file is not smaller than dev — prevents the
    # 5.2MB local stub from overwriting the 327MB dev DB on every run.
    local _ldb_size
    _ldb_size=$(stat -c %s "$REPO_ROOT/backend/database/galaxy_ai_tools.db" 2>/dev/null \
      || stat -f %z "$REPO_ROOT/backend/database/galaxy_ai_tools.db" 2>/dev/null \
      || echo 0)
    # Push when local is not a STUB. Historically this required local >= dev BYTES,
    # but that wrongly blocks a legitimately-smaller FULL DB (e.g. after a VACUUM,
    # or with an added column that is still < dev's un-VACUUMed bytes). A real DB is
    # >100MB; a stub is ~5MB. So push when local >= dev OR local is clearly a full DB.
    if [[ "${_ldb_size:-0}" -ge "${_DEV_DB_SIZE:-0}" || "${_ldb_size:-0}" -ge 104857600 ]]; then
      do_db=true
    else
      log "[db] local (${_ldb_size}B) looks like a stub (<100MB and < dev ${_DEV_DB_SIZE:-?}B) — skipping DB sync"
    fi
  fi

  # Frontend-only override: ship just the frontend layer, leaving the Galaxy
  # backend + workflow DB exactly as they are on dev. Use when a frontend/Node
  # change must go out but the backend/DB layers are unchanged or known-bad for
  # this commit (e.g. a stale workflow DB missing a column the merged backend
  # queries — which would fail the smoke gate and roll the whole deploy back).
  # Trigger via BIOMATE_ONLY_FRONTEND=1.
  if [[ "${BIOMATE_ONLY_FRONTEND:-}" == "1" ]]; then
    do_backend=false; do_workflows=false; do_db=false
    log "[layers] BIOMATE_ONLY_FRONTEND=1 → forcing backend/workflows/db OFF (frontend only)"
  fi
  # Explicit DB opt-out (wrong-worktree catalog, FTS rebuild pending, code-only ship).
  if [[ "${BIOMATE_SYNC_DB:-1}" == "0" ]]; then
    do_db=false
    log "[layers] BIOMATE_SYNC_DB=0 → forcing db=false (DEV keeps current galaxy_ai_tools.db)"
  fi

  # Diagnostic: log which layers will run (makes silent skips visible in the log)
  log "Layers: frontend=$do_frontend backend=$do_backend workflows=$do_workflows db=$do_db"
  # Stash for the post-sync DEV receipt
  _SYNC_LAYERS_SUMMARY="frontend=$do_frontend backend=$do_backend workflows=$do_workflows db=$do_db"

  # Snapshot the pre-sync state BEFORE any mutation (and before the optional
  # resync_galaxy_env recreates the container) so we can roll back if the sync
  # leaves dev unhealthy.
  validate_sync_inputs || return 1
  snapshot_for_rollback "$do_frontend"

  # Cosmetic assets are mutations too: ship only after preflight and snapshot.
  sync_logo 2>/dev/null || true

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
  if $do_backend || $do_workflows; then
    ensure_nfcore_pipelines || return 1
  fi

  $do_backend   && deploy_backend_python
  $do_workflows && deploy_workflows
  $do_db        && deploy_databases

  # Build the TOOL semantic index (galaxy_ai_tools_embeddings.npz) as a deploy
  # artifact — on a backend change (embedding-recipe/code) OR a DB change (tool
  # rows). Mirrors the workflow-embedding warm. VectorToolSearch builds in
  # __init__; BIOMATE_EMBED_SERVER_DISABLE=1 forces the fast in-process batch
  # encode (server may not be up here). Short-text recipe keeps 12k under the
  # timeout. Non-fatal — tool search degrades to FTS-only if it fails. No
  # apostrophes in the ssh block (see sync 9 root cause in CLAUDE.md).
  if $do_backend || $do_db; then
    # Install the pre-built TOOL semantic index (galaxy_ai_tools_embeddings.npz),
    # built OFFLINE on a fast box and shipped via S3 — instead of the ~30-min
    # in-container build that starves the dev CPU. The .npz carries a "shipped"
    # marker so VectorToolSearch trusts it (no staleness rebuild). Non-fatal:
    # tool search degrades to FTS-only if it is absent.
    _TE_NPZ_S3="s3://biomate-models-399683337364/v6_eval_runs/galaxy_ai_tools_embeddings.npz"
    _TE_LOCAL="/tmp/biomate_tool_embed.npz"
    if aws s3 cp "$_TE_NPZ_S3" "$_TE_LOCAL" >/dev/null 2>&1; then
      ec2_scp "$_TE_LOCAL" "${EC2_USER}@${EC2_HOST}:/tmp/tool_embed.npz" >/dev/null 2>&1
      ec2_ssh '
        GC=$(docker ps --filter "name=biomate-galaxy" --format "{{.Names}}" | grep -Ev "rollback|chatgpt" | head -1)
        GC="${GC:-biomate-galaxy-dev}"
        docker cp /tmp/tool_embed.npz "$GC":/app/database/galaxy_ai_tools_embeddings.npz \
          && docker exec "$GC" chown galaxy:galaxy /app/database/galaxy_ai_tools_embeddings.npz \
          && echo "[tool-embed] shipped npz installed" || echo "[tool-embed] WARNING: npz install failed"
      ' || log "[tool-embed] WARNING: npz install ssh step failed"
    else
      log "[tool-embed] no prebuilt npz at $_TE_NPZ_S3 — tool search FTS-only until one is shipped"
    fi
  fi
  # HUP Galaxy when either backend Python OR workflow .nf files change.
  # Workflows used to skip the HUP on the theory that Nextflow reads .nf
  # from disk per-run, but Galaxy's in-process workflow_search keeps a
  # parsed step cache + tool DB cache that stays pinned to old file
  # contents until the worker process recycles. Skipping HUP caused the
  # 2026-05-21 class of "fix shipped but old behaviour persists" issues.
  #
  # ORDERING: restart_galaxy MUST run AFTER deploy_databases. deploy_databases
  # does `docker stop/start` + `docker restart` on the Galaxy container (to
  # safely copy the 304MB galaxy_ai_tools.db + 3.4MB universe.sqlite). Each
  # of these restarts triggers a 3.5-minute Galaxy cold-start. If restart_galaxy
  # (with its health wait) ran BEFORE deploy_databases, the health confirmation
  # was worthless — the DB sync would immediately restart Galaxy again, and
  # the post-sync health gate would start before Galaxy had time to boot.
  # Root cause of sync 7 failure (2026-07-03): Docker build took ~2 min (warm
  # cache), health gate started only ~2 min after the last `docker restart`,
  # but Galaxy needs 3.5 min to boot → all 48 probes timed out.
  ($do_backend || $do_workflows || $do_db) && restart_galaxy
  # The new frontend applies pending PostgreSQL migrations transactionally at
  # startup, before registering routes. Health/rollback catches startup failure.
  # A failed frontend deploy MUST abort the sync before the health gate and the
  # marker write — otherwise the health gate passes on the still-running OLD
  # container and the sync records a false success (2026-09-13 silent-fail).
  # set -e is suppressed here (if do_sync ...), so check the rc explicitly.
  if $do_frontend; then
    if ! deploy_frontend; then
      log "[frontend] deploy FAILED — aborting sync; dev NOT advanced to ${CURRENT_COMMIT:0:8} (marker unchanged, re-run when the link is stable)"
      SYNC_RESULT=failed
      return 1
    fi
  fi
  # remote_mcp runs AFTER the frontend (which now points MCP_UPSTREAM_URL at the
  # mcp container). Failure here never aborts the sync — it self-reports + logs;
  # the connector canary below also flags a down /mcp. Never fails the deploy.
  $do_frontend  && { deploy_remote_mcp || log "[remote_mcp] ⚠ deploy step failed — /mcp may be down; see logs above"; }

  # --- Post-sync health gate + auto-rollback -------------------------------
  # 120 retries × 5s = 600s (10 min). Galaxy is confirmed healthy by
  # restart_galaxy's internal wait (which now runs AFTER deploy_databases),
  # so this gate mainly covers frontend cold-start + rare Galaxy edge cases.
  # covers the frontend container's cold-start (Node.js + DB migrations).
  if [[ "$ROLLBACK_READY" == 1 ]]; then
    log "[health] Verifying dev health after sync..."
    postsync_health_ok 120; _health_rc=$?
    if [[ $_health_rc -eq 2 ]]; then
      # Could not reach the host at all: rolling back needs that same connection and would undo a
      # deploy nobody could check. Report it; a human verifies dev and decides.
      log "[health] ⚠ dev health UNVERIFIED (host unreachable) — NOT rolling back; verify https://dev-public.biomate.ai before relying on this deploy"
      SYNC_RESULT=unverified
    elif [[ $_health_rc -eq 0 ]]; then
      if smoke_test_workflow; then
        log "[health] ✓ dev healthy + smoke test passed"
        SYNC_RESULT=healthy
        # Behavioral canary — WARN ONLY. It never blocks or rolls back the
        # deploy; it just surfaces an operation-routing regression loudly so a
        # human investigates. (Kept advisory until proven across real syncs;
        # promote to a rollback gate later if desired.)
        if ! smoke_test_db_search; then
          log "[health] ⚠ WARNING: DB-search operation-routing canary FAILED — deploy KEPT (not rolled back). Investigate proxy/operation forwarding; see docs/20260719_INTENT_DRIVEN_DB_SEARCH_AND_DEPLOY_ROOT_CAUSE.md"
        fi
        # Connector contract canary — WARN ONLY (same policy as db-search). Surfaces
        # a broken MCP/connector tool (dead route, wrong verb, stub, adapter miss,
        # or /mcp down) at deploy time instead of when a user hits it.
        if ! smoke_test_connector; then
          log "[health] ⚠ WARNING: connector contract canary FAILED — deploy KEPT (not rolled back). A tool's endpoint 404s / wrong verb / stub, or the manifest drifted from the running server. See docs/20260723_CONNECTOR_CONTRACT_TEST_AND_STABILITY.md"
        fi
      else
        log "[health] ✗ smoke test FAILED (workflow generation broken) — auto-rolling back"
        rollback_sync || true
      fi
    else
      log "[health] ✗ dev UNHEALTHY after sync — auto-rolling back"
      rollback_sync || true
    fi
  else
    # Snapshot wasn't taken — can't safely roll back. Still report real health.
    log "[health] No snapshot — health-gate without rollback safety"
    if postsync_health_ok 120; then SYNC_RESULT=healthy; else SYNC_RESULT=failed; fi
  fi

  log "=== Sync complete for ${commit:0:8} (result=${SYNC_RESULT:-unknown}) ==="
  [[ "$SYNC_RESULT" == healthy ]] && record_deploy_ledger "$commit"
  [[ "$SYNC_RESULT" == healthy ]] && return 0 || return 1
}

# ---------------------------------------------------------------------------
# Deploy ledger — who put what on dev (append-only, on the dev host)
# ---------------------------------------------------------------------------
# Every successful scripted sync and every GitHub-Action deploy appends one JSON
# line to /opt/biomate/.deploy-ledger.jsonl. Before deploying we print the last
# entries and warn when what is LIVE is not the last recorded deploy — i.e. someone
# deployed through a path that skips the ancestry gate (an old checkout of this
# script, a raw docker command). "Who removed my fix" becomes answerable.
DEPLOY_LEDGER=/opt/biomate/.deploy-ledger.jsonl
record_deploy_ledger() {
  local _commit="$1" _branch _who _line
  _branch="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
  _who="$(git -C "$REPO_ROOT" config user.name 2>/dev/null || echo '?')@$(hostname -s 2>/dev/null || echo '?')"
  _line="$(python3 -c 'import json,sys,datetime; print(json.dumps({"at": datetime.datetime.utcnow().isoformat(timespec="seconds")+"Z", "commit": sys.argv[1], "branch": sys.argv[2], "by": sys.argv[3], "via": "sync_to_dev.sh", "override": sys.argv[4] or None}))' "$_commit" "$_branch" "$_who" "${BIOMATE_EMERGENCY_DEPLOY_REASON:-}")"
  ec2_ssh "printf '%s\\n' $(printf '%q' "$_line") >> $DEPLOY_LEDGER" \
    && log "[ledger] recorded ${_commit:0:8} (${_branch}) by ${_who}" \
    || log "[ledger] WARNING: could not append to $DEPLOY_LEDGER"
}
show_deploy_ledger() {
  local _live="$1" _tail _last
  _tail="$(ec2_ssh "tail -n 5 $DEPLOY_LEDGER 2>/dev/null" || true)"
  if [[ -z "$_tail" ]]; then
    log "[ledger] no deploy ledger yet on dev (first recorded sync)"
    return 0
  fi
  log "[ledger] last deploys to dev:"
  printf '%s\n' "$_tail" | sed 's/^/    /'
  _last="$(printf '%s\n' "$_tail" | tail -n 1 | python3 -c 'import json,sys; print(json.loads(sys.stdin.read()).get("commit",""))' 2>/dev/null || true)"
  if [[ -n "$_last" && "$_last" != "$_live" ]]; then
    log "[ledger] WARNING: dev is running ${_live:0:10} but the last RECORDED deploy was ${_last:0:10}."
    log "[ledger]          Someone deployed without the ancestry gate. The gate below still refuses"
    log "[ledger]          to drop what is live; merge it if refused."
  fi
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
  grep -E "^(frontend/client/|frontend/server/|frontend/shared/|backend/lib/|backend/biomni_workflows/|backend/nf-core-workflows/modules/biomate-ai-tools/)" || true)
if [[ -n "$DIRTY_SOURCE" && "${BIOMATE_ENABLE_IT:-}" != "1" ]]; then
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
#   Code layers (frontend/, backend/lib/, backend/biomni_workflows/, backend/nf-core-workflows/modules/biomate-ai-tools/):
#     git diff against last-synced commit — only files in those trees
#     that actually changed get included.
#   DB layer (galaxy_ai_tools.db):
#     gitignored binary — use md5 of the local file vs. a stored
#     "last-synced md5" in .last_dev_sync_db_md5. Only syncs when
#     the file content has actually changed.
_PREV_COMMIT_FILE="$REPO_ROOT/.last_dev_sync_commit"
_DB_MD5_FILE="$REPO_ROOT/.last_dev_sync_db_md5"
# Remote atomic lease also excludes deployments from other workstations.
REMOTE_SYNC_LEASE="$(python3 -c 'import uuid; print(uuid.uuid4().hex)')"
# Staleness break: a sync killed/stopped before its on_exit trap (e.g. a too-short
# background timeout, or session teardown) leaves the lock dir with a dead owner and no
# self-heal — blocking ALL deploys until a human clears it (hit twice 2026-11-11). Break
# the lease ONLY when it is older than any real sync could run (a full sync is ~14 min),
# so a LIVE deploy is never touched; then re-acquire. 1800s = 30 min.
_LEASE_STALE_S=1800
if ec2_ssh "umask 077; mkdir /opt/biomate/.dev-deploy.lock && printf '%s\n' '$REMOTE_SYNC_LEASE' > /opt/biomate/.dev-deploy.lock/owner"; then
  REMOTE_SYNC_LEASE_ACQUIRED=1
else
  _lease_age=$(ec2_ssh 'echo $(( $(date +%s) - $(stat -c %Y /opt/biomate/.dev-deploy.lock 2>/dev/null || date +%s) ))' 2>/dev/null | tr -cd '0-9')
  if [[ -n "$_lease_age" && "$_lease_age" -gt "$_LEASE_STALE_S" ]] && \
     ec2_ssh "rm -f /opt/biomate/.dev-deploy.lock/owner; rmdir /opt/biomate/.dev-deploy.lock 2>/dev/null; umask 077; mkdir /opt/biomate/.dev-deploy.lock && printf '%s\n' '$REMOTE_SYNC_LEASE' > /opt/biomate/.dev-deploy.lock/owner"; then
    log "Broke a STALE remote lease (orphaned ${_lease_age}s > ${_LEASE_STALE_S}s, no live sync runs that long) and re-acquired"
    REMOTE_SYNC_LEASE_ACQUIRED=1
  else
    _lease_owner="$(ec2_ssh 'cat /opt/biomate/.dev-deploy.lock/owner 2>/dev/null' 2>/dev/null || true)"
    biomate_remote_lease_refuse_message "${_lease_age:-unknown}" "$_LEASE_STALE_S" "${_lease_owner:-}" >&2
    exit 1
  fi
fi
# Refuse stale/divergent worktrees while holding the deployment lease. This is
# read-only and does not change existing layer selection or health/rollback.
_ANCESTRY_ARGS=(--repo "$REPO_ROOT")
if [[ -n "${BIOMATE_EMERGENCY_DEPLOY_REASON:-}" ]]; then
  log "WARNING: explicit emergency ancestry override requested; retain the incident reason"
  _ANCESTRY_ARGS+=(--emergency-override-reason "$BIOMATE_EMERGENCY_DEPLOY_REASON")
fi
# The public build-info.json is baked only into the FRONTEND image, so a
# backend/db/workflow-only deploy leaves it stale and the gate above (build-info
# only) could let a later full deploy silently overwrite that backend-only work.
# The ledger records every deploy's full HEAD; read its last commit (over the
# lease we already hold) and make the gate require HEAD to contain it too.
_LEDGER_HEAD="$(ec2_ssh "tail -n 1 $DEPLOY_LEDGER 2>/dev/null" 2>/dev/null | python3 -c 'import json,sys,re
try:
  c=(json.loads(sys.stdin.read() or "{}") or {}).get("commit","")
  print(c if c and re.fullmatch(r"[0-9a-f]{40}", c) else "")
except Exception:
  print("")' 2>/dev/null || true)"
if [[ -n "$_LEDGER_HEAD" ]]; then
  _ANCESTRY_ARGS+=(--ledger-head "$_LEDGER_HEAD")
fi
_ANCESTRY_JSON="$(python3 "$REPO_ROOT/scripts/dev_deploy_ancestry.py" "${_ANCESTRY_ARGS[@]}")" || exit 2
_DEPLOYED_COMMIT="$(printf '%s' "$_ANCESTRY_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["deployedCommit"])')"
log "Public dev ancestry verified: ${_DEPLOYED_COMMIT:0:8} -> ${CURRENT_COMMIT:0:8}"
show_deploy_ledger "$_DEPLOYED_COMMIT"
if [[ "${BIOMATE_ENABLE_IT:-}" == "1" ]]; then
  enable_interactive_tools
  log "=== IT review/apply path finished (full code and DB sync skipped) ==="
  exit 0
fi

_LOCAL_DB="$REPO_ROOT/backend/database/galaxy_ai_tools.db"
_SYNC_LAYERS_SUMMARY=""   # filled inside do_sync for the DEV receipt
_RECEIPT_DB_MD5="?"
_RECEIPT_WF_COUNT="?"
_RECEIPT_IK_COUNT="?"

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
#
# BIOMATE_SYNC_DB=0: never schedule a catalog upload (code/workflows-only). Required when
# this worktree's galaxy_ai_tools.db is the wrong lineage (review vs biomate vs stub) or
# FTS-broken — do not use "DB aside" hot-patches (2026-11-13).
_DEV_DB_WF_COUNT="-1"
_LOCAL_DB_MD5="$(md5 -q "$_LOCAL_DB" 2>/dev/null || md5sum "$_LOCAL_DB" 2>/dev/null | cut -d' ' -f1 || echo '')"
if [[ "${BIOMATE_SYNC_DB:-1}" == "0" ]]; then
  log "BIOMATE_SYNC_DB=0 — catalog upload disabled for this run"
elif [[ -n "$_LOCAL_DB_MD5" ]]; then
  # Fetch the actual dev DB md5 + size + workflow count via SSH. One round-trip saves 300MB.
  _DEV_DB_PROBE="$(ec2_ssh '
    GC=$(docker ps --filter "name=biomate-galaxy" --format "{{.Names}}" | grep -Ev "rollback|chatgpt" | head -1)
    GC="${GC:-biomate-galaxy-dev}"
    md5=$(docker exec "$GC" md5sum /app/database/galaxy_ai_tools.db 2>/dev/null | cut -d" " -f1)
    sz=$(docker exec "$GC" stat -c %s /app/database/galaxy_ai_tools.db 2>/dev/null || echo 0)
    wf=$(docker exec "$GC" python3.9 -c "import sqlite3; print(sqlite3.connect(\"/app/database/galaxy_ai_tools.db\").execute(\"select count(*) from workflows\").fetchone()[0])" 2>/dev/null || echo -1)
    printf "%s %s %s\n" "${md5:-}" "${sz:-0}" "${wf:--1}"
  ' 2>/dev/null || echo '')"
  _DEV_DB_MD5="$(awk '{print $1}' <<<"$_DEV_DB_PROBE")"
  _DEV_DB_SIZE="$(awk '{print $2}' <<<"$_DEV_DB_PROBE")"
  _DEV_DB_WF_COUNT="$(awk '{print $3}' <<<"$_DEV_DB_PROBE")"
  [[ "$_DEV_DB_SIZE" =~ ^[0-9]+$ ]] || _DEV_DB_SIZE=0
  [[ "$_DEV_DB_WF_COUNT" =~ ^-?[0-9]+$ ]] || _DEV_DB_WF_COUNT=-1

  # Preflight DB policy before do_sync mutates anything: FTS / min count / shrink.
  # Stub / low-count DBs → skip upload and continue (code sync still OK).
  # FTS-broken or shrink of a full local catalog → hard abort (do not "DB aside").
  _LOCAL_WF_COUNT="$(biomate_db_workflow_count "$_LOCAL_DB")"
  _DB_DECISION="$(biomate_db_upload_decision "$_LOCAL_DB" "$_DEV_DB_WF_COUNT")"
  _LOCAL_DB_SIZE="$(stat -c %s "$_LOCAL_DB" 2>/dev/null || stat -f %z "$_LOCAL_DB" 2>/dev/null || echo 0)"
  if [[ "$_LOCAL_DB_MD5" != "$_DEV_DB_MD5" || "${_DEV_DB_SIZE:-0}" -lt 1048576 ]]; then
    case "$_DB_DECISION" in
      allow)
        if [[ "${_LOCAL_DB_SIZE:-0}" -lt "${_DEV_DB_SIZE:-0}" && "${_LOCAL_DB_SIZE:-0}" -lt 104857600 ]]; then
          log "DB: local (${_LOCAL_DB_SIZE}B) looks like a stub (<100MB and < dev ${_DEV_DB_SIZE}B) — skipping upload"
        else
          CHANGED="$CHANGED"$'\n'"backend/database/"
          log "DB out of sync (local=$_LOCAL_DB_MD5 dev=${_DEV_DB_MD5:-?} local_wf=$_LOCAL_WF_COUNT dev_wf=${_DEV_DB_WF_COUNT} size=${_DEV_DB_SIZE}B) — will sync"
        fi
        ;;
      refuse_count|refuse_missing)
        log "DB: $(biomate_db_decision_message "$_DB_DECISION" "$_LOCAL_DB" "$_LOCAL_WF_COUNT" "$_DEV_DB_WF_COUNT")"
        log "DB: skipping catalog upload; continuing with code layers (set BIOMATE_SYNC_DB=0 to silence)"
        ;;
      refuse_fts|refuse_shrink)
        # Full-looking local DB that would have been uploaded under the old soft-skip path.
        if [[ "${_LOCAL_DB_SIZE:-0}" -ge 104857600 ]]; then
          log "ERROR: $(biomate_db_decision_message "$_DB_DECISION" "$_LOCAL_DB" "$_LOCAL_WF_COUNT" "$_DEV_DB_WF_COUNT")"
          log "ERROR: refusing sync so DEV is not left with a wrong/silent catalog. Fix FTS, use the designated catalog worktree, BIOMATE_SYNC_DB_ALLOW_SHRINK=1 (shrink only), or BIOMATE_SYNC_DB=0 for code-only."
          exit 2
        fi
        log "DB: $(biomate_db_decision_message "$_DB_DECISION" "$_LOCAL_DB" "$_LOCAL_WF_COUNT" "$_DEV_DB_WF_COUNT") — treating as stub skip"
        ;;
      *)
        log "ERROR: unexpected DB decision '$_DB_DECISION'"
        exit 2
        ;;
    esac
  else
    log "DB in sync on dev (${_DEV_DB_MD5}; wf=${_DEV_DB_WF_COUNT}) — skipping 300MB transfer"
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
  # The marker means "last commit shipped to ALL code layers". A frontend-only run
  # (BIOMATE_ONLY_FRONTEND=1) leaves backend/workflows/db commits unshipped, so it must
  # NOT advance it; otherwise the next full sync diffs from here and silently skips them
  # (happened twice on 2026-11-02, see docs/20261102_SEARCH_FAILURE_VISIBILITY_AND_SYNC_MARKER.md).
  if [[ "${BIOMATE_ONLY_FRONTEND:-}" == "1" ]]; then
    log "[marker] frontend-only run: last-synced marker NOT advanced (stays at ${_PREV_COMMIT:0:8})"
  else
    echo "$CURRENT_COMMIT" > "$_PREV_COMMIT_FILE"
  fi
  log "=== Sync OK at ${CURRENT_COMMIT:0:8} ==="
  # One-screen DEV receipt — what is live after this healthy sync (cheap docker exec).
  _RECEIPT_PROBE="$(ec2_ssh '
    GC=$(docker ps --filter "name=biomate-galaxy" --format "{{.Names}}" | grep -Ev "rollback|chatgpt" | head -1)
    GC="${GC:-biomate-galaxy-dev}"
    md5=$(docker exec "$GC" md5sum /app/database/galaxy_ai_tools.db 2>/dev/null | cut -d" " -f1)
    stats=$(docker exec "$GC" python3.9 -c "
import sqlite3
c=sqlite3.connect(\"/app/database/galaxy_ai_tools.db\")
wf=c.execute(\"select count(*) from workflows\").fetchone()[0]
try:
  ik=c.execute(\"select count(*) from workflows where input_kinds is not null and trim(input_kinds) not in (\\\"\\\",\\\"null\\\")\").fetchone()[0]
except Exception:
  ik=\"?\"
print(f\"{wf} {ik}\")
" 2>/dev/null || echo "? ?")
    printf "%s %s\n" "${md5:-?}" "${stats:-? ?}"
  ' 2>/dev/null || echo '? ? ?')"
  _RECEIPT_DB_MD5="$(awk '{print $1}' <<<"$_RECEIPT_PROBE")"
  _RECEIPT_WF_COUNT="$(awk '{print $2}' <<<"$_RECEIPT_PROBE")"
  _RECEIPT_IK_COUNT="$(awk '{print $3}' <<<"$_RECEIPT_PROBE")"
  _RECEIPT_BRANCH="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
  biomate_print_dev_receipt \
    "$CURRENT_COMMIT" \
    "$_RECEIPT_BRANCH" \
    "${_SYNC_LAYERS_SUMMARY:-unknown}" \
    "$_RECEIPT_DB_MD5" \
    "$_RECEIPT_WF_COUNT" \
    "$_RECEIPT_IK_COUNT" \
    "${SYNC_RESULT:-healthy}"
  # Ensure all AWS Batch CEs are pinned to the latest Launch Template version.
  # The aws-cli libz regression (2026-04 → 2026-06) was caused by CEs being
  # left behind on old LT versions when the LT was updated. Auto-fix on every
  # sync so it can't survive across deploys. See
  # docs/20260607_BATCH_AMI_AWSCLI_NOT_SELF_CONTAINED.md.
  log "Ensuring Batch CE Launch-Template versions are current..."
  bash "$REPO_ROOT/scripts/audit_batch_ce_lt_versions.sh" --apply --quiet 2>&1 | sed 's/^/  /'
  if [[ "${BIOMATE_POSTSYNC_TEST_MODE:-background}" == "manual" ]]; then
    # A supervised browser/API review can replace the legacy background suites.
    # Health and generation smoke gates above still run; manual is not a test pass.
    log "[tests] Supervised post-sync verification pending (BIOMATE_POSTSYNC_TEST_MODE=manual); no background E2E launched"
  else
    log "Launching post-sync E2E tests in background..."
    bash "$REPO_ROOT/scripts/run_postsync_tests.sh" "$CURRENT_COMMIT" \
      >> /tmp/biomate_sync.log 2>&1 &
  fi
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
