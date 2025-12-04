#!/usr/bin/env nextflow
/*
 * biomni_physiology_pk_ode_system
 * 
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process STEP_1__NP_ZEROS_LIKE {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("step_1__np_zeros_like_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_zeros_like
    # Runs in unified Docker container
    echo 'Running STEP_1__NP_ZEROS_LIKE'
        touch step_1__np_zeros_like_output.txt
    """
}

workflow BIOMNI_PHYSIOLOGY_PK_ODE_SYSTEM {
    main:

    STEP_1__NP_ZEROS_LIKE()

    emit:
    output = STEP_1__NP_ZEROS_LIKE.out.output
}

workflow {
    BIOMNI_PHYSIOLOGY_PK_ODE_SYSTEM()
}