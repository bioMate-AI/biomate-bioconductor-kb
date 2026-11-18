#!/usr/bin/env bash
#
# Marketing-site-ONLY deploy + self-diagnosis — refresh biomate.ai without the
# full 5-layer sync_to_dev.sh.
#
# Ships JUST the static site (reference/claude_design/webpage_design_v2/) to the
# prod box and, crucially, REPORTS which nginx docroot the apex biomate.ai
# server_name actually serves from — so we can tell whether the long-standing
# "webpage fell back to the old version" is a stale deploy or a docroot mismatch
# (sync_to_dev.sh historically targeted /var/www/biomate-marketing, which is the
# dev-public.biomate.ai vhost; the apex may serve from elsewhere).
#
# Deploys from THIS checkout's webpage_design_v2/, so run it from a checkout of
# the branch you want live (e.g. a worktree on integration/next-phase).
#
# Usage:   bash scripts/deploy_marketing.sh            # full deploy + verify (re-probes docroot, ships whole tree)
#          bash scripts/deploy_marketing.sh --fast     # incremental rsync of changed files only, one reused session
#          bash scripts/deploy_marketing.sh --probe    # diagnose only, no write

set -uo pipefail   # NOT -e: we want diagnostics even if a step fails

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INSTANCE_ID="i-06696b0d91f4346e0"
AZ="us-west-2a"
EC2_USER="ubuntu"
EC2_HOST="52.42.49.175"
KEY_FILE="/tmp/biomate_ec2_key_sync"
# Tunnel SSH/scp over SSM (like sync_to_dev.sh) so the deploy works from any
# network — the prod SG only allows port 22 from a few fixed IPs, which breaks
# direct SSH from e.g. a phone hotspot (carrier NAT). SSM rides the AWS API.
_SSM_PROXY="aws ssm start-session --target ${INSTANCE_ID} --document-name AWS-StartSSHSession --parameters portNumber=%p --region us-west-2"
# session-manager-plugin is required by the ProxyCommand above; install user-local.
export PATH="$HOME/bin:$PATH"
if ! command -v session-manager-plugin &>/dev/null; then
  _ARCH=$(uname -m)
  _SSM_URL="https://s3.amazonaws.com/session-manager-downloads/plugin/latest/mac_arm64/sessionmanager-bundle.zip"
  [[ "$_ARCH" != "arm64" ]] && _SSM_URL="https://s3.amazonaws.com/session-manager-downloads/plugin/latest/mac/sessionmanager-bundle.zip"
  mkdir -p "$HOME/bin"
  curl -sSL "$_SSM_URL" -o /tmp/ssm-bundle.zip 2>/dev/null && \
    unzip -qo /tmp/ssm-bundle.zip -d /tmp/ssm-bundle/ 2>/dev/null && \
    cp /tmp/ssm-bundle/sessionmanager-bundle/bin/session-manager-plugin "$HOME/bin/" && \
    chmod +x "$HOME/bin/session-manager-plugin"
fi
SRC="$REPO_ROOT/reference/claude_design"
PROBE_ONLY="${1:-}"

# Never publish stale shared links or a failed metadata/navigation regression.
if [[ "$PROBE_ONLY" != "--probe" ]]; then
  node "$REPO_ROOT/scripts/prepare_marketing_shell.cjs" --check || exit 1
  node --test "$REPO_ROOT/reference/claude_design/webpage_design_v2/tests/"*.test.cjs || exit 1
fi

log() { echo "[$(date '+%H:%M:%S')] $*"; }

inject_key() {
  [[ -f "${KEY_FILE}" ]] || ssh-keygen -t ed25519 -f "$KEY_FILE" -N "" -q
  aws ec2-instance-connect send-ssh-public-key \
    --instance-id "$INSTANCE_ID" --availability-zone "$AZ" \
    --instance-os-user "$EC2_USER" --ssh-public-key "file://${KEY_FILE}.pub" \
    --region us-west-2 --output text --query 'Success' || {
      log "FATAL: ec2-instance-connect key injection failed (AWS creds / instance state?)"; exit 1; }
}

# SSH/scp over the SSM tunnel (connects to the instance id, not a public IP).
ec2_ssh() {
  inject_key >/dev/null
  ssh -i "$KEY_FILE" -o ProxyCommand="$_SSM_PROXY" \
    -o StrictHostKeyChecking=no -o IdentitiesOnly=yes -o ConnectTimeout=30 \
    -o ServerAliveInterval=30 -o ServerAliveCountMax=4 \
    "${EC2_USER}@${INSTANCE_ID}" "$@"
}
ec2_scp() {
  inject_key >/dev/null
  scp -i "$KEY_FILE" -o ProxyCommand="$_SSM_PROXY" \
    -o StrictHostKeyChecking=no -o IdentitiesOnly=yes -o ConnectTimeout=30 \
    -o ServerAliveInterval=30 -o ServerAliveCountMax=100 "$@"
}

log "Source: $SRC/webpage_design_v2  (14-day mentions: $(grep -c '14-day\|14 day' "$SRC/webpage_design_v2/pricing.html" 2>/dev/null))"

# --- Fast incremental path --------------------------------------------------
# `--fast`: rsync ONLY changed files straight into the cached docroot over a
# single reused SSH session, instead of tar-ing + scp-ing the whole 130 MB tree
# across five fresh SSM handshakes. Assumes the apex serves from
# /var/www/biomate-marketing (what --probe has consistently found); use the
# default path if you need the docroot re-probed or a new docroot covered.
if [[ "$PROBE_ONLY" == "--fast" ]]; then
  DOCROOT="/var/www/biomate-marketing"
  CP="/tmp/biomate_mkt_cm.sock"
  SSH_BASE=(-i "$KEY_FILE" -o StrictHostKeyChecking=no -o IdentitiesOnly=yes
            -o ConnectTimeout=30 -o ServerAliveInterval=30 -o ServerAliveCountMax=4)
  log "Fast deploy → $DOCROOT (single session, incremental rsync)"
  inject_key >/dev/null
  # Open ONE multiplexed master over SSM; later rsync/ssh reuse it (no re-handshake).
  ssh "${SSH_BASE[@]}" -o ProxyCommand="$_SSM_PROXY" \
      -o ControlMaster=yes -o ControlPath="$CP" -o ControlPersist=120 \
      -fN "${EC2_USER}@${INSTANCE_ID}" \
    || { log "FATAL: could not open SSH master over SSM"; exit 1; }
  trap 'ssh -o ControlPath="$CP" -O exit "${EC2_USER}@${INSTANCE_ID}" 2>/dev/null || true' EXIT
  _REUSE=(-o ControlMaster=no -o ControlPath="$CP")
  STATS=$(rsync -rltzi --delete --stats \
      --exclude='blog-llm-comparison.html' \
      --exclude='blog-llm-comparison-supplement.html' \
      --rsync-path="sudo rsync" \
      -e "ssh ${SSH_BASE[*]} ${_REUSE[*]}" \
      "$SRC/webpage_design_v2/" "${EC2_USER}@${INSTANCE_ID}:${DOCROOT}/" 2>&1) \
    || { log "FATAL: rsync failed"; echo "$STATS" | tail -5; exit 1; }
  echo "$STATS" | grep -E '^(<|>|c)' | sed 's/^/  [sync] /' | head -20
  log "Transferred: $(echo "$STATS" | grep -E 'Number of regular files transferred|files transferred' | head -1 | sed 's/^[^:]*: //')"
  ssh "${SSH_BASE[@]}" "${_REUSE[@]}" "${EC2_USER}@${INSTANCE_ID}" \
    "sudo chown -R www-data:www-data '$DOCROOT'/ 2>/dev/null; sudo nginx -t && sudo systemctl reload nginx && echo '[nginx] reloaded'"
  log "Verifying live site..."
  sleep 2
  LIVE=$(curl -sS -L https://biomate.ai/pricing.html 2>/dev/null | grep -c '14-day\|14 day')
  log "LIVE biomate.ai/pricing.html 14-day mentions: $LIVE  (>0 = up)"
  [[ "$LIVE" -gt 0 ]] && log "✅ Fast deploy done." || log "⚠️  0 — run the default (non-fast) path to re-probe the docroot."
  exit 0
fi

# --- Diagnose: where does the APEX biomate.ai actually serve from? ----------
log "Probing nginx for the biomate.ai docroot..."
ec2_ssh '
  echo "[probe] nginx server blocks mentioning biomate.ai:";
  sudo grep -rEl "server_name[^;]*biomate\.ai" /etc/nginx/ 2>/dev/null | while read f; do
    echo "  conf: $f";
    sudo awk "/server[ \t]*\{/{b=1} b&&/server_name/{print \"    \"\$0} b&&/root /{print \"    \"\$0} /\}/{if(b)b=b}" "$f" 2>/dev/null | sed -n "1,40p";
  done
  echo "[probe] docroots that exist:";
  for d in /var/www/biomate-marketing /var/www/html /var/www/biomate.ai /var/www/biomate; do
    [ -d "$d" ] && echo "  $d  ->  pricing.html 14-day: $(grep -c "14-day\|14 day" "$d/pricing.html" 2>/dev/null || echo NA), mtime: $(stat -c %y "$d/pricing.html" 2>/dev/null || echo none)";
  done
'

if [[ "$PROBE_ONLY" == "--probe" ]]; then log "probe-only — no files written"; exit 0; fi

# --- Build + ship ----------------------------------------------------------
TAR=/tmp/biomate_marketing_only.tar.gz
# Publish web assets only; editorial plans and regression tests stay local.
tar --exclude='*.md' --exclude='*/tests' --exclude='*.cjs' \
  -czf "$TAR" -C "$SRC" webpage_design_v2/
log "Archive: $(du -sh "$TAR" | cut -f1), $(tar tzf "$TAR" | grep -c '\.html$') html files"
ec2_scp "$TAR" "${EC2_USER}@${INSTANCE_ID}:/tmp/marketing_only.tar.gz" || { log "FATAL: scp failed"; exit 1; }

# The probe confirms this dedicated marketing docroot. Do not sync unrelated
# nginx roots (including app roots or paths mentioned only in backup configs).
ec2_ssh '
  set -e
  rm -rf /tmp/mkt_only && mkdir -p /tmp/mkt_only
  tar -xzf /tmp/marketing_only.tar.gz -C /tmp/mkt_only
  for R in /var/www/biomate-marketing; do
    sudo mkdir -p "$R"
    sudo mkdir -p /var/backups/biomate-marketing
    BACKUP=$(sudo mktemp /var/backups/biomate-marketing/pre-sync-XXXXXXXX.tar.gz)
    sudo tar -czf "$BACKUP" -C "$R" .
    echo "[backup] $BACKUP"
    sudo rsync -a --delete \
      --exclude='blog-llm-comparison.html' \
      --exclude='blog-llm-comparison-supplement.html' \
      /tmp/mkt_only/webpage_design_v2/ "$R"/
    sudo chown -R www-data:www-data "$R"/ 2>/dev/null || true
    echo "[deploy] $R -> 14-day now: $(grep -c "14-day\|14 day" "$R/pricing.html" 2>/dev/null || echo NA)"
  done
  rm -rf /tmp/mkt_only
' || { log "FATAL: marketing sync failed"; exit 1; }
log "Reloading nginx..."
ec2_ssh 'sudo nginx -t && sudo systemctl reload nginx && echo "[nginx] reloaded"' || { log "FATAL: nginx validation/reload failed"; exit 1; }

log "Verifying live site..."
sleep 2
LIVE=$(curl -sS -L https://biomate.ai/pricing.html 2>/dev/null | grep -c '14-day\|14 day')
log "LIVE biomate.ai/pricing.html 14-day mentions: $LIVE  (>0 = fixed)"
[[ "$LIVE" -gt 0 ]] && log "✅ Done — biomate.ai refreshed." || log "⚠️  Still 0 — see [probe] docroots above; the apex may serve from a path not yet covered."
