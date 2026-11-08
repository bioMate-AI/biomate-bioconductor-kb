#!/bin/bash
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2
mkdir -p /opt/guangzhou-peptide/code
trap 'shutdown -h now' ERR
aws s3 cp s3://knowledge-datasets-1759951976/cyclic_peptide/runs/pepglad-spot-20260912T221500Z/code/code.tar.gz /opt/guangzhou-peptide/code.tar.gz --only-show-errors
echo 'd733acbbf92bfa4d32325ab4a7708ad8c0ef7fd5a249e0403c94bee7c699cbf5  /opt/guangzhou-peptide/code.tar.gz' | sha256sum -c -
tar xzf /opt/guangzhou-peptide/code.tar.gz -C /opt/guangzhou-peptide/code
export OUT_S3=s3://knowledge-datasets-1759951976/cyclic_peptide/runs/pepglad-spot-20260912T221500Z
export DEADLINE_UTC='2026-09-13 01:45:52 UTC'
export RESUME_TRAINING_S3=s3://knowledge-datasets-1759951976/cyclic_peptide/runs/pepglad-initial-20260912T215600Z
bash /opt/guangzhou-peptide/code/run_pepglad_ec2.sh
