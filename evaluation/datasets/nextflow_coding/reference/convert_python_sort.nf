#!/usr/bin/env nextflow
nextflow.enable.dsl=2
process SORT_FRUIT {
    output:
    path "sorted.txt"
    script:
    """
    printf 'banana\\napple\\ncherry\\n' | sort > sorted.txt
    """
}
workflow {
    SORT_FRUIT()
}
