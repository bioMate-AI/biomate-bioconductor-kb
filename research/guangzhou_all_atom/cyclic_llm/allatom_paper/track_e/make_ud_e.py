#!/usr/bin/env python3
"""EC2 user-data generator for Track E (stage-0). usage: make_ud_e.py STAGE OUT.sh [--cap-min N] [--itype ...]
STAGE: prep  (pytest + source groups + smoke)      -> prefix .../allatom/E/<run>/prep
       main  (prep checks, then tune -> eval -> controls; sequential, no bare wait) -> prefix .../allatom/E/<run>/main
One writer per S3 prefix. Spot only; the instance shuts itself down at the end or at the wall-clock cap."""
import argparse, sys
B = "s3://biomate-nextflow-work/cyclic_peptide/allatom/E"
HEAD = """#!/bin/bash
P=__B__/__RUN__/__STAGE__
exec > /var/log/ud.log 2>&1; set -x
shutdown -h +__CAP__
( while true; do aws s3 cp /var/log/ud.log $P/boot.log --only-show-errors; sleep 20; done ) &
BOOT=$!
dnf install -y python3.11 python3.11-pip python3.11-devel gcc >/dev/null 2>&1
python3.11 -m pip install numpy scipy scikit-learn rdkit pandas pytest selfies 2>&1 | tail -2
mkdir -p /w/out /w/code && cd /w
aws s3 cp __B__/__RUN__/code.tgz /w/code.tgz --only-show-errors && tar xzf /w/code.tgz -C /w/code
export ANN_CSV=/w/code/cyclic_llm/stratification/data/annotations.csv.gz PYTHONHASHSEED=0 OMP_NUM_THREADS=1
cd /w/code/cyclic_llm/allatom_paper
( while true; do aws s3 sync /w/out $P/out --only-show-errors; sleep 30; done ) &
SYNC=$!
python3.11 -m pytest -q -p no:cacheprovider test_pmo_harness.py > /w/out/pytest.log 2>&1; echo "pytest rc=$?" >> /w/out/pytest.log
python3.11 track_e/make_groups.py > /w/out/groups.log 2>&1; echo "groups rc=$?" >> /w/out/groups.log; cp track_e/source_groups.json /w/out/ 2>/dev/null
python3.11 track_e/run_stage0.py smoke /w/out/smoke_run --workers 8 --n-ref 5 > /w/out/smoke.log 2>&1; SMOKE=$?; echo "smoke rc=$SMOKE" >> /w/out/smoke.log
"""
MAIN = """if [ $SMOKE -eq 0 ]; then
  python3.11 track_e/run_stage0.py tune /w/out/run --budget 1000 --seeds 100-102 > /w/out/tune.log 2>&1; echo "tune rc=$?" >> /w/out/tune.log
  python3.11 track_e/run_stage0.py eval /w/out/run --budget 1000 --seeds 0-9 > /w/out/eval.log 2>&1; echo "eval rc=$?" >> /w/out/eval.log
  python3.11 track_e/run_stage0.py controls /w/out/run --budget 1000 --seeds 0-4 > /w/out/controls.log 2>&1; echo "controls rc=$?" >> /w/out/controls.log
else echo SMOKE_FAILED > /w/out/SMOKE_FAILED; fi
"""
TAIL = """echo DONE > /w/out/done.flag
aws s3 sync /w/out $P/out --only-show-errors
kill $SYNC $BOOT
aws s3 cp /var/log/ud.log $P/boot.log --only-show-errors
shutdown -h now
"""
if __name__ == "__main__":
    ap = argparse.ArgumentParser(); ap.add_argument("stage", choices=["prep", "main"]); ap.add_argument("out"); ap.add_argument("--run", default="r1"); ap.add_argument("--cap-min", type=int, default=240)
    a = ap.parse_args()
    s = HEAD + (MAIN if a.stage == "main" else "") + TAIL
    s = s.replace("__B__", B).replace("__RUN__", a.run).replace("__STAGE__", a.stage).replace("__CAP__", str(a.cap_min))
    open(a.out, "w").write(s); print("wrote", a.out)
