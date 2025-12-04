#!/usr/bin/env nextflow
/*
 * biomni_database_query_uniprot
 * Query the UniProt REST API using either natural language or a direct endpoint.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process QUERY_UNIPROT {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("query_uniprot_output.txt"), emit: output

    script:
    """
    # Tool: biomni_database_query_uniprot
    # Runs in unified Docker container
    echo 'Running QUERY_UNIPROT'
        touch query_uniprot_output.txt
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

workflow BIOMNI_DATABASE_QUERY_UNIPROT {
    main:

    QUERY_UNIPROT()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_DATABASE_QUERY_UNIPROT()
}