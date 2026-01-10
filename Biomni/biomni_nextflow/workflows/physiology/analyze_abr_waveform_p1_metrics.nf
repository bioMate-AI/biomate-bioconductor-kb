#!/usr/bin/env nextflow
/*
 * biomni_physiology_analyze_abr_waveform_p1_metrics
 * Extracts P1 amplitude and latency from Auditory Brainstem Response (ABR) waveform data.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.time_ms = null
params.amplitude_uv = null

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

process STEP_2__NP_WHERE {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_2__np_where_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_where
    # Runs in unified Docker container
    echo 'Running STEP_2__NP_WHERE'
        touch step_2__np_where_output.txt
    """
}

process STEP_3__NP_ARGMAX {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_3__np_argmax_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_argmax
    # Runs in unified Docker container
    echo 'Running STEP_3__NP_ARGMAX'
        touch step_3__np_argmax_output.txt
    """
}

process STEP_4__FIND_PEAKS {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_4__find_peaks_output.txt"), emit: output

    script:
    """
    # Tool: python_scipy_find_peaks
    # Runs in unified Docker container
    echo 'Running STEP_4__FIND_PEAKS'
        touch step_4__find_peaks_output.txt
    """
}

workflow BIOMNI_PHYSIOLOGY_ANALYZE_ABR_WAVEFORM_P1_METRICS {
    main:
    ch_time_ms = Channel.value(params.time_ms)
    ch_amplitude_uv = Channel.value(params.amplitude_uv)

    STEP_1__NP_ARRAY(ch_amplitude_uv)
    STEP_2__NP_WHERE(STEP_1__NP_ARRAY.out.output)
    STEP_3__NP_ARGMAX(STEP_2__NP_WHERE.out.output)
    STEP_4__FIND_PEAKS(STEP_3__NP_ARGMAX.out.output)

    emit:
    output = STEP_4__FIND_PEAKS.out.output
}

workflow {
    BIOMNI_PHYSIOLOGY_ANALYZE_ABR_WAVEFORM_P1_METRICS()
}