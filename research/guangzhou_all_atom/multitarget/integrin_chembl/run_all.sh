#!/bin/bash
# runs all splits (CPU only). Predictions are written to data/preds/ (compact csv.gz).
cd "$(dirname "$0")"
for s in ${@:-S3 S3b S0 S1 S2 S2b}; do /opt/homebrew/bin/python3.14 06_run.py $s 7 > logs_$s.txt 2>&1; done
