#!/usr/bin/env nextflow
/*
 * biomni_systems_biology_simulate_metabolic_network_perturbation
 * 
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.model_file = null

// Processes
process SIMULATE_METABOLIC_NETWORK_PERTURBATION {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(model_file)

    output:
    path("simulate_metabolic_network_perturbation_output.txt"), emit: output

    script:
    """
    # Tool: biomni_systems_biology_simulate_metabolic_network_perturbation
    # Runs in unified Docker container
    echo 'Running SIMULATE_METABOLIC_NETWORK_PERTURBATION'
        touch simulate_metabolic_network_perturbation_output.txt
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

workflow BIOMNI_SYSTEMS_BIOLOGY_SIMULATE_METABOLIC_NETWORK_PERTURBATION {
    main:
    ch_model_file = Channel.fromPath(params.model_file)

    SIMULATE_METABOLIC_NETWORK_PERTURBATION(ch_model_file)
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_SYSTEMS_BIOLOGY_SIMULATE_METABOLIC_NETWORK_PERTURBATION()
}