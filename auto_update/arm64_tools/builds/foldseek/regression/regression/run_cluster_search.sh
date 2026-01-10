#!/bin/sh -ex
INPUT="${DATADIR}/scop"
INPUTDB="${RESULTS}/input"
SCOPANOTATION="${DATADIR}/scop_lookup_bench.tsv"
"${FOLDSEEK}" createdb "${INPUT}" "${INPUTDB}"

"${FOLDSEEK}" cluster "$INPUTDB"  "${INPUTDB}_clu" "$RESULTS/tmp" -c 0.9 --min-seq-id 0.3 -s 9
"${FOLDSEEK}" createclusearchdb  "${INPUTDB}" "${INPUTDB}_clu" "$RESULTS/db"
"${FOLDSEEK}" search "${INPUTDB}" "$RESULTS/db" "$RESULTS/results_aln" "$RESULTS/tmp" --cluster-search 1 -e 10000 -s 9 --max-seqs 100 -a --remove-tmp-files 0
"${FOLDSEEK}" convertalis "$INPUTDB" "$INPUTDB" "$RESULTS/results_aln" "$RESULTS/results_aln.m8"

"${EVALUATE}" "$SCOPANOTATION" "$RESULTS/results_aln.m8" > "${RESULTS}/evaluation.log"

ACTUAL=$(awk '{ famsum+=$3; supfamsum+=$4; foldsum+=$5}END{print famsum/NR,supfamsum/NR,foldsum/NR}' "${RESULTS}/evaluation.log")
TARGET="0.986667 0.797273 0.460425"
awk -v actual="$ACTUAL" -v target="$TARGET" \
    'BEGIN { print (actual == target) ? "GOOD" : "BAD"; print "Expected: ", target; print "Actual: ", actual; }' \
    > "${RESULTS}.report"
