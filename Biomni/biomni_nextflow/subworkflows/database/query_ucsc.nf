#!/usr/bin/env nextflow
/*
 * biomni_database_query_ucsc
 * Query the UCSC Genome Browser API using natural language or a direct endpoint.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process QUERY_UCSC {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("query_ucsc_output.txt"), emit: output

    script:
    """
    # Tool: biomni_database_query_ucsc
    # Runs in unified Docker container
    echo 'Running QUERY_UCSC'
        touch query_ucsc_output.txt
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

workflow BIOMNI_DATABASE_QUERY_UCSC {
    main:

    QUERY_UCSC()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_DATABASE_QUERY_UCSC()
}