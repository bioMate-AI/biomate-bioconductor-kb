#!/usr/bin/env nextflow
nextflow.enable.dsl=2
process MAKE_SEED {
    output:
    path "seed.txt", emit: seed
    script:
    """
    echo hello > seed.txt
    """
}
process TO_UPPER {
    input:
    path seed
    output:
    path "upper.txt"
    script:
    """
    tr 'a-z' 'A-Z' < ${seed} > upper.txt
    """
}
workflow {
    MAKE_SEED()
    TO_UPPER(MAKE_SEED.out.seed)
}
