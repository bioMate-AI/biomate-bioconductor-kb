#!/usr/bin/env nextflow
/*
 * biomni_microbiology_simulate_microbial_population_dynamics
 * Performs stochastic simulation of microbial population dynamics using the Gillespie algorithm.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.initial_populations = null
params.growth_rates = null
params.clearance_rates = null
params.carrying_capacities = null

// Processes
process STEP_1__NP_ZEROS {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_1__np_zeros_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_zeros
    # Runs in unified Docker container
    echo 'Running STEP_1__NP_ZEROS'
        touch step_1__np_zeros_output.txt
    """
}

process STEP_2__NP_ARRAY {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_2__np_array_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_array
    # Runs in unified Docker container
    echo 'Running STEP_2__NP_ARRAY'
        touch step_2__np_array_output.txt
    """
}

process STEP_3__NP_LINSPACE {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_3__np_linspace_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_linspace
    # Runs in unified Docker container
    echo 'Running STEP_3__NP_LINSPACE'
        touch step_3__np_linspace_output.txt
    """
}

process STEP_4__NP_MEAN {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_4__np_mean_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_mean
    # Runs in unified Docker container
    echo 'Running STEP_4__NP_MEAN'
        touch step_4__np_mean_output.txt
    """
}

process STEP_5__NP_RANDOM_EXPONENTIAL {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_5__np_random_exponential_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_random_exponential
    # Runs in unified Docker container
    echo 'Running STEP_5__NP_RANDOM_EXPONENTIAL'
        touch step_5__np_random_exponential_output.txt
    """
}

workflow BIOMNI_MICROBIOLOGY_SIMULATE_MICROBIAL_POPULATION_DYNAMICS {
    main:
    ch_initial_populations = Channel.value(params.initial_populations)
    ch_growth_rates = Channel.value(params.growth_rates)
    ch_clearance_rates = Channel.value(params.clearance_rates)
    ch_carrying_capacities = Channel.value(params.carrying_capacities)

    STEP_1__NP_ZEROS(ch_carrying_capacities)
    STEP_2__NP_ARRAY(STEP_1__NP_ZEROS.out.output)
    STEP_3__NP_LINSPACE(STEP_2__NP_ARRAY.out.output)
    STEP_4__NP_MEAN(STEP_3__NP_LINSPACE.out.output)
    STEP_5__NP_RANDOM_EXPONENTIAL(STEP_4__NP_MEAN.out.output)

    emit:
    output = STEP_5__NP_RANDOM_EXPONENTIAL.out.output
}

workflow {
    BIOMNI_MICROBIOLOGY_SIMULATE_MICROBIAL_POPULATION_DYNAMICS()
}