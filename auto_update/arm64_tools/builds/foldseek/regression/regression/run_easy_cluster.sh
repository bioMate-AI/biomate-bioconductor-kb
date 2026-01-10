#!/bin/sh -ex
INPUT="${DATADIR}/scop"
INPUTDB="${RESULTS}/input"
SCOPANOTATION="${DATADIR}/scop_lookup_bench.tsv"

"${FOLDSEEK}" easy-cluster "${INPUT}"  "$RESULTS/results" "$RESULTS/tmp" -c 0.5 -s 9 

"${EVALUATE}" "$SCOPANOTATION" "$RESULTS/results_cluster.tsv" > "${RESULTS}/evaluation.log"
cat "${RESULTS}/evaluation.log"
ACTUAL=$(awk '{ if($3 > 0 && $4 == 0 ){ goodcluster+=1;} if($4 > 0){ badcluster+=1;} tp+=$3; fp+=$4; }END{print goodcluster,badcluster,tp,fp}' "${RESULTS}/evaluation.log")
TARGET="169 4 281 3"
awk -v actual="$ACTUAL" -v target="$TARGET" \
    'BEGIN { print (actual == target) ? "GOOD" : "BAD"; print "Expected: ", target; print "Actual: ", actual; }' \
    > "${RESULTS}.report"

