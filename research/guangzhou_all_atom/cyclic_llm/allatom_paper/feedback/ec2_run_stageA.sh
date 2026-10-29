#!/bin/bash
# U2/U3 stage A on a throwaway spot instance: unit tests + environment validity (NO monitor evaluation). Owner rule: no laptop compute.
B=s3://biomate-nextflow-work/cyclic_peptide/allatom/u23/stageA
shutdown -h +45
exec > /var/log/u23A.log 2>&1
( while true; do aws s3 cp /var/log/u23A.log $B/boot.log --only-show-errors; sleep 20; done ) &
SYNC=$!
dnf install -y python3.11 python3.11-pip >/dev/null 2>&1
python3.11 -m pip install -q numpy scipy pytest
mkdir -p /w/allatom_paper && cd /w
aws s3 cp $B/code.tgz . --only-show-errors && tar xzf code.tgz -C /w
cd /w/allatom_paper
python3.11 -m pytest -q -p no:cacheprovider feedback/test_preference_updater.py feedback/test_stop_monitor.py > /w/pytest.log 2>&1
echo "pytest rc=$?" >> /w/pytest.log
aws s3 cp /w/pytest.log $B/pytest.log --only-show-errors
python3.11 -m feedback.sim_u2 validity /w/validity.json > /w/validity.log 2>&1
echo "validity rc=$?" >> /w/validity.log
aws s3 cp /w/validity.log $B/validity.log --only-show-errors
aws s3 cp /w/validity.json $B/validity.json --only-show-errors
kill $SYNC
aws s3 cp /var/log/u23A.log $B/boot.log --only-show-errors
shutdown -h now
