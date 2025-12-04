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
process MONO_EXP_MODEL {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("mono_exp_model_output.txt"), emit: output

    script:
    """
    # Tool: biomni_physiology_mono_exp_model
    # Runs in unified Docker container
    echo 'Running MONO_EXP_MODEL'
        touch mono_exp_model_output.txt
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

workflow BIOMNI_PHYSIOLOGY_MONO_EXP_MODEL {
    main:

    MONO_EXP_MODEL()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_PHYSIOLOGY_MONO_EXP_MODEL()
}