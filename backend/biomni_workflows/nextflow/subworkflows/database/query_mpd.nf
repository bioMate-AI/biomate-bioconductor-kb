#!/usr/bin/env nextflow
/*
 * biomni_database_query_mpd
 * Query the Mouse Phenome Database (MPD) for mouse strain phenotype data.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process QUERY_MPD {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("query_mpd_output.txt"), emit: output

    script:
    """
    # Tool: biomni_database_query_mpd
    # Runs in unified Docker container
    echo 'Running QUERY_MPD'
        touch query_mpd_output.txt
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

workflow BIOMNI_DATABASE_QUERY_MPD {
    main:

    QUERY_MPD()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_DATABASE_QUERY_MPD()
}