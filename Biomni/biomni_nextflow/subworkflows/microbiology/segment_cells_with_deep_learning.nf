#!/usr/bin/env nextflow
/*
 * biomni_microbiology_segment_cells_with_deep_learning
 * Perform cell segmentation on fluorescence microscopy images using deep learning.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.image_path = null

// Processes
process SEGMENT_CELLS_WITH_DEEP_LEARNING {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(image_path)

    output:
    path("segment_cells_with_deep_learning_output.txt"), emit: output

    script:
    """
    # Tool: biomni_microbiology_segment_cells_with_deep_learning
    # Runs in unified Docker container
    echo 'Running SEGMENT_CELLS_WITH_DEEP_LEARNING'
        touch segment_cells_with_deep_learning_output.txt
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

workflow BIOMNI_MICROBIOLOGY_SEGMENT_CELLS_WITH_DEEP_LEARNING {
    main:
    ch_image_path = Channel.fromPath(params.image_path)

    SEGMENT_CELLS_WITH_DEEP_LEARNING(ch_image_path)
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_MICROBIOLOGY_SEGMENT_CELLS_WITH_DEEP_LEARNING()
}