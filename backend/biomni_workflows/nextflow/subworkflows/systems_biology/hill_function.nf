#!/usr/bin/env nextflow
/*
 * biomni_systems_biology_hill_function
 * 
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process HILL_FUNCTION {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("hill_function_output.txt"), emit: output

    script:
    """
    # Tool: biomni_systems_biology_hill_function
    # Runs in unified Docker container
    echo 'Running HILL_FUNCTION'
        touch hill_function_output.txt
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

workflow BIOMNI_SYSTEMS_BIOLOGY_HILL_FUNCTION {
    main:

    HILL_FUNCTION()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_SYSTEMS_BIOLOGY_HILL_FUNCTION()
}