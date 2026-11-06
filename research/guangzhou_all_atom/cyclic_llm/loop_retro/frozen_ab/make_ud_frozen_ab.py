#!/usr/bin/env python3
"""Generate the spot user-data script for the frozen aware-vs-blind experiment. usage: make_ud_frozen_ab.py OUT.sh
Design: one process per (learner, regime, 10-seed chunk) = 36 real jobs + 8 planted-control jobs, run through `xargs -P <vCPU>` (bounded concurrency, exit codes collected; no bare wait).
Every step is logged to /w/boot.log and shipped to S3 every 20 s from the first second."""
import sys
B = "s3://biomate-nextflow-work/cyclic_peptide/loop_retro"; RES = f"{B}/res_frozen_ab"
R = "/w/data/CycPeptMPDB_Peptide_All.csv"; ARMS = "--arms frozen,frozen_sub --no-curve"
jobs = []
for lrn, backend, chiral in (("aware", "gbm", 1), ("blind", "gbm", 0), ("phys", "gbm_physchem", 1)):
    for g in "ABL":
        for ch in ("0-9", "10-19", "20-29", "30-39"):
            jobs.append(f"FP_CHIRAL={chiral} python3.11 run_l7a.py {R} /w/out/real/{lrn} --backend {backend} --regimes {g} --seeds {ch} {ARMS}")
for kind in ("chiral", "flat"):
    for lrn, chiral in (("aware", 1), ("blind", 0)):
        for g in "AL":
            jobs.append(f"FP_CHIRAL={chiral} python3.11 frozen_ab/planted_run.py {kind} {R} /w/out/controls/{kind}_{lrn} --backend gbm --regimes {g} --seeds 0-9 {ARMS}")
cmds = "\n".join(f"{j} > /w/logs/j{i:02d}.log 2>&1" for i, j in enumerate(jobs))
UD = f"""#!/bin/bash
# frozen aware-vs-blind (docs/20261031_FROZEN_AWARE_VS_BLIND_PREREG.md). Spot CPU, resumable (existing task files are skipped), self-terminating.
B={B}; RES={RES}
mkdir -p /w/logs /w/data /w/code /w/out/real /w/out/controls
exec > >(tee -a /w/boot.log) 2>&1
shutdown -h +120
( while true; do aws s3 cp /w/boot.log $RES/boot.log --only-show-errors; aws s3 sync /w/out $RES/ --only-show-errors; aws s3 sync /w/logs $RES/logs/ --only-show-errors; sleep 20; done ) &
SYNC=$!
echo "[boot] install"; dnf install -y python3.11 python3.11-pip python3.11-devel gcc; python3.11 -m pip install -q numpy scipy scikit-learn rdkit
echo "[boot] code"; aws s3 cp $B/code7q/ /w/code/ --recursive --exclude atom_ckpt.pt --only-show-errors; aws s3 cp $RES/code/ /w/code/loop_retro/ --recursive --only-show-errors
aws s3 cp $B/data/CycPeptMPDB_Peptide_All.csv /w/data/ --only-show-errors
aws s3 sync $RES/real /w/out/real --only-show-errors; aws s3 sync $RES/controls /w/out/controls --only-show-errors
cd /w/code/loop_retro; export LABEL_COL=PAMPA SCRATCH=/w/data OMP_NUM_THREADS=1 PYTHONHASHSEED=0 FP_CHIRAL=1
echo "[boot] preflight"; (python3.11 test_l7a.py core; echo "core rc=$?"; python3.11 frozen_ab/test_frozen_ab.py; echo "ab rc=$?") > /w/pre.log 2>&1
aws s3 cp /w/pre.log $RES/preflight.log --only-show-errors
if [ "$(grep -c 'rc=0' /w/pre.log)" != "2" ]; then echo "[boot] PREFLIGHT FAILED"; aws s3 cp /w/boot.log $RES/PREFLIGHT_FAILED.log --only-show-errors; sleep 600; shutdown -h now; exit 3; fi
echo "[run] start $(date)"
cat > /w/jobs.txt <<'JOBS'
{cmds}
JOBS
NP=$(nproc --all)
xargs -P $NP -I{{}} bash -c '{{}}' < /w/jobs.txt; RC=$?
echo "[run] xargs rc=$RC $(date)"
aws s3 sync /w/out $RES/ --only-show-errors; aws s3 sync /w/logs $RES/logs/ --only-show-errors
if [ $RC -eq 0 ]; then echo DONE > /w/done.flag; aws s3 cp /w/done.flag $RES/done.flag --only-show-errors; else echo "FAILED rc=$RC" > /w/failed.flag; aws s3 cp /w/failed.flag $RES/failed.flag --only-show-errors; fi
aws s3 cp /w/boot.log $RES/boot.log --only-show-errors
kill $SYNC; sleep 30; shutdown -h now
"""
if __name__ == "__main__":
    open(sys.argv[1], "w").write(UD); print("wrote", sys.argv[1], "jobs", len(jobs))
