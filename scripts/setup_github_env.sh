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
# Source-of-value priority (pick the most authoritative .env you have):
#   1. The WORKING dev EC2 /opt/biomate/.env  ← most correct (values proven live)
#         dump it first, e.g. via SSM:
#         aws ssm send-command --document-name AWS-RunShellScript \
#           --parameters 'commands=["cat /opt/biomate/.env"]' ...  > opt-biomate.env
#   2. env-files/frontend/.env + backend/.env  ← dev values; localhost DATABASE_URL
#         / REDIS_URL / GALAXY_URL are WRONG for the EC2 containers — override them.
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

# Sensitive vars → GitHub Secrets. Everything else in the manifest → Variables.
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
  return 1
}

get_value() { sed -n "s/^$1=//p" "$SOURCE_ENV" | head -n1; }

set_secret=0; set_var=0; skipped=0
while read -r name _req _; do
  [[ -z "$name" || "$name" == \#* ]] && continue
  val="$(get_value "$name")"
  if [[ -z "$val" ]]; then
    skipped=$((skipped+1)); continue
  fi
  if is_secret "$name"; then
    kind="secret"
  else
    kind="variable"
  fi
  if [[ "$DRY_RUN" == true ]]; then
    printf 'WOULD set %-9s %s\n' "$kind" "$name"
  else
    gh "$kind" set "$name" --body "$val" "${REPO_ARG[@]}"
    printf 'set %-9s %s\n' "$kind" "$name"
  fi
  [[ "$kind" == secret ]] && set_secret=$((set_secret+1)) || set_var=$((set_var+1))
done < "$MANIFEST"

echo ""
echo "Done. secrets=$set_secret variables=$set_var skipped(empty)=$skipped"
[[ "$DRY_RUN" == true ]] && echo "(dry-run — nothing was changed)"
