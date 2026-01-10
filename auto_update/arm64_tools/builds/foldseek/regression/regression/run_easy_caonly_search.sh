#!/bin/sh -ex

# Reduce structures to Ca only
mkdir -p "$RESULTS/scop_caonly"
set +x
for f in "${DATADIR}/scop"/d*; 
do 
  awk '$3 == "CA" {print}' "$f" > "$RESULTS/scop_caonly/$(basename "$f")" ;
done
set -x

QUERY="$RESULTS/scop_caonly/d1alva_"
TARGET="$RESULTS/scop_caonly"

"${FOLDSEEK}" easy-search "$QUERY" "$TARGET" "$RESULTS/results_aln.m8" "$RESULTS/tmp" -e 10 -s 9 --max-seqs 100

ACTUAL=$(wc -l "$RESULTS/results_aln.m8"|awk '{print $1 }')
TARGET="27"
awk -v actual="$ACTUAL" -v target="$TARGET" \
    'BEGIN { print (actual == target) ? "GOOD" : "BAD"; print "Expected: ", target; print "Actual: ", actual; }' \
    > "${RESULTS}.report"
