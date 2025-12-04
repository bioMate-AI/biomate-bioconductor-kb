#!/usr/bin/env nextflow
/*
 * biomni_database_query_encode
 * Query the ENCODE Portal API to help users locate functional genomics data.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process QUERY_ENCODE {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("query_encode_output.txt"), emit: output

    script:
    """
    # Tool: biomni_database_query_encode
    # Runs in unified Docker container
    echo 'Running QUERY_ENCODE'
        touch query_encode_output.txt
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

workflow BIOMNI_DATABASE_QUERY_ENCODE {
    main:

    QUERY_ENCODE()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_DATABASE_QUERY_ENCODE()
}