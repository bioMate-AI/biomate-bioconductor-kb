#!/usr/bin/env nextflow
/*
 * biomni_molecular_biology_get_gene_coding_sequence
 * Retrieves the coding sequence(s) of a specified gene from NCBI Entrez.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process GET_GENE_CODING_SEQUENCE {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("get_gene_coding_sequence_output.txt"), emit: output

    script:
    """
    # Tool: biomni_molecular_biology_get_gene_coding_sequence
    # Runs in unified Docker container
    echo 'Running GET_GENE_CODING_SEQUENCE'
        touch get_gene_coding_sequence_output.txt
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

workflow BIOMNI_MOLECULAR_BIOLOGY_GET_GENE_CODING_SEQUENCE {
    main:

    GET_GENE_CODING_SEQUENCE()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_MOLECULAR_BIOLOGY_GET_GENE_CODING_SEQUENCE()
}