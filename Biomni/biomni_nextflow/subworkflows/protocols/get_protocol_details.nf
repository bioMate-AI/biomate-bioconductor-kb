#!/usr/bin/env nextflow
/*
 * biomni_protocols_get_protocol_details
 * 
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process GET_PROTOCOL_DETAILS {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("get_protocol_details_output.txt"), emit: output

    script:
    """
    # Tool: biomni_protocols_get_protocol_details
    # Runs in unified Docker container
    echo 'Running GET_PROTOCOL_DETAILS'
        touch get_protocol_details_output.txt
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

workflow BIOMNI_PROTOCOLS_GET_PROTOCOL_DETAILS {
    main:

    GET_PROTOCOL_DETAILS()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_PROTOCOLS_GET_PROTOCOL_DETAILS()
}