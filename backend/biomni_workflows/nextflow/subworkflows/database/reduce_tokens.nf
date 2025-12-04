#!/usr/bin/env nextflow
/*
 * biomni_database_reduce_tokens
 * 
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process REDUCE_TOKENS {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("reduce_tokens_output.txt"), emit: output

    script:
    """
    # Tool: biomni_database_reduce_tokens
    # Runs in unified Docker container
    echo 'Running REDUCE_TOKENS'
        touch reduce_tokens_output.txt
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

workflow BIOMNI_DATABASE_REDUCE_TOKENS {
    main:

    REDUCE_TOKENS()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_DATABASE_REDUCE_TOKENS()
}