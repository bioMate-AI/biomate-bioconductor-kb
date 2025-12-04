#!/usr/bin/env nextflow
/*
 * biomni_biochemistry_one_site_model
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

workflow BIOMNI_BIOCHEMISTRY_ONE_SITE_MODEL {
    main:

    STEP_1__NP_ZEROS_LIKE()

    emit:
    output = STEP_1__NP_ZEROS_LIKE.out.output
}

workflow {
    BIOMNI_BIOCHEMISTRY_ONE_SITE_MODEL()
}