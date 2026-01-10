#!/usr/bin/env nextflow
/*
 * biomni_database_query_dailymed
 * Query the DailyMed RESTful API using natural language or a direct endpoint.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process QUERY_DAILYMED {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("query_dailymed_output.txt"), emit: output

    script:
    """
    # Tool: biomni_database_query_dailymed
    # Runs in unified Docker container
    echo 'Running QUERY_DAILYMED'
        touch query_dailymed_output.txt
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

workflow BIOMNI_DATABASE_QUERY_DAILYMED {
    main:

    QUERY_DAILYMED()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_DATABASE_QUERY_DAILYMED()
}