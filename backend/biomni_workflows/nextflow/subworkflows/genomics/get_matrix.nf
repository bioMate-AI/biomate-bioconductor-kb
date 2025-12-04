#!/usr/bin/env nextflow
/*
 * biomni_genomics_get_matrix
 * 
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process GET_MATRIX {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("get_matrix_output.txt"), emit: output

    script:
    """
    # Tool: biomni_genomics_get_matrix
    # Runs in unified Docker container
    echo 'Running GET_MATRIX'
        touch get_matrix_output.txt
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

workflow BIOMNI_GENOMICS_GET_MATRIX {
    main:

    GET_MATRIX()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_GENOMICS_GET_MATRIX()
}