#!/bin/sh -ex
QUERY="${DATADIR}/cif/1tim.cif"
TARGET="${DATADIR}/scop"
SCOPANOTATION="${DATADIR}/scop_lookup_bench.tsv"

"${FOLDSEEK}" easy-search "$QUERY" "$TARGET" "$RESULTS/results_aln.m8" "$RESULTS/tmp" -e 10000 -s 9 --max-seqs 100
"${FOLDSEEK}" createdb "$TARGET" "$RESULTS/targetDB"
"${FOLDSEEK}" easy-search "${QUERY}.gz" "$RESULTS/targetDB" "$RESULTS/results_aln_gz.m8" "$RESULTS/tmp" -e 10000 -s 5 --max-seqs 100

ACTUAL1=$(wc -l "$RESULTS/results_aln.m8"|awk '{print $1 }')
ACTUAL2=$(wc -l "$RESULTS/results_aln_gz.m8"|awk '{print $1 }')
ACTUAL="${ACTUAL1} ${ACTUAL2}"
TARGET="200 74"
awk -v actual="$ACTUAL" -v target="$TARGET" \
    'BEGIN { print (actual == target) ? "GOOD" : "BAD"; print "Expected: ", target; print "Actual: ", actual; }' \
    > "${RESULTS}.report"
