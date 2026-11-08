#!/usr/bin/env nextflow
nextflow.enable.dsl=2
process MAP_ITEM {
    input:
    val item
    output:
    path "${item}.row"
    script:
    """
    echo "row:${item}" > ${item}.row
    """
}
process AGGREGATE {
    input:
    path rows
    output:
    path "summary.txt"
    script:
    """
    cat ${rows} > summary.txt
    """
}
workflow {
    MAP_ITEM(Channel.of('x','y','z'))
    AGGREGATE(MAP_ITEM.out.collect())
}
