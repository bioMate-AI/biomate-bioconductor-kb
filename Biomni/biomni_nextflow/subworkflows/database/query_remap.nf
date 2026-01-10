#!/usr/bin/env nextflow
/*
 * biomni_database_query_remap
 * Query the ReMap database for regulatory elements and transcription factor binding sites.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process QUERY_REMAP {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("query_remap_output.txt"), emit: output

    script:
    """
    # Tool: biomni_database_query_remap
    # Runs in unified Docker container
    echo 'Running QUERY_REMAP'
        touch query_remap_output.txt
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

workflow BIOMNI_DATABASE_QUERY_REMAP {
    main:

    QUERY_REMAP()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_DATABASE_QUERY_REMAP()
}