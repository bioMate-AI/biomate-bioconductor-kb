#!/usr/bin/env bash -C -e -u -o pipefail
cat input1/SRR6357074_1.fastq.gz input2/SRR6357075_1.fastq.gz > RAP1_UNINDUCED_REP2.merged.fastq.gz

cat <<-END_VERSIONS > versions.yml
"NFCORE_RNASEQ:RNASEQ:FASTQ_QC_TRIM_FILTER_SETSTRANDEDNESS:CAT_FASTQ":
    cat: $(echo $(cat --version 2>&1) | sed 's/^.*coreutils) //; s/ .*$//')
END_VERSIONS
