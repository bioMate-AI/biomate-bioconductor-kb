#!/usr/bin/env nextflow
/*
 * biomni_database_query_openfda
 * Query the OpenFDA API using natural language or direct parameters.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process QUERY_OPENFDA {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("query_openfda_output.txt"), emit: output

    script:
    """
    # Tool: biomni_database_query_openfda
    # Runs in unified Docker container
    echo 'Running QUERY_OPENFDA'
        touch query_openfda_output.txt
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

workflow BIOMNI_DATABASE_QUERY_OPENFDA {
    main:

    QUERY_OPENFDA()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_DATABASE_QUERY_OPENFDA()
}