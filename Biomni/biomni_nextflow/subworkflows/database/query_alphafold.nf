#!/usr/bin/env nextflow
/*
 * biomni_database_query_alphafold
 * Query the AlphaFold Database API for protein structure predictions.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.file_format = null

// Processes
process QUERY_ALPHAFOLD {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(file_format)

    output:
    path("query_alphafold_output.txt"), emit: output

    script:
    """
    # Tool: biomni_database_query_alphafold
    # Runs in unified Docker container
    echo 'Running QUERY_ALPHAFOLD'
        touch query_alphafold_output.txt
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

workflow BIOMNI_DATABASE_QUERY_ALPHAFOLD {
    main:
    ch_file_format = Channel.fromPath(params.file_format)

    QUERY_ALPHAFOLD(ch_file_format)
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_DATABASE_QUERY_ALPHAFOLD()
}