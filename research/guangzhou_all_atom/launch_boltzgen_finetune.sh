#!/bin/bash
# launch_boltzgen_finetune.sh — Path-A BoltzGen cyclic fine-tune pipeline (SMOKE-gated).
# MODE=introspect : install boltzgen, download targets.zip/mols/ckpt, run boltzgen_introspect.py
#                   to PIN the Record/Manifest/config construction. (cheap; no training)
# MODE=smoke      : run --batch on a small subset + main.py max_steps=10 (added after introspect pins the API).
# Spot-first, self-terminating (shutdown=terminate + dead-man's-switch), streams to S3. ONE GPU instance.
set -Eeuo pipefail
REGION=${REGION:-us-west-2}; export AWS_DEFAULT_REGION=$REGION
BUCKET=${BUCKET:-knowledge-datasets-1759951976}
AMI=${AMI:-ami-04f7da1c787a89267}      # DL Base OSS Nvidia GPU AMI (Ubuntu 22.04) us-west-2 (CUDA drivers + awscli)
SG=${SG:-sg-011121fdf81073ec8}; KEY=${KEY:-biomate-trial-resume-20260912}
MODE=${MODE:-introspect}
MAX_RUNTIME=${MAX_RUNTIME:-1h}
RUNID=bgen-ft-${MODE}-$(date -u +%Y%m%dT%H%M%SZ)
S3RUN=s3://$BUCKET/cyclic_peptide/runs/$RUNID
HERE=$(cd "$(dirname "$0")" && pwd)

# ship our scripts
aws s3 cp "$HERE/boltzgen_introspect.py" "$S3RUN/code/boltzgen_introspect.py" --only-show-errors
aws s3 cp "$HERE/boltzgen_cyclic_convert.py" "$S3RUN/code/boltzgen_cyclic_convert.py" --only-show-errors
echo "shipped code -> $S3RUN/code/ (MODE=$MODE)"

cat > "/tmp/bgenft_driver.$$" <<'DRIVER'
#!/bin/bash
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2 DEBIAN_FRONTEND=noninteractive PYTHONUNBUFFERED=1
ROOT=/opt/bgenft; mkdir -p "$ROOT/status" "$ROOT/code"; cd "$ROOT"
exec > >(tee -a "$ROOT/status/boot.log") 2>&1
stage(){ printf '{"stage":"%s","time":"%s"}\n' "$1" "$(date -u +%FT%TZ)" > "$ROOT/status/status.json"; aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true; }
finish(){ rc=$?; trap - EXIT; [ "$rc" -ne 0 ] && stage failed || stage done_rc0; aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true; sleep 4; shutdown -h now; exit "$rc"; }
trap finish EXIT
(while sleep 60; do aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true; done) &
BUCKET=$(echo "$OUT_S3" | cut -d/ -f3)   # derive from OUT_S3 (not passed via UD)
# huggingface_hub 2.x drops `huggingface-cli` -> use the python API (called after conda activate)
hfget(){ python - "$1" "$2" "${3:-dataset}" <<'PY'
import sys, shutil
from huggingface_hub import hf_hub_download
repo, fn, rt = sys.argv[1], sys.argv[2], sys.argv[3]
p = hf_hub_download(repo, fn, repo_type=rt)
shutil.copy(p, fn); print("hfget ok", fn)
PY
}

stage installing
for a in 1 2 3 4 5; do aws s3 cp "$OUT_S3/code/boltzgen_introspect.py" "$ROOT/code/" --only-show-errors && aws s3 cp "$OUT_S3/code/boltzgen_cyclic_convert.py" "$ROOT/code/" --only-show-errors && break; sleep 8; done
# The DL-AMI has NO `python` on PATH non-interactively -> install miniconda + a py3.12 env (the proven
# pattern from boltzgen_ourtarget.sh). Then editable-install boltzgen (training code + [dev] extras).
apt-get -o DPkg::Lock::Timeout=300 install -y -qq git curl unzip 2>&1 | tail -1 || true
curl -fsSL https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -o /tmp/mc.sh
bash /tmp/mc.sh -b -p /opt/miniconda
set +u; source /opt/miniconda/etc/profile.d/conda.sh
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main || true
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r || true
conda create -y -n bg -c conda-forge python=3.12
conda activate bg; set -u
git clone --depth 1 https://github.com/HannesStark/boltzgen "$ROOT/boltzgen" 2>&1 | tail -3
cd "$ROOT/boltzgen"
pip install -q -e ".[dev]" 2>&1 | tail -8 || { echo "FATAL: boltzgen install failed"; exit 1; }
pip install -q huggingface_hub pyyaml 2>&1 | tail -2
python -c "import boltzgen, torch; print('boltzgen ok; cuda', torch.cuda.is_available())"

stage fetching_data
mkdir -p "$ROOT/dl"; cd "$ROOT/dl"
# CCD mols (required by parse_mmcif)
hfget boltzgen/inference-data mols.zip dataset 2>&1 | tail -2 || true
[ -f mols.zip ] && { mkdir -p mols && unzip -q -o mols.zip -d mols && echo "mols: $(ls mols | wc -l) files"; } || echo "WARN: mols.zip not fetched"
# shipped training targets (to introspect Record/Manifest construction) + fold ckpt + small ckpt
# targets.zip = the large BASE BoltzGen training set; only introspect needs a real example to pin the
# Record/Manifest format. The smoke trains on OUR converted data ($TARGETS_DIR), so skip the multi-GB
# download for smoke (it was stalling fetching_data).
if [ "$MODE" = "introspect" ]; then
  hfget boltzgen/boltzgen1_train targets.zip dataset 2>&1 | tail -2 || true
  [ -f targets.zip ] && { mkdir -p shipped && unzip -q -o targets.zip -d shipped && echo "shipped targets: $(find shipped -maxdepth 3 -name manifest.json | head -1)"; } || echo "WARN: targets.zip not fetched"
else
  echo "smoke mode: skipping base targets.zip (trains on our converted data)"
fi

stage "running_${MODE}"
CFG="$ROOT/boltzgen/src/boltzgen/resources/config/train/boltzgen_small.yaml"
SHIPPED_TARGETS=$(dirname "$(find "$ROOT/dl/shipped" -maxdepth 4 -name manifest.json 2>/dev/null | head -1)")
echo "SHIPPED_TARGETS=$SHIPPED_TARGETS  CFG=$CFG"
MOLS="$ROOT/dl/mols"
if [ "$MODE" = "introspect" ]; then
  python "$ROOT/code/boltzgen_introspect.py" "${SHIPPED_TARGETS:-$ROOT/dl/shipped}" "$CFG" 2>&1 | tee "$ROOT/status/introspect.txt"
  aws s3 cp "$ROOT/status/introspect.txt" "$OUT_S3/status/introspect.txt" --only-show-errors || true

elif [ "$MODE" = "smoke" ]; then
  cd "$ROOT/dl"
  stage smoke_fetch
  # small structure-trained ckpt (fine-tune init) + boltz2 fold ckpt (val validator dependency)
  hfget boltzgen/boltzgen-1 boltzgen1_structuretrained_small.ckpt model 2>&1 | tail -2 || true
  SMALL_CKPT=$(find "$ROOT/dl" -name boltzgen1_structuretrained_small.ckpt | head -1)
  # our cyclic manifest + a ~20-complex subset of CIFs (fetch from RCSB)
  aws s3 cp "s3://$BUCKET/cyclic_peptide/datasets/bound_cyclic_v1/bound_cyclic_manifest.jsonl" "$ROOT/dl/bound_cyclic_manifest.jsonl" --only-show-errors || \
    aws s3 cp "s3://$BUCKET/cyclic_peptide/datasets/bound_cyclic_agg/bound_cyclic_manifest.jsonl" "$ROOT/dl/bound_cyclic_manifest.jsonl" --only-show-errors || true
  head -20 "$ROOT/dl/bound_cyclic_manifest.jsonl" > "$ROOT/dl/subset.jsonl"
  mkdir -p "$ROOT/dl/cifs"
  python - "$ROOT/dl/subset.jsonl" "$ROOT/dl/cifs" <<'PY'
import json, sys, urllib.request
rows=[json.loads(l) for l in open(sys.argv[1]) if l.strip()]
for r in rows:
    pid=(r.get("pdb_id") or r.get("id") or "").lower()
    if not pid: continue
    out=f"{sys.argv[2]}/{pid}.cif"
    try:
        urllib.request.urlretrieve(f"https://files.rcsb.org/download/{pid}.cif", out)
        print("fetched", pid, flush=True)
    except Exception as e:
        print("cif FAIL", pid, e, flush=True)
PY
  stage smoke_batch
  TARGETS_DIR="$ROOT/training_data/targets"
  python "$ROOT/code/boltzgen_cyclic_convert.py" --batch "$ROOT/dl/subset.jsonl" \
     --cif-dir "$ROOT/dl/cifs" --moldir "$MOLS" --out "$TARGETS_DIR" --limit 20 2>&1 | tee "$ROOT/status/batch.log"
  aws s3 cp "$ROOT/status/batch.log" "$OUT_S3/status/batch.log" --only-show-errors || true
  mkdir -p "$TARGETS_DIR/msa"
  # a 2-id val split (so val set isn't empty) from the converted records
  ls "$TARGETS_DIR/records" | sed 's/.json$//' | head -2 > "$ROOT/training_data/val_split.txt"
  stage smoke_config
  SMOKE_CFG="$ROOT/smoke.yaml"
  python - "$CFG" "$SMOKE_CFG" "$TARGETS_DIR" "$MOLS" "$ROOT/training_data/val_split.txt" <<'PY'
import yaml, sys
cfg_p, out_p, targets, mols, split = sys.argv[1:6]
cfg=yaml.safe_load(open(cfg_p))
d=cfg.get("data",{})
d["datasets"]=[d["datasets"][0]]
ds=d["datasets"][0]
ds["target_dir"]=targets; ds["msa_dir"]=targets+"/msa"; ds["filters"]=[]; ds["split"]=split
d["moldir"]=mols; d["max_tokens"]=128; d["max_atoms"]=512; d["max_seqs"]=1
d["single_sequence_prop_training"]=1.0; d["num_workers"]=0; d["batch_size"]=1; d["samples_per_epoch"]=20
def rec(o):
    if isinstance(o,dict):
        for k in list(o):
            if k=="activation_checkpointing": o[k]=True
            if k=="checkpoint_diffusion_conditioning": o[k]=True
            rec(o[k])
    elif isinstance(o,list):
        for v in o: rec(v)
rec(cfg)
tr=cfg.setdefault("trainer",{})
tr["devices"]=[0]; tr["max_steps"]=10; tr["num_sanity_val_steps"]=0
tr["limit_val_batches"]=0; tr["val_check_interval"]=100  # no val in a 10-step smoke -> no folding ckpt needed
yaml.safe_dump(cfg, open(out_p,"w"))
print("wrote smoke config", out_p)
PY
  aws s3 cp "$SMOKE_CFG" "$OUT_S3/status/smoke.yaml" --only-show-errors || true
  stage smoke_train
  cd "$ROOT/boltzgen"
  python src/boltzgen/resources/main.py "$SMOKE_CFG" name=cyclic_smoke \
     ${SMALL_CKPT:+pretrained=$SMALL_CKPT} 2>&1 | tee "$ROOT/status/smoke_train.log" || echo "SMOKE_TRAIN_RC=$?"
  aws s3 cp "$ROOT/status/smoke_train.log" "$OUT_S3/status/smoke_train.log" --only-show-errors || true
  # verdict
  if grep -qiE "loss" "$ROOT/status/smoke_train.log" && ! grep -qiE "Traceback|Error:|RuntimeError|AssertionError" "$ROOT/status/smoke_train.log"; then
    echo "SMOKE_PASS"; else echo "SMOKE_FAIL (see smoke_train.log)"; fi
fi
stage complete
echo "=== $MODE DONE -> $OUT_S3/status/ ==="
DRIVER
aws s3 cp "/tmp/bgenft_driver.$$" "$S3RUN/code/driver.sh" --only-show-errors; rm -f "/tmp/bgenft_driver.$$"

UD=$(cat <<EOF | base64
#!/bin/bash
systemd-run --unit=bgenft-deadline --on-active=${MAX_RUNTIME} /sbin/shutdown -h now || shutdown -h +75 &
exec > /var/log/bgenft-boot.log 2>&1
export AWS_DEFAULT_REGION=us-west-2
mkdir -p /opt/bgenft/code
for i in 1 2 3 4 5; do aws s3 cp $S3RUN/code/driver.sh /opt/bgenft/driver.sh && break; sleep 10; done
chmod +x /opt/bgenft/driver.sh
OUT_S3=$S3RUN MODE=$MODE bash /opt/bgenft/driver.sh
EOF
)

declare -a COMBO=(
  "g5.2xlarge subnet-0254e4c3634b41bfc" "g5.2xlarge subnet-09e4dce46682a6c60"
  "g6.2xlarge subnet-0b35a6e2c1cf02dc2" "g5.2xlarge subnet-03b277a7a08d388c1"
  "g4dn.2xlarge subnet-0254e4c3634b41bfc"
)
[ -n "${COMBO_OVERRIDE:-}" ] && mapfile -t COMBO <<< "$COMBO_OVERRIDE"
try(){ local mode=$1 c T S opt; for c in "${COMBO[@]}"; do set -- $c; T=$1; S=$2
  [ "$mode" = spot ] && opt=(--instance-market-options '{"MarketType":"spot","SpotOptions":{"SpotInstanceType":"one-time","InstanceInterruptionBehavior":"terminate"}}') || opt=()
  IID=$(aws ec2 run-instances --image-id "$AMI" --instance-type "$T" ${KEY:+--key-name $KEY} \
    --subnet-id "$S" --security-group-ids "$SG" --iam-instance-profile Name=AutoimmuneCorpusProfile \
    "${opt[@]}" --instance-initiated-shutdown-behavior terminate \
    --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":200,"VolumeType":"gp3"}}]' \
    --user-data "$UD" --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$RUNID},{Key=project,Value=cyclic_peptide}]" \
    --query 'Instances[0].InstanceId' --output text 2>/dev/null) && [ -n "$IID" ] && { echo "LAUNCHED [$mode] $T $S -> $IID"; return 0; }
  echo "  no capacity ($T $S)"; done; return 1; }
IID=""; try spot || { echo "spot exhausted -> on-demand"; try ondemand; } || true
[ -z "$IID" ] && { echo "FATAL: no GPU capacity"; exit 1; }
echo "RUNID=$RUNID"; echo "INSTANCE=$IID"
echo "poll: aws s3 cp $S3RUN/status/status.json -"
echo "introspect: aws s3 cp $S3RUN/status/introspect.txt -"
