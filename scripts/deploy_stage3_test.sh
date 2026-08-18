#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# deploy_stage3_test.sh — Deploy Stage 3 sandbox hardening to test i-0482.
#
# Run from YOUR LOCAL MACHINE (SSH egress is blocked from the dev sandbox).
# Requires: aws CLI with SSM access to i-0482a6fa98c6f301a.
#
# What it pushes (all via SSM AWS-RunShellScript):
#   1. /opt/biomate/patched/commands.py  — new_clean_env DOCKER_HOST passthrough
#   2. /opt/biomate/launcher.py          — /run_it + /inspect_it + /stop_it
#   3. Patches the live docker-compose.sandbox.yml:
#       • removes /var/run/docker.sock from backend volumes
#       • adds commands.py bind-mount to backend
#       • adds DOCKER_HOST=tcp://docker-socket-proxy:2375 to backend env
#       • adds depends_on: docker-socket-proxy to backend
#   4. docker restart sandbox-launcher   (picks up new launcher.py via bind-mount)
#   5. docker compose up --force-recreate galaxy-backend-deploy
#   6. Verification checks
#
# Usage:  bash scripts/deploy_stage3_test.sh
# ---------------------------------------------------------------------------
set -euo pipefail

INSTANCE_ID="i-0482a6fa98c6f301a"
REGION="us-west-2"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# ── 1. base64-encode the two patched files ─────────────────────────────────
echo "[deploy] Encoding files..."
COMMANDS_PY_B64="$(base64 < "$REPO_ROOT/backend/lib/galaxy/util/commands.py" | tr -d '\n')"
LAUNCHER_PY_B64="$(base64 < "$REPO_ROOT/deploy/sandbox-launcher/launcher.py" | tr -d '\n')"

echo "[deploy] commands.py  $(wc -c < "$REPO_ROOT/backend/lib/galaxy/util/commands.py") bytes  (${#COMMANDS_PY_B64} b64)"
echo "[deploy] launcher.py  $(wc -c < "$REPO_ROOT/deploy/sandbox-launcher/launcher.py") bytes  (${#LAUNCHER_PY_B64} b64)"

# ── 2. Build the inner Python script (runs on the instance) ────────────────
# Base64 payloads are interpolated here (client side) so the script is
# self-contained — the instance does not need curl or S3 access.
INNER_SCRIPT="$(cat <<PYEOF
#!/usr/bin/env python3
import base64, os, re, subprocess, sys, time, datetime, shutil

def run(cmd, fatal=True):
    print(f'[run] {cmd}', flush=True)
    r = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    print(r.stdout, end='', flush=True)
    if r.stderr.strip():
        print('[stderr]', r.stderr[:400], flush=True)
    if fatal and r.returncode != 0:
        sys.exit(r.returncode)
    return r

# ── Step 1: write patched commands.py ─────────────────────────────────────
os.makedirs('/opt/biomate/patched', exist_ok=True)
open('/opt/biomate/patched/commands.py','wb').write(
    base64.b64decode('${COMMANDS_PY_B64}'))
print('[ok] commands.py written', flush=True)

# ── Step 2: write new launcher.py ──────────────────────────────────────────
open('/opt/biomate/launcher.py','wb').write(
    base64.b64decode('${LAUNCHER_PY_B64}'))
print('[ok] launcher.py written', flush=True)

# ── Step 3: patch the live docker-compose.sandbox.yml ─────────────────────
overlay = '/opt/biomate/docker-compose.sandbox.yml'
ts = datetime.datetime.now().strftime('%Y%m%d%H%M%S')
shutil.copy(overlay, overlay + '.bak.stage3.' + ts)
print(f'[ok] overlay backed up → .bak.stage3.{ts}', flush=True)

with open(overlay) as f:
    txt = f.read()

changed = []

# 3a — remove raw docker.sock volume from backend block
if '/var/run/docker.sock:/var/run/docker.sock' in txt:
    txt = re.sub(r'[ \t]*-[ \t]*/var/run/docker\.sock:/var/run/docker\.sock[^\n]*\n', '', txt)
    changed.append('removed docker.sock volume')

# 3b — add commands.py bind-mount (anchor: last /opt/biomate/patched/ mount line)
if '/opt/biomate/patched/commands.py' not in txt:
    # try to anchor on the last patched/ bind line
    m = None
    for m in re.finditer(r'([ \t]*-[ \t]*/opt/biomate/patched/[^\n]+\n)', txt):
        pass
    if m:
        indent = re.match(r'([ \t]*)', m.group(1)).group(1)
        insert = indent + '- /opt/biomate/patched/commands.py:/app/lib/galaxy/util/commands.py:ro\n'
        txt = txt[:m.end()] + insert + txt[m.end():]
        changed.append('added commands.py bind-mount')
    else:
        print('[warn] could not find /opt/biomate/patched/ anchor — add commands.py mount manually', flush=True)

# 3c — add DOCKER_HOST env (anchor: NF_HEAD_LAUNCHER_URL line)
if 'DOCKER_HOST=tcp://docker-socket-proxy:2375' not in txt:
    nf_m = re.search(r'([ \t]*-[ \t]*NF_HEAD_LAUNCHER_URL=[^\n]+\n)', txt)
    if nf_m:
        indent = re.match(r'([ \t]*)', nf_m.group(1)).group(1)
        insert = indent + '- DOCKER_HOST=tcp://docker-socket-proxy:2375\n'
        txt = txt[:nf_m.end()] + insert + txt[nf_m.end():]
        changed.append('added DOCKER_HOST env')
    else:
        # fallback: anchor on SANDBOX_ENABLED
        se_m = re.search(r'([ \t]*-[ \t]*SANDBOX_ENABLED=[^\n]+\n)', txt)
        if se_m:
            indent = re.match(r'([ \t]*)', se_m.group(1)).group(1)
            insert = indent + '- DOCKER_HOST=tcp://docker-socket-proxy:2375\n'
            txt = txt[:se_m.end()] + insert + txt[se_m.end():]
            changed.append('added DOCKER_HOST env (via SANDBOX_ENABLED anchor)')
        else:
            print('[warn] cannot add DOCKER_HOST — add manually', flush=True)

# 3d — add depends_on: docker-socket-proxy to backend (before frontend-deploy section)
be_section = txt.split('galaxy-backend-deploy', 1)
if len(be_section) > 1:
    fe_split = be_section[1].split('frontend-deploy', 1)
    backend_block = fe_split[0]
    if 'depends_on' not in backend_block:
        txt = re.sub(r'(\n  frontend-deploy:)',
                     r'\n    depends_on:\n      - docker-socket-proxy\1', txt, count=1)
        changed.append('added depends_on: docker-socket-proxy')

with open(overlay, 'w') as f:
    f.write(txt)
print(f'[ok] overlay patched: {changed}', flush=True)

# ── Step 4: restart sandbox-launcher (picks up new launcher.py) ─────────────
run('docker restart sandbox-launcher')
time.sleep(8)   # wait for apk install + python start
print('[ok] sandbox-launcher restarted', flush=True)

# ── Step 5: recreate backend (new overlay: no socket, DOCKER_HOST, commands.py mount)
run(
    'docker compose '
    '-f /opt/biomate/docker-compose.deploy.yml '
    '-f /opt/biomate/docker-compose.sandbox.yml '
    'up -d --no-deps --force-recreate galaxy-backend-deploy'
)
print('[ok] galaxy-backend-deploy recreated, waiting 30s for Galaxy startup...', flush=True)
time.sleep(30)

# ── Step 6: verify ──────────────────────────────────────────────────────────

# 6a — no raw socket in backend binds
r = run("docker inspect biomate-galaxy-deploy --format '{{json .HostConfig.Binds}}'", fatal=False)
sock_count = r.stdout.count('docker.sock')
status = 'PASS' if sock_count == 0 else 'FAIL'
print(f'[{status}] raw socket count in backend Binds = {sock_count}  (want 0)', flush=True)

# 6b — DOCKER_HOST set in backend
r = run('docker exec biomate-galaxy-deploy printenv DOCKER_HOST', fatal=False)
dh = r.stdout.strip()
status = 'PASS' if dh == 'tcp://docker-socket-proxy:2375' else 'FAIL'
print(f'[{status}] DOCKER_HOST in backend: {dh!r}', flush=True)

# 6c — commands.py bind-mount present and contains DOCKER_HOST
r = run("docker exec biomate-galaxy-deploy grep -c DOCKER_HOST /app/lib/galaxy/util/commands.py", fatal=False)
status = 'PASS' if r.returncode == 0 and int(r.stdout.strip() or 0) >= 1 else 'FAIL'
print(f'[{status}] commands.py mounted + DOCKER_HOST present (grep count={r.stdout.strip()!r})', flush=True)

# 6d — launcher health from backend (proves network + new launcher running)
r = run("docker exec biomate-galaxy-deploy sh -c 'wget -qO- http://sandbox-launcher:8899/health 2>&1'", fatal=False)
status = 'PASS' if 'true' in r.stdout else 'FAIL'
print(f'[{status}] launcher health from backend: {r.stdout.strip()!r}', flush=True)

# 6e — launcher self-health + endpoints in startup log
r = run('docker logs --tail 5 sandbox-launcher 2>&1', fatal=False)
print(f'[info] launcher startup log (last 5 lines):\n{r.stdout.strip()}', flush=True)
status = 'PASS' if 'run_it' in r.stdout or 'run_it' in r.stderr else 'INFO'
print(f'[{status}] /run_it visible in launcher log', flush=True)

# 6f — Galaxy API health
r = run('curl -sf http://localhost:8081/api/version 2>/dev/null', fatal=False)
status = 'PASS' if r.returncode == 0 else 'WARN'
print(f'[{status}] Galaxy API /api/version: {r.stdout[:80]!r}', flush=True)

print('', flush=True)
print('=== Stage 3 deploy complete ===', flush=True)
print('Next: launch a JupyterLab IT tool via the UI and confirm it starts (no exit 125).', flush=True)
PYEOF
)"

# ── 3. base64 the inner script and send to SSM ─────────────────────────────
echo "[deploy] Sending to SSM..."
INNER_B64="$(printf '%s' "$INNER_SCRIPT" | base64 | tr -d '\n')"

CMD_ID="$(aws ssm send-command \
  --region "$REGION" \
  --instance-ids "$INSTANCE_ID" \
  --document-name AWS-RunShellScript \
  --parameters "commands=[\"echo '${INNER_B64}' | base64 -d | python3\"]" \
  --comment "Sandbox Stage3: backend zero-socket + IT via DOCKER_HOST proxy" \
  --query "Command.CommandId" \
  --output text)"

echo "[deploy] SSM command ID: $CMD_ID"
echo "[deploy] Polling (updates every 5s, up to 4 min)..."

# ── 4. Poll for completion ──────────────────────────────────────────────────
for i in $(seq 1 48); do
  sleep 5
  STATUS="$(aws ssm get-command-invocation \
    --region "$REGION" \
    --command-id "$CMD_ID" \
    --instance-id "$INSTANCE_ID" \
    --query "Status" \
    --output text 2>/dev/null || echo "InProgress")"
  printf "  [%2d/48] %s\n" "$i" "$STATUS"
  if [[ "$STATUS" == "Success" || "$STATUS" == "Failed" || "$STATUS" == "Cancelled" || "$STATUS" == "TimedOut" ]]; then
    break
  fi
done

# ── 5. Print output ─────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════ STDOUT ════════════════════════════════"
aws ssm get-command-invocation \
  --region "$REGION" \
  --command-id "$CMD_ID" \
  --instance-id "$INSTANCE_ID" \
  --query "StandardOutputContent" \
  --output text

echo ""
echo "════════════════════════════════ STDERR ════════════════════════════════"
aws ssm get-command-invocation \
  --region "$REGION" \
  --command-id "$CMD_ID" \
  --instance-id "$INSTANCE_ID" \
  --query "StandardErrorContent" \
  --output text

echo ""
echo "[deploy] Done.  Final SSM status: $STATUS"
