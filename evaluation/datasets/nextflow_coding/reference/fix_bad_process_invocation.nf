#!/usr/bin/env nextflow
nextflow.enable.dsl=2
process GREET {
    output:
    path "hi.txt"
    script:
    """
    echo "hi there" > hi.txt
    """
}
workflow {
    GREET()
}
