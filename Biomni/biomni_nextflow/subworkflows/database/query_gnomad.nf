#!/usr/bin/env nextflow
/*
 * biomni_database_query_gnomad
 * Query gnomAD for variants in a gene using natural language or direct gene symbol.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process QUERY_GNOMAD {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("query_gnomad_output.txt"), emit: output

    script:
    """
    # Tool: biomni_database_query_gnomad
    # Runs in unified Docker container
    echo 'Running QUERY_GNOMAD'
        touch query_gnomad_output.txt
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

workflow BIOMNI_DATABASE_QUERY_GNOMAD {
    main:

    QUERY_GNOMAD()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_DATABASE_QUERY_GNOMAD()
}