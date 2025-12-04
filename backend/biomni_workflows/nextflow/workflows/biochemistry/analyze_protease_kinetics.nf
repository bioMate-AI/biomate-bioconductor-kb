#!/usr/bin/env nextflow
/*
 * biomni_biochemistry_analyze_protease_kinetics
 * Analyze protease kinetics data from fluorogenic peptide cleavage assays, fit the data to Michaelis-Menten kinetics, and determine key kinetic parameters.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.time_points = null
params.fluorescence_data = null
params.substrate_concentrations = null
params.enzyme_concentration = null

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

process STEP_2__NP_POLYFIT {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_2__np_polyfit_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_polyfit
    # Runs in unified Docker container
    echo 'Running STEP_2__NP_POLYFIT'
        touch step_2__np_polyfit_output.txt
    """
}

workflow BIOMNI_BIOCHEMISTRY_ANALYZE_PROTEASE_KINETICS {
    main:
    ch_time_points = Channel.value(params.time_points)
    ch_fluorescence_data = Channel.value(params.fluorescence_data)
    ch_substrate_concentrations = Channel.value(params.substrate_concentrations)
    ch_enzyme_concentration = Channel.value(params.enzyme_concentration)

    STEP_1__NP_ZEROS(ch_enzyme_concentration)
    STEP_2__NP_POLYFIT(STEP_1__NP_ZEROS.out.output)

    emit:
    output = STEP_2__NP_POLYFIT.out.output
}

workflow {
    BIOMNI_BIOCHEMISTRY_ANALYZE_PROTEASE_KINETICS()
}