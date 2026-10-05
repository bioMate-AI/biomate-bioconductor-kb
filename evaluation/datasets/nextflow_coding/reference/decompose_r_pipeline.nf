#!/usr/bin/env nextflow
nextflow.enable.dsl=2
process READ_IDS {
    output:
    path "ids.txt", emit: ids
    script:
    """
    printf 'a\\nb\\nc\\n' > ids.txt
    """
}
process PER_ID {
    input:
    val id
    output:
    path "${id}.out"
    script:
    """
    echo "${id}:done" > ${id}.out
    """
}
process COMBINE {
    input:
    path parts
    output:
    path "combined.txt"
    script:
    """
    cat ${parts} > combined.txt
    """
}
workflow {
    READ_IDS()
    ids = READ_IDS.out.ids.splitText().map { it.trim() }.filter { it }
    PER_ID(ids)
    COMBINE(PER_ID.out.collect())
}
