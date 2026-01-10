#!/bin/sh -ex
QUERY="${DATADIR}/scop"
QUERYDB="${RESULTS}/query"
"${FOLDSEEK}" createdb "${QUERY}" "${QUERYDB}"

TARGET="${DATADIR}/scop"
SCOPANOTATION="${DATADIR}/scop_lookup_bench.tsv"
TARGETDB="${RESULTS}/target"
"${FOLDSEEK}" createdb "${TARGET}" "${TARGETDB}"

"${FOLDSEEK}" search "$QUERYDB" "$TARGETDB" "$RESULTS/results_aln" "$RESULTS/tmp" --alignment-type 3 -e 10000 -s 5 --max-seqs 100
"${FOLDSEEK}" convertalis "$QUERYDB" "$TARGETDB" "$RESULTS/results_aln" "$RESULTS/results_aln.m8"

"${EVALUATE}" "$SCOPANOTATION" "$RESULTS/results_aln.m8" > "${RESULTS}/evaluation.log"

ACTUAL=$(awk '{ famsum+=$3; supfamsum+=$4; foldsum+=$5}END{print famsum/NR,supfamsum/NR,foldsum/NR}' "${RESULTS}/evaluation.log")
ACTUAL1="$(echo "$ACTUAL" | awk '{ print $1 }')"
ACTUAL2="$(echo "$ACTUAL" | awk '{ print $2 }')"
ACTUAL3="$(echo "$ACTUAL" | awk '{ print $3 }')"
TARGET1="0.873333"
TARGET2="0.462222"
TARGET3="0.268066"
TARGET3_LOW="0.2653" #0.268066-1%
TARGET3_HIGH="0.272" #0.268066+1%, actual AVX2 value is 0.27199
awk -v actual1="$ACTUAL1" -v target1="$TARGET1" \
    -v actual2="$ACTUAL2" -v target2="$TARGET2" \
    -v actual3="$ACTUAL3" -v target3="$TARGET3" -v target3low="$TARGET3_LOW" -v target3high="$TARGET3_HIGH" \
    'BEGIN { print (actual1 == target1 && actual2 == target2 && actual3 > target3low && actual3 < target3high) ? "GOOD" : "BAD"; \
        print "Expected: ", target1" "target2" "target3; print "Actual: ", actual1" "actual2" "actual3; }' \
    > "${RESULTS}.report"
