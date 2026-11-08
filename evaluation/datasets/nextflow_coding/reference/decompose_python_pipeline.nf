#!/usr/bin/env nextflow
nextflow.enable.dsl=2
process LIST_SAMPLES {
    output:
    path "samples.txt", emit: samples
    script:
    """
    printf 's1\\ns2\\ns3\\n' > samples.txt
    """
}
process PER_SAMPLE {
    input:
    val sample
    output:
    path "${sample}.res"
    script:
    """
    echo "${sample}=ok" > ${sample}.res
    """
}
process AGGREGATE {
    input:
    path results
    output:
    path "report.txt"
    script:
    """
    cat ${results} > report.txt
    """
}
workflow {
    LIST_SAMPLES()
    ids = LIST_SAMPLES.out.samples.splitText().map { it.trim() }.filter { it }
    PER_SAMPLE(ids)
    AGGREGATE(PER_SAMPLE.out.collect())
}
