#!/usr/bin/env nextflow
/*
 * biomni_physiology_mono_exp_model
 * 
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process STEP_1__NP_EXP {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("step_1__np_exp_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_exp
    # Runs in unified Docker container
    echo 'Running STEP_1__NP_EXP'
        touch step_1__np_exp_output.txt
    """
}

workflow BIOMNI_PHYSIOLOGY_MONO_EXP_MODEL {
    main:

    STEP_1__NP_EXP()

    emit:
    output = STEP_1__NP_EXP.out.output
}

workflow {
    BIOMNI_PHYSIOLOGY_MONO_EXP_MODEL()
}