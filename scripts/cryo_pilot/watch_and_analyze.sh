#!/usr/bin/env bash
# Watches for cryoDRGN TRAIN completion on Batch, then immediately runs gap analysis.
# Run in background: bash watch_and_analyze.sh &

JOB_ID="13c021ed-30e3-412d-9213-cf86ec0c1870"
CRYO_S3="s3://biomate-nextflow-work/pilot/results/trpv1-cryodrgn-r6"
BIO_S3="s3://biomate-nextflow-work/pilot/results/trpv1-bioemu-v3"
REF_PDB="s3://biomate-nextflow-work/pilot/pdbs/trpv1.pdb"
OUTDIR="/tmp/gap_results_real"
LOG="/tmp/watch_and_analyze.log"

echo "[$(date)] Watching cryoDRGN job $JOB_ID..." | tee $LOG

while true; do
  STATUS=$(aws batch describe-jobs --jobs $JOB_ID \
    --output json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
print(d['jobs'][0]['status'] if d.get('jobs') else 'UNKNOWN')
")
  echo "[$(date)] Status: $STATUS" | tee -a $LOG

  if [ "$STATUS" = "SUCCEEDED" ]; then
    echo "[$(date)] CryoDRGN SUCCEEDED. Starting gap analysis..." | tee -a $LOG
    
    # Wait for Nextflow to finish copying outputs to S3 (up to 5 min)
    sleep 60
    
    # Check if cryodrgn_output appeared in S3
    NF_LOG=$(ls /tmp/pilot2_r6.log 2>/dev/null)
    if [ -n "$NF_LOG" ]; then
      echo "[$(date)] Nextflow log: $(tail -3 $NF_LOG)" | tee -a $LOG
    fi
    
    python3 /home/yzhang/biomate/scripts/cryo_pilot/gap_analysis.py \
      --mode real \
      --bioemu_dir   "$BIO_S3" \
      --cryodrgn_dir "$CRYO_S3" \
      --reference_pdb "$REF_PDB" \
      --protein trpv1 \
      --outdir "$OUTDIR" 2>&1 | tee -a $LOG
    
    echo "[$(date)] Gap analysis complete. Results in $OUTDIR" | tee -a $LOG
    
    # Upload results to S3
    aws s3 cp $OUTDIR/gap_results.json \
      s3://biomate-nextflow-work/pilot/results/gap_analysis_real.json --quiet
    echo "[$(date)] Results uploaded to S3." | tee -a $LOG
    break

  elif [ "$STATUS" = "FAILED" ]; then
    echo "[$(date)] CryoDRGN FAILED. Check logs." | tee -a $LOG
    break
  fi

  sleep 120  # poll every 2 min
done
