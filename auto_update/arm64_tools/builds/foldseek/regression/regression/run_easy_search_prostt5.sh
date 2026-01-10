#!/bin/sh -e
QUERY="${RESULTS}/query.fasta"
TARGET="${DATADIR}/scop"

cat <<EOF > "${QUERY}"
>d2pf1a2
SATDAFWAKYTACESARNPREKLNECLEGN
EOF

if [ ! -e "$RESULTS/pt5/prostt5-f16.gguf" ]; then
    "${FOLDSEEK}" databases ProstT5 "$RESULTS/pt5" "$RESULTS/tmp"
fi
"${FOLDSEEK}" easy-search "$QUERY" "$TARGET" "$RESULTS/results_aln.m8" "$RESULTS/tmp" -e 10000 -s 9 --max-seqs 100 --prostt5-model "$RESULTS/pt5" -v 4 --threads 1

awk -v target="d2pf1a2" \
    'NR == 1 { result = "BAD"; if ($1 == $2 && $1 == target) result = "GOOD"; printf("%s\nExpected:\n%s %s\nActual:\n%s %s\n", result, target, target, $1, $2); exit; }' \
    "$RESULTS/results_aln.m8" > "${RESULTS}.report"
