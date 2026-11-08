#!/usr/bin/env bash

QUERY=$(cat <<EOF
SELECT
    count(distinct p.ProteinGroup),
    count(distinct p2p.PeptideSeq)
FROM proteinscores p, peptidetoprotein p2p
WHERE p.ProteinAccession=p2p.ProteinAccession
    and p2p.isDecoy == 0
EOF
)

function count_unique_peptides_proteins {
    [[ $# -eq 0 ]] && return
    FILE=$1
    sqlite3 $FILE "${QUERY}" \
        | awk -v FILE="${FILE}" \
            '{split($0,a,"|"); printf "%s,%d,%d\n",FILE,a[1],a[2]}'
}

count_unique_peptides_proteins $1
