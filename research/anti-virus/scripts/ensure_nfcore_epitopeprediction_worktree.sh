#!/usr/bin/env bash
# Restore full nf-core/epitopeprediction worktree (conf/, workflows/, modules/, …).
#
# BioMate workflow id 12700 resolves to backend/nf-core-workflows/epitopeprediction/main.nf.
# If that nested clone was created with git sparse-checkout excluding directories, Nextflow
# fails with: "Config file does not exist: .../epitopeprediction/conf/base.config"
#
# This script is safe to run repeatedly. Parent repo does not track nf-core-workflows/
# (.gitignore); each developer machine needs this once per broken clone.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
EP="${ROOT}/backend/nf-core-workflows/epitopeprediction"

if [[ ! -d "${EP}/.git" ]]; then
  echo "ERROR: expected nested git repo at ${EP}" >&2
  exit 1
fi

cd "${EP}"
if git sparse-checkout list 2>/dev/null | grep -q .; then
  echo "[ensure_nfcore_epitopeprediction] disabling sparse-checkout (was excluding conf/)"
  git sparse-checkout disable
fi
# Materialize any paths that were index-only in a broken sparse worktree
git checkout . 2>/dev/null || true

if [[ ! -f conf/base.config ]]; then
  echo "ERROR: conf/base.config still missing after checkout — try: cd ${EP} && git fetch && git reset --hard origin/master" >&2
  exit 2
fi

echo "[ensure_nfcore_epitopeprediction] OK: $(wc -l < conf/base.config) lines in conf/base.config"
echo "[ensure_nfcore_epitopeprediction] workflows: $(test -d workflows && echo yes || echo no)"
