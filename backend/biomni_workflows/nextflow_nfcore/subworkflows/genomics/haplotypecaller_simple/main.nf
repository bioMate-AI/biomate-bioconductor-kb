#!/usr/bin/env nextflow
nextflow.enable.dsl = 2

params.bam = null
params.bam_index = null
params.reference = null
params.sample_id = 'SAMPLE'
params.outdir = './results'

process HAPLOTYPECALLER {
    tag "${params.sample_id}"
    publishDir "${params.outdir}", mode: 'copy'
    container '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/genomics-germline:x86'
    cpus 4
    memory '16 GB'

    input:
    path bam
    path bam_index
    path ref

    output:
    path "variants.vcf", emit: vcf

    script:
    """
    # Download reference index files if needed
    samtools faidx ${ref} || true
    samtools dict ${ref} > ${ref.baseName}.dict || true

    gatk HaplotypeCaller \
        -R ${ref} \
        -I ${bam} \
        -O variants.vcf \
        --sample-ploidy 2 \
        --min-base-quality-score 20 2>&1 | tail -20
    """
}

workflow {
    bam_ch = Channel.fromPath(params.bam)
    idx_ch = Channel.fromPath(params.bam_index)
    ref_ch = Channel.fromPath(params.reference)
    HAPLOTYPECALLER(bam_ch, idx_ch, ref_ch)
}
