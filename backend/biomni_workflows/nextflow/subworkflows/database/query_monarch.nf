#!/usr/bin/env nextflow
/*
 * biomni_database_query_monarch
 * Query the Monarch Initiative API using natural language or a direct endpoint.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process QUERY_MONARCH {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("query_monarch_output.txt"), emit: output

    script:
    """
    # Tool: biomni_database_query_monarch
    # Runs in unified Docker container
    echo 'Running QUERY_MONARCH'
        touch query_monarch_output.txt
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

workflow BIOMNI_DATABASE_QUERY_MONARCH {
    main:

    QUERY_MONARCH()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_DATABASE_QUERY_MONARCH()
}