#!/usr/bin/env nextflow
nextflow.enable.dsl=2
process GREET {
    output:
    path "g.txt"
    script:
    """
    echo "ready" > g.txt
    """
}
workflow {
    GREET()
}
