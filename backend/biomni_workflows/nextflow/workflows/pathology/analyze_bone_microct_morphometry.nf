#!/usr/bin/env nextflow
/*
 * biomni_pathology_analyze_bone_microct_morphometry
 * Analyze bone microarchitecture parameters from 3D micro-CT images to calculate bone mineral density, bone volume, trabecular number, thickness, and separation.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.input_file_path = null

// Processes
process STEP_1__FILTERS_THRESHOLD_OTSU {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_1__filters_threshold_otsu_output.txt"), emit: output

    script:
    """
    # Tool: python_skimage_filters_threshold_otsu
    # Runs in unified Docker container
    echo 'Running STEP_1__FILTERS_THRESHOLD_OTSU'
        touch step_1__filters_threshold_otsu_output.txt
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

process STEP_4__NP_SUM {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_4__np_sum_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_sum
    # Runs in unified Docker container
    echo 'Running STEP_4__NP_SUM'
        touch step_4__np_sum_output.txt
    """
}

process STEP_5__NP_MEAN {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_5__np_mean_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_mean
    # Runs in unified Docker container
    echo 'Running STEP_5__NP_MEAN'
        touch step_5__np_mean_output.txt
    """
}

workflow BIOMNI_PATHOLOGY_ANALYZE_BONE_MICROCT_MORPHOMETRY {
    main:
    ch_input_file_path = Channel.value(params.input_file_path)

    STEP_1__FILTERS_THRESHOLD_OTSU(ch_input_file_path)
    STEP_2__IO_IMREAD(STEP_1__FILTERS_THRESHOLD_OTSU.out.output)
    STEP_3__IO_IMSAVE(STEP_2__IO_IMREAD.out.output)
    STEP_4__NP_SUM(STEP_3__IO_IMSAVE.out.output)
    STEP_5__NP_MEAN(STEP_4__NP_SUM.out.output)

    emit:
    output = STEP_5__NP_MEAN.out.output
}

workflow {
    BIOMNI_PATHOLOGY_ANALYZE_BONE_MICROCT_MORPHOMETRY()
}