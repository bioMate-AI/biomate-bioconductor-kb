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
params.markers_list = null

// Processes
process STEP_1__IO_IMREAD {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_1__io_imread_output.txt"), emit: output

    script:
    """
    # Tool: python_skimage_io_imread
    # Runs in unified Docker container
    echo 'Running STEP_1__IO_IMREAD'
        touch step_1__io_imread_output.txt
    """
}

process STEP_2__IO_IMSAVE {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_2__io_imsave_output.txt"), emit: output

    script:
    """
    # Tool: python_skimage_io_imsave
    # Runs in unified Docker container
    echo 'Running STEP_2__IO_IMSAVE'
        touch step_2__io_imsave_output.txt
    """
}

process STEP_3__MEASURE_REGIONPROPS {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_3__measure_regionprops_output.txt"), emit: output

    script:
    """
    # Tool: python_skimage_measure_regionprops
    # Runs in unified Docker container
    echo 'Running STEP_3__MEASURE_REGIONPROPS'
        touch step_3__measure_regionprops_output.txt
    """
}

process STEP_4__MEASURE_LABEL {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_4__measure_label_output.txt"), emit: output

    script:
    """
    # Tool: python_skimage_measure_label
    # Runs in unified Docker container
    echo 'Running STEP_4__MEASURE_LABEL'
        touch step_4__measure_label_output.txt
    """
}

process STEP_5__SEGMENTATION_WATERSHED {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_5__segmentation_watershed_output.txt"), emit: output

    script:
    """
    # Tool: python_skimage_segmentation_watershed
    # Runs in unified Docker container
    echo 'Running STEP_5__SEGMENTATION_WATERSHED'
        touch step_5__segmentation_watershed_output.txt
    """
}

workflow BIOMNI_PATHOLOGY_SEGMENT_AND_QUANTIFY_CELLS_IN_MULTIPLEXED_IMAGES {
    main:
    ch_image_path = Channel.value(params.image_path)
    ch_markers_list = Channel.value(params.markers_list)

    STEP_1__IO_IMREAD(ch_markers_list)
    STEP_2__IO_IMSAVE(STEP_1__IO_IMREAD.out.output)
    STEP_3__MEASURE_REGIONPROPS(STEP_2__IO_IMSAVE.out.output)
    STEP_4__MEASURE_LABEL(STEP_3__MEASURE_REGIONPROPS.out.output)
    STEP_5__SEGMENTATION_WATERSHED(STEP_4__MEASURE_LABEL.out.output)

    emit:
    output = STEP_5__SEGMENTATION_WATERSHED.out.output
}

workflow {
    BIOMNI_PATHOLOGY_SEGMENT_AND_QUANTIFY_CELLS_IN_MULTIPLEXED_IMAGES()
}