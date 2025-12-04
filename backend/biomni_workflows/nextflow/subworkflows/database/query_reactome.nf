#!/usr/bin/env nextflow
/*
 * biomni_database_query_reactome
 * Query the Reactome database using natural language or a direct endpoint.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process QUERY_REACTOME {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("query_reactome_output.txt"), emit: output

    script:
    """
    # Tool: biomni_database_query_reactome
    # Runs in unified Docker container
    echo 'Running QUERY_REACTOME'
        touch query_reactome_output.txt
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

workflow BIOMNI_DATABASE_QUERY_REACTOME {
    main:

    QUERY_REACTOME()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_DATABASE_QUERY_REACTOME()
}