#!/usr/bin/env python3
"""Generate EC2 user-data scripts for T2 stages (spot-safe: per-task results synced to S3 every 45 s; resumable; self-terminating). usage: make_ud.py STAGE OUT.sh"""
import sys
B = "s3://biomate-nextflow-work/cyclic_peptide/technique_sprint/t2"
CSV = "/w/data/CycPeptMPDB_Peptide_All.csv"; RUN = f"python3.11 -u run_acq.py {CSV} /w/res"; CACHE = "--cache /w/acq_cache.pkl --procs $(nproc)"
STAGES = {
 "preflight": [f"python3.11 -u test_aggregate.py > /w/res/test_aggregate.log 2>&1; echo $? > /w/res/test_aggregate.rc", "python3.11 -u test_acq.py > /w/res/test_acq.log 2>&1; echo $? > /w/res/test_acq.rc",
               f"python3.11 -u repro_audit.py {CSV} /w/res/repro.json --cache /w/acq_cache.pkl > /w/res/repro.log 2>&1; echo $? > /w/res/repro.rc"],
 "unittest": ["python3.11 -u test_acq.py > /w/res/test_acq.log 2>&1; echo $? > /w/res/test_acq.rc"],
 "dev": [f"{RUN} --arms greedy,prov --regimes A,B,L --seeds 100-104 --grid {CACHE}"],
 "evalbaseAB": [f"{RUN} --arms random,greedy,ucb,rule_phys,nn_greedy,fuse --regimes A,B --seeds 0-29 {CACHE}"],
 "evalbaseLC": [f"{RUN} --arms random,greedy,ucb,rule_phys,nn_greedy,fuse --regimes L --seeds 0-29 {CACHE}", f"{RUN} --arms random,greedy,ucb,rule_phys --regimes C --seeds 0-29 {CACHE}"],
 "evalprov": [f"aws s3 cp {B}/frozen_config.json /w/frozen_config.json --only-show-errors", f"{RUN} --arms prov,div --regimes A,B,L --seeds 0-29 --cfg /w/frozen_config.json {CACHE}", f"{RUN} --arms prov --regimes C --seeds 0-29 --cfg /w/frozen_config.json {CACHE}"],
 "controls": [f"aws s3 cp {B}/frozen_config.json /w/frozen_config.json --only-show-errors",
              f"python3.11 -u run_acq.py {CSV} /w/res/planted1 --arms random,greedy,prov --regimes A --seeds 900-904 --labels planted1 --cfg /w/frozen_config.json {CACHE}",
              f"python3.11 -u run_acq.py {CSV} /w/res/planted2 --arms random,greedy,prov --regimes A --seeds 900-904 --labels planted2 --cfg /w/frozen_config.json {CACHE}",
              f"python3.11 -u run_acq.py {CSV} /w/res/shuffle --arms random,greedy,prov --regimes A,B --seeds 2000-2009 --labels shuffle --cfg /w/frozen_config.json {CACHE}"],
}
HEAD = """#!/bin/bash
# T2 spot-safe job (stage __STAGE__); results synced to S3 continuously; resumable; self-terminating.
B=__B__
shutdown -h +400
dnf install -y python3.11 python3.11-pip python3.11-devel gcc >/dev/null 2>&1
python3.11 -m pip install -q numpy scipy scikit-learn rdkit >/dev/null 2>&1
mkdir -p /w/data /w/res /w/code/loop_retro /w/code/technique_sprint/acquisition && cd /w
aws s3 cp s3://biomate-nextflow-work/cyclic_peptide/loop_retro/data/CycPeptMPDB_Peptide_All.csv /w/data/ --only-show-errors
aws s3 cp $B/code/ /w/code/technique_sprint/acquisition/ --recursive --only-show-errors
aws s3 cp $B/loop_code/ /w/code/loop_retro/ --recursive --only-show-errors
aws s3 sync $B/res___STAGE__/ /w/res/ --only-show-errors
( while true; do aws s3 sync /w/res/ $B/res___STAGE__/ --only-show-errors --exclude "*.tmp"; aws s3 cp /w/job.log $B/logs/job___STAGE___latest.log --only-show-errors; sleep 45; done ) &
SYNCPID=$!
export OMP_NUM_THREADS=1
cd /w/code/technique_sprint/acquisition
{
"""
TAIL = """} > /w/job.log 2>&1
aws s3 sync /w/res/ $B/res___STAGE__/ --only-show-errors --exclude "*.tmp"; aws s3 cp /w/job.log $B/logs/job___STAGE___latest.log --only-show-errors
echo JOB_DONE > /w/done.flag; aws s3 cp /w/done.flag $B/flags/__STAGE___done.flag --only-show-errors
kill $SYNCPID; shutdown -h now
"""
if __name__ == "__main__":
    st = sys.argv[1]; body = "\n".join(STAGES[st]); s = (HEAD + body + "\n" + TAIL).replace("__STAGE__", st).replace("__B__", B); open(sys.argv[2], "w").write(s); print("wrote", sys.argv[2])
