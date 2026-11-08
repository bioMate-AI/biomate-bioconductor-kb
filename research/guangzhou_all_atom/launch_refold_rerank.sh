#!/bin/bash
# =============================================================================
# launch_refold_rerank.sh — PROVISIONING launcher for the self-consistency refold+rerank stage.
#
# Pulls a finished UniMoMo cyclic generation run's saved candidate poses (results/{base,ft}),
# re-folds the top-K per target with Boltz (independent cyclic prediction), computes scRMSD, and
# re-ranks by self-consistency vs the generator's own likelihood pick -> selfconsistency_summary.json.
#
# The on-GPU work is refold_rerank_driver.sh (installs Boltz in its own venv, runs build_candidates.py
# -> selfconsistency_rerank.py). THIS script only: validates inputs, uploads code, boots ONE self-
# terminating GPU instance (on-demand default given spot scarcity; spot->on-demand ladder when
# MARKET=spot), pulls the generation outputs onto it, and runs the driver.
#
# DRY_RUN=1 (DEFAULT) = cheapest A1/A2 confirmation: ONE target, ONE label (first of LABELS). It fails
# LOUD if the candidate-pose layout (A1) or the per-candidate DockQ/likelihood schema (A2) differ from
# what build_candidates.py expects. Confirm the dry run before spending the full K x 88 x 2 folds.
#
# A1/A2 were checked read-only against the default GEN_RUN on 2026-10-04 and HOLD:
#   A1  poses at results/<label>/candidates/<target>/<k>.pdb (100/target, 0-99, 2 chains)   [HOLDS]
#   A2a per-target DockQ.individual = 100 per-candidate values                              [HOLDS]
#   A2b per-candidate likelihood = DockQ.individual_pmet (argmax(pmet) DockQ == max*, higher = pick-1);
#       build_candidates.py was updated to read individual_pmet                             [RESOLVED]
#
# Poll:   aws s3 cp $S3RUN/status/sc_status.json -
# Result: aws s3 cp $S3RUN/status/selfconsistency_summary.json -        (full run; base vs ft)
#         aws s3 cp $S3RUN/status/candidates_<label>.jsonl -            (dry run)
# =============================================================================
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2

BUCKET=knowledge-datasets-1759951976
AMI=${AMI:-ami-04f7da1c787a89267}
SG=sg-011121fdf81073ec8
KEY=biomate-trial-resume-20260912
PROFILE=AutoimmuneCorpusProfile

# ---- inputs (env-overridable) ----
GEN_RUN=${GEN_RUN:-unimomo-cyclic-ft-20261004T042753Z}   # run whose results/{base,ft} to refold
TOPK=${TOPK:-10}                                          # refold the top-K candidates/target by pmet
DRY_RUN=${DRY_RUN:-1}                                     # 1 = one target+one label (cheap A1/A2 check)
LABELS=${LABELS:-"base ft"}                               # generation labels to refold/rerank
MARKET=${MARKET:-ondemand}                                # ondemand default; set spot for spot->ondemand ladder
DISK_GB=${DISK_GB:-150}
# deadline: DRY short (one target * TOPK folds + boltz install), full generous (TOPK*88*2 folds)
if [ "$DRY_RUN" = 1 ]; then MAX_RUNTIME=${MAX_RUNTIME:-2h}; else MAX_RUNTIME=${MAX_RUNTIME:-48h}; fi

[[ "$MARKET" = spot || "$MARKET" = ondemand ]] || { echo "FATAL: MARKET must be spot or ondemand"; exit 1; }
[[ "$DRY_RUN" = 0 || "$DRY_RUN" = 1 ]] || { echo "FATAL: DRY_RUN must be 0 or 1"; exit 1; }

GEN_PFX=s3://$BUCKET/cyclic_peptide/runs/$GEN_RUN
RUNID=refold-rerank-$(date -u +%Y%m%dT%H%M%SZ)
S3RUN=s3://$BUCKET/cyclic_peptide/runs/$RUNID
HERE=$(cd "$(dirname "$0")" && pwd)

# ---- preflight: generation inputs + local code must exist ----
for label in $LABELS; do
  for f in eval_report_.jsonl candidates/; do
    aws s3 ls "$GEN_PFX/results/$label/$f" >/dev/null 2>&1 \
      || { echo "FATAL: missing generation input $GEN_PFX/results/$label/$f"; exit 1; }
  done
done
for f in refold_rerank_driver.sh build_candidates.py selfconsistency_rerank.py scrmsd.py; do
  [ -f "$HERE/$f" ] || { echo "FATAL: local code missing: $f"; exit 1; }
done

# ---- upload the code the driver needs ----
for f in refold_rerank_driver.sh build_candidates.py selfconsistency_rerank.py scrmsd.py; do
  aws s3 cp "$HERE/$f" "$S3RUN/code/$f" --only-show-errors
done
aws s3 cp "$HERE/launch_refold_rerank.sh" "$S3RUN/code/launch_refold_rerank.sh" --only-show-errors

# ---- on-instance bootstrap wrapper (adds deadline/self-terminate/sync + input pull around the driver) ----
BOOT=$(mktemp)
cat > "$BOOT" <<'BOOT_EOF'
#!/bin/bash
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2
export DEBIAN_FRONTEND=noninteractive
export PYTHONUNBUFFERED=1
ROOT=/opt/refold-run
OUT_S3=${OUT_S3:?}; GEN_PFX=${GEN_PFX:?}
TOPK=${TOPK:-10}; DRY_RUN=${DRY_RUN:-1}; LABELS=${LABELS:-"base ft"}; MAX_RUNTIME=${MAX_RUNTIME:-48h}
# match the driver's DRY collapse so we only pull what we process
if [ "$DRY_RUN" = 1 ]; then LABELS=$(echo "$LABELS" | awk '{print $1}'); fi

mkdir -p "$ROOT/status" "$ROOT/code"
exec > >(tee -a "$ROOT/status/bootstrap.log") 2>&1
sync_status(){ aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true; }
finish(){ rc=$?; trap - EXIT; [ "$rc" -ne 0 ] && printf '{"stage":"bootstrap_failed","rc":%s,"time":"%s"}\n' "$rc" "$(date -u +%FT%TZ)" > "$ROOT/status/sc_status.json"; sync_status; shutdown -h now; exit "$rc"; }
trap finish EXIT
systemctl is-active --quiet refold-deadline.timer 2>/dev/null || systemd-run --unit=refold-deadline --on-active="$MAX_RUNTIME" /sbin/shutdown -h now
(while sleep 120; do sync_status; done) &

# --- modern python (for `python3 -m venv` + Boltz) via miniforge; AMI python may be too old for Boltz ---
if [ ! -x /opt/miniforge/bin/python3 ]; then
  for i in 1 2 3 4 5; do curl -fsSL -o /tmp/miniforge.sh https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh && break; sleep 10; done
  bash /tmp/miniforge.sh -b -p /opt/miniforge
fi
export PATH=/opt/miniforge/bin:$PATH
python3 --version

# --- pull driver + extractor code ---
for f in refold_rerank_driver.sh build_candidates.py selfconsistency_rerank.py scrmsd.py; do
  aws s3 cp "$OUT_S3/code/$f" "$ROOT/code/$f" --only-show-errors
done
chmod +x "$ROOT/code/refold_rerank_driver.sh"

# --- pull generation outputs the driver refolds (RES/<label>/{eval_report_.jsonl, candidates/}) ---
RES="$ROOT/results"
for label in $LABELS; do
  mkdir -p "$RES/$label/candidates"
  aws s3 cp "$GEN_PFX/results/$label/eval_report_.jsonl" "$RES/$label/eval_report_.jsonl" --only-show-errors
  if [ "$DRY_RUN" = 1 ]; then
    # build_candidates.py uses recs[:1] -> only the first target's poses are needed
    TID=$(python3 -c "import json;print(json.loads(open('$RES/$label/eval_report_.jsonl').readline())['id'])")
    echo "DRY: pulling only first target '$TID' candidates for label '$label'"
    aws s3 sync "$GEN_PFX/results/$label/candidates/$TID" "$RES/$label/candidates/$TID" --only-show-errors
  else
    aws s3 sync "$GEN_PFX/results/$label/candidates" "$RES/$label/candidates" --only-show-errors
  fi
done

# --- run the refold+rerank driver (installs Boltz in its own venv, does the folds) ---
ROOT="$ROOT" RES="$RES" OUT_S3="$OUT_S3" TOPK="$TOPK" DRY_RUN="$DRY_RUN" LABELS="$LABELS" \
  HERE="$ROOT/code" bash "$ROOT/code/refold_rerank_driver.sh"
sync_status
BOOT_EOF

aws s3 cp "$BOOT" "$S3RUN/code/bootstrap.sh" --only-show-errors

# ---- user-data: pull + exec the bootstrap wrapper with env ----
UD=$(cat <<EOF | base64
#!/bin/bash
exec > /var/log/refold-boot.log 2>&1
mkdir -p /opt/refold-run
for i in 1 2 3 4 5; do aws s3 cp $S3RUN/code/bootstrap.sh /opt/refold-run/bootstrap.sh --region us-west-2 && break; sleep 10; done
chmod +x /opt/refold-run/bootstrap.sh
OUT_S3=$S3RUN GEN_PFX=$GEN_PFX TOPK=$TOPK DRY_RUN=$DRY_RUN LABELS="$LABELS" MAX_RUNTIME=$MAX_RUNTIME \\
  bash /opt/refold-run/bootstrap.sh
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
IID=""
if [ "$MARKET" = ondemand ]; then
  launch_one ondemand || true
else
  launch_one spot || launch_one ondemand || true
fi
{ [ -z "${IID:-}" ] || [ "$IID" = "None" ]; } && { echo "FATAL: no GPU capacity"; rm -f "$BOOT"; exit 1; }
rm -f "$BOOT"
echo "=============================================================="
echo "RUNID    = $RUNID   (DRY_RUN=$DRY_RUN  TOPK=$TOPK  LABELS='$LABELS'  MARKET=$MARKET  deadline=$MAX_RUNTIME)"
echo "GEN_RUN  = $GEN_RUN"
echo "INSTANCE = $IID"
echo "poll     : aws s3 cp $S3RUN/status/sc_status.json -"
if [ "$DRY_RUN" = 1 ]; then
  echo "result   : aws s3 cp $S3RUN/status/candidates_<label>.jsonl -   (confirm A1/A2 before full run)"
else
  echo "result   : aws s3 cp $S3RUN/status/selfconsistency_summary.json -   (base vs ft)"
fi
echo "=============================================================="
