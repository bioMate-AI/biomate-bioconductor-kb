#!/bin/bash
# Fetch datasets + reference code surfaced by the small-molecule-transfer survey, stage to S3 with
# pinned provenance. CPU-only, self-terminating. ORDER MATTERS: small/reliable fetches (reference code,
# MCP dataset) run FIRST so a slow/hung CREMP download can't block them; CREMP runs LAST under a hard
# timeout with visible progress (prior run hung 3h with no output on the CREMP zenodo_get).
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2 DEBIAN_FRONTEND=noninteractive PYTHONUNBUFFERED=1 HOME=/root
ROOT=/opt/collect
OUT_S3=${OUT_S3:?}
DEST=s3://knowledge-datasets-1759951976/cyclic_peptide
mkdir -p "$ROOT/status" "$ROOT/dl" "$ROOT/code"
exec > >(tee -a "$ROOT/status/collect.log") 2>&1
stage(){ printf '{"stage":"%s","time":"%s"}\n' "$1" "$(date -u +%FT%TZ)" > "$ROOT/status/status.json"; aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true; }
prov(){ printf '{"dataset":"%s","source":"%s","fetched_utc":"%s"}\n' "$1" "$2" "$(date -u +%FT%TZ)" >> "$ROOT/status/provenance.jsonl"; }
trap 'rc=$?; [ $rc -ne 0 ] && stage failed; sync; sleep 6; aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true; sleep 4; shutdown -h now; exit $rc' EXIT
systemd-run --unit=col-deadline --on-active=6h /sbin/shutdown -h now || true

stage installing
command -v aws >/dev/null 2>&1 || { apt-get update -qq && apt-get install -y -qq unzip curl && curl -fsSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o /tmp/a.zip && (cd /tmp && unzip -q -o a.zip && ./aws/install --update); }
apt-get -o DPkg::Lock::Timeout=300 install -y -qq git git-lfs python3-pip >/dev/null 2>&1 || true
git lfs install || true
pip install -q --disable-pip-version-check zenodo_get huggingface_hub || pip install -q zenodo_get huggingface_hub

# ---------- 1) reference code (small git clones -> tarball -> S3) : reliable, do FIRST ----------
stage code_refs
clone_ref(){ # $1=url $2=name
  local d="$ROOT/code/$2"
  if git clone --depth 1 "$1" "$d" 2>/dev/null; then
    ( cd "$d" && git rev-parse HEAD > .pinned_commit 2>/dev/null || true )
    tar -C "$ROOT/code" -czf "$ROOT/$2.tgz" "$2" && aws s3 cp "$ROOT/$2.tgz" "$DEST/code_refs/$2.tgz" --only-show-errors && prov "code:$2" "$1"
    rm -rf "$d" "$ROOT/$2.tgz"
  else echo "clone failed: $1"; fi
}
clone_ref https://github.com/Gobliu/BenchmarkCycPeptMP benchmark_cycpeptmp
clone_ref https://github.com/akiyamalab/cycpeptmp cycpeptmp
clone_ref https://github.com/akiyamalab/MDML_PeptPerm mdml_peptperm
clone_ref https://github.com/charlesxu90/helm-gpt helm_gpt
clone_ref https://github.com/Genentech/ringer ringer
clone_ref https://github.com/Genentech/cremp cremp_code
clone_ref https://github.com/NVIDIA-Digital-Bio/genmol genmol
clone_ref https://github.com/wenhao-gao/synformer synformer
clone_ref https://github.com/mirunacrt/synflownet synflownet
clone_ref https://github.com/koziarskilab/RGFN rgfn

# ---------- 2) FuncBind MCP macrocyclic-peptide dataset (HuggingFace python API) ----------
stage mcp
python3 - <<'PY' && aws s3 sync "$ROOT/dl/mcp" "$DEST/datasets/funcbind_mcp/" --only-show-errors && prov funcbind_mcp "hf.co/datasets/Willete3/mcpp_dataset" || echo "MCP fetch failed (continue)"
import os
from huggingface_hub import snapshot_download
snapshot_download('Willete3/mcpp_dataset', repo_type='dataset', local_dir=os.environ['ROOT']+'/dl/mcp')
PY
rm -rf "$ROOT/dl/mcp" || true

# ---------- 3) CREMP (Zenodo 7931445): LARGE + prone to hang -> timeout + progress logger, LAST ----------
stage cremp
mkdir -p "$ROOT/dl/cremp"
( while sleep 120; do printf '{"stage":"cremp","size":"%s","time":"%s"}\n' "$(du -sh "$ROOT/dl/cremp" 2>/dev/null | cut -f1)" "$(date -u +%FT%TZ)" > "$ROOT/status/status.json"; aws s3 cp "$ROOT/status/status.json" "$OUT_S3/status/status.json" --only-show-errors; done ) &
PROG=$!
if timeout 4h python3 -u -m zenodo_get -R 3 7931445 -o "$ROOT/dl/cremp"; then
  aws s3 sync "$ROOT/dl/cremp" "$DEST/datasets/cremp/" --only-show-errors && prov cremp "zenodo.org/records/7931445"
  echo "CREMP done: $(du -sh "$ROOT/dl/cremp" 2>/dev/null)"
else
  echo "CREMP fetch timed out or failed at $(du -sh "$ROOT/dl/cremp" 2>/dev/null | cut -f1); syncing partial"
  aws s3 sync "$ROOT/dl/cremp" "$DEST/datasets/cremp_partial/" --only-show-errors || true
fi
kill "$PROG" 2>/dev/null || true
rm -rf "$ROOT/dl/cremp" || true

stage listing
aws s3 ls "$DEST/code_refs/" || true
aws s3 ls "$DEST/datasets/funcbind_mcp/" || true
aws s3 ls "$DEST/datasets/cremp/" || true
cp "$ROOT/status/provenance.jsonl" "$ROOT/status/" 2>/dev/null || true
stage collect_complete
