#!/usr/bin/env nextflow
/*
 * biomni_database_query_gtopdb
 * Query the Guide to PHARMACOLOGY database (GtoPdb) using natural language or a direct endpoint.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process QUERY_GTOPDB {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("query_gtopdb_output.txt"), emit: output

    script:
    """
    # Tool: biomni_database_query_gtopdb
    # Runs in unified Docker container
    echo 'Running QUERY_GTOPDB'
        touch query_gtopdb_output.txt
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

workflow BIOMNI_DATABASE_QUERY_GTOPDB {
    main:

    QUERY_GTOPDB()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_DATABASE_QUERY_GTOPDB()
}