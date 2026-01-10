#!/usr/bin/env nextflow
/*
 * biomni_synthetic_biology_gompertz_model
 * Gompertz growth model.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process GOMPERTZ_MODEL {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("gompertz_model_output.txt"), emit: output

    script:
    """
    # Tool: biomni_synthetic_biology_gompertz_model
    # Runs in unified Docker container
    echo 'Running GOMPERTZ_MODEL'
        touch gompertz_model_output.txt
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

workflow BIOMNI_SYNTHETIC_BIOLOGY_GOMPERTZ_MODEL {
    main:

    GOMPERTZ_MODEL()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_SYNTHETIC_BIOLOGY_GOMPERTZ_MODEL()
}