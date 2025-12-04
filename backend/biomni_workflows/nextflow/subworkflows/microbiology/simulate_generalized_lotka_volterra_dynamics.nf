#!/usr/bin/env nextflow
/*
 * biomni_microbiology_simulate_generalized_lotka_volterra_dynamics
 * Simulate microbial community dynamics using the Generalized Lotka-Volterra (gLV) model.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.output_file = null

// Processes
process SIMULATE_GENERALIZED_LOTKA_VOLTERRA_DYNAMICS {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(output_file)

    output:
    path("simulate_generalized_lotka_volterra_dynamics_output.txt"), emit: output

    script:
    """
    # Tool: biomni_microbiology_simulate_generalized_lotka_volterra_dynamics
    # Runs in unified Docker container
    echo 'Running SIMULATE_GENERALIZED_LOTKA_VOLTERRA_DYNAMICS'
        touch simulate_generalized_lotka_volterra_dynamics_output.txt
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

workflow BIOMNI_MICROBIOLOGY_SIMULATE_GENERALIZED_LOTKA_VOLTERRA_DYNAMICS {
    main:
    ch_output_file = Channel.fromPath(params.output_file)

    SIMULATE_GENERALIZED_LOTKA_VOLTERRA_DYNAMICS(ch_output_file)
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_MICROBIOLOGY_SIMULATE_GENERALIZED_LOTKA_VOLTERRA_DYNAMICS()
}