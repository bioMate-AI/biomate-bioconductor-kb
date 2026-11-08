#!/usr/bin/env nextflow
nextflow.enable.dsl=2
process WORD_COUNT {
    input:
    val sentence
    output:
    path "wordcount.txt"
    script:
    """
    echo "${sentence}" | wc -w | tr -d ' ' > wordcount.txt
    """
}
workflow {
    WORD_COUNT(Channel.of('the quick brown fox'))
}
