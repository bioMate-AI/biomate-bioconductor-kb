#!/usr/bin/env nextflow
nextflow.enable.dsl=2
process STATUS {
    output:
    path "status.txt"
    script:
    """
    echo "pipeline-ok" > status.txt
    """
}
workflow {
    STATUS()
}
