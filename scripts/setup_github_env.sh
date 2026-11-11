#!/usr/bin/env bash
#
# setup_github_env.sh — push BioMate env values into GitHub Secrets / Variables.
#
# Reads variable NAMES from deploy/biomate.env.manifest and VALUES from a source
# .env file, then sets each as a GitHub Secret (sensitive) or Variable (public)
# per the classification below. This is the one-shot bootstrap for the CI/CD env
# pipeline (see docs/20260613_CICD_ENV_PIPELINE.md).
#
# REQUIRES: gh (GitHub CLI) installed and authenticated (`gh auth login`).
#
# Usage:
#   scripts/setup_github_env.sh <source-env-file> [--dry-run] [--repo owner/name]
#
# Use an approved, owner-readable source file or secret-manager export. Never
# print a live .env through SSM, CI logs, screenshots or chat. Check that values
# belong to the intended deployment; local URLs are not container endpoints.
#
# Empty values are skipped (never overwrite a configured secret with blank).
# Re-running is safe (gh updates existing secrets/variables in place).

set -euo pipefail

SOURCE_ENV="${1:-}"
DRY_RUN=false
REPO_ARG=()
shift || true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true ;;
    --repo) REPO_ARG=(--repo "$2"); shift ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
  shift
done

if [[ -z "$SOURCE_ENV" || ! -f "$SOURCE_ENV" ]]; then
  echo "Usage: $0 <source-env-file> [--dry-run] [--repo owner/name]" >&2
  echo "  source-env-file: an .env with real values (see header for which one)." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$SCRIPT_DIR/../deploy/biomate.env.manifest"
[[ -f "$MANIFEST" ]] || { echo "manifest not found: $MANIFEST" >&2; exit 1; }

if [[ "$DRY_RUN" == false ]]; then
  if ! command -v gh >/dev/null 2>&1; then
    echo "Error: gh (GitHub CLI) not installed. Install + 'gh auth login' first." >&2
    exit 1
  fi
  if ! gh auth status >/dev/null 2>&1; then
    echo "Error: gh not authenticated. Run 'gh auth login'." >&2
    exit 1
  fi
fi

# Only explicitly reviewed non-sensitive settings become Variables. Unknown
# names default to Secrets: adding a new API key cannot silently publish it.
#
# INVARIANT: GALAXY_JWT_SECRET (used by the Node billing proxy in server/routes.ts
# to re-sign the JWT it forwards to Galaxy) MUST equal the Galaxy backend's
# JWT_SECRET. It only exists to bridge environments where the frontend's and
# Galaxy's JWT_SECRET differ; if they're the same, leave GALAXY_JWT_SECRET unset
# (the proxy falls back to JWT_SECRET). A stale/mismatched GALAXY_JWT_SECRET makes
# EVERY /api/billing/* call fail with "Signature verification failed" (401) —
# see docs/20260727_BILLING_PROXY_JWT_401_ROOTCAUSE.md (dev incident 2026-07-27).
SECRETS=(
  ANTHROPIC_API_KEY JWT_SECRET SESSION_SECRET BILLING_INTERNAL_KEY DATABASE_URL
  GALAXY_API_KEY AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY ENCRYPTION_KEY CSRF_SECRET
  GALAXY_JWT_SECRET OPENAI_API_KEY GEMINI_API_KEY LAGO_API_KEY REDIS_URL
  AWS_NF_ACCESS_KEY_ID AWS_NF_SECRET_ACCESS_KEY POSTGRES_PASSWORD
  FIELD_ENCRYPTION_SECRET MFA_ENCRYPTION_SECRET LAGO_WEBHOOK_SECRET EMAIL_PASS
  CRYOSPARC_PASSWORD
)
is_secret() {
  local n="$1"
  for s in "${SECRETS[@]}"; do [[ "$s" == "$n" ]] && return 0; done
  case "$n" in
    *KEY*|*SECRET*|*PASSWORD*|*TOKEN*|*CREDENTIAL*|*LICENSE*) return 0 ;;
  esac
  for s in "${PUBLIC_VARIABLES[@]}"; do [[ "$s" == "$n" ]] && return 1; done
  return 0
}

PUBLIC_VARIABLES=(
  GALAXY_URL AWS_REGION S3_BUCKET_NAME NODE_ENV APP_URL CORS_ORIGINS FORCE_HTTPS
  ENABLE_HSTS LAGO_API_URL JAVA_BILLING_SERVICE_URL JAVA_BILLING_ENABLED BILLING_DEV_MODE
  AWS_S3_NEXTFLOW_BUCKET AWS_S3_BUCKET AWS_DEFAULT_REGION AWS_BATCH_QUEUE GPU_BATCH_QUEUE
  NEXTFLOW_USE_AWS BIOMATE_NF_PROFILE POSTGRES_DB POSTGRES_USER EMAIL_HOST EMAIL_PORT
  EMAIL_SECURE EMAIL_USER EMAIL_FROM BIOMATE_INTENT_MODEL BIOMATE_RESPONSE_MODEL
  BIOMATE_CHAT_VIA_CHAIN BIOMATE_MULTITASK_DAG_ENABLED BIOMATE_PATTERN_ROUTER_ENABLED
  ADMIN_ALERT_EMAIL CRYOSPARC_AMI_ID CRYOSPARC_HOST CRYOSPARC_PORT CRYOSPARC_EMAIL
  CRYOSPARC_INSTANCE_REGION CRYOSPARC_INSTANCE_TYPE CRYOSPARC_MOVIES_S3
  CRYOSPARC_PROJECT_DIR CRYOSPARC_DEFAULT_MOVIE_DIR CRYOSPARC_SSH_USER
  JWT_EXPIRY REDIS_PORT DATABASE_PATH
)

get_value() { sed -n "s/^$1=//p" "$SOURCE_ENV" | head -n1; }

set_secret=0; set_var=0; skipped=0
while read -r name _req _; do
  [[ -z "$name" || "$name" == \#* ]] && continue
  [[ "$name" =~ ^[A-Z_][A-Z0-9_]*$ ]] || { echo "Invalid manifest name" >&2; exit 1; }
  val="$(get_value "$name")"
  if [[ -z "$val" ]]; then
    skipped=$((skipped+1)); continue
  fi
  if is_secret "$name"; then
    kind="secret"
  else
    kind="variable"
  fi
  # Credential-bearing URLs must not become public even under a reviewed name.
  # Query/fragment credentials have too many spellings (API_KEY, Sig, encoded
  # names, vendor-specific parameters) for a safe small-name denylist. Keep any
  # URL carrying them private, even under an otherwise public setting name.
  if [[ "$val" =~ ://[^/]*@ ]] || [[ "$val" == *://* && ( "$val" == *\?* || "$val" == *\#* ) ]]; then
    kind="secret"
  fi
  if [[ "$DRY_RUN" == true ]]; then
    printf 'WOULD set %-9s %s\n' "$kind" "$name"
  else
    printf '%s' "$val" | gh "$kind" set "$name" "${REPO_ARG[@]}"
    printf 'set %-9s %s\n' "$kind" "$name"
  fi
  [[ "$kind" == secret ]] && set_secret=$((set_secret+1)) || set_var=$((set_var+1))
done < "$MANIFEST"

echo ""
echo "Done. secrets=$set_secret variables=$set_var skipped(empty)=$skipped"
if [[ "$DRY_RUN" == true ]]; then
  echo "(dry-run — nothing was changed)"
fi
