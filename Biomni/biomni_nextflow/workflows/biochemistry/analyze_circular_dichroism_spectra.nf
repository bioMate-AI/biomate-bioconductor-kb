#!/usr/bin/env nextflow
/*
 * biomni_biochemistry_analyze_circular_dichroism_spectra
 * Analyzes circular dichroism (CD) spectroscopy data to determine secondary structure and thermal stability.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.sample_name = null
params.sample_type = null
params.wavelength_data = null
params.cd_signal_data = null

// Processes
process STEP_1__NP_ARRAY {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_1__np_array_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_array
    # Runs in unified Docker container
    echo 'Running STEP_1__NP_ARRAY'
        touch step_1__np_array_output.txt
    """
}

process STEP_2__NP_ABS {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_2__np_abs_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_abs
    # Runs in unified Docker container
    echo 'Running STEP_2__NP_ABS'
        touch step_2__np_abs_output.txt
    """
}

process STEP_3__NP_ARGMIN {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_3__np_argmin_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_argmin
    # Runs in unified Docker container
    echo 'Running STEP_3__NP_ARGMIN'
        touch step_3__np_argmin_output.txt
    """
}

process STEP_4__NP_SUM {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_4__np_sum_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_sum
    # Runs in unified Docker container
    echo 'Running STEP_4__NP_SUM'
        touch step_4__np_sum_output.txt
    """
}

process STEP_5__NP_MIN {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_5__np_min_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_min
    # Runs in unified Docker container
    echo 'Running STEP_5__NP_MIN'
        touch step_5__np_min_output.txt
    """
}

workflow BIOMNI_BIOCHEMISTRY_ANALYZE_CIRCULAR_DICHROISM_SPECTRA {
    main:
    ch_sample_name = Channel.value(params.sample_name)
    ch_sample_type = Channel.value(params.sample_type)
    ch_wavelength_data = Channel.value(params.wavelength_data)
    ch_cd_signal_data = Channel.value(params.cd_signal_data)

    STEP_1__NP_ARRAY(ch_cd_signal_data)
    STEP_2__NP_ABS(STEP_1__NP_ARRAY.out.output)
    STEP_3__NP_ARGMIN(STEP_2__NP_ABS.out.output)
    STEP_4__NP_SUM(STEP_3__NP_ARGMIN.out.output)
    STEP_5__NP_MIN(STEP_4__NP_SUM.out.output)

    emit:
    output = STEP_5__NP_MIN.out.output
}

workflow {
    BIOMNI_BIOCHEMISTRY_ANALYZE_CIRCULAR_DICHROISM_SPECTRA()
}