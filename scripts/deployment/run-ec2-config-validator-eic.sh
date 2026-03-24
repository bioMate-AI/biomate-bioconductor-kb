#!/usr/bin/env bash
set -euo pipefail

# Run EC2 config validator over SSH using EC2 Instance Connect.
# No persistent PEM key file is required.
#
# Default target:
#   domain: dev-public.biomate.ai
#   root domain: biomate.ai
#   region: AWS_DEFAULT_REGION or us-west-2
#
# Usage:
#   bash scripts/deployment/run-ec2-config-validator-eic.sh
#   bash scripts/deployment/run-ec2-config-validator-eic.sh --domain dev-public.biomate.ai --region us-west-2
#   bash scripts/deployment/run-ec2-config-validator-eic.sh --repo-root /opt/biomate-dev/current --env-file /opt/biomate-dev/shared/.env.ec2

usage() {
  cat <<'EOF'
Usage:
  run-ec2-config-validator-eic.sh [--domain <fqdn>] [--root-domain <domain>] [--region <aws-region>] [--repo-root <path>] [--env-file <path>] [--no-bootstrap-env]

Optional:
  --domain       FQDN to resolve in Route53 (default: dev-public.biomate.ai)
  --root-domain  Hosted zone root name used by Route53 lookup (default: biomate.ai)
  --region       AWS region (default: AWS_DEFAULT_REGION or us-west-2)
  --repo-root    Explicit repo root on EC2 (default: auto-detect)
  --env-file     Explicit env file path on EC2 (default: auto-detect from repo root)
  --no-bootstrap-env  Do not create /opt/biomate/shared/.env.ec2 from .env.ec2.example when missing
EOF
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: missing command '$1'" >&2
    exit 1
  }
}

DOMAIN="dev-public.biomate.ai"
ROOT_DOMAIN="biomate.ai"
REGION="${AWS_DEFAULT_REGION:-us-west-2}"
BOOTSTRAP_ENV="1"
REMOTE_REPO_ROOT=""
REMOTE_ENV_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain)
      DOMAIN="$2"; shift 2 ;;
    --root-domain)
      ROOT_DOMAIN="$2"; shift 2 ;;
    --region)
      REGION="$2"; shift 2 ;;
    --repo-root)
      REMOTE_REPO_ROOT="$2"; shift 2 ;;
    --env-file)
      REMOTE_ENV_FILE="$2"; shift 2 ;;
    --no-bootstrap-env)
      BOOTSTRAP_ENV="0"; shift 1 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "ERROR: unknown argument '$1'" >&2
      usage
      exit 1 ;;
  esac
done

require_cmd aws
require_cmd ssh
require_cmd ssh-keygen
require_cmd mktemp
require_cmd sed

if ! aws sts get-caller-identity >/dev/null 2>&1; then
  echo "ERROR: AWS credentials are not configured for this shell." >&2
  exit 1
fi

fqdn="${DOMAIN%.}."

echo "==> Resolving Route53 hosted zone for ${ROOT_DOMAIN}"
ZONE_ID="$(aws route53 list-hosted-zones-by-name \
  --dns-name "${ROOT_DOMAIN}" \
  --query "HostedZones[0].Id" \
  --output text | sed 's|/hostedzone/||')"

if [[ -z "$ZONE_ID" || "$ZONE_ID" == "None" ]]; then
  echo "ERROR: could not resolve hosted zone for ${ROOT_DOMAIN}" >&2
  exit 1
fi

echo "==> Resolving A record for ${DOMAIN}"
PUBLIC_IP="$(aws route53 list-resource-record-sets \
  --hosted-zone-id "$ZONE_ID" \
  --query "ResourceRecordSets[?Name == '${fqdn}' && Type == 'A'].ResourceRecords[0].Value" \
  --output text)"

if [[ -z "$PUBLIC_IP" || "$PUBLIC_IP" == "None" ]]; then
  echo "ERROR: A record not found for ${DOMAIN} in zone ${ROOT_DOMAIN}" >&2
  exit 1
fi

echo "==> Finding running EC2 instance for public IP ${PUBLIC_IP}"
INSTANCE_ID="$(aws ec2 describe-instances \
  --region "$REGION" \
  --filters "Name=instance-state-name,Values=running" "Name=ip-address,Values=${PUBLIC_IP}" \
  --query "Reservations[0].Instances[0].InstanceId" \
  --output text)"

AZ="$(aws ec2 describe-instances \
  --region "$REGION" \
  --instance-ids "$INSTANCE_ID" \
  --query "Reservations[0].Instances[0].Placement.AvailabilityZone" \
  --output text)"

if [[ -z "$INSTANCE_ID" || "$INSTANCE_ID" == "None" || -z "$AZ" || "$AZ" == "None" ]]; then
  echo "ERROR: no running instance found for IP ${PUBLIC_IP} in region ${REGION}" >&2
  exit 1
fi

echo "==> Target instance: ${INSTANCE_ID} (${AZ})"

TMP_DIR="$(mktemp -d)"
KEY_PATH="${TMP_DIR}/ec2-eic-key"
trap 'rm -rf "$TMP_DIR"' EXIT

ssh-keygen -t ed25519 -N "" -f "$KEY_PATH" -q

run_for_user() {
  local user="$1"
  echo "==> Trying EC2 Instance Connect as user '${user}'"
  if ! aws ec2-instance-connect send-ssh-public-key \
    --region "$REGION" \
    --instance-id "$INSTANCE_ID" \
    --availability-zone "$AZ" \
    --instance-os-user "$user" \
    --ssh-public-key "file://${KEY_PATH}.pub" >/dev/null; then
    return 1
  fi

  # Public key is valid for a short time; connect immediately.
  # If validator script exists on remote, use it. Otherwise run inline fallback validator.
  ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=20 -i "$KEY_PATH" "${user}@${PUBLIC_IP}" \
    "bash -s -- ${REMOTE_ENV_FILE:-__auto__} ${REMOTE_REPO_ROOT:-__auto__} ${BOOTSTRAP_ENV}" <<'EOF'
set -euo pipefail
ENV_FILE_ARG="$1"
REPO_ROOT_ARG="$2"
BOOTSTRAP_ENV="$3"

if [[ "$REPO_ROOT_ARG" == "__auto__" ]]; then
  for candidate in /opt/biomate/current /opt/biomate-dev/current /opt/biomate "$HOME/biomate"; do
    if [[ -f "$candidate/docker-compose.ec2.yml" || -f "$candidate/docker-compose.yml" ]]; then
      REPO_ROOT="$candidate"
      break
    fi
  done
  if [[ -z "${REPO_ROOT:-}" ]]; then
    echo "ERROR: could not auto-detect repo root on EC2." >&2
    echo "Tried: /opt/biomate/current, /opt/biomate-dev/current, /opt/biomate, \$HOME/biomate" >&2
    exit 1
  fi
else
  REPO_ROOT="$REPO_ROOT_ARG"
fi

if [[ "$ENV_FILE_ARG" == "__auto__" ]]; then
  case "$REPO_ROOT" in
    /opt/biomate/current) ENV_FILE="/opt/biomate/shared/.env.ec2" ;;
    /opt/biomate-dev/current) ENV_FILE="/opt/biomate-dev/shared/.env.ec2" ;;
    /opt/biomate) ENV_FILE="/opt/biomate/.env" ;;
    *) ENV_FILE="$REPO_ROOT/.env.ec2" ;;
  esac
else
  ENV_FILE="$ENV_FILE_ARG"
fi

echo "==> Remote repo root: $REPO_ROOT"
echo "==> Remote env file: $ENV_FILE"

VALIDATOR="$REPO_ROOT/scripts/deployment/validate-ec2-config.sh"

if [[ ! -f "$ENV_FILE" ]]; then
  if [[ "$BOOTSTRAP_ENV" == "1" ]]; then
    TEMPLATE="$REPO_ROOT/.env.ec2.example"
    if [[ ! -f "$TEMPLATE" ]]; then
      echo "ERROR: env file not found: $ENV_FILE" >&2
      echo "ERROR: template also missing: $TEMPLATE" >&2
      exit 1
    fi
    echo "==> Bootstrapping missing env file from template"
    sudo mkdir -p "$(dirname "$ENV_FILE")"
    sudo cp "$TEMPLATE" "$ENV_FILE"
    sudo chown "$(id -un)":"$(id -gn)" "$ENV_FILE" || true
    echo "==> Created $ENV_FILE from $TEMPLATE"
  else
    echo "ERROR: env file not found: $ENV_FILE" >&2
    exit 1
  fi
fi

if [[ -f "$VALIDATOR" ]]; then
  bash "$VALIDATOR" --env-file "$ENV_FILE" --repo-root "$REPO_ROOT"
  exit $?
fi

echo "WARN: $VALIDATOR not found; running inline fallback validation."
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

require_nonempty "JWT_SECRET"
require_nonempty "SESSION_SECRET"
require_nonempty "BILLING_INTERNAL_KEY"
require_nonempty "AWS_ACCESS_KEY_ID"
require_nonempty "AWS_SECRET_ACCESS_KEY"
require_nonempty "AWS_REGION"
require_nonempty "S3_BUCKET_NAME"
if [[ -z "${GALAXY_URL:-}" && -z "${GALAXY_API_URL:-}" ]]; then
  missing+=("GALAXY_URL or GALAXY_API_URL")
fi
require_nonempty "GALAXY_API_KEY"

if [[ -z "${OPENAI_API_KEY:-}" && -z "${ANTHROPIC_API_KEY:-}" ]]; then
  missing+=("OPENAI_API_KEY or ANTHROPIC_API_KEY")
fi

if [[ ${#missing[@]} -gt 0 ]]; then
  echo "ERROR: missing required env variables in $ENV_FILE:" >&2
  for key in "${missing[@]}"; do
    echo "  - $key" >&2
  done
  exit 1
fi

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
EOF
}

run_and_handle() {
  local user="$1"
  set +e
  run_for_user "$user"
  local rc=$?
  set -e
  if [[ $rc -eq 0 ]]; then
    exit 0
  fi
  # ssh returns 255 for transport/auth/connectivity failures.
  if [[ $rc -ne 255 ]]; then
    exit "$rc"
  fi
  return 255
}

if run_and_handle "ubuntu"; then
  exit 0
fi

if run_and_handle "ec2-user"; then
  exit 0
fi

echo "ERROR: could not connect via EC2 Instance Connect as ubuntu or ec2-user." >&2
echo "Verify inbound SSH (22), IAM permissions for ec2-instance-connect, and instance OS user." >&2
exit 1
