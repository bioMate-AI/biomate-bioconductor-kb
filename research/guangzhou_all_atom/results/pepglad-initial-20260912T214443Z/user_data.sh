#!/bin/bash
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2
mkdir -p /opt/guangzhou-peptide/code
trap 'shutdown -h now' ERR
aws s3 cp s3://knowledge-datasets-1759951976/cyclic_peptide/runs/pepglad-initial-20260912T214443Z/code/code.tar.gz /opt/guangzhou-peptide/code.tar.gz --only-show-errors
echo '25568b03ac3edcc089401dc6cb4c2c3bd69fac4ff150b69ab6f0011ee21820fd  /opt/guangzhou-peptide/code.tar.gz' | sha256sum -c -
tar xzf /opt/guangzhou-peptide/code.tar.gz -C /opt/guangzhou-peptide/code
export OUT_S3=s3://knowledge-datasets-1759951976/cyclic_peptide/runs/pepglad-initial-20260912T214443Z
bash /opt/guangzhou-peptide/code/run_pepglad_ec2.sh
