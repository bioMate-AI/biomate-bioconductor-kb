#!/bin/bash
# Fetch the datasets + reference code surfaced by the small-molecule-transfer survey (2024-2026) and
# stage them to S3 with pinned provenance. CPU-only, self-terminating. Priorities:
#  - CREMP (36,198 macrocyclic peptides, ~31M xTB geometries) — realistic conformer ensembles for the
#    permeability oracle + macrocycle ML-potential training (cross-corroborated by 3 surveys).
#  - FuncBind MCP macrocyclic-peptide dataset (unified-generator benchmark).
#  - Permeability code+data we should build on (BenchmarkCycPeptMP, CycPeptMP, MDML_PeptPerm).
#  - Reference generators (HELM-GPT, RINGER) + small-molecule patterns to port (GenMol, SynFormer, RGFN...).
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2 DEBIAN_FRONTEND=noninteractive PYTHONUNBUFFERED=1
ROOT=/opt/collect
OUT_S3=${OUT_S3:?}
DEST=s3://knowledge-datasets-1759951976/cyclic_peptide
mkdir -p "$ROOT/status" "$ROOT/dl" "$ROOT/code"
exec > >(tee -a "$ROOT/status/collect.log") 2>&1
stage(){ printf '{"stage":"%s","time":"%s"}\n' "$1" "$(date -u +%FT%TZ)" > "$ROOT/status/status.json"; aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true; }
prov(){ printf '{"dataset":"%s","source":"%s","fetched_utc":"%s"}\n' "$1" "$2" "$(date -u +%FT%TZ)" >> "$ROOT/status/provenance.jsonl"; }
trap 'rc=$?; [ $rc -ne 0 ] && stage failed; aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true; shutdown -h now; exit $rc' EXIT
systemd-run --unit=col-deadline --on-active=3h /sbin/shutdown -h now || true

stage installing
command -v aws >/dev/null 2>&1 || { apt-get update -qq && apt-get install -y -qq unzip curl && curl -fsSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o /tmp/a.zip && (cd /tmp && unzip -q -o a.zip && ./aws/install --update); }
apt-get -o DPkg::Lock::Timeout=300 install -y -qq git git-lfs python3-pip >/dev/null 2>&1 || true
git lfs install || true
pip install -q --disable-pip-version-check zenodo_get "huggingface_hub[cli]" || pip install -q zenodo_get huggingface_hub

# --- CREMP (Zenodo record 7931445) ---
stage cremp
( python3 -m zenodo_get 7931445 -o "$ROOT/dl/cremp" || zenodo_get 7931445 -o "$ROOT/dl/cremp" ) && \
  aws s3 sync "$ROOT/dl/cremp" "$DEST/datasets/cremp/" --only-show-errors && prov cremp "zenodo.org/records/7931445" || echo "CREMP fetch failed (continue)"
du -sh "$ROOT/dl/cremp" 2>/dev/null || true
rm -rf "$ROOT/dl/cremp"  # free disk after upload

# --- FuncBind MCP macrocyclic-peptide dataset (HuggingFace) ---
stage mcp
( huggingface-cli download Willete3/mcpp_dataset --repo-type dataset --local-dir "$ROOT/dl/mcp" ) && \
  aws s3 sync "$ROOT/dl/mcp" "$DEST/datasets/funcbind_mcp/" --only-show-errors && prov funcbind_mcp "hf.co/datasets/Willete3/mcpp_dataset" || echo "MCP fetch failed (continue)"
rm -rf "$ROOT/dl/mcp"

# --- reference code (shallow clones -> tarball -> S3 code_refs) ---
stage code_refs
clone_ref(){ # $1=url $2=name
  local d="$ROOT/code/$2"
  if git clone --depth 1 "$1" "$d" 2>/dev/null; then
    ( cd "$d" && git rev-parse HEAD > .pinned_commit 2>/dev/null || true )
    tar -C "$ROOT/code" -czf "$ROOT/$2.tgz" "$2" && aws s3 cp "$ROOT/$2.tgz" "$DEST/code_refs/$2.tgz" --only-show-errors && prov "code:$2" "$1"
    rm -rf "$d" "$ROOT/$2.tgz"
  else echo "clone failed: $1"; fi
}
# permeability (build directly on these)
clone_ref https://github.com/Gobliu/BenchmarkCycPeptMP benchmark_cycpeptmp
clone_ref https://github.com/akiyamalab/cycpeptmp cycpeptmp
clone_ref https://github.com/akiyamalab/MDML_PeptPerm mdml_peptperm
# peptide generators / conformers (reference)
clone_ref https://github.com/charlesxu90/helm-gpt helm_gpt
clone_ref https://github.com/Genentech/ringer ringer
clone_ref https://github.com/Genentech/cremp cremp_code
# small-molecule patterns to port
clone_ref https://github.com/NVIDIA-Digital-Bio/genmol genmol
clone_ref https://github.com/wenhao-gao/synformer synformer
clone_ref https://github.com/mirunacrt/synflownet synflownet
clone_ref https://github.com/koziarskilab/RGFN rgfn

stage listing
aws s3 ls "$DEST/datasets/cremp/" || true
aws s3 ls "$DEST/datasets/funcbind_mcp/" || true
aws s3 ls "$DEST/code_refs/" || true
cp "$ROOT/status/provenance.jsonl" "$ROOT/status/" 2>/dev/null || true
stage collect_complete
