#!/usr/bin/env nextflow
/*
 * biomni_molecular_biology_annotate_open_reading_frames
 * Find all Open Reading Frames (ORFs) in a DNA sequence using Biopython.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process ANNOTATE_OPEN_READING_FRAMES {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("annotate_open_reading_frames_output.txt"), emit: output

    script:
    """
    # Tool: biomni_molecular_biology_annotate_open_reading_frames
    # Runs in unified Docker container
    echo 'Running ANNOTATE_OPEN_READING_FRAMES'
        touch annotate_open_reading_frames_output.txt
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

workflow BIOMNI_MOLECULAR_BIOLOGY_ANNOTATE_OPEN_READING_FRAMES {
    main:

    ANNOTATE_OPEN_READING_FRAMES()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_MOLECULAR_BIOLOGY_ANNOTATE_OPEN_READING_FRAMES()
}