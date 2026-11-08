#!/usr/bin/env nextflow
nextflow.enable.dsl=2
process LOAD {
    output:
    path "words.txt", emit: words
    script:
    """
    printf 'alpha\\nbeta\\ngamma\\n' > words.txt
    """
}
process TRANSFORM {
    input:
    path words
    output:
    path "out.txt"
    script:
    """
    tr 'a-z' 'A-Z' < ${words} > out.txt
    """
}
workflow {
    LOAD()
    TRANSFORM(LOAD.out.words)
}
