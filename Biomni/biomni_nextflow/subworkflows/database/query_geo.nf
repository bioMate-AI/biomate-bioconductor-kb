#!/usr/bin/env nextflow
/*
 * biomni_database_query_geo
 * Query the NCBI Gene Expression Omnibus (GEO) using natural language or a direct search term.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process QUERY_GEO {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("query_geo_output.txt"), emit: output

    script:
    """
    # Tool: biomni_database_query_geo
    # Runs in unified Docker container
    echo 'Running QUERY_GEO'
        touch query_geo_output.txt
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

workflow BIOMNI_DATABASE_QUERY_GEO {
    main:

    QUERY_GEO()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_DATABASE_QUERY_GEO()
}