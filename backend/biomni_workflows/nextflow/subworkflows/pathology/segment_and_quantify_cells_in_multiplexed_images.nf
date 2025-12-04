#!/usr/bin/env nextflow
/*
 * biomni_pathology_segment_and_quantify_cells_in_multiplexed_images
 * Segment cells and quantify protein expression levels from multichannel tissue images.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.image_path = null

// Processes
process SEGMENT_AND_QUANTIFY_CELLS_IN_MULTIPLEXED_IMAGES {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(image_path)

    output:
    path("segment_and_quantify_cells_in_multiplexed_images_output.txt"), emit: output

    script:
    """
    # Tool: biomni_pathology_segment_and_quantify_cells_in_multiplexed_images
    # Runs in unified Docker container
    echo 'Running SEGMENT_AND_QUANTIFY_CELLS_IN_MULTIPLEXED_IMAGES'
        touch segment_and_quantify_cells_in_multiplexed_images_output.txt
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

workflow BIOMNI_PATHOLOGY_SEGMENT_AND_QUANTIFY_CELLS_IN_MULTIPLEXED_IMAGES {
    main:
    ch_image_path = Channel.fromPath(params.image_path)

    SEGMENT_AND_QUANTIFY_CELLS_IN_MULTIPLEXED_IMAGES(ch_image_path)
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_PATHOLOGY_SEGMENT_AND_QUANTIFY_CELLS_IN_MULTIPLEXED_IMAGES()
}