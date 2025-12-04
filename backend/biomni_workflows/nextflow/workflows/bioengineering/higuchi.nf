#!/usr/bin/env nextflow
/*
 * biomni_bioengineering_higuchi
 * 
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process STEP_1__NP_SQRT {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("step_1__np_sqrt_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_sqrt
    # Runs in unified Docker container
    echo 'Running STEP_1__NP_SQRT'
        touch step_1__np_sqrt_output.txt
    """
}

workflow BIOMNI_BIOENGINEERING_HIGUCHI {
    main:

    STEP_1__NP_SQRT()

    emit:
    output = STEP_1__NP_SQRT.out.output
}

workflow {
    BIOMNI_BIOENGINEERING_HIGUCHI()
}