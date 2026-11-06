#!/bin/bash
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2
mkdir -p /opt/guangzhou-peptide/code
trap 'shutdown -h now' ERR
aws s3 cp s3://knowledge-datasets-1759951976/cyclic_peptide/runs/pepglad-initial-20260912T215600Z/code/code.tar.gz /opt/guangzhou-peptide/code.tar.gz --only-show-errors
echo '03bfab6350ef5a891a2d2da81af3b872e09af927060d9054327726c1834c586e  /opt/guangzhou-peptide/code.tar.gz' | sha256sum -c -
tar xzf /opt/guangzhou-peptide/code.tar.gz -C /opt/guangzhou-peptide/code
export OUT_S3=s3://knowledge-datasets-1759951976/cyclic_peptide/runs/pepglad-initial-20260912T215600Z
export DEADLINE_UTC='2026-09-13 01:45:52 UTC'
bash /opt/guangzhou-peptide/code/run_pepglad_ec2.sh
