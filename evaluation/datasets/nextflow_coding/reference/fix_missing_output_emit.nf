#!/usr/bin/env nextflow
nextflow.enable.dsl=2
process MAKE {
    output:
    path "seed.txt", emit: seed
    script:
    """
    echo hello > seed.txt
    """
}
process UPPER {
    input:
    path f
    output:
    path "upper.txt", emit: upper
    script:
    """
    tr 'a-z' 'A-Z' < $f > upper.txt
    """
}
workflow {
    MAKE()
    UPPER(MAKE.out.seed)
}
