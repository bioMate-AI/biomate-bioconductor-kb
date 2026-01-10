#!/usr/bin/env nextflow
/*
 * biomni_database_query_regulomedb
 * Query the RegulomeDB database using natural language or direct variant/coordinate specification.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process QUERY_REGULOMEDB {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("query_regulomedb_output.txt"), emit: output

    script:
    """
    # Tool: biomni_database_query_regulomedb
    # Runs in unified Docker container
    echo 'Running QUERY_REGULOMEDB'
        touch query_regulomedb_output.txt
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

workflow BIOMNI_DATABASE_QUERY_REGULOMEDB {
    main:

    QUERY_REGULOMEDB()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_DATABASE_QUERY_REGULOMEDB()
}