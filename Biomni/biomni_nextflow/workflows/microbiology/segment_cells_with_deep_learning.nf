#!/usr/bin/env nextflow
/*
 * biomni_microbiology_segment_cells_with_deep_learning
 * Perform cell segmentation on fluorescence microscopy images using deep learning with pre-trained models from the Cellpose/Omnipose library.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.image_path = null

// Processes
process STEP_1__FIND_BOUNDARIES {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_1__find_boundaries_output.txt"), emit: output

    script:
    """
    # Tool: python_skimage_find_boundaries
    # Runs in unified Docker container
    echo 'Running STEP_1__FIND_BOUNDARIES'
        touch step_1__find_boundaries_output.txt
    """
}

process STEP_2__IO_IMREAD {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_2__io_imread_output.txt"), emit: output

    script:
    """
    # Tool: python_skimage_io_imread
    # Runs in unified Docker container
    echo 'Running STEP_2__IO_IMREAD'
        touch step_2__io_imread_output.txt
    """
}

process STEP_3__IO_IMSAVE {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_3__io_imsave_output.txt"), emit: output

    script:
    """
    # Tool: python_skimage_io_imsave
    # Runs in unified Docker container
    echo 'Running STEP_3__IO_IMSAVE'
        touch step_3__io_imsave_output.txt
    """
}

process STEP_4__NP_STD {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_4__np_std_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_std
    # Runs in unified Docker container
    echo 'Running STEP_4__NP_STD'
        touch step_4__np_std_output.txt
    """
}

process STEP_5__NP_SUM {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_5__np_sum_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_sum
    # Runs in unified Docker container
    echo 'Running STEP_5__NP_SUM'
        touch step_5__np_sum_output.txt
    """
}

workflow BIOMNI_MICROBIOLOGY_SEGMENT_CELLS_WITH_DEEP_LEARNING {
    main:
    ch_image_path = Channel.value(params.image_path)

    STEP_1__FIND_BOUNDARIES(ch_image_path)
    STEP_2__IO_IMREAD(STEP_1__FIND_BOUNDARIES.out.output)
    STEP_3__IO_IMSAVE(STEP_2__IO_IMREAD.out.output)
    STEP_4__NP_STD(STEP_3__IO_IMSAVE.out.output)
    STEP_5__NP_SUM(STEP_4__NP_STD.out.output)

    emit:
    output = STEP_5__NP_SUM.out.output
}

workflow {
    BIOMNI_MICROBIOLOGY_SEGMENT_CELLS_WITH_DEEP_LEARNING()
}