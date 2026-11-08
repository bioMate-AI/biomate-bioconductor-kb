#!/usr/bin/env nextflow
nextflow.enable.dsl=2
process GREET {
    input:
    val name
    output:
    path "greeting.txt"
    stub:
    """
    echo "stub" > greeting.txt
    """
    script:
    """
    echo "Hello, ${name}!" > greeting.txt
    """
}
workflow {
    GREET(Channel.of('BioMate'))
}
