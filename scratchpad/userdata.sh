#!/bin/bash
# dead-man's switch FIRST: hard cap 3h regardless of what happens below (cost guard)
( sleep 10800; shutdown -h now ) &
exec > /var/log/bench-userdata.log 2>&1
set -x
REGION=us-west-2
S3=s3://biomate-nextflow-work/proteomics_speed_recall_20260929

# tools
dnf install -y docker time tar gzip >/dev/null 2>&1 || yum install -y docker time tar gzip
systemctl enable --now docker
usermod -aG docker ec2-user 2>/dev/null || true

# fetch + run the driver
mkdir -p /mnt/bench && cd /mnt/bench
for i in 1 2 3 4 5; do
  aws s3 cp $S3/code/run_speed_recall_benchmark.sh ./run.sh --region $REGION && break
  sleep 10
done
chmod +x run.sh
bash ./run.sh
RC=$?
aws s3 cp /var/log/bench-userdata.log $S3/results/userdata.log --region $REGION || true
echo "driver exit=$RC — self-terminating"
# self-terminate the spot instance (interruption-safe; stream already on S3)
shutdown -h now
