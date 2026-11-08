#!/usr/bin/env nextflow
nextflow.enable.dsl=2
process ECHO_MSG {
    input:
    val message
    output:
    path "out.txt"
    script:
    """
    echo "${message}" > out.txt
    """
}
workflow {
    ECHO_MSG(Channel.of('cwl-ok'))
}
