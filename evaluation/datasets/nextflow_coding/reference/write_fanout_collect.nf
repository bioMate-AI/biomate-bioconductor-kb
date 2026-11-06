#!/usr/bin/env nextflow
nextflow.enable.dsl=2
process TAG {
    input:
    val v
    output:
    path "${v}.tag"
    script:
    """
    echo "tag:${v}" > ${v}.tag
    """
}
process COLLECT {
    input:
    path tags
    output:
    path "all.txt"
    script:
    """
    cat ${tags} > all.txt
    """
}
workflow {
    TAG(Channel.of('a','b','c'))
    COLLECT(TAG.out.collect())
}
