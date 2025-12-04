#!/usr/bin/env nextflow
/*
 * biomni_synthetic_biology_hamming_distance
 * 
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process HAMMING_DISTANCE {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("hamming_distance_output.txt"), emit: output

    script:
    """
    # Tool: biomni_synthetic_biology_hamming_distance
    # Runs in unified Docker container
    echo 'Running HAMMING_DISTANCE'
        touch hamming_distance_output.txt
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

workflow BIOMNI_SYNTHETIC_BIOLOGY_HAMMING_DISTANCE {
    main:

    HAMMING_DISTANCE()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_SYNTHETIC_BIOLOGY_HAMMING_DISTANCE()
}