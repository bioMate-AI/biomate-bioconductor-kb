#!/bin/bash
# resumable driver; every stage writes incrementally to results/preds
cd "$(dirname "$0")"; P=/opt/homebrew/bin/python3; export OMP_NUM_THREADS=2
$P features.py > logs/feat.log 2>&1
for m in M1 M2 M3 M4 M5; do nohup $P run_classical.py $m > logs/$m.log 2>&1 & done
for m in G1 G2; do nohup $P gnn.py $m S1,S2,S3,S0 > logs/$m.log 2>&1 & done
nohup $P gnn.py pretrain > logs/pre.log 2>&1 &
wait
