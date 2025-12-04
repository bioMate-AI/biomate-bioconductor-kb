#!/usr/bin/env nextflow
/*
 * biomni_physiology_calculate_brain_adc_map
 * Calculate Apparent Diffusion Coefficient (ADC) map from diffusion-weighted MRI data using monoexponential diffusion model.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.dwi_file_path = null
params.b_values = null

// Processes
process STEP_1__NP_ARGMIN {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_1__np_argmin_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_argmin
    # Runs in unified Docker container
    echo 'Running STEP_1__NP_ARGMIN'
        touch step_1__np_argmin_output.txt
    """
}

process STEP_2__NP_SUM {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_2__np_sum_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_sum
    # Runs in unified Docker container
    echo 'Running STEP_2__NP_SUM'
        touch step_2__np_sum_output.txt
    """
}

process STEP_3__NP_MEAN {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_3__np_mean_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_mean
    # Runs in unified Docker container
    echo 'Running STEP_3__NP_MEAN'
        touch step_3__np_mean_output.txt
    """
}

workflow BIOMNI_PHYSIOLOGY_CALCULATE_BRAIN_ADC_MAP {
    main:
    ch_dwi_file_path = Channel.value(params.dwi_file_path)
    ch_b_values = Channel.value(params.b_values)

    STEP_1__NP_ARGMIN(ch_b_values)
    STEP_2__NP_SUM(STEP_1__NP_ARGMIN.out.output)
    STEP_3__NP_MEAN(STEP_2__NP_SUM.out.output)

    emit:
    output = STEP_3__NP_MEAN.out.output
}

workflow {
    BIOMNI_PHYSIOLOGY_CALCULATE_BRAIN_ADC_MAP()
}