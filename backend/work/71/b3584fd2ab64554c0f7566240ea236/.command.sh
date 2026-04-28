#!/usr/bin/env bash -C -e -u -o pipefail
fq lint \
    --disable-validator P001 \
    SRR6357076_1.fastq.gz SRR6357076_2.fastq.gz > RAP1_IAA_30M_REP1.fq_lint.txt

cat <<-END_VERSIONS > versions.yml
"NFCORE_RNASEQ:RNASEQ:FASTQ_QC_TRIM_FILTER_SETSTRANDEDNESS:FQ_LINT":
    fq: $(echo $(fq lint --version | sed 's/fq-lint //g'))
END_VERSIONS
