#!/usr/bin/env nextflow
nextflow.enable.dsl=2
params.greeting = 'hi'
process MESSAGE {
    output:
    path "msg.txt"
    script:
    """
    echo "${params.greeting}, world" > msg.txt
    """
}
workflow {
    MESSAGE()
}
