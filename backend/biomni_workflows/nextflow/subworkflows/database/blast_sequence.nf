#!/usr/bin/env nextflow
/*
 * biomni_database_blast_sequence
 * Identifies a DNA sequence using NCBI BLAST with improved error handling, timeout management, and debugging.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.database = null

// Processes
process BLAST_SEQUENCE {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(database)

    output:
    path("blast_sequence_output.txt"), emit: output

    script:
    """
    # Tool: biomni_database_blast_sequence
    # Runs in unified Docker container
    echo 'Running BLAST_SEQUENCE'
        touch blast_sequence_output.txt
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

workflow BIOMNI_DATABASE_BLAST_SEQUENCE {
    main:
    ch_database = Channel.fromPath(params.database)

    BLAST_SEQUENCE(ch_database)
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_DATABASE_BLAST_SEQUENCE()
}