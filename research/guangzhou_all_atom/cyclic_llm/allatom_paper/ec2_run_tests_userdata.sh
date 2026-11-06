#!/bin/bash
# Runs allatom_paper/test_pmo_harness.py on a throwaway spot instance (owner rule: no compute on the laptop).
# Reads code from S3, writes the log to S3, always shuts down. Hard wall-clock cap 30 minutes.
B=s3://biomate-nextflow-work/cyclic_peptide/allatom_paper/harness_test
shutdown -h +30
exec > /var/log/harness_test.log 2>&1
( while true; do aws s3 cp /var/log/harness_test.log $B/boot.log --only-show-errors; sleep 20; done ) &
SYNC=$!
dnf install -y python3.11 python3.11-pip >/dev/null 2>&1
python3.11 -m pip install -q numpy scipy pytest rdkit
mkdir -p /w && cd /w
aws s3 cp $B/code/ . --recursive --only-show-errors
python3.11 -m pytest -q -p no:cacheprovider test_pmo_harness.py > /w/pytest.log 2>&1
echo "pytest rc=$?" >> /w/pytest.log
aws s3 cp /w/pytest.log $B/pytest.log --only-show-errors
kill $SYNC
aws s3 cp /var/log/harness_test.log $B/boot.log --only-show-errors
shutdown -h now
