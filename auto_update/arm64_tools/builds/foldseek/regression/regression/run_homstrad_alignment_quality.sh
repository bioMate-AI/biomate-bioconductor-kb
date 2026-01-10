#!/bin/sh -ex

# Search homstrad pdbs all-vs-all
# (simplest way, we actually only need the pairwise alignments specfied in the reference alignments file)
"${FOLDSEEK}" createdb "${DATADIR}"/homstrad/*/*.pdb "${RESULTS}/db"
"${FOLDSEEK}" easy-search "${DATADIR}"/homstrad/*/*.pdb "${RESULTS}/db" "${RESULTS}/result_aln.m8" "${RESULTS}/tmp" --format-output "query,target,qstart,tstart,qaln,taln" -e inf -a --exhaustive-search

# 1. Filter all-vs-all alignment for (query, target) pairs from HOMSTRAD reference alingments.
# 2. Merge Foldseek and reference alignments:
#    (qname, tname, family, ref_qaln, ref_taln, qstart, tstart, qaln, taln)
awk 'FNR==NR{pairs[$2$3]=$1 " " $4 " " $5; next}
     {gsub(/\.pdb$/,"",$1); gsub(/\.pdb$/,"",$2);
       if(pairs[$1$2]){print  $1, $2, pairs[$1$2], $3, $4, $5, $6}}' \
         "${DATADIR}/homstrad/reference_alignments.csv" "${RESULTS}/result_aln.m8" > "${RESULTS}/alignments.txt"

# Evaluate alignments based on reference alignments
"${EVALUATE}" "${RESULTS}/alignments.txt" > "${RESULTS}/alignment_quality.csv"

# Check avarage of alignment quality
ACTUAL=$(awk '{sensitivity_sum+=$2; precision_sum+=$3} END{print sensitivity_sum/NR, precision_sum/NR}' "${RESULTS}/alignment_quality.csv")
TARGET="0.80136 0.83748"  # sensitivity, precision
awk -v actual="$ACTUAL" -v target="$TARGET" \
    'BEGIN { print (actual == target) ? "GOOD" : "BAD"; print "Expected: ", target; print "Actual: ", actual; }' \
    > "${RESULTS}.report"

