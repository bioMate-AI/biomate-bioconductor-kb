#!/usr/bin/env nextflow
nextflow.enable.dsl=2
process TWO {
    input:
    val a
    val b
    output:
    path "pair.txt"
    script:
    """
    echo "$a $b" > pair.txt
    """
}
workflow {
    TWO(Channel.of('left'), Channel.of('right'))
}
