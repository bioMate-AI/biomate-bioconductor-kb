#!/usr/bin/env nextflow
/*
 * biomni_physiology_cosinor_model
 * Cosine function with baseline (mesor), amplitude, and phase shift.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process COSINOR_MODEL {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("cosinor_model_output.txt"), emit: output

    script:
    """
    # Tool: biomni_physiology_cosinor_model
    # Runs in unified Docker container
    echo 'Running COSINOR_MODEL'
        touch cosinor_model_output.txt
    """
}

process OUTPUT {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("output_output.txt"), emit: output

    script:
    """
    # Tool: cat1
    # Runs in unified Docker container
    echo 'Running OUTPUT'
        touch output_output.txt
    """
}

workflow BIOMNI_PHYSIOLOGY_COSINOR_MODEL {
    main:

    COSINOR_MODEL()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_PHYSIOLOGY_COSINOR_MODEL()
}