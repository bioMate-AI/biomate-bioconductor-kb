#!/usr/bin/env nextflow
/*
 * biomni_systems_biology_ode_system
 * 
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process STEP_1__NP_ZEROS {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("step_1__np_zeros_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_zeros
    # Runs in unified Docker container
    echo 'Running STEP_1__NP_ZEROS'
        touch step_1__np_zeros_output.txt
    """
}

process STEP_2__NP_ZEROS_LIKE {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_2__np_zeros_like_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_zeros_like
    # Runs in unified Docker container
    echo 'Running STEP_2__NP_ZEROS_LIKE'
        touch step_2__np_zeros_like_output.txt
    """
}

workflow BIOMNI_SYSTEMS_BIOLOGY_ODE_SYSTEM {
    main:

    STEP_1__NP_ZEROS()
    STEP_2__NP_ZEROS_LIKE(STEP_1__NP_ZEROS.out.output)

    emit:
    output = STEP_2__NP_ZEROS_LIKE.out.output
}

workflow {
    BIOMNI_SYSTEMS_BIOLOGY_ODE_SYSTEM()
}