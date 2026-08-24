#!/bin/bash
exec > /var/log/omtps-build.log 2>&1
set -x
shutdown -h +150 &   # dead-man failsafe
R=us-west-2; B=biomate-nextflow-work; ECR=399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/om-tps:v1
S3=s3://$B/builds/omtps/latest
put(){ aws s3 cp "$1" $S3/"$2" --region $R || true; }
st(){ echo "$1 $(date -u)" > /root/STATUS; put /root/STATUS STATUS; }
st STARTED
dnf install -y docker git >/dev/null 2>&1; systemctl start docker
mkdir -p /root/ctx && cd /root/ctx
git clone --depth 1 https://github.com/ASK-Berkeley/OM-TPS.git 2>&1 | tail -3
aws s3 cp s3://$B/builds/omtps-ctx/Dockerfile ./Dockerfile --region $R
aws s3 cp s3://$B/builds/omtps-ctx/density_guidance.py ./OM-TPS/two-for-one-diffusion/density_guidance.py --region $R
st BUILDING
docker build -t om-tps:v1 -f Dockerfile . 2>&1 | tee /root/build.log | tail -5
RC=${PIPESTATUS[0]}; put /root/build.log build.log
if [ "$RC" != "0" ]; then st "BUILD_FAILED_rc=$RC"; put /var/log/omtps-build.log full.log; sleep 30; shutdown -h now; fi
st PUSHING
aws ecr get-login-password --region $R | docker login --username AWS --password-stdin 399683337364.dkr.ecr.us-west-2.amazonaws.com
docker tag om-tps:v1 $ECR; docker push $ECR 2>&1 | tee /root/push.log | tail -5
RC=${PIPESTATUS[0]}; put /root/push.log push.log
[ "$RC" = "0" ] && st SUCCESS || st "PUSH_FAILED_rc=$RC"
put /var/log/omtps-build.log full.log
sleep 20; shutdown -h now
