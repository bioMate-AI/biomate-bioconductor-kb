#!/usr/bin/env nextflow
/*
 * biomni_bioengineering_simulate_whole_cell_ode_model
 * Simulate a whole-cell model represented as a system of ordinary differential equations (ODEs).
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process SIMULATE_WHOLE_CELL_ODE_MODEL {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("simulate_whole_cell_ode_model_output.txt"), emit: output

    script:
    """
    # Tool: biomni_bioengineering_simulate_whole_cell_ode_model
    # Runs in unified Docker container
    echo 'Running SIMULATE_WHOLE_CELL_ODE_MODEL'
        touch simulate_whole_cell_ode_model_output.txt
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

workflow BIOMNI_BIOENGINEERING_SIMULATE_WHOLE_CELL_ODE_MODEL {
    main:

    SIMULATE_WHOLE_CELL_ODE_MODEL()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_BIOENGINEERING_SIMULATE_WHOLE_CELL_ODE_MODEL()
}