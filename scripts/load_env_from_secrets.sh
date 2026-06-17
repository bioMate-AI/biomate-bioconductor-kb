#!/usr/bin/env bash
#
# load_env_from_secrets.sh — materialize /opt/biomate/.env from AWS Secrets Manager.
#
# This is the "GitLab-style external config" mechanism for BioMate: the runtime
# env values live in AWS Secrets Manager (configure them in the AWS console/CLI),
# the repo holds only variable NAMES (deploy/biomate.env.manifest), and the
# deploy host pulls the values at deploy/boot time using its EC2 instance role.
# Values never transit GitHub, the repo, or a developer workstation.
#
# Runs ON the deploy host (the EC2 instance role BioMateEc2DeployRole already has
# secretsmanager:GetSecretValue on test/biomate/galaxy-env, test/biomate/rds-galaxy,
# biomate/lago/api-key). No static AWS credentials are used or needed.
#
# Usage (on the EC2):
#   sudo BIOMATE_ENV=test bash scripts/load_env_from_secrets.sh
#   BIOMATE_ENV=test DRY_RUN=1 bash scripts/load_env_from_secrets.sh   # preview only
#
# Env knobs:
#   BIOMATE_ENV   test|staging|prod (default test) → secret <env>/biomate/galaxy-env
#   ENV_FILE      target file (default /opt/biomate/.env)
#   AWS_REGION    default us-west-2
#   DRY_RUN       1 = print what would change, do not write
#
# Behavior: per-key UPSERT into ENV_FILE — keys present in the secret are written
# (overriding any existing value), keys only on the host (not in the secret) are
# preserved. The previous ENV_FILE is backed up first.

set -euo pipefail

BIOMATE_ENV="${BIOMATE_ENV:-test}"
ENV_FILE="${ENV_FILE:-/opt/biomate/.env}"
REGION="${AWS_REGION:-us-west-2}"
DRY_RUN="${DRY_RUN:-0}"
SECRET_ID="${BIOMATE_ENV}/biomate/galaxy-env"
RDS_SECRET_ID="${BIOMATE_ENV}/biomate/rds-galaxy"

command -v aws     >/dev/null || { echo "load-env: aws cli required" >&2; exit 1; }
command -v python3 >/dev/null || { echo "load-env: python3 required" >&2; exit 1; }

echo "load-env: pulling $SECRET_ID (region $REGION)..."
secret_json=$(aws secretsmanager get-secret-value --region "$REGION" \
  --secret-id "$SECRET_ID" --query SecretString --output text) || {
  echo "load-env: FATAL — cannot read $SECRET_ID (is the instance role attached? does the secret exist?)" >&2
  exit 1
}

# Optional: take DATABASE_URL from the dedicated RDS secret if the env secret
# does not carry one (keeps DB creds in their own rotatable secret).
rds_url=$(aws secretsmanager get-secret-value --region "$REGION" \
  --secret-id "$RDS_SECRET_ID" --query SecretString --output text 2>/dev/null \
  | python3 -c 'import sys,json;
try: print(json.load(sys.stdin).get("url",""))
except Exception: print("")' 2>/dev/null || true)

# Render KEY=VAL lines from the JSON secret (python handles any special chars
# in values safely; secret is read from stdin, never the process arg list).
managed="$(mktemp)"; trap 'rm -f "$managed"' EXIT
printf '%s' "$secret_json" | RDS_URL="$rds_url" python3 -c '
import sys, json, os
d = json.load(sys.stdin)
if not isinstance(d, dict):
    sys.stderr.write("load-env: secret is not a JSON object\n"); sys.exit(1)
rds = os.environ.get("RDS_URL", "")
if rds and not d.get("DATABASE_URL"):
    d["DATABASE_URL"] = rds
for k, v in d.items():
    if v is None:
        continue
    # env-file values are single line; collapse accidental newlines
    print(f"{k}={str(v)}".replace("\n", " "))
' > "$managed"

n=$(grep -c '=' "$managed" || true)
[ "$n" -gt 0 ] || { echo "load-env: FATAL — secret produced 0 vars" >&2; exit 1; }

if [ "$DRY_RUN" = "1" ]; then
  echo "load-env: DRY-RUN — would upsert $n var(s) from $SECRET_ID into $ENV_FILE:"
  cut -d= -f1 "$managed" | sort | sed 's/^/  /'
  exit 0
fi

mkdir -p "$(dirname "$ENV_FILE")"
touch "$ENV_FILE"
orig_owner="$(stat -c '%U:%G' "$ENV_FILE" 2>/dev/null || echo "")"
cp "$ENV_FILE" "${ENV_FILE}.backup.$(date +%Y%m%d_%H%M%S)"

# Per-key upsert: drop each secret key from the file, then append the block.
while IFS='=' read -r k _; do
  [ -n "$k" ] && sed -i "/^${k}=/d" "$ENV_FILE"
done < "$managed"
cat "$managed" >> "$ENV_FILE"

chmod 600 "$ENV_FILE"
[ -n "$orig_owner" ] && chown "$orig_owner" "$ENV_FILE" 2>/dev/null || true
echo "load-env: wrote $n var(s) from $SECRET_ID → $ENV_FILE ($(grep -cE '^[A-Z_].*=' "$ENV_FILE") total)"
echo "load-env: restart containers to apply (docker --env-file is read at start)."
