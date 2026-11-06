#!/usr/bin/env nextflow
nextflow.enable.dsl=2
process SEED {
    output:
    path "seed.txt", emit: seeded
    script:
    """
    echo hello > seed.txt
    """
}
process UPPER {
    input:
    path infile
    output:
    path "upper.txt"
    script:
    """
    tr 'a-z' 'A-Z' < ${infile} > upper.txt
    """
}
workflow {
    SEED()
    UPPER(SEED.out.seeded)
}
