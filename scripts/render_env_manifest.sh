#!/usr/bin/env bash
#
# render_env_manifest.sh — render the managed env file from the manifest.
#
# Reads deploy/biomate.env.manifest (variable NAMES only) and, for each var that
# has a non-empty value in the current environment, emits `NAME=value` to the
# output file. Required vars with no value fail the render (fail-fast).
#
# This is intentionally separate from deploy.sh: it runs in a context where the
# APP's secret values (including AWS_ACCESS_KEY_ID as a *value to write*) are in
# the environment. deploy.sh then transports the rendered file using the OIDC
# deploy-role creds — the two must not share one process (same env var names,
# different identities).
#
# Usage:
#   render_env_manifest.sh <output-file> [manifest-path]
#
# Exit codes:
#   0  rendered OK (output may be empty → caller keeps existing .env)
#   1  required var(s) missing, or bad invocation
#
# Backward compatibility: if NO managed var has a value (operator hasn't set any
# GitHub Secrets yet), the output is empty and exit is 0 — the deploy preserves
# the existing host .env. Required vars are only enforced once at least one
# managed var is provided (i.e. the operator has opted in).

set -euo pipefail

OUT="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="${2:-$SCRIPT_DIR/../deploy/biomate.env.manifest}"

if [[ -z "$OUT" ]]; then
  echo "Usage: $0 <output-file> [manifest-path]" >&2
  exit 1
fi
if [[ ! -f "$MANIFEST" ]]; then
  echo "Error: manifest not found at $MANIFEST" >&2
  exit 1
fi

: > "$OUT"
chmod 600 "$OUT"

provided=0
missing=()
while read -r name req _; do
  [[ -z "$name" || "$name" == \#* ]] && continue
  val="${!name-}"
  if [[ -n "$val" ]]; then
    printf '%s=%s\n' "$name" "$val" >> "$OUT"
    provided=$((provided + 1))
  elif [[ "$req" == "required" ]]; then
    missing+=("$name")
  fi
done < "$MANIFEST"

if [[ "$provided" -eq 0 ]]; then
  # Nothing provided → backward-compatible: caller keeps existing .env.
  echo "render: no managed vars provided; existing host .env will be preserved." >&2
  exit 0
fi

if [[ "${#missing[@]}" -gt 0 ]]; then
  echo "::error::render: missing required env var(s) — set them in GitHub Secrets/Variables: ${missing[*]}" >&2
  : > "$OUT"
  exit 1
fi

echo "render: wrote $provided managed var(s) to $OUT" >&2
exit 0
