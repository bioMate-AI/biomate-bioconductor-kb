#!/usr/bin/env nextflow
/*
 * biomni_microbiology_glv_equations
 * 
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process STEP_1__NP_DOT {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("step_1__np_dot_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_dot
    # Runs in unified Docker container
    echo 'Running STEP_1__NP_DOT'
        touch step_1__np_dot_output.txt
    """
}

workflow BIOMNI_MICROBIOLOGY_GLV_EQUATIONS {
    main:

    STEP_1__NP_DOT()

    emit:
    output = STEP_1__NP_DOT.out.output
}

workflow {
    BIOMNI_MICROBIOLOGY_GLV_EQUATIONS()
}