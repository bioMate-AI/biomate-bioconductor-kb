#!/usr/bin/env nextflow
/*
 * biomni_pathology_quantify_corneal_nerve_fibers
 * Quantify the volume/density of immunofluorescence-labeled corneal nerve fibers.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.image_path = null
params.marker_type = null

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

process STEP_3__RGB2GRAY {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_3__rgb2gray_output.txt"), emit: output

    script:
    """
    # Tool: python_skimage_rgb2gray
    # Runs in unified Docker container
    echo 'Running STEP_3__RGB2GRAY'
        touch step_3__rgb2gray_output.txt
    """
}

process STEP_4__MEASURE_REGIONPROPS {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_4__measure_regionprops_output.txt"), emit: output

    script:
    """
    # Tool: python_skimage_measure_regionprops
    # Runs in unified Docker container
    echo 'Running STEP_4__MEASURE_REGIONPROPS'
        touch step_4__measure_regionprops_output.txt
    """
}

process STEP_5__MEASURE_LABEL {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_5__measure_label_output.txt"), emit: output

    script:
    """
    # Tool: python_skimage_measure_label
    # Runs in unified Docker container
    echo 'Running STEP_5__MEASURE_LABEL'
        touch step_5__measure_label_output.txt
    """
}

workflow BIOMNI_PATHOLOGY_QUANTIFY_CORNEAL_NERVE_FIBERS {
    main:
    ch_image_path = Channel.value(params.image_path)
    ch_marker_type = Channel.value(params.marker_type)

    STEP_1__IO_IMREAD(ch_marker_type)
    STEP_2__IO_IMSAVE(STEP_1__IO_IMREAD.out.output)
    STEP_3__RGB2GRAY(STEP_2__IO_IMSAVE.out.output)
    STEP_4__MEASURE_REGIONPROPS(STEP_3__RGB2GRAY.out.output)
    STEP_5__MEASURE_LABEL(STEP_4__MEASURE_REGIONPROPS.out.output)

    emit:
    output = STEP_5__MEASURE_LABEL.out.output
}

workflow {
    BIOMNI_PATHOLOGY_QUANTIFY_CORNEAL_NERVE_FIBERS()
}