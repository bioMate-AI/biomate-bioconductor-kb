#!/usr/bin/env nextflow
/*
 * biomni_genomics_get_rna_seq_archs4
 * Given a gene name, this function returns the steps it performs and the max K transcripts-per-million (TPM)
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process GET_RNA_SEQ_ARCHS4 {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("get_rna_seq_archs4_output.txt"), emit: output

    script:
    """
    # Tool: biomni_genomics_get_rna_seq_archs4
    # Runs in unified Docker container
    echo 'Running GET_RNA_SEQ_ARCHS4'
        touch get_rna_seq_archs4_output.txt
    """
}

process OUTPUT {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("output_output.txt"), emit: output

    script:
    """
    # Tool: cat1
    # Runs in unified Docker container
    echo 'Running OUTPUT'
        touch output_output.txt
    """
}

workflow BIOMNI_GENOMICS_GET_RNA_SEQ_ARCHS4 {
    main:

    GET_RNA_SEQ_ARCHS4()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_GENOMICS_GET_RNA_SEQ_ARCHS4()
}