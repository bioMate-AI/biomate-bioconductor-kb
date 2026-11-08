#!/usr/bin/env nextflow
nextflow.enable.dsl=2
process GENERATE {
    output:
    path "nums.txt", emit: nums
    script:
    """
    seq 1 5 > nums.txt
    """
}
process SUMMARIZE {
    input:
    path nums
    output:
    path "count.txt"
    script:
    """
    wc -l < ${nums} | tr -d ' ' > count.txt
    """
}
workflow {
    GENERATE()
    SUMMARIZE(GENERATE.out.nums)
}
