#!/usr/bin/env nextflow
/*
 * biomni_systems_biology_model_protein_dimerization_network
 * Model protein dimerization networks to find equilibrium concentrations of dimers.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.monomer_concentrations = null
params.dimerization_affinities = null
params.network_topology = null

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

workflow BIOMNI_SYSTEMS_BIOLOGY_MODEL_PROTEIN_DIMERIZATION_NETWORK {
    main:
    ch_monomer_concentrations = Channel.value(params.monomer_concentrations)
    ch_dimerization_affinities = Channel.value(params.dimerization_affinities)
    ch_network_topology = Channel.value(params.network_topology)

    STEP_1__NP_ZEROS(ch_network_topology)

    emit:
    output = STEP_1__NP_ZEROS.out.output
}

workflow {
    BIOMNI_SYSTEMS_BIOLOGY_MODEL_PROTEIN_DIMERIZATION_NETWORK()
}