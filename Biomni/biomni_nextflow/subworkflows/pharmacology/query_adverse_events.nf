#!/usr/bin/env nextflow
/*
 * biomni_pharmacology_query_adverse_events
 * Query adverse events with robust error handling and validation.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process QUERY_ADVERSE_EVENTS {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("query_adverse_events_output.txt"), emit: output

    script:
    """
    # Tool: biomni_pharmacology_query_adverse_events
    # Runs in unified Docker container
    echo 'Running QUERY_ADVERSE_EVENTS'
        touch query_adverse_events_output.txt
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

workflow BIOMNI_PHARMACOLOGY_QUERY_ADVERSE_EVENTS {
    main:

    QUERY_ADVERSE_EVENTS()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_PHARMACOLOGY_QUERY_ADVERSE_EVENTS()
}