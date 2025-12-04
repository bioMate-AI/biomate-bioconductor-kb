#!/usr/bin/env nextflow
/*
 * biomni_molecular_biology_get_bacterial_transformation_protocol
 * Return a standard protocol for bacterial transformation.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process GET_BACTERIAL_TRANSFORMATION_PROTOCOL {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("get_bacterial_transformation_protocol_output.txt"), emit: output

    script:
    """
    # Tool: biomni_molecular_biology_get_bacterial_transformation_protocol
    # Runs in unified Docker container
    echo 'Running GET_BACTERIAL_TRANSFORMATION_PROTOCOL'
        touch get_bacterial_transformation_protocol_output.txt
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

workflow BIOMNI_MOLECULAR_BIOLOGY_GET_BACTERIAL_TRANSFORMATION_PROTOCOL {
    main:

    GET_BACTERIAL_TRANSFORMATION_PROTOCOL()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_MOLECULAR_BIOLOGY_GET_BACTERIAL_TRANSFORMATION_PROTOCOL()
}