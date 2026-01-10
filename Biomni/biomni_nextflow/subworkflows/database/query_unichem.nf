#!/usr/bin/env nextflow
/*
 * biomni_database_query_unichem
 * Query the UniChem 2.0 REST API using natural language or a direct endpoint.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process QUERY_UNICHEM {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("query_unichem_output.txt"), emit: output

    script:
    """
    # Tool: biomni_database_query_unichem
    # Runs in unified Docker container
    echo 'Running QUERY_UNICHEM'
        touch query_unichem_output.txt
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

workflow BIOMNI_DATABASE_QUERY_UNICHEM {
    main:

    QUERY_UNICHEM()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_DATABASE_QUERY_UNICHEM()
}