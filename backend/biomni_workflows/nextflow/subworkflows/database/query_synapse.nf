#!/usr/bin/env nextflow
/*
 * biomni_database_query_synapse
 * Query Synapse REST API for biomedical datasets and files.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process QUERY_SYNAPSE {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("query_synapse_output.txt"), emit: output

    script:
    """
    # Tool: biomni_database_query_synapse
    # Runs in unified Docker container
    echo 'Running QUERY_SYNAPSE'
        touch query_synapse_output.txt
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

workflow BIOMNI_DATABASE_QUERY_SYNAPSE {
    main:

    QUERY_SYNAPSE()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_DATABASE_QUERY_SYNAPSE()
}