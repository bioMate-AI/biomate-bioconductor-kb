#!/usr/bin/env nextflow
/*
 * biomni_physiology_analyze_hemodynamic_data
 * Analyzes raw blood pressure data to calculate key hemodynamic parameters.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.pressure_data = null
params.sampling_rate = null

// Processes
process STEP_1__SIGNAL_BUTTER {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_1__signal_butter_output.txt"), emit: output

    script:
    """
    # Tool: python_scipy_signal_butter
    # Runs in unified Docker container
    echo 'Running STEP_1__SIGNAL_BUTTER'
        touch step_1__signal_butter_output.txt
    """
}

process STEP_2__SIGNAL_FILTFILT {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_2__signal_filtfilt_output.txt"), emit: output

    script:
    """
    # Tool: python_scipy_signal_filtfilt
    # Runs in unified Docker container
    echo 'Running STEP_2__SIGNAL_FILTFILT'
        touch step_2__signal_filtfilt_output.txt
    """
}

process STEP_3__SIGNAL_FIND_PEAKS {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_3__signal_find_peaks_output.txt"), emit: output

    script:
    """
    # Tool: python_scipy_signal_find_peaks
    # Runs in unified Docker container
    echo 'Running STEP_3__SIGNAL_FIND_PEAKS'
        touch step_3__signal_find_peaks_output.txt
    """
}

process STEP_4__NP_ARGMIN {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_4__np_argmin_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_argmin
    # Runs in unified Docker container
    echo 'Running STEP_4__NP_ARGMIN'
        touch step_4__np_argmin_output.txt
    """
}

process STEP_5__NP_DIFF {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_5__np_diff_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_diff
    # Runs in unified Docker container
    echo 'Running STEP_5__NP_DIFF'
        touch step_5__np_diff_output.txt
    """
}

workflow BIOMNI_PHYSIOLOGY_ANALYZE_HEMODYNAMIC_DATA {
    main:
    ch_pressure_data = Channel.value(params.pressure_data)
    ch_sampling_rate = Channel.value(params.sampling_rate)

    STEP_1__SIGNAL_BUTTER(ch_sampling_rate)
    STEP_2__SIGNAL_FILTFILT(STEP_1__SIGNAL_BUTTER.out.output)
    STEP_3__SIGNAL_FIND_PEAKS(STEP_2__SIGNAL_FILTFILT.out.output)
    STEP_4__NP_ARGMIN(STEP_3__SIGNAL_FIND_PEAKS.out.output)
    STEP_5__NP_DIFF(STEP_4__NP_ARGMIN.out.output)

    emit:
    output = STEP_5__NP_DIFF.out.output
}

workflow {
    BIOMNI_PHYSIOLOGY_ANALYZE_HEMODYNAMIC_DATA()
}