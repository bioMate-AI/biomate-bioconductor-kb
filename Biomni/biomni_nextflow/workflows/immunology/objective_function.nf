#!/usr/bin/env nextflow
/*
 * biomni_immunology_objective_function
 * 
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process STEP_1__NP_SUM {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("step_1__np_sum_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_sum
    # Runs in unified Docker container
    echo 'Running STEP_1__NP_SUM'
        touch step_1__np_sum_output.txt
    """
}

process STEP_2__NP_ARRAY {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_2__np_array_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_array
    # Runs in unified Docker container
    echo 'Running STEP_2__NP_ARRAY'
        touch step_2__np_array_output.txt
    """
}

workflow BIOMNI_IMMUNOLOGY_OBJECTIVE_FUNCTION {
    main:

    STEP_1__NP_SUM()
    STEP_2__NP_ARRAY(STEP_1__NP_SUM.out.output)

    emit:
    output = STEP_2__NP_ARRAY.out.output
}

workflow {
    BIOMNI_IMMUNOLOGY_OBJECTIVE_FUNCTION()
}