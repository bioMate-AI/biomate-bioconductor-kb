#!/bin/sh -ex

QUERY="${DATADIR}/complex/complexdir.tar.gz"

"${FOLDSEEK}" createdb "$QUERY" "$RESULTS/db"
"${FOLDSEEK}" createdimerdb "$RESULTS/db" "$RESULTS/dimerdb" "$RESULTS/dimertmp"
"${FOLDSEEK}" multimercluster "$RESULTS/dimerdb" "$RESULTS/multimerclu" "$RESULTS/clutmp" --chain-tm-threshold 0.5 --tmscore-threshold 0.9 --interface-lddt-threshold 0

awk 'FNR==NR{name[$1]=1; next}{if($3 in name){print}}' "$RESULTS/multimerclu.index" "$RESULTS/dimerdb.lookup" > "$RESULTS/clulookupindex"

"${FOLDSEEK}" createsudbdb "$RESULTS/clulookupindex" "$RESULTS/dimerdb" "$RESULTS/subdb"
"${FOLDSEEK}" createinterfacedb "$RESULTS/subdb" "$RESULTS/interfacedb"
"${FOLDSEEK}" easy-multimersearch "$RESULTS/interfacedb" "$RESULTS/interfacedb" "$RESULTS/aln" "$RESULTS/tmp" --tmscore-threshold 0.4 --interface-lddt-threshold 0 --chain-tm-threshold 0

ACTUAL=$(awk 'BEGIN{qtm=0;ttm=0;qcov=0;tcov=0;n=0}{qtm+=$5;ttm+=$6;qcov+=$9;tcov+=$10;n++}END{print qtm/n,ttm,qcov,tcov/n,n}' "$RESULTS/aln_report")

TARGET="0.962781 2526.26 2584.7 0.985027 2624"

awk -v actual="$ACTUAL" -v target="$TARGET" \
    'BEGIN { print (actual == target) ? "GOOD" : "BAD"; print "Expected: ", target; print "Actual: ", actual; }' \
    > "${RESULTS}.report"
