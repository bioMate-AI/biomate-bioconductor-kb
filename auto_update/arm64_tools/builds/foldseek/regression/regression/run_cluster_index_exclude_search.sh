#!/bin/sh -ex
INPUT="${DATADIR}/scop"
INPUTDB="${RESULTS}/input"
SCOPANOTATION="${DATADIR}/scop_lookup_bench.tsv"
"${FOLDSEEK}" createdb "${INPUT}" "${INPUTDB}"

"${FOLDSEEK}" cluster "$INPUTDB"  "${INPUTDB}_clu" "$RESULTS/tmp" -c 0.9 --min-seq-id 0.3 -s 9
"${FOLDSEEK}" createclusearchdb  "${INPUTDB}" "${INPUTDB}_clu" "$RESULTS/db"
"${FOLDSEEK}" createindex "$RESULTS/db" tmp --index-exclude 3 
"${FOLDSEEK}" easy-search "${INPUT}" "$RESULTS/db" "$RESULTS/results_aln.m8" "$RESULTS/tmp" --cluster-search 1 --prefilter-mode 1 --sort-by-structure-bits 0 -e 10000 -s 9 --max-seqs 100 -a --remove-tmp-files 0

"${EVALUATE}" "$SCOPANOTATION" "$RESULTS/results_aln.m8" > "${RESULTS}/evaluation.log"

ACTUAL=$(awk '{ famsum+=$3; supfamsum+=$4; foldsum+=$5}END{print famsum/NR,supfamsum/NR,foldsum/NR}' "${RESULTS}/evaluation.log")
TARGET="0.986667 0.792626 0.454002"
awk -v actual="$ACTUAL" -v target="$TARGET" \
    'BEGIN { print (actual == target) ? "GOOD" : "BAD"; print "Expected: ", target; print "Actual: ", actual; }' \
    > "${RESULTS}.report"
