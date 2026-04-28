#!/usr/bin/env bash -C -e -u -o pipefail
filter_gtf.py \
    --gtf genes_with_empty_tid.gtf \
    --fasta genome.fasta \
    --prefix genes_with_empty_tid

cat <<-END_VERSIONS > versions.yml
"NFCORE_RNASEQ:PREPARE_GENOME:GTF_FILTER":
    python: $(python --version | sed 's/Python //g')
END_VERSIONS
