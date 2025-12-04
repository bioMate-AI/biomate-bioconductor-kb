#!/usr/bin/env nextflow
/*
 * biomni_protocols_search_protocols
 * 
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process SEARCH_PROTOCOLS {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("search_protocols_output.txt"), emit: output

    script:
    """
    # Tool: biomni_protocols_search_protocols
    # Runs in unified Docker container
    echo 'Running SEARCH_PROTOCOLS'
        touch search_protocols_output.txt
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

workflow BIOMNI_PROTOCOLS_SEARCH_PROTOCOLS {
    main:

    SEARCH_PROTOCOLS()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_PROTOCOLS_SEARCH_PROTOCOLS()
}