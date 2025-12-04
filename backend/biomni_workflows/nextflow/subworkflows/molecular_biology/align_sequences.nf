#!/usr/bin/env nextflow
/*
 * biomni_molecular_biology_align_sequences
 * Align short sequences (primers) to a longer sequence, allowing for one mismatch.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process ALIGN_SEQUENCES {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("align_sequences_output.txt"), emit: output

    script:
    """
    # Tool: biomni_molecular_biology_align_sequences
    # Runs in unified Docker container
    echo 'Running ALIGN_SEQUENCES'
        touch align_sequences_output.txt
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

workflow BIOMNI_MOLECULAR_BIOLOGY_ALIGN_SEQUENCES {
    main:

    ALIGN_SEQUENCES()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_MOLECULAR_BIOLOGY_ALIGN_SEQUENCES()
}