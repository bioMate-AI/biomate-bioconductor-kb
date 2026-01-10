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
process OBJECTIVE_FUNCTION {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("objective_function_output.txt"), emit: output

    script:
    """
    # Tool: biomni_immunology_objective_function
    # Runs in unified Docker container
    echo 'Running OBJECTIVE_FUNCTION'
        touch objective_function_output.txt
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

workflow BIOMNI_IMMUNOLOGY_OBJECTIVE_FUNCTION {
    main:

    OBJECTIVE_FUNCTION()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_IMMUNOLOGY_OBJECTIVE_FUNCTION()
}