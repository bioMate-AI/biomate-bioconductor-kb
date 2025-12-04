#!/usr/bin/env nextflow
/*
 * biomni_physiology_cosinor_model
 * 
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process STEP_1__NP_COS {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("step_1__np_cos_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_cos
    # Runs in unified Docker container
    echo 'Running STEP_1__NP_COS'
        touch step_1__np_cos_output.txt
    """
}

workflow BIOMNI_PHYSIOLOGY_COSINOR_MODEL {
    main:

    STEP_1__NP_COS()

    emit:
    output = STEP_1__NP_COS.out.output
}

workflow {
    BIOMNI_PHYSIOLOGY_COSINOR_MODEL()
}