#!/bin/bash
# serve_sft_gold_standing.sh — stand up a PERSISTENT (on-demand, NOT spot) vLLM
# OpenAI-compatible endpoint serving base Qwen3.5-9B + the SFT-from-gold LoRA
# adapter (model name "sft_gold"), locked to the BioMate dev backend only, with
# an idle auto-stop safeguard so it cannot silently burn money.
#
# DEV ONLY. Reversible: the dev mixture routes to this endpoint only when the
# BIOMATE_SFT_GOLD_ENABLED flag is set on the dev Galaxy container (default OFF).
#
# Topology parity: this is the same base + R16-LoRA topology the eval used
# (build_eval_vllm_v8.sh: `vllm serve <base> --enable-lora --lora-modules ...
# --max-lora-rank 16`). The certified gold numbers came from the transformers
# text-backbone shim (harness_shim.py); vLLM serves the full multimodal
# Qwen3_5ForConditionalGeneration and applies the same LoRA — run smoke_sft_gold.py
# after boot to confirm served behavior tracks the evaluated behavior.
#
# SIZING: the base resolves to a MULTIMODAL Qwen3_5ForConditionalGeneration
# (heavier than a text-only 9B). serve_eval_routing.sh documents it needs a 48GB
# L40S (g6e), NOT the 24GB L4 g6.2xlarge. Default here is g6e.xlarge (1x L40S 48GB).
#
#   bash serve_sft_gold_standing.sh            # launch with safe defaults
#   IDLE_MINUTES=30 MAX_HOURS=8 bash serve_sft_gold_standing.sh
#
set -euo pipefail

REGION=${REGION:-us-west-2}
AMI=${AMI:-ami-04f7da1c787a89267}                      # DL Base GPU AMI (us-west-2)
INSTANCE_TYPE=${INSTANCE_TYPE:-g6e.xlarge}             # 1x L40S 48GB — fits the multimodal 9B + LoRA
PROFILE=${PROFILE:-biomate-core-trial-20260912}        # IAM profile with S3 read for the adapter
SUBNET=${SUBNET:-subnet-0254e4c3634b41bfc}             # us-west-2c, VPC vpc-00059887828237f1f (same VPC as dev)
VPC=${VPC:-vpc-00059887828237f1f}
DEV_BACKEND_SG=${DEV_BACKEND_SG:-sg-0b2188a4d48d989b8} # biomate-sg (dev backend) — the ONLY allowed ingress
PORT=${PORT:-8000}
IDLE_MINUTES=${IDLE_MINUTES:-60}                       # auto-stop after this many minutes with no completed requests
MAX_HOURS=${MAX_HOURS:-12}                             # hard backstop: stop no matter what after this many hours
BASE_HF=${BASE_HF:-Qwen/Qwen3.5-9B}
ADAPTER_S3=${ADAPTER_S3:-s3://biomate-models-399683337364/biomate-core-local-trial/20260912/serving/sft_gold_9b_20261006/}
LOG_S3=${LOG_S3:-s3://biomate-models-399683337364/biomate-core-local-trial/20260912/serving/standing_logs}

# ---- 1. Dedicated security group: inbound PORT from the dev backend SG ONLY ----
SG_NAME=${SG_NAME:-biomate-sft-gold-serve}
SG=$(aws ec2 describe-security-groups --region "$REGION" \
      --filters "Name=group-name,Values=$SG_NAME" "Name=vpc-id,Values=$VPC" \
      --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || echo "None")
if [ "$SG" = "None" ] || [ -z "$SG" ]; then
  echo "[sg] creating $SG_NAME in $VPC"
  SG=$(aws ec2 create-security-group --region "$REGION" --group-name "$SG_NAME" \
        --description "vLLM sft_gold endpoint - dev backend ingress only" \
        --vpc-id "$VPC" --query 'GroupId' --output text)
fi
# Idempotent: allow PORT from the dev backend SG as source (private, intra-VPC). No public ingress.
aws ec2 authorize-security-group-ingress --region "$REGION" --group-id "$SG" \
  --ip-permissions "IpProtocol=tcp,FromPort=$PORT,ToPort=$PORT,UserIdGroupPairs=[{GroupId=$DEV_BACKEND_SG,Description='dev backend only'}]" \
  2>/dev/null || echo "[sg] ingress rule already present"
echo "[sg] $SG allows tcp/$PORT from $DEV_BACKEND_SG only"

# ---- 2. User-data: install vLLM, pull base+adapter, serve, watchdog ----
USERDATA=$(cat <<EOF | base64
#!/bin/bash
exec > /var/log/ud.log 2>&1
set -x
PORT=$PORT; IDLE_MINUTES=$IDLE_MINUTES; MAX_HOURS=$MAX_HOURS
BASE_HF="$BASE_HF"; ADAPTER_S3="$ADAPTER_S3"; LOG_S3="$LOG_S3"
SCRATCH=/opt/dlami/nvme; mkdir -p \$SCRATCH/base \$SCRATCH/sft_gold
( while true; do aws s3 cp /var/log/ud.log \$LOG_S3/boot.log --quiet 2>/dev/null; sleep 30; done ) &

# 2a. deps
python3 -m pip install -q --upgrade pip
python3 -m pip install -q vllm openai "huggingface_hub>=0.25" || { echo "VLLM_INSTALL_FAILED"; exit 10; }

# 2b. weights
python3 -c "from huggingface_hub import snapshot_download; snapshot_download('\$BASE_HF', local_dir='\$SCRATCH/base')" || { echo "BASE_DL_FAILED"; exit 11; }
aws s3 cp --recursive "\$ADAPTER_S3" \$SCRATCH/sft_gold/ || { echo "ADAPTER_DL_FAILED"; exit 12; }

# 2c. serve under systemd so it restarts on crash and survives logout.
cat > /etc/systemd/system/sftgold.service <<UNIT
[Unit]
Description=vLLM sft_gold endpoint
After=network-online.target
[Service]
ExecStart=/usr/bin/env vllm serve \$SCRATCH/base --served-model-name Qwen/Qwen3.5-9B \\
  --enable-lora --lora-modules sft_gold=\$SCRATCH/sft_gold \\
  --max-lora-rank 16 --dtype bfloat16 --max-model-len 4096 \\
  --gpu-memory-utilization 0.9 --host 0.0.0.0 --port \$PORT
Restart=always
RestartSec=10
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now sftgold.service

# 2d. wait for health, then publish the private endpoint URL to S3 for operator pickup
for i in \$(seq 1 120); do curl -sf localhost:\$PORT/health >/dev/null 2>&1 && break; sleep 10; done
PRIV_IP=\$(ec2metadata --local-ipv4 2>/dev/null || curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
echo "http://\$PRIV_IP:\$PORT/v1" > /tmp/endpoint.txt
aws s3 cp /tmp/endpoint.txt \$LOG_S3/endpoint.txt --quiet || true
echo "ENDPOINT http://\$PRIV_IP:\$PORT/v1"

# 2e. auto-stop watchdog: stop (NOT terminate) when idle or past the hard cap.
# shutdown-behavior=stop means `shutdown -h now` STOPS the instance with NO IAM
# API perms required; EBS persists so a later restart is instant.
cat > /usr/local/bin/sftgold_watchdog.sh <<'WD'
#!/bin/bash
PORT=__PORT__; IDLE_MINUTES=__IDLE__; MAX_HOURS=__MAX__
BOOT=\$(date +%s); LAST_ACTIVE=\$BOOT; PREV=-1
reqcount() { curl -s localhost:\$PORT/metrics 2>/dev/null | awk '/vllm:e2e_request_latency_seconds_count/{s+=\$2} END{print s+0}'; }
while true; do
  sleep 60
  NOW=\$(date +%s)
  # hard cap
  if [ \$(( (NOW-BOOT)/3600 )) -ge \$MAX_HOURS ]; then echo "watchdog: MAX_HOURS cap -> stop"; shutdown -h now; fi
  CUR=\$(reqcount)
  if [ "\$CUR" != "\$PREV" ]; then LAST_ACTIVE=\$NOW; PREV=\$CUR; fi
  if [ \$(( (NOW-LAST_ACTIVE)/60 )) -ge \$IDLE_MINUTES ]; then echo "watchdog: idle \$IDLE_MINUTES min -> stop"; shutdown -h now; fi
done
WD
sed -i "s/__PORT__/\$PORT/; s/__IDLE__/\$IDLE_MINUTES/; s/__MAX__/\$MAX_HOURS/" /usr/local/bin/sftgold_watchdog.sh
chmod +x /usr/local/bin/sftgold_watchdog.sh
cat > /etc/systemd/system/sftgold-watchdog.service <<UNIT
[Unit]
Description=sft_gold idle auto-stop watchdog
[Service]
ExecStart=/usr/local/bin/sftgold_watchdog.sh
Restart=always
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now sftgold-watchdog.service
echo "SFTGOLD_SERVE_READY"
EOF
)

# ---- 3. Launch: on-demand, persistent (stop-on-shutdown, NOT terminate) ----
echo "Launching $INSTANCE_TYPE on-demand in $REGION (subnet $SUBNET, sg $SG)"
IID=$(aws ec2 run-instances --region "$REGION" \
  --image-id "$AMI" --instance-type "$INSTANCE_TYPE" \
  --subnet-id "$SUBNET" --security-group-ids "$SG" \
  --iam-instance-profile "Name=$PROFILE" \
  --block-device-mappings 'DeviceName=/dev/sda1,Ebs={VolumeSize=300,VolumeType=gp3}' \
  --instance-initiated-shutdown-behavior stop \
  --user-data "$USERDATA" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=biomate-sft-gold-serve},{Key=purpose,Value=onprem-9b-sft-gold-serving}]" \
  --query 'Instances[0].InstanceId' --output text)

echo "INSTANCE=$IID"
echo "boot log : $LOG_S3/boot.log"
echo "endpoint : $LOG_S3/endpoint.txt  (written once vLLM is healthy; grep ENDPOINT in boot.log)"
echo "hourly   : ~\$1.86/h on-demand (g6e.xlarge, us-west-2); auto-stops after ${IDLE_MINUTES}m idle / ${MAX_HOURS}h hard cap"
echo "to STOP now : aws ec2 stop-instances --region $REGION --instance-ids $IID"
echo "to DELETE   : aws ec2 terminate-instances --region $REGION --instance-ids $IID"
