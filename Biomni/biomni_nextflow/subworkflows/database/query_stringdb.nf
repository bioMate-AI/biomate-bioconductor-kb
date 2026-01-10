#!/usr/bin/env nextflow
/*
 * biomni_database_query_stringdb
 * Query the STRING protein interaction database using natural language or direct endpoint.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process QUERY_STRINGDB {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("query_stringdb_output.txt"), emit: output

    script:
    """
    # Tool: biomni_database_query_stringdb
    # Runs in unified Docker container
    echo 'Running QUERY_STRINGDB'
        touch query_stringdb_output.txt
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

workflow BIOMNI_DATABASE_QUERY_STRINGDB {
    main:

    QUERY_STRINGDB()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_DATABASE_QUERY_STRINGDB()
}