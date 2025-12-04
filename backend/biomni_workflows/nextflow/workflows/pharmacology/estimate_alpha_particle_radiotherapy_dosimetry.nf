#!/usr/bin/env nextflow
/*
 * biomni_pharmacology_estimate_alpha_particle_radiotherapy_dosimetry
 * Estimate radiation absorbed doses to tumor and normal organs for alpha-particle radiotherapeutics using the Medical Internal Radiation Dose (MIRD) schema.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.biodistribution_data = null
params.radiation_parameters = null

// Processes
process STEP_1__NP_LOG {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_1__np_log_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_log
    # Runs in unified Docker container
    echo 'Running STEP_1__NP_LOG'
        touch step_1__np_log_output.txt
    """
}

process STEP_2__NP_EXP {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_2__np_exp_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_exp
    # Runs in unified Docker container
    echo 'Running STEP_2__NP_EXP'
        touch step_2__np_exp_output.txt
    """
}

process STEP_3__TRAPEZOID {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_3__trapezoid_output.txt"), emit: output

    script:
    """
    # Tool: python_scipy_trapezoid
    # Runs in unified Docker container
    echo 'Running STEP_3__TRAPEZOID'
        touch step_3__trapezoid_output.txt
    """
}

workflow BIOMNI_PHARMACOLOGY_ESTIMATE_ALPHA_PARTICLE_RADIOTHERAPY_DOSIMETRY {
    main:
    ch_biodistribution_data = Channel.value(params.biodistribution_data)
    ch_radiation_parameters = Channel.value(params.radiation_parameters)

    STEP_1__NP_LOG(ch_radiation_parameters)
    STEP_2__NP_EXP(STEP_1__NP_LOG.out.output)
    STEP_3__TRAPEZOID(STEP_2__NP_EXP.out.output)

    emit:
    output = STEP_3__TRAPEZOID.out.output
}

workflow {
    BIOMNI_PHARMACOLOGY_ESTIMATE_ALPHA_PARTICLE_RADIOTHERAPY_DOSIMETRY()
}