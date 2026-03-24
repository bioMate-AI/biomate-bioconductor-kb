#!/usr/bin/env bash
set -euo pipefail

# Validate required EC2 deployment configuration before docker compose up.
#
# Usage:
#   bash scripts/deployment/validate-ec2-config.sh \
#     --env-file /opt/biomate/shared/.env.ec2 \
#     --repo-root /opt/biomate/current

usage() {
  cat <<'EOF'
Usage:
  validate-ec2-config.sh --env-file <path> --repo-root <path>

Required:
  --env-file   Path to .env.ec2 file
  --repo-root  Root path of deployed repo (contains backend/config)
EOF
}

ENV_FILE=""
REPO_ROOT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file)
      ENV_FILE="$2"; shift 2 ;;
    --repo-root)
      REPO_ROOT="$2"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "ERROR: unknown argument '$1'" >&2
      usage
      exit 1 ;;
  esac
done

if [[ -z "$ENV_FILE" || -z "$REPO_ROOT" ]]; then
  echo "ERROR: --env-file and --repo-root are required" >&2
  usage
  exit 1
fi

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: env file not found: $ENV_FILE" >&2
  exit 1
fi

if [[ ! -d "$REPO_ROOT" ]]; then
  echo "ERROR: repo root not found: $REPO_ROOT" >&2
  exit 1
fi

# shellcheck disable=SC1090
set -a && source "$ENV_FILE" && set +a

missing=()

require_nonempty() {
  local name="$1"
  local value="${!name:-}"
  if [[ -z "$value" ]]; then
    missing+=("$name")
  fi
}

# Frontend hard requirements in production runtime
require_nonempty "JWT_SECRET"
require_nonempty "SESSION_SECRET"
require_nonempty "BILLING_INTERNAL_KEY"

# S3 service requirements used by frontend server paths
require_nonempty "AWS_ACCESS_KEY_ID"
require_nonempty "AWS_SECRET_ACCESS_KEY"
require_nonempty "AWS_REGION"
require_nonempty "S3_BUCKET_NAME"

# AI provider key (at least one expected for assistant features)
if [[ -z "${OPENAI_API_KEY:-}" && -z "${ANTHROPIC_API_KEY:-}" ]]; then
  missing+=("OPENAI_API_KEY or ANTHROPIC_API_KEY")
fi

# Galaxy backend connectivity expected by frontend
if [[ -z "${GALAXY_URL:-}" && -z "${GALAXY_API_URL:-}" ]]; then
  missing+=("GALAXY_URL or GALAXY_API_URL")
fi
require_nonempty "GALAXY_API_KEY"

if [[ ${#missing[@]} -gt 0 ]]; then
  echo "ERROR: missing required env variables in $ENV_FILE:" >&2
  for key in "${missing[@]}"; do
    echo "  - $key" >&2
  done
  exit 1
fi

# Galaxy backend required config files
galaxy_cfg_dir="$REPO_ROOT/backend/config"
required_files=(
  "$galaxy_cfg_dir/galaxy.yml"
  "$galaxy_cfg_dir/tool_conf.xml.sample"
  "$galaxy_cfg_dir/shed_tool_conf.xml"
)

missing_files=()
for f in "${required_files[@]}"; do
  if [[ ! -f "$f" ]]; then
    missing_files+=("$f")
  fi
done

if [[ ${#missing_files[@]} -gt 0 ]]; then
  echo "ERROR: missing required Galaxy config files:" >&2
  for f in "${missing_files[@]}"; do
    echo "  - $f" >&2
  done
  exit 1
fi

echo "EC2 config validation passed."
