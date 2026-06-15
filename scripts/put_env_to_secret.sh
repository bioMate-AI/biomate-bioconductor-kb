#!/usr/bin/env bash
#
# put_env_to_secret.sh — populate the AWS Secrets Manager env secret from a .env.
#
# The write counterpart to load_env_from_secrets.sh. Run this ONCE (and again
# whenever a value changes) from a machine/identity that has
# secretsmanager:PutSecretValue on <env>/biomate/galaxy-env. It reads a complete
# .env file and stores it as the JSON secret the deploy host pulls at boot.
#
# This is the "configure variables in the console/CLI" half of the GitLab-style
# flow — except instead of typing each value in a UI, you point it at an
# authoritative .env. (You can also edit values directly in the AWS console.)
#
# Usage:
#   BIOMATE_ENV=test bash scripts/put_env_to_secret.sh <complete.env>
#   BIOMATE_ENV=test DRY_RUN=1 bash scripts/put_env_to_secret.sh <complete.env>
#
# Env knobs:
#   BIOMATE_ENV   test|staging|prod (default test) → <env>/biomate/galaxy-env
#   AWS_REGION    default us-west-2
#   DRY_RUN       1 = print the key list + create-vs-update, do not write
#   EXCLUDE       space-separated keys to omit (default: build-time / host-local)
#
# By default it excludes build-time VITE_* and host-local-only keys that should
# NOT live in the shared secret. Override with EXCLUDE="".

set -euo pipefail

SRC="${1:-}"
BIOMATE_ENV="${BIOMATE_ENV:-test}"
REGION="${AWS_REGION:-us-west-2}"
DRY_RUN="${DRY_RUN:-0}"
SECRET_ID="${BIOMATE_ENV}/biomate/galaxy-env"
# VITE_* are baked into the frontend bundle at build time, not runtime env.
# DATABASE_PATH/GALAXY_CONFIG_FILE/PORT are container-local. Adjust as needed.
EXCLUDE="${EXCLUDE:-VITE_ENABLE_BACKEND_SYNC VITE_GALAXY_API_KEY VITE_BACKEND_URL VITE_API_URL GALAXY_CONFIG_FILE PORT}"

[[ -n "$SRC" && -f "$SRC" ]] || { echo "Usage: $0 <complete.env>" >&2; exit 1; }
command -v aws     >/dev/null || { echo "put-env: aws cli required" >&2; exit 1; }
command -v python3 >/dev/null || { echo "put-env: python3 required" >&2; exit 1; }

# Build the JSON object from the .env (skip comments/blank/empty-value/excluded).
json="$(EXCLUDE="$EXCLUDE" python3 - "$SRC" <<'PY'
import sys, os, json
exclude = set(os.environ.get("EXCLUDE", "").split())
out = {}
for line in open(sys.argv[1], encoding="utf-8"):
    line = line.rstrip("\n")
    if not line or line.lstrip().startswith("#") or "=" not in line:
        continue
    k, v = line.split("=", 1)
    k = k.strip()
    if not k or k in exclude or v == "":
        continue
    out[k] = v
print(json.dumps(out))
PY
)"

count="$(printf '%s' "$json" | python3 -c 'import sys,json;print(len(json.load(sys.stdin)))')"
echo "put-env: built JSON with $count var(s) for $SECRET_ID"

if [ "$DRY_RUN" = "1" ]; then
  echo "put-env: DRY-RUN — keys that would be stored:"
  printf '%s' "$json" | python3 -c 'import sys,json;[print("  "+k) for k in sorted(json.load(sys.stdin))]'
  exit 0
fi

# Create the secret if missing, else put a new version.
if aws secretsmanager describe-secret --region "$REGION" --secret-id "$SECRET_ID" >/dev/null 2>&1; then
  printf '%s' "$json" | aws secretsmanager put-secret-value --region "$REGION" \
    --secret-id "$SECRET_ID" --secret-string file:///dev/stdin >/dev/null
  echo "put-env: updated $SECRET_ID ($count vars)"
else
  printf '%s' "$json" | aws secretsmanager create-secret --region "$REGION" \
    --name "$SECRET_ID" --secret-string file:///dev/stdin >/dev/null
  echo "put-env: created $SECRET_ID ($count vars)"
fi
