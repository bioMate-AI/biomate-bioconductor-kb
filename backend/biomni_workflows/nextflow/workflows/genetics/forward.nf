#!/usr/bin/env nextflow
/*
 * biomni_genetics_forward
 * 
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process STEP_1__TORCH_SIGMOID {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("step_1__torch_sigmoid_output.txt"), emit: output

    script:
    """
    # Tool: python_torch_torch_sigmoid
    # Runs in unified Docker container
    echo 'Running STEP_1__TORCH_SIGMOID'
        touch step_1__torch_sigmoid_output.txt
    """
}

workflow BIOMNI_GENETICS_FORWARD {
    main:

    STEP_1__TORCH_SIGMOID()

    emit:
    output = STEP_1__TORCH_SIGMOID.out.output
}

workflow {
    BIOMNI_GENETICS_FORWARD()
}