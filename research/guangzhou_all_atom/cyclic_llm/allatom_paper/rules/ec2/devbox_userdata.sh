#!/bin/bash
# U1 CPU dev box (spot, persistent; driven over SSM). run id dev2.
B=s3://biomate-nextflow-work/cyclic_peptide/allatom/u1/dev2
exec > /var/log/ud.log 2>&1; set -x
shutdown -h +180
( while true; do aws s3 cp /var/log/ud.log $B/boot.log --only-show-errors; sleep 20; done ) &
dnf install -y python3.11 python3.11-pip python3.11-devel gcc >/dev/null 2>&1
python3.11 -m pip install numpy scipy scikit-learn rdkit pytest transformers tokenizers 2>&1 | tail -2
mkdir -p /w/tok && cd /w && aws s3 cp $B/tok/ /w/tok/ --recursive --only-show-errors
echo DEVBOX_READY > /w/ready; aws s3 cp /w/ready $B/ready.flag --only-show-errors
sleep 10800
