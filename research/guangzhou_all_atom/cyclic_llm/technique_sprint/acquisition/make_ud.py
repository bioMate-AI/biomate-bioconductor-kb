#!/usr/bin/env python3
"""Generate EC2 user-data scripts for T2 stages (spot-safe: per-task results synced to S3 every 45 s; resumable; self-terminating). usage: make_ud.py STAGE OUT.sh"""
import sys
B = "s3://biomate-nextflow-work/cyclic_peptide/technique_sprint/t2"
CSV = "/w/data/CycPeptMPDB_Peptide_All.csv"; RUN = f"python3.11 -u run_acq.py {CSV} /w/res"; CACHE = "--cache /w/acq_cache.pkl --procs $(nproc --all)"
STAGES = {
 "preflight2": ["python3.11 -u test_aggregate.py > /w/res/test_aggregate.log 2>&1; echo $? > /w/res/test_aggregate.rc", "python3.11 -u test_a2.py > /w/res/test_a2.log 2>&1; echo $? > /w/res/test_a2.rc",
                "python3.11 -u test_acq.py > /w/res/test_acq.log 2>&1; echo $? > /w/res/test_acq.rc",
                f"python3.11 -u repro_audit.py {CSV} /w/res/repro.json --cache /w/acq_cache.pkl > /w/res/repro.log 2>&1; echo $? > /w/res/repro.rc",
                f"python3.11 -u leakage_report.py {CSV} /w/res/leakage.json --cache /w/acq_cache.pkl --seeds 10 > /w/res/leakage.log 2>&1; echo $? > /w/res/leakage.rc"],
 # PRIMARY: causal standardisation (amendment A2); development grid on seeds 100-104, config selected under the primary variant
 "devc": [f"{RUN} --arms greedy,prov --regimes A,B,L --seeds 100-102 --grid6 --ymode causal {CACHE}"],
 "evalc": [f"{RUN} --arms random,rule_phys,greedy,ucb,nn_greedy --regimes A,B,B2,L --seeds 0-14 --ymode causal {CACHE}"],
 "evalcC2": [f"{RUN} --arms random,rule_phys,greedy --regimes C2 --seeds 0-14 --ymode causal {CACHE}"],
 "evalcprov": [f"aws s3 cp {B}/frozen_config.json /w/frozen_config.json --only-show-errors", f"{RUN} --arms prov,div --regimes A,B,B2,L --seeds 0-14 --cfg /w/frozen_config.json --ymode causal {CACHE}"],
 "evalcprovC2": [f"aws s3 cp {B}/frozen_config.json /w/frozen_config.json --only-show-errors", f"{RUN} --arms prov --regimes C2 --seeds 0-14 --cfg /w/frozen_config.json --ymode causal {CACHE}"],
 # LABELLED CONTROL: transductive (L5-style) standardisation; seeded with the finished transductive result files
 "evalt": [f"{RUN} --arms random,greedy,ucb,rule_phys --regimes A,B,L --seeds 0-7 --ymode trans {CACHE}"],
 "evaltprov": [f"aws s3 cp {B}/frozen_config.json /w/frozen_config.json --only-show-errors", f"{RUN} --arms prov --regimes A,B,L --seeds 0-7 --cfg /w/frozen_config.json --ymode trans {CACHE}"],
 "controls": [f"aws s3 cp {B}/frozen_config.json /w/frozen_config.json --only-show-errors",
              f"python3.11 -u run_acq.py {CSV} /w/res/planted1 --arms random,greedy,prov --regimes A --seeds 900-902 --labels planted1 --cfg /w/frozen_config.json {CACHE}",
              f"python3.11 -u run_acq.py {CSV} /w/res/planted2 --arms random,greedy,prov --regimes A --seeds 900-902 --labels planted2 --cfg /w/frozen_config.json {CACHE}",
              f"python3.11 -u run_acq.py {CSV} /w/res/shuffle --arms random,greedy,prov --regimes A --seeds 2000-2003 --labels shuffle --cfg /w/frozen_config.json {CACHE}"],
}
RESMAP = {"evalcC2": "evalc", "evalcprov": "evalc", "evalcprovC2": "evalc", "evaltprov": "evalt"}      # stages that write into another stage's S3 prefix
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
aws s3 sync $B/res___RES__/ /w/res/ --only-show-errors
( while true; do aws s3 sync /w/res/ $B/res___RES__/ --only-show-errors --exclude "*.tmp"; aws s3 cp /w/job.log $B/logs/job___STAGE___latest.log --only-show-errors; sleep 45; done ) &
SYNCPID=$!
export OMP_NUM_THREADS=1
export PYTHONHASHSEED=0
cd /w/code/technique_sprint/acquisition
{
"""
TAIL = """} > /w/job.log 2>&1
aws s3 sync /w/res/ $B/res___RES__/ --only-show-errors --exclude "*.tmp"; aws s3 cp /w/job.log $B/logs/job___STAGE___latest.log --only-show-errors
echo JOB_DONE > /w/done.flag; aws s3 cp /w/done.flag $B/flags/__STAGE___done.flag --only-show-errors
kill $SYNCPID; shutdown -h now
"""
if __name__ == "__main__":
    # usage: make_ud.py STAGE OUT.sh [SEEDS REGIMES TAG]   (optional overrides split a stage across instances; results go to the base stage's S3 prefix, flag/log use TAG)
    st = sys.argv[1]; tag = st
    # comma-joined stages run sequentially on one instance; they must share one S3 result prefix
    parts = st.split(","); assert len({RESMAP.get(x, x) for x in parts}) == 1, "stages write to different S3 prefixes"
    body = "\n".join(l for x in parts for l in STAGES[x]); st = parts[0]
    if len(sys.argv) >= 6:
        seeds, regs, tag = sys.argv[3], sys.argv[4], sys.argv[5]
        import re; body = re.sub(r"--seeds \S+", f"--seeds {seeds}", body); body = re.sub(r"--regimes \S+", f"--regimes {regs}", body)
    s = (HEAD + body + "\n" + TAIL).replace("__RES__", RESMAP.get(st, st)).replace("__STAGE__", tag).replace("__B__", B); open(sys.argv[2], "w").write(s); print("wrote", sys.argv[2], tag)
