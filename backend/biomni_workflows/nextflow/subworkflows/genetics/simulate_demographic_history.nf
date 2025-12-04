#!/usr/bin/env nextflow
/*
 * biomni_genetics_simulate_demographic_history
 * Simulate DNA sequences with specified demographic and coalescent histories using msprime.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.output_file = null

// Processes
process SIMULATE_DEMOGRAPHIC_HISTORY {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(output_file)

    output:
    path("simulate_demographic_history_output.txt"), emit: output

    script:
    """
    # Tool: biomni_genetics_simulate_demographic_history
    # Runs in unified Docker container
    echo 'Running SIMULATE_DEMOGRAPHIC_HISTORY'
        touch simulate_demographic_history_output.txt
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

workflow BIOMNI_GENETICS_SIMULATE_DEMOGRAPHIC_HISTORY {
    main:
    ch_output_file = Channel.fromPath(params.output_file)

    SIMULATE_DEMOGRAPHIC_HISTORY(ch_output_file)
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_GENETICS_SIMULATE_DEMOGRAPHIC_HISTORY()
}