#!/usr/bin/env nextflow
/*
 * biomni_systems_biology_simulate_metabolic_network_perturbation
 * Construct and simulate kinetic models of metabolic networks and analyze their responses to perturbations.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.model_file = null
params.initial_concentrations = null
params.perturbation_params = null

// Processes
process STEP_1__COBRA_IO_READ_SBML_MODEL {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_1__cobra_io_read_sbml_model_output.txt"), emit: output

    script:
    """
    # Tool: python_cobra_cobra_io_read_sbml_model
    # Runs in unified Docker container
    echo 'Running STEP_1__COBRA_IO_READ_SBML_MODEL'
        touch step_1__cobra_io_read_sbml_model_output.txt
    """
}

process STEP_2__NP_ONES {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_2__np_ones_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_ones
    # Runs in unified Docker container
    echo 'Running STEP_2__NP_ONES'
        touch step_2__np_ones_output.txt
    """
}

workflow BIOMNI_SYSTEMS_BIOLOGY_SIMULATE_METABOLIC_NETWORK_PERTURBATION {
    main:
    ch_model_file = Channel.value(params.model_file)
    ch_initial_concentrations = Channel.value(params.initial_concentrations)
    ch_perturbation_params = Channel.value(params.perturbation_params)

    STEP_1__COBRA_IO_READ_SBML_MODEL(ch_perturbation_params)
    STEP_2__NP_ONES(STEP_1__COBRA_IO_READ_SBML_MODEL.out.output)

    emit:
    output = STEP_2__NP_ONES.out.output
}

workflow {
    BIOMNI_SYSTEMS_BIOLOGY_SIMULATE_METABOLIC_NETWORK_PERTURBATION()
}