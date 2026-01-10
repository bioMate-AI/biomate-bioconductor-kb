#!/usr/bin/env nextflow
/*
 * biomni_physiology_reconstruct_3d_face_from_mri
 * Generate a 3D model of facial anatomy from MRI scans of the head and neck.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.mri_file_path = null

// Processes
process STEP_1__NP_MIN {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_1__np_min_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_min
    # Runs in unified Docker container
    echo 'Running STEP_1__NP_MIN'
        touch step_1__np_min_output.txt
    """
}

process STEP_2__NP_MAX {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_2__np_max_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_max
    # Runs in unified Docker container
    echo 'Running STEP_2__NP_MAX'
        touch step_2__np_max_output.txt
    """
}

process STEP_3__MEASURE_MARCHING_CUBES {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_3__measure_marching_cubes_output.txt"), emit: output

    script:
    """
    # Tool: python_skimage_measure_marching_cubes
    # Runs in unified Docker container
    echo 'Running STEP_3__MEASURE_MARCHING_CUBES'
        touch step_3__measure_marching_cubes_output.txt
    """
}

workflow BIOMNI_PHYSIOLOGY_RECONSTRUCT_3D_FACE_FROM_MRI {
    main:
    ch_mri_file_path = Channel.value(params.mri_file_path)

    STEP_1__NP_MIN(ch_mri_file_path)
    STEP_2__NP_MAX(STEP_1__NP_MIN.out.output)
    STEP_3__MEASURE_MARCHING_CUBES(STEP_2__NP_MAX.out.output)

    emit:
    output = STEP_3__MEASURE_MARCHING_CUBES.out.output
}

workflow {
    BIOMNI_PHYSIOLOGY_RECONSTRUCT_3D_FACE_FROM_MRI()
}