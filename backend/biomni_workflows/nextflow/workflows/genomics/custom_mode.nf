#!/usr/bin/env nextflow
/*
 * biomni_genomics_custom_mode
 * 
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process STEP_1__NP_UNIQUE {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("step_1__np_unique_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_unique
    # Runs in unified Docker container
    echo 'Running STEP_1__NP_UNIQUE'
        touch step_1__np_unique_output.txt
    """
}

process STEP_2__NP_ARGMAX {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_2__np_argmax_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_argmax
    # Runs in unified Docker container
    echo 'Running STEP_2__NP_ARGMAX'
        touch step_2__np_argmax_output.txt
    """
}

workflow BIOMNI_GENOMICS_CUSTOM_MODE {
    main:

    STEP_1__NP_UNIQUE()
    STEP_2__NP_ARGMAX(STEP_1__NP_UNIQUE.out.output)

    emit:
    output = STEP_2__NP_ARGMAX.out.output
}

workflow {
    BIOMNI_GENOMICS_CUSTOM_MODE()
}