#!/bin/bash
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2
mkdir -p /opt/guangzhou-peptide/code
trap 'shutdown -h now' ERR
aws s3 cp s3://knowledge-datasets-1759951976/cyclic_peptide/runs/pepglad-spot-20260912T221107Z/code/code.tar.gz /opt/guangzhou-peptide/code.tar.gz --only-show-errors
echo '873197581aef1f307d2ab7fd22faa365fc2617f01be0941bb371b2a67b866c5e  /opt/guangzhou-peptide/code.tar.gz' | sha256sum -c -
tar xzf /opt/guangzhou-peptide/code.tar.gz -C /opt/guangzhou-peptide/code
export OUT_S3=s3://knowledge-datasets-1759951976/cyclic_peptide/runs/pepglad-spot-20260912T221107Z
export DEADLINE_UTC='2026-09-13 01:45:52 UTC'
export RESUME_TRAINING_S3=s3://knowledge-datasets-1759951976/cyclic_peptide/runs/pepglad-initial-20260912T215600Z
bash /opt/guangzhou-peptide/code/run_pepglad_ec2.sh
