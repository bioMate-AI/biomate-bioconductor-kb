#!/usr/bin/env nextflow
/*
 * biomni_database_query_dbsnp
 * Query the NCBI dbSNP database using natural language or a direct search term.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process QUERY_DBSNP {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("query_dbsnp_output.txt"), emit: output

    script:
    """
    # Tool: biomni_database_query_dbsnp
    # Runs in unified Docker container
    echo 'Running QUERY_DBSNP'
        touch query_dbsnp_output.txt
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

workflow BIOMNI_DATABASE_QUERY_DBSNP {
    main:

    QUERY_DBSNP()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_DATABASE_QUERY_DBSNP()
}