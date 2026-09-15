#!/bin/bash
# Adopt BoltzGen (backbone pivot). Qualification smoke: install BoltzGen, run native CYCLIC-peptide
# binder design on a provided example (peptide-anything protocol, covalent-bond closure) — the
# capability that solves our macrocyclic-closure gap for free. Verifies the model runs + produces
# ranked cyclic designs, before committing to full campaigns.
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2 DEBIAN_FRONTEND=noninteractive PYTHONUNBUFFERED=1
ROOT=/opt/boltzgen-run
BUCKET=knowledge-datasets-1759951976
OUT_S3=${OUT_S3:?}
NUM_DESIGNS=${NUM_DESIGNS:-10}
BUDGET=${BUDGET:-2}
mkdir -p "$ROOT/status"
exec > >(tee -a "$ROOT/status/boltzgen.log") 2>&1
stage(){ printf '{"stage":"%s","time":"%s"}\n' "$1" "$(date -u +%FT%TZ)" > "$ROOT/status/status.json"; aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true; }
trap 'rc=$?; [ $rc -ne 0 ] && stage failed; aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true; shutdown -h now; exit $rc' EXIT
systemd-run --unit=bg-deadline --on-active=4h /sbin/shutdown -h now || true

stage installing
command -v aws >/dev/null 2>&1 || { apt-get update -qq && apt-get install -y -qq unzip curl git && curl -fsSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o /tmp/a.zip && (cd /tmp && unzip -q -o a.zip && ./aws/install --update); }
apt-get -o DPkg::Lock::Timeout=300 install -y -qq git curl
# BoltzGen needs python>=3.11; DLAMI base is 3.10 -> use miniconda (per BoltzGen README)
curl -fsSL https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -o /tmp/mc.sh
bash /tmp/mc.sh -b -p /opt/miniconda
source /opt/miniconda/etc/profile.d/conda.sh
# recent Miniconda gates conda create behind channel ToS acceptance
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main || true
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r || true
conda create -y -n bg -c conda-forge python=3.12
conda activate bg
pip install -q boltzgen
git clone https://github.com/HannesStark/boltzgen "$ROOT/boltzgen"
export HF_HOME="$ROOT/hf_cache"    # weights (~6GB) download here
python -c "import boltzgen, torch; print('boltzgen import ok; cuda', torch.cuda.is_available())"

stage checking_spec
cd "$ROOT/boltzgen"
SPEC=example/cylcic_against_kras_with_specific_site/cyclicdesign.yaml
[ -f "$SPEC" ] || SPEC=example/cyclic_against_hiv_antibody_site/9d3d.yaml
echo "using spec: $SPEC"; cat "$SPEC" | head -40
boltzgen check "$SPEC" 2>&1 | tail -20

stage generating_cyclic
boltzgen run "$SPEC" --protocol peptide-anything --num_designs "$NUM_DESIGNS" --budget "$BUDGET" \
  --output "$ROOT/out" --cache "$ROOT/hf_cache" 2>&1 | tail -40

stage reporting
python - <<'PY'
import glob, json, os
root='/opt/boltzgen-run/out'
files = glob.glob(root+'/**/*', recursive=True)
pdbs = [f for f in files if f.endswith('.pdb') or f.endswith('.cif')]
jsons = [f for f in files if f.endswith('.json') or f.endswith('.jsonl') or f.endswith('.csv')]
rep = {'output_files': len(files), 'structure_files': len(pdbs), 'summary_files': len(jsons),
       'sample_structures': [os.path.relpath(p, root) for p in pdbs[:5]],
       'sample_summaries': [os.path.relpath(j, root) for j in jsons[:8]]}
# try to surface designed sequences / ranking from any results table
for j in jsons:
    if j.endswith(('.json','.jsonl')):
        try:
            txt = open(j).read()[:2000]; rep.setdefault('peek', {})[os.path.basename(j)] = txt[:800]
        except Exception: pass
json.dump(rep, open('/opt/boltzgen-run/status/boltzgen_qualify.json','w'), indent=2)
print(json.dumps({k:v for k,v in rep.items() if k!='peek'}, indent=2))
PY
cp /opt/boltzgen-run/status/boltzgen_qualify.json "$ROOT/status/" 2>/dev/null || true
# sync the design outputs (bounded) for inspection
aws s3 sync "$ROOT/out" "$OUT_S3/boltzgen_out/" --only-show-errors --exclude "*" --include "*.json" --include "*.jsonl" --include "*.csv" --include "*.pdb" || true
stage boltzgen_qualify_complete
