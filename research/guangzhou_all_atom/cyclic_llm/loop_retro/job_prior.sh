#!/bin/bash
# Spot-safe L2 job: per-task results synced to S3 continuously; resumable.
B=s3://biomate-nextflow-work/cyclic_peptide/loop_retro
shutdown -h +240
dnf install -y python3.11 python3.11-pip python3.11-devel gcc >/dev/null 2>&1
python3.11 -m pip install -q numpy scipy scikit-learn rdkit >/dev/null 2>&1
mkdir -p /w/data /w/code /w/res3 && cd /w/code
aws s3 cp $B/data/CycPeptMPDB_Peptide_All.csv /w/data/ --only-show-errors
aws s3 cp $B/code4/ . --recursive --only-show-errors
aws s3 sync $B/res3/ /w/res3/ --only-show-errors
( while true; do aws s3 sync /w/res3/ $B/res3/ --only-show-errors; aws s3 cp /w/job.log $B/logs/job_res3_latest.log --only-show-errors; sleep 45; done ) &
SYNCPID=$!
export OMP_NUM_THREADS=1
python3.11 run_loop_prior.py /w/data/CycPeptMPDB_Peptide_All.csv /w/res3 30 > /w/job.log 2>&1
aws s3 sync /w/res3/ $B/res3/ --only-show-errors; aws s3 cp /w/job.log $B/logs/job_res3_latest.log --only-show-errors
echo JOB_DONE > /w/done.flag; aws s3 cp /w/done.flag $B/res3_done.flag --only-show-errors
kill $SYNCPID; shutdown -h now
