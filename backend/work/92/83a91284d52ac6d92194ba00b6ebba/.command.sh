#!/usr/bin/env bash -C -e -u -o pipefail
cat input1/SRR6357070_1.fastq.gz input3/SRR6357071_1.fastq.gz > WT_REP1_1.merged.fastq.gz
cat input2/SRR6357070_2.fastq.gz input4/SRR6357071_2.fastq.gz > WT_REP1_2.merged.fastq.gz

cat <<-END_VERSIONS > versions.yml
"NFCORE_RNASEQ:RNASEQ:FASTQ_QC_TRIM_FILTER_SETSTRANDEDNESS:CAT_FASTQ":
    cat: $(echo $(cat --version 2>&1) | sed 's/^.*coreutils) //; s/ .*$//')
END_VERSIONS
