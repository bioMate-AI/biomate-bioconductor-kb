"""Pilot 4 spot job generator. usage: make_ud4.py STAGE OUT.sh   STAGE = traindev | test
Template follows the standing rules: ecsInstanceRole instance, boot log + results synced to S3 every 20 s, explicit PID waits (no bare wait), wall-clock shutdown, terminate on done."""
import sys
B = "s3://biomate-nextflow-work/cyclic_peptide/ihlm_pilot4"
HEAD = """#!/bin/bash
mkdir -p /w; exec > >(tee -a /w/boot.log) 2>&1
echo boot $(date -u)
B=__B__
shutdown -h +180
( while true; do aws s3 cp /w/boot.log $B/logs/boot___STAGE__.log --only-show-errors; aws s3 sync /w/repo/pilot4/results $B/results/ --only-show-errors --exclude "*.npy" --exclude "emb_small.npz"; sleep 20; done ) &
SYNC=$!
dnf install -y python3.11 python3.11-pip python3.11-devel gcc >/dev/null 2>&1
python3.11 -m pip install -q numpy scipy scikit-learn pandas joblib rdkit 2>&1 | tail -2
python3.11 -m pip install -q torch==2.13.0+cpu --extra-index-url https://download.pytorch.org/whl/cpu 2>&1 | tail -2
mkdir -p /w/repo/pilot4/results /w/repo/data
aws s3 sync $B/code/ /w/repo/pilot4/ --only-show-errors
aws s3 sync $B/data/ /w/data_flat/ --only-show-errors
aws s3 sync $B/results/ /w/repo/pilot4/results/ --only-show-errors
# p4common expects HERE/../../../multitarget/integrin_chembl/retro_recovery/data : build that layout
mkdir -p /w/layout/research/guangzhou_all_atom/cyclic_llm/ihlm_backbone /w/layout/research/guangzhou_all_atom/multitarget/integrin_chembl/retro_recovery
cp -r /w/repo/pilot4 /w/layout/research/guangzhou_all_atom/cyclic_llm/ihlm_backbone/pilot4
cp -r /w/data_flat /w/layout/research/guangzhou_all_atom/multitarget/integrin_chembl/retro_recovery/data
cd /w/layout/research/guangzhou_all_atom/cyclic_llm/ihlm_backbone/pilot4
ln -sfn /w/layout/research/guangzhou_all_atom/cyclic_llm/ihlm_backbone/pilot4/results /w/repo/pilot4/results_link

RESD=/w/layout/research/guangzhou_all_atom/cyclic_llm/ihlm_backbone/pilot4/results
mkdir -p $RESD; aws s3 sync $B/results/ $RESD/ --only-show-errors
( while true; do aws s3 sync $RESD $B/results/ --only-show-errors --exclude "fp.npy" --exclude "emb_small.npz"; aws s3 cp /w/boot.log $B/logs/boot___STAGE__.log --only-show-errors; sleep 20; done ) &
SYNC2=$!
kill $SYNC
export JOBS=16 OMP_NUM_THREADS=4
"""
STAGES = {
 "traindev": """PIDS=()
for f in 0 1 2 3 4 5; do NT=5 python3.11 p4models.py $f > $RESD/train_$f.log 2>&1 & PIDS+=($!); done
for p in "${PIDS[@]}"; do wait $p; done
ls $RESD/fold*.pkl | wc -l
python3.11 p4eval.py dev $RESD/eval_dev.pkl > $RESD/eval_dev.log 2>&1
""",
 "dev": """python3.11 p4eval.py dev $RESD/eval_dev.pkl > $RESD/eval_dev.log 2>&1
""",
 "test": """python3.11 p4eval.py test $RESD/eval_test.pkl > $RESD/eval_test.log 2>&1
python3.11 p4extras.py $RESD > $RESD/extras.log 2>&1
""",
}
TAIL = """
aws s3 sync $RESD $B/results/ --only-show-errors --exclude "fp.npy" --exclude "emb_small.npz"
echo DONE > /w/done.flag; aws s3 cp /w/done.flag $B/flags/__STAGE___done.flag --only-show-errors
aws s3 cp /w/boot.log $B/logs/boot___STAGE__.log --only-show-errors
kill $SYNC2; shutdown -h now
"""
st, out = sys.argv[1], sys.argv[2]
s = (HEAD + STAGES[st] + TAIL).replace("__B__", B).replace("__STAGE__", st); open(out, "w").write(s); print("wrote", out)
