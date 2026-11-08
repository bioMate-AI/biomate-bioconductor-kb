#!/bin/bash
# L7q resume (spot reclaimed the first instance): same grid/seeds, resumable from S3. Determinism check already passed (seeds 0-1, regime L, PYTHONHASHSEED 1 vs 2). Explicit PID waits only.
B=s3://biomate-nextflow-work/cyclic_peptide/loop_retro
shutdown -h +300
dnf install -y python3.11 python3.11-pip python3.11-devel gcc >/dev/null 2>&1
python3.11 -m pip install -q numpy scipy scikit-learn rdkit >/dev/null 2>&1
mkdir -p /w/data /w/code /w/o_aware /w/o_blind /w/o_phys /w/o_conf && cd /w/code
aws s3 cp $B/code7q/ . --recursive --exclude "atom_ckpt.pt" --only-show-errors
aws s3 cp $B/data/CycPeptMPDB_Peptide_All.csv /w/data/ --only-show-errors
M=(aware:o_aware blind:o_blind phys:o_phys confirm:o_conf)
for m in "${M[@]}"; do v=${m%%:*}; d=${m##*:}; aws s3 sync $B/res7q_gbm_$v/ /w/$d/ --exclude "*.log" --exclude "*.flag" --exclude "preflight.log" --exclude "det_check.txt" --only-show-errors; done
cd loop_retro; export LABEL_COL=PAMPA SCRATCH=/w/data OMP_NUM_THREADS=2 FP_CHIRAL=1
python3.11 test_l7a.py core > /w/pre.log 2>&1; echo "core rc=$?" >> /w/pre.log; aws s3 cp /w/pre.log $B/res7q_gbm_aware/preflight2.log --only-show-errors
if ! grep -q "core rc=0" /w/pre.log; then aws s3 cp /w/pre.log $B/res7q_gbm_aware/PREFLIGHT_FAILED.log --only-show-errors; shutdown -h now; exit 3; fi
( while true; do for m in "${M[@]}"; do v=${m%%:*}; d=${m##*:}; aws s3 sync /w/$d $B/res7q_gbm_$v/ --only-show-errors; done; for f in /w/job_*.log; do aws s3 cp $f $B/logs/ --only-show-errors; done; sleep 45; done ) &
SYNC=$!
KARMS="loop_sub,loop_kphys_sub,loop_kshuf_sub"; R=/w/data/CycPeptMPDB_Peptide_All.csv; PIDS=()
for seeds in 0-1 2-3 4-5 6-7 8-9; do
  FP_CHIRAL=1 python3.11 run_l7a.py $R /w/o_aware --backend gbm --regimes ABL --seeds $seeds --arms $KARMS --no-curve > /w/job_qa_$seeds.log 2>&1 & PIDS+=($!)
  FP_CHIRAL=0 python3.11 run_l7a.py $R /w/o_blind --backend gbm --regimes ABL --seeds $seeds --arms $KARMS --no-curve > /w/job_qb_$seeds.log 2>&1 & PIDS+=($!)
  python3.11 run_l7a.py $R /w/o_phys --backend gbm_physchem --regimes ABL --seeds $seeds --arms $KARMS --no-curve > /w/job_qp_$seeds.log 2>&1 & PIDS+=($!)
done
wait "${PIDS[@]}"; PIDS=()
for seeds in 10-12 13-15 16-18 19-21 22-24 25-27 28-29; do
  FP_CHIRAL=1 python3.11 run_l7a.py $R /w/o_conf --backend gbm --regimes ABL --seeds $seeds --arms $KARMS --no-curve > /w/job_qc_$seeds.log 2>&1 & PIDS+=($!)
done
wait "${PIDS[@]}"
for m in "${M[@]}"; do v=${m%%:*}; d=${m##*:}; aws s3 sync /w/$d $B/res7q_gbm_$v/ --only-show-errors; done
echo DONE > /w/done.flag; aws s3 cp /w/done.flag $B/res7q_gbm_aware/done.flag --only-show-errors; kill $SYNC; shutdown -h now
