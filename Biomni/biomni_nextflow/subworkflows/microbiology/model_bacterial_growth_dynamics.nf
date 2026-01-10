#!/usr/bin/env nextflow
/*
 * biomni_microbiology_model_bacterial_growth_dynamics
 * Model bacterial population dynamics over time using ordinary differential equations.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process MODEL_BACTERIAL_GROWTH_DYNAMICS {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("model_bacterial_growth_dynamics_output.txt"), emit: output

    script:
    """
    # Tool: biomni_microbiology_model_bacterial_growth_dynamics
    # Runs in unified Docker container
    echo 'Running MODEL_BACTERIAL_GROWTH_DYNAMICS'
        touch model_bacterial_growth_dynamics_output.txt
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

workflow BIOMNI_MICROBIOLOGY_MODEL_BACTERIAL_GROWTH_DYNAMICS {
    main:

    MODEL_BACTERIAL_GROWTH_DYNAMICS()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_MICROBIOLOGY_MODEL_BACTERIAL_GROWTH_DYNAMICS()
}