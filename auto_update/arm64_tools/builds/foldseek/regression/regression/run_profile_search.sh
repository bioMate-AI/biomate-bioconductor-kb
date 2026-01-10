#!/bin/sh -ex
QUERY="${DATADIR}/scop"
QUERYDB="${RESULTS}/query"
"${FOLDSEEK}" createdb "${QUERY}" "${QUERYDB}"

TARGET="${DATADIR}/scop"
SCOPANOTATION="${DATADIR}/scop_lookup_bench.tsv"
TARGETDB="${RESULTS}/target"
"${FOLDSEEK}" createdb "${TARGET}" "${TARGETDB}" 

"${FOLDSEEK}" createindex "$TARGETDB"  "$RESULTS/tmp" 
"${FOLDSEEK}" search "$QUERYDB" "$TARGETDB" "$RESULTS/results_aln" "$RESULTS/tmp" -e 10000 -s 9 --max-seqs 100 -a
# "${FOLDSEEK}" result2profile "${QUERYDB}_ss" "${TARGETDB}_ss" "$RESULTS/results_aln" "$RESULTS/profile_ss" --max-seq-id 1.0 --e-profile 0.001 --pca 1.0 --pcb 3.0 --mask-profile 0 --comp-bias-corr 0
"${FOLDSEEK}" result2profile "${QUERYDB}" "${TARGETDB}" "$RESULTS/results_aln" "$RESULTS/profile" 
# "${FOLDSEEK}" lndb "$QUERYDB" "$RESULTS/profile"
# "${FOLDSEEK}" lndb "${QUERYDB}_h" "$RESULTS/profile_h"
# "${FOLDSEEK}" lndb "${QUERYDB}_ca" "$RESULTS/profile_ca"
"${FOLDSEEK}" prefilter "$RESULTS/profile_ss" "${TARGETDB}_ss" "$RESULTS/prefilter" -s 7.5 --max-seqs 2000 --mask 0 --comp-bias-corr 0
"${FOLDSEEK}" structurealign "$RESULTS/profile" "${TARGETDB}" "$RESULTS/prefilter" "$RESULTS/result_profile_aln" -e 1000 --gap-open 10 --gap-extend 1 --comp-bias-corr 0 
#"${FOLDSEEK}" align "$RESULTS/profile_ss" "${TARGETDB}_ss" "$RESULTS/prefilter" "$RESULTS/result_profile_aln" -e 1000 --gap-open 10 --gap-extend 1 --comp-bias-corr 0 
"${FOLDSEEK}" convertalis "$QUERYDB" "$TARGETDB" "$RESULTS/result_profile_aln" "$RESULTS/results_aln.m8"

"${EVALUATE}" "$SCOPANOTATION" "$RESULTS/results_aln.m8" > "${RESULTS}/evaluation.log"

ACTUAL=$(awk '{ famsum+=$3; supfamsum+=$4; foldsum+=$5}END{print famsum/NR,supfamsum/NR,foldsum/NR}' "${RESULTS}/evaluation.log")
TARGET="0.986667 0.842626 0.481988"
awk -v actual="$ACTUAL" -v target="$TARGET" \
    'BEGIN { print (actual == target) ? "GOOD" : "BAD"; print "Expected: ", target; print "Actual: ", actual; }' \
    > "${RESULTS}.report"
