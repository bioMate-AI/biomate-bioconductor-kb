#!/usr/bin/env nextflow
nextflow.enable.dsl=2
process TAG_ITEM {
    input:
    val item
    output:
    path "${item}.txt"
    script:
    """
    echo "item:${item}" > ${item}.txt
    """
}
process GATHER {
    input:
    path parts
    output:
    path "all.txt"
    script:
    """
    cat ${parts} > all.txt
    """
}
workflow {
    TAG_ITEM(Channel.of('a','b','c'))
    GATHER(TAG_ITEM.out.collect())
}
