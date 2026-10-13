#!/bin/bash
# =============================================================================
# launch_cofold_v2.sh — cofold the v2 cyclic peptides into the receptor with Boltz-2
# (`boltz predict`, cyclic bond) to produce receptor+peptide COMPLEX CIFs, which the
# tested MM-GBSA runner (launch_mmgbsa_pool.sh DESIGNS_S3=<this run's complexes>) then
# scores on the round-1 dG scale. This launcher is NEW; the MM-GBSA stage is unchanged.
#
# Recipe is from build_candidates.py (refold_boltz): in.yaml with R (receptor) + P
# (peptide, cyclic:true); boltz env per refold_rerank_driver.sh (conda py3.11 +
# conda-forge numpy/scipy; pip boltz cuequivariance-torch).
#
# DRY_RUN=1 (DEFAULT): cofold ONE peptide on ONE target — cheapest confirmation that
# boltz folds a 2-chain cyclic complex and emits a parseable CIF. Confirm before the set.
#
# Poll:   aws s3 cp s3://$BUCKET/cyclic_peptide/runs/$RUNID/status/status.json -
# Result: aws s3 ls s3://$BUCKET/cyclic_peptide/runs/$RUNID/complexes/$TARGET/
# Then MM-GBSA:
#   DESIGNS_S3=s3://$BUCKET/cyclic_peptide/runs/$RUNID/complexes TARGET=$TARGET \
#     bash launch_mmgbsa_pool.sh
# =============================================================================
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2
BUCKET=knowledge-datasets-1759951976
AMI=${AMI:-ami-04f7da1c787a89267}
SG=sg-011121fdf81073ec8
KEY=biomate-trial-resume-20260912
PROFILE=AutoimmuneCorpusProfile
TARGET=${TARGET:-5o45}                 # 5o45 (PD-L1) tractable; 9xmm (avb6) needs 2-chain receptor + truncation
DRY_RUN=${DRY_RUN:-1}
MARKET=${MARKET:-ondemand}
DISK_GB=${DISK_GB:-150}
MAX_RUNTIME=${MAX_RUNTIME:-3h}
[[ "$MARKET" = spot || "$MARKET" = ondemand ]] || { echo "FATAL: MARKET must be spot|ondemand"; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
RUNID=cofold-v2-${TARGET}-$(date -u +%Y%m%dT%H%M%SZ)
S3RUN=s3://$BUCKET/cyclic_peptide/runs/$RUNID

# ---- build the cofold input (receptor seq + peptide list) from the staged plan ----
PGROUP=$([ "$TARGET" = 9xmm ] && echo avb6 || echo pdl1)
python3 - "$TARGET" "$PGROUP" "$DRY_RUN" > /tmp/cofold_input.json <<'PY'
import json, sys
target, pgroup, dry = sys.argv[1], sys.argv[2], sys.argv[3]
plan = json.load(open("results/docking/cofold_mmgbsa_plan_v2.json"))
R = plan["receptors"][target]["chains"].get("R")
if R is None:
    sys.exit(f"FATAL: receptor {target} has no single R chain in the plan (2-chain target needs the multi-chain path)")
peps = plan["peptides"][pgroup]
if dry == "1":
    peps = peps[:1]
json.dump({"target": target, "receptor": R, "peptides": peps}, sys.stdout, indent=2)
PY
NPEP=$(python3 -c "import json;print(len(json.load(open('/tmp/cofold_input.json'))['peptides']))")
echo "[cofold] TARGET=$TARGET DRY_RUN=$DRY_RUN peptides=$NPEP"
aws s3 cp /tmp/cofold_input.json "$S3RUN/input/cofold_input.json" --only-show-errors

# ---- on-GPU driver ----
cat > /tmp/cofold_v2_driver.sh <<'DRIVER'
#!/bin/bash
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2 HOME=/root PYTHONUNBUFFERED=1
ROOT=/opt/cofold; OUT_S3=${OUT_S3:?}; TARGET=${TARGET:?}; MAX_RUNTIME=${MAX_RUNTIME:-3h}
mkdir -p "$ROOT/status" "$ROOT/w"; cd "$ROOT/w"
exec > >(tee -a "$ROOT/status/cofold.log") 2>&1
stage(){ printf '{"stage":"%s","time":"%s"}\n' "$1" "$(date -u +%FT%TZ)" > "$ROOT/status/status.json"; aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true; }
trap 'rc=$?; [ $rc -ne 0 ] && stage failed; sync; sleep 6; aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true; sleep 4; shutdown -h now; exit $rc' EXIT
systemd-run --unit=cofold-deadline --on-active="$MAX_RUNTIME" /sbin/shutdown -h now || true

stage installing_boltz
command -v aws >/dev/null 2>&1 || { apt-get update -qq && apt-get install -y -qq unzip curl && curl -fsSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o /tmp/a.zip && (cd /tmp && unzip -q -o a.zip && ./aws/install --update); }
curl -fsSL https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -o /tmp/mc.sh
bash /tmp/mc.sh -b -p /opt/mc; source /opt/mc/etc/profile.d/conda.sh
conda create -y -n boltz -c conda-forge python=3.11 numpy scipy >/dev/null 2>&1 || { echo FATAL conda; exit 1; }
conda activate boltz
pip install -q --upgrade pip
pip install -q boltz || { echo "FATAL: boltz install failed"; exit 1; }
pip install -q cuequivariance-torch || { echo "FATAL: cuequivariance-torch failed"; exit 1; }
python -c "import boltz, cuequivariance_torch; print('boltz', getattr(boltz,'__version__','?'),'cueq OK')"

aws s3 cp "$OUT_S3/input/cofold_input.json" ./input.json --only-show-errors
stage folding
python - <<'PYEOF'
import json, os, glob, shutil, subprocess
d = json.load(open("input.json")); R = d["receptor"]; T = d["target"]
os.makedirs(T, exist_ok=True)
summary = []
for it in d["peptides"]:
    pid, pep = it["id"], it["pep"]
    y = f"in_{pid}.yaml"
    with open(y, "w") as f:
        f.write("version: 1\nsequences:\n")
        f.write(f"  - protein:\n      id: R\n      sequence: {R}\n")
        f.write(f"  - protein:\n      id: P\n      sequence: {pep}\n      cyclic: true\n")
    rec = {"id": pid, "pep": pep}
    try:
        subprocess.run(["boltz","predict",y,"--out_dir",f"out_{pid}","--use_msa_server","--override"], check=True)
        cifs = (glob.glob(f"out_{pid}/**/*_model_0.cif", recursive=True)
                or glob.glob(f"out_{pid}/**/*.cif", recursive=True))
        if cifs:
            shutil.copy(sorted(cifs)[0], f"{T}/{pid}.cif"); rec["status"] = "ok"; rec["cif"] = os.path.basename(cifs[0])
            conf = glob.glob(f"out_{pid}/**/confidence_*.json", recursive=True)
            if conf: rec["confidence"] = json.load(open(sorted(conf)[0]))
        else:
            rec["status"] = "no_cif"
    except Exception as e:
        rec["status"] = "fail"; rec["error"] = str(e)[:300]
    print(pid, rec["status"])
    summary.append(rec)
json.dump({"target": T, "results": summary}, open("/opt/cofold/status/cofold_summary.json","w"), indent=2)
PYEOF
stage uploading
aws s3 sync "./$TARGET/" "$OUT_S3/complexes/$TARGET/" --only-show-errors || true
aws s3 cp "$ROOT/status/cofold_summary.json" "$OUT_S3/status/cofold_summary.json" --only-show-errors || true
stage done
DRIVER
aws s3 cp /tmp/cofold_v2_driver.sh "$S3RUN/code/cofold_v2_driver.sh" --only-show-errors

# ---- bootstrap (user-data) ----
BOOT=/tmp/cofold_bootstrap_$$.sh
cat > "$BOOT" <<EOF
#!/bin/bash
exec > /var/log/cofold-boot.log 2>&1
mkdir -p /opt/cofold/code
for i in 1 2 3 4 5; do aws s3 cp $S3RUN/code/cofold_v2_driver.sh /opt/cofold/code/driver.sh --region us-west-2 && break; sleep 10; done
chmod +x /opt/cofold/code/driver.sh
OUT_S3=$S3RUN TARGET=$TARGET MAX_RUNTIME=$MAX_RUNTIME bash /opt/cofold/code/driver.sh
EOF
UD=$(base64 < "$BOOT" | tr -d '\n')

# ---- launch (capacity ladder; same COMBO/IAM pattern as launch_refold_rerank.sh) ----
declare -a COMBO=(
  "g5.2xlarge subnet-0254e4c3634b41bfc" "g6.2xlarge subnet-0b35a6e2c1cf02dc2"
  "g5.4xlarge subnet-0254e4c3634b41bfc" "g6.4xlarge subnet-0254e4c3634b41bfc"
  "g5.4xlarge subnet-03b277a7a08d388c1" "g5.4xlarge subnet-09e4dce46682a6c60"
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
IID=""
if [ "$MARKET" = ondemand ]; then launch_one ondemand || true; else launch_one spot || launch_one ondemand || true; fi
{ [ -z "${IID:-}" ] || [ "$IID" = "None" ]; } && { echo "FATAL: no GPU capacity"; rm -f "$BOOT"; exit 1; }
rm -f "$BOOT"
echo "=============================================================="
echo "RUNID    = $RUNID  (TARGET=$TARGET DRY_RUN=$DRY_RUN peptides=$NPEP MARKET=$MARKET deadline=$MAX_RUNTIME)"
echo "INSTANCE = $IID"
echo "poll     : aws s3 cp $S3RUN/status/status.json -"
echo "summary  : aws s3 cp $S3RUN/status/cofold_summary.json -"
echo "complexes: aws s3 ls $S3RUN/complexes/$TARGET/"
echo "then MMGBSA: DESIGNS_S3=$S3RUN/complexes TARGET=$TARGET bash launch_mmgbsa_pool.sh"
echo "=============================================================="
