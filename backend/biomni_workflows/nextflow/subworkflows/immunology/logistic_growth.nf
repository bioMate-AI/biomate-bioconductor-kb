#!/usr/bin/env nextflow
/*
 * biomni_immunology_logistic_growth
 * Logistic growth model: N(t) = K / (1 + ((K - N0) / N0) * exp(-r*t)).
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process LOGISTIC_GROWTH {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("logistic_growth_output.txt"), emit: output

    script:
    """
    # Tool: biomni_immunology_logistic_growth
    # Runs in unified Docker container
    echo 'Running LOGISTIC_GROWTH'
        touch logistic_growth_output.txt
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

workflow BIOMNI_IMMUNOLOGY_LOGISTIC_GROWTH {
    main:

    LOGISTIC_GROWTH()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_IMMUNOLOGY_LOGISTIC_GROWTH()
}