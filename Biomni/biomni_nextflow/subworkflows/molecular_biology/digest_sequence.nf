#!/usr/bin/env nextflow
/*
 * biomni_molecular_biology_digest_sequence
 * Simulates restriction enzyme digestion using Biopython's catalyze method and returns the resulting DNA fragments.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process DIGEST_SEQUENCE {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("digest_sequence_output.txt"), emit: output

    script:
    """
    # Tool: biomni_molecular_biology_digest_sequence
    # Runs in unified Docker container
    echo 'Running DIGEST_SEQUENCE'
        touch digest_sequence_output.txt
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

workflow BIOMNI_MOLECULAR_BIOLOGY_DIGEST_SEQUENCE {
    main:

    DIGEST_SEQUENCE()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_MOLECULAR_BIOLOGY_DIGEST_SEQUENCE()
}