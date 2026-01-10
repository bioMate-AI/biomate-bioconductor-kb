#!/usr/bin/env nextflow
/*
 * biomni_genomics_get_rna_seq_archs4
 * Given a gene name, fetch RNA-seq expression data showing the top K tissues with highest transcripts-per-million (TPM) values.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.gene_name = null

// Processes
process STEP_1__GGET_ARCHS4 {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_1__gget_archs4_output.txt"), emit: output

    script:
    """
    # Tool: python_gget_gget_archs4
    # Runs in unified Docker container
    echo 'Running STEP_1__GGET_ARCHS4'
        touch step_1__gget_archs4_output.txt
    """
}

workflow BIOMNI_GENOMICS_GET_RNA_SEQ_ARCHS4 {
    main:
    ch_gene_name = Channel.value(params.gene_name)

    STEP_1__GGET_ARCHS4(ch_gene_name)

    emit:
    output = STEP_1__GGET_ARCHS4.out.output
}

workflow {
    BIOMNI_GENOMICS_GET_RNA_SEQ_ARCHS4()
}