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
# Usage:   bash scripts/deploy_marketing.sh            # deploy + verify
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
tar -czf "$TAR" -C "$SRC" webpage_design_v2/
log "Archive: $(du -sh "$TAR" | cut -f1), $(tar tzf "$TAR" | grep -c '\.html$') html files"
ec2_scp "$TAR" "${EC2_USER}@${INSTANCE_ID}:/tmp/marketing_only.tar.gz" || { log "FATAL: scp failed"; exit 1; }

# Deploy into EVERY docroot that nginx serves biomate.ai from (discovered above),
# falling back to /var/www/biomate-marketing.
ec2_ssh '
  set -e
  rm -rf /tmp/mkt_only && mkdir -p /tmp/mkt_only
  tar -xzf /tmp/marketing_only.tar.gz -C /tmp/mkt_only
  ROOTS=$(sudo grep -rhE "root[ \t]+/var/www[^;]*;" /etc/nginx/ 2>/dev/null | \
            grep -i biomate -A0 | sed -E "s/.*root[ \t]+([^;]+);.*/\1/" | sort -u)
  [ -z "$ROOTS" ] && ROOTS="/var/www/biomate-marketing"
  for R in $ROOTS /var/www/biomate-marketing; do
    R=$(echo "$R" | xargs)
    sudo mkdir -p "$R"
    sudo rsync -a --delete \
      --exclude='blog-llm-comparison.html' \
      --exclude='blog-llm-comparison-supplement.html' \
      /tmp/mkt_only/webpage_design_v2/ "$R"/ 2>/dev/null \
      || sudo cp -r /tmp/mkt_only/webpage_design_v2/. "$R"/
    sudo chown -R www-data:www-data "$R"/ 2>/dev/null || true
    echo "[deploy] $R -> 14-day now: $(grep -c "14-day\|14 day" "$R/pricing.html" 2>/dev/null || echo NA)"
  done
  rm -rf /tmp/mkt_only
'
log "Reloading nginx..."
ec2_ssh 'sudo nginx -t && sudo systemctl reload nginx && echo "[nginx] reloaded"'

log "Verifying live site..."
sleep 2
LIVE=$(curl -sS -L https://biomate.ai/pricing.html 2>/dev/null | grep -c '14-day\|14 day')
log "LIVE biomate.ai/pricing.html 14-day mentions: $LIVE  (>0 = fixed)"
[[ "$LIVE" -gt 0 ]] && log "✅ Done — biomate.ai refreshed." || log "⚠️  Still 0 — see [probe] docroots above; the apex may serve from a path not yet covered."
