#!/bin/bash
# =============================================================================
# launch_unimomo_cyclic_ft.sh — cyclic-specialization FINE-TUNE of the reproduced UniMoMo base
# (0.7754 DockQ), then base-vs-FT cyclic DockQ eval on the SAME UniMoMo harness. Step 4 of
# docs/20261002_BEST_PEPTIDE_LLM_PROGRAM.md (minus transfer-pretrain, already in the base weights).
#
# Pipeline (on one GPU instance, self-terminating):
#   1. build UniMoMo env @ pinned commit; download base model.ckpt; extract its .autoencoder -> ae.ckpt
#   2. TRAIN data: d2-mine cyclic manifest -> dataprep (PepBDB-cyclic test HELD OUT) -> pepbench -> mmap
#      -> split train/valid index
#   3. fine-tune the LDM (warm-start load_ckpt=base, frozen AE, lr 1e-5, few epochs) via train.py
#   4. EVAL: PepBDB-cyclic test -> dataprep(test) -> pepbench --remove_het; generate+DockQ for BOTH the
#      base and the best FT ckpt on that cyclic test set -> ft_summary.json (base vs FT, matched sampling)
#
# LAUNCHER only: uploads the driver + dataprep + config to S3, starts a spot(→on-demand) GPU.
# Poll:  aws s3 cp $S3RUN/status/status.json -
# Result: aws s3 cp $S3RUN/status/ft_summary.json -   (base_cyclic_DockQ vs ft_cyclic_DockQ)
# =============================================================================
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2

BUCKET=knowledge-datasets-1759951976
AMI=ami-04f7da1c787a89267
SG=sg-011121fdf81073ec8
KEY=biomate-trial-resume-20260912
PROFILE=AutoimmuneCorpusProfile
UNIMOMO_REPO=https://github.com/kxz18/UniMoMo.git
UNIMOMO_COMMIT=f58f117d43975d45dc2521b34ae3066a095582f0
CKPT_URL=https://github.com/kxz18/UniMoMo/releases/download/v1.0/model.ckpt
CKPT_SIZE=420891881
ENV_YAML=env_cuda121.yaml

# inputs (env-overridable)
MANIFEST_S3=${MANIFEST_S3:-s3://$BUCKET/cyclic_peptide/runs/d2-mine-local-20261001T235534Z/bound_cyclic_manifest.jsonl}
TEST_INDEX_S3=${TEST_INDEX_S3:-s3://$BUCKET/cyclic_peptide/runs/pepglad-cyclicprep-20260914T194504Z/pepbdb_cyclic_processed/test_index.txt}
N_SAMPLES=${N_SAMPLES:-100}            # eval candidates/target (matched to the repro budget)
MANIFEST_FILTER=${MANIFEST_FILTER:-}   # e.g. head_to_tail to restrict cyclization type; empty=all 616
MAX_RUNTIME=${MAX_RUNTIME:-20h}
DISK_GB=${DISK_GB:-250}

RUNID=unimomo-cyclic-ft-$(date -u +%Y%m%dT%H%M%SZ)
S3RUN=s3://$BUCKET/cyclic_peptide/runs/$RUNID
HERE=$(cd "$(dirname "$0")" && pwd)

# preflight: inputs must exist
for uri in "$MANIFEST_S3" "$TEST_INDEX_S3"; do
  aws s3 ls "$uri" >/dev/null 2>&1 || { echo "FATAL: missing input $uri"; exit 1; }
done
[ -f "$HERE/unimomo_cyclic_dataprep.py" ] || { echo "FATAL: unimomo_cyclic_dataprep.py missing"; exit 1; }
[ -f "$HERE/unimomo_cyclic_ft.yaml" ] || { echo "FATAL: unimomo_cyclic_ft.yaml missing"; exit 1; }

# upload code the driver pulls
aws s3 cp "$HERE/unimomo_cyclic_dataprep.py" "$S3RUN/code/unimomo_cyclic_dataprep.py" --only-show-errors
aws s3 cp "$HERE/unimomo_cyclic_ft.yaml"     "$S3RUN/code/unimomo_cyclic_ft.yaml"     --only-show-errors

DRIVER=$(mktemp)
cat > "$DRIVER" <<'DRIVER_EOF'
#!/bin/bash
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2
export DEBIAN_FRONTEND=noninteractive
export PYTHONUNBUFFERED=1
ROOT=/opt/unimomo-run
OUT_S3=${OUT_S3:?}; UNIMOMO_REPO=${UNIMOMO_REPO:?}; UNIMOMO_COMMIT=${UNIMOMO_COMMIT:?}
CKPT_URL=${CKPT_URL:?}; CKPT_SIZE=${CKPT_SIZE:?}; ENV_YAML=${ENV_YAML:?}
MANIFEST_S3=${MANIFEST_S3:?}; TEST_INDEX_S3=${TEST_INDEX_S3:?}
N_SAMPLES=${N_SAMPLES:-100}; MANIFEST_FILTER=${MANIFEST_FILTER:-}; MAX_RUNTIME=${MAX_RUNTIME:-20h}

mkdir -p "$ROOT/status"; exec > >(tee -a "$ROOT/status/bootstrap.log") 2>&1
stage(){ printf '{"stage":"%s","time":"%s","runid":"%s"}\n' "$1" "$(date -u +%FT%TZ)" "$(basename "$OUT_S3")" > "$ROOT/status/status.json"; aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true; }
sync_results(){ aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true; [ -d "$ROOT/UniMoMo/ckpts" ] && aws s3 sync "$ROOT/UniMoMo/ckpts" "$OUT_S3/ckpts/" --only-show-errors || true; }
finish(){ rc=$?; trap - EXIT; [ "$rc" -ne 0 ] && stage failed; sync_results; shutdown -h now; exit "$rc"; }
trap finish EXIT
systemctl is-active --quiet unimomo-deadline.timer || systemd-run --unit=unimomo-deadline --on-active="$MAX_RUNTIME" /sbin/shutdown -h now || true
(while sleep 120; do sync_results; done) &

stage installing_conda
for i in 1 2 3 4 5; do curl -fsSL -o /tmp/miniforge.sh https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh && break; sleep 10; done
bash /tmp/miniforge.sh -b -p /opt/miniforge
source /opt/miniforge/etc/profile.d/conda.sh

stage cloning_unimomo
cd "$ROOT"; git clone "$UNIMOMO_REPO" UniMoMo; cd "$ROOT/UniMoMo"; git checkout "$UNIMOMO_COMMIT"
git rev-parse HEAD > "$ROOT/status/unimomo_commit.txt"

# make pepbench SKIP-AND-CONTINUE on per-structure parse failures (biotite CCD NoneType crash on an
# unknown residue killed the whole batch 2026-10-02; pipeline already tolerates RCSB-fetch failures).
stage patching_pepbench
python - <<'PBPATCH'
import re, py_compile, sys
p='scripts/data_process/peptide/pepbench.py'
src=open(p).read()
NEW='''def process_iterator(items, pocket_th, remove_het=False):

    for cnt, pdb_id in enumerate(items):
        try:
            summary = items[pdb_id]
            rec_chain, lig_chain = summary['rec_chain'], summary['pep_chain']
            cplx = pdb_to_complex(summary['pdb_path'], selected_chains=[rec_chain, lig_chain], remove_het=remove_het)
            target_blocks = cplx[rec_chain].blocks
            lig_blocks = cplx[lig_chain].blocks
            target_seq = ''.join([VOCAB.abrv_to_symbol(block.name) for block in target_blocks])
            lig_seq = ''.join([VOCAB.abrv_to_symbol(block.name) for block in lig_blocks])
            pocket_block_id, _ = compute_pocket(cplx, [rec_chain], [lig_chain], dist_th=pocket_th)
            pocket_blocks = [recur_index(cplx, _id) for _id in pocket_block_id]
            data = cplx.to_tuple()
            properties = {
                'pocket_num_blocks': len(pocket_block_id),
                'ligand_num_blocks': len(lig_blocks),
                'pocket_num_atoms': sum([len(block) for block in pocket_blocks]),
                'ligand_num_atoms': sum([len(block) for block in lig_blocks]),
                'target_chain_ids': [rec_chain],
                'ligand_chain_ids': [lig_chain],
                'target_sequences': [target_seq],
                'ligand_sequences': [lig_seq],
                'pocket_block_id': pocket_block_id,
            }
        except Exception as e:
            print_log(f'WARN pepbench skip {pdb_id}: {type(e).__name__}: {e}')
            continue
        yield pdb_id, data, properties, cnt
'''
if 'WARN pepbench skip' in src:
    print('pepbench already patched'); sys.exit(0)
pat=re.compile(r'def process_iterator\(.*?(?=\ndef main\()', re.S)
n=len(pat.findall(src))
assert n==1, f'FATAL pepbench anchor count={n} (expected 1) -- UniMoMo changed; aborting patch'
open(p,'w').write(pat.sub(NEW+'\n', src, count=1))
py_compile.compile(p, doraise=True)
print('pepbench patched: skip-and-continue on per-structure failure')
PBPATCH

stage building_env
conda env create -f "$ENV_YAML"
set +u; conda activate UniMoMo; set -u   # MKL_INTERFACE_LAYER unbound under set -u (repro fix)
python -c 'import torch; print("cuda", torch.cuda.is_available())' | tee "$ROOT/status/torch_check.txt"

stage downloading_base_ckpt
mkdir -p checkpoints
for i in 1 2 3 4 5; do wget -q -O checkpoints/model.ckpt "$CKPT_URL" && break; sleep 15; done
GOT=$(stat -c%s checkpoints/model.ckpt); [ "$GOT" = "$CKPT_SIZE" ] || { echo "FATAL ckpt size $GOT != $CKPT_SIZE"; exit 1; }
# extract the frozen IterVAE autoencoder from the pickled base LDMMolDesign (LDMMolDesign.__init__ needs it)
python - <<'PY'
import torch
m = torch.load('checkpoints/model.ckpt', map_location='cpu')
torch.save(m.autoencoder, 'checkpoints/ae.ckpt')
print('extracted ae.ckpt from base model.ckpt (.autoencoder)')
PY

# ---- pull our code + inputs ----
aws s3 cp "$OUT_S3/code/unimomo_cyclic_dataprep.py" ./unimomo_cyclic_dataprep.py --only-show-errors
aws s3 cp "$OUT_S3/code/unimomo_cyclic_ft.yaml" ./configs/unimomo_cyclic_ft.yaml --only-show-errors
aws s3 cp "$MANIFEST_S3" ./manifest.jsonl --only-show-errors
aws s3 cp "$TEST_INDEX_S3" ./pepbdb_test_index.txt --only-show-errors

# ---- TRAIN data: dataprep (holdout PepBDB test) -> pepbench -> mmap -> split ----
stage dataprep_train
FILT=""; [ -n "$MANIFEST_FILTER" ] && FILT="--type_filter $MANIFEST_FILTER"
python unimomo_cyclic_dataprep.py --mode train --manifest manifest.jsonl --test_index pepbdb_test_index.txt --out_dir ./cyc_train $FILT 2>&1 | tee "$ROOT/status/dataprep_train.log"
stage processing_train
python -m scripts.data_process.peptide.pepbench --index ./cyc_train/index.txt --out_dir ./datasets/peptide/cyclic/processed 2>&1 | tee "$ROOT/status/pepbench_train.log"
python - <<'PY'
import random
lines=[l for l in open('./datasets/peptide/cyclic/processed/index.txt').read().splitlines() if l.strip()]
random.seed(0); random.shuffle(lines); k=max(1,len(lines)//10)
open('./datasets/peptide/cyclic/processed/valid_index.txt','w').write('\n'.join(lines[:k])+'\n')
open('./datasets/peptide/cyclic/processed/train_index.txt','w').write('\n'.join(lines[k:])+'\n')
print(f'train={len(lines)-k} valid={k}')
PY
echo "train/valid split done" | tee -a "$ROOT/status/pepbench_train.log"
sync_results

# ---- fine-tune ----
stage training
python train.py --config ./configs/unimomo_cyclic_ft.yaml --gpus 0 2>&1 | tee "$ROOT/status/train.log"
sync_results
FT_CKPT=$(head -1 ckpts/cyclic_ft/version_*/checkpoint/topk_map.txt | sed 's/^[^:]*: //')
echo "best FT ckpt: $FT_CKPT" | tee "$ROOT/status/ft_ckpt.txt"
[ -f "$FT_CKPT" ] || { echo "FATAL: no FT ckpt"; exit 1; }

# ---- EVAL data: PepBDB-cyclic test -> dataprep(test) -> pepbench --remove_het ----
stage eval_dataprep
python unimomo_cyclic_dataprep.py --mode test --test_index pepbdb_test_index.txt --out_dir ./cyc_test 2>&1 | tee "$ROOT/status/dataprep_test.log"
python -m scripts.data_process.peptide.pepbench --index ./cyc_test/index.txt --out_dir ./datasets/peptide/cyclic_test/processed --remove_het 2>&1 | tee "$ROOT/status/pepbench_test.log"
sed 's#./datasets/peptide/LNR/processed#./datasets/peptide/cyclic_test/processed#' configs/test/test_pep.yaml > configs/test/test_cyclic.yaml
NCPU=$(nproc)

# ---- generate + DockQ for BASE and FT on the SAME cyclic test (matched sampling) ----
eval_ckpt(){  # $1=label $2=ckpt
  local label="$1" ck="$2"
  stage "generating_$label"
  python generate.py --config configs/test/test_cyclic.yaml --ckpt "$ck" --gpu 0 --save_dir ./results/$label --n_samples=$N_SAMPLES 2>&1 | tee "$ROOT/status/generate_$label.log"
  stage "evaluating_$label"
  python -m scripts.metrics.peptide --results ./results/$label/results.jsonl --num_workers "$NCPU" 2>&1 | tee "$ROOT/status/eval_$label.log"
  cp -f ./results/$label/eval_final_.log "$ROOT/status/eval_final_$label.log" 2>/dev/null || true
}
eval_ckpt base ./checkpoints/model.ckpt
eval_ckpt ft "$FT_CKPT"

stage summarizing
python - "$N_SAMPLES" <<'PY'
import json,re,os
ns=int(__import__('sys').argv[1])
def dockq(label):
    p=f"./results/{label}/eval_final_.log"
    if not os.path.exists(p): return None
    m=re.search(r"DockQ \(mean\):\s*([0-9.]+)", open(p).read()); return float(m.group(1)) if m else None
b,f=dockq('base'),dockq('ft')
out={'benchmark':'UniMoMo-format PepBDB-cyclic test (reprocessed via pepbench), co-design DockQ',
 'aggregation':'mean over targets of max DockQ over candidates [oracle best-of-N]',
 'candidates_per_target':ns,'base_cyclic_DockQ':b,'ft_cyclic_DockQ':f,
 'delta_ft_minus_base':(None if (b is None or f is None) else round(f-b,4)),
 'note':'base = reproduced UniMoMo 0.7754-on-LINEAR; here both scored on the CYCLIC test set, same harness. NOT comparable to PepGLAD 0.403/0.506 (different format/harness).'}
open('/opt/unimomo-run/status/ft_summary.json','w').write(json.dumps(out,indent=2)); print(json.dumps(out,indent=2))
PY
sync_results
stage complete
DRIVER_EOF

aws s3 cp "$DRIVER" "$S3RUN/code/run_cyclic_ft.sh" --only-show-errors
aws s3 cp "$HERE/launch_unimomo_cyclic_ft.sh" "$S3RUN/code/launch_unimomo_cyclic_ft.sh" --only-show-errors

UD=$(cat <<EOF | base64
#!/bin/bash
exec > /var/log/unimomo-ft-boot.log 2>&1
mkdir -p /opt/unimomo-run
for i in 1 2 3 4 5; do aws s3 cp $S3RUN/code/run_cyclic_ft.sh /opt/unimomo-run/run.sh --region us-west-2 && break; sleep 10; done
chmod +x /opt/unimomo-run/run.sh
OUT_S3=$S3RUN UNIMOMO_REPO=$UNIMOMO_REPO UNIMOMO_COMMIT=$UNIMOMO_COMMIT CKPT_URL=$CKPT_URL CKPT_SIZE=$CKPT_SIZE \\
ENV_YAML=$ENV_YAML MANIFEST_S3=$MANIFEST_S3 TEST_INDEX_S3=$TEST_INDEX_S3 N_SAMPLES=$N_SAMPLES \\
MANIFEST_FILTER="$MANIFEST_FILTER" MAX_RUNTIME=$MAX_RUNTIME bash /opt/unimomo-run/run.sh
EOF
)

declare -a COMBO=(
  "g5.4xlarge subnet-0254e4c3634b41bfc" "g5.4xlarge subnet-03b277a7a08d388c1" "g5.4xlarge subnet-09e4dce46682a6c60"
  "g6.4xlarge subnet-0254e4c3634b41bfc" "g6.4xlarge subnet-0b35a6e2c1cf02dc2"
  "g5.8xlarge subnet-0254e4c3634b41bfc" "g6.8xlarge subnet-0254e4c3634b41bfc"
  "g5.2xlarge subnet-0254e4c3634b41bfc" "g6.2xlarge subnet-0b35a6e2c1cf02dc2"
)
launch_one(){
  local market="$1" c TYPE SUBNET market_opt=""
  [ "$market" = spot ] && market_opt='--instance-market-options {"MarketType":"spot","SpotOptions":{"SpotInstanceType":"one-time","InstanceInterruptionBehavior":"terminate"}}'
  for c in "${COMBO[@]}"; do
    set -- $c; TYPE=$1; SUBNET=$2
    echo "[$market] trying $TYPE in $SUBNET ..."
    IID=$(aws ec2 run-instances --image-id "$AMI" --instance-type "$TYPE" --key-name "$KEY" \
      --subnet-id "$SUBNET" --security-group-ids "$SG" --iam-instance-profile Name=$PROFILE $market_opt \
      --instance-initiated-shutdown-behavior terminate \
      --block-device-mappings "[{\"DeviceName\":\"/dev/sda1\",\"Ebs\":{\"VolumeSize\":$DISK_GB,\"VolumeType\":\"gp3\"}}]" \
      --user-data "$UD" \
      --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$RUNID},{Key=project,Value=cyclic_peptide}]" \
      --query 'Instances[0].InstanceId' --output text 2>/dev/null) && [ -n "$IID" ] && [ "$IID" != "None" ] \
      && { echo "LAUNCHED [$market] $TYPE $SUBNET -> $IID"; return 0; }
    echo "  no capacity ([$market] $TYPE $SUBNET)"
  done
  return 1
}
IID=""; launch_one spot || launch_one ondemand || true
{ [ -z "${IID:-}" ] || [ "$IID" = "None" ]; } && { echo "FATAL: no GPU capacity"; rm -f "$DRIVER"; exit 1; }
rm -f "$DRIVER"
echo "=============================================================="
echo "RUNID    = $RUNID"
echo "INSTANCE = $IID"
echo "poll     : aws s3 cp $S3RUN/status/status.json -"
echo "result   : aws s3 cp $S3RUN/status/ft_summary.json -   (base vs FT cyclic DockQ)"
echo "=============================================================="
