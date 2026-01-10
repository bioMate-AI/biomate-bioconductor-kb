#!/usr/bin/env nextflow
/*
 * biomni_database_query_chembl
 * Query the ChEMBL REST API using natural language, direct endpoint, or specific identifiers.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process QUERY_CHEMBL {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("query_chembl_output.txt"), emit: output

    script:
    """
    # Tool: biomni_database_query_chembl
    # Runs in unified Docker container
    echo 'Running QUERY_CHEMBL'
        touch query_chembl_output.txt
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

workflow BIOMNI_DATABASE_QUERY_CHEMBL {
    main:

    QUERY_CHEMBL()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_DATABASE_QUERY_CHEMBL()
}