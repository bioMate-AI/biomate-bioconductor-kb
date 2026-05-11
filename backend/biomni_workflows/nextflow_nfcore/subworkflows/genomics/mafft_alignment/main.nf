#!/usr/bin/env nextflow
nextflow.enable.dsl = 2

params.input_files = null   // comma-separated S3 paths or glob pattern
params.input_dir   = null   // alt: directory (glob *.faa)
params.outdir = './results'

process MAFFT_ALIGN {
    tag "${faa.name}"
    publishDir "${params.outdir}/alignments", mode: 'copy'
    container 'staphb/mafft:7.526'
    cpus 2
    memory '4 GB'

    input:
    path faa

    output:
    path "${faa.baseName}.aln.faa", emit: aligned

    script:
    """
    mafft --auto ${faa} > ${faa.baseName}.aln.faa
    """
}

workflow {
    // input_dir may be a glob pattern (e.g., s3://bucket/path/*.faa) or a directory
    def pattern = params.input_dir.contains('*') ? params.input_dir : "${params.input_dir}/*.faa"
    faas = Channel.fromPath(pattern)
    MAFFT_ALIGN(faas)
}
