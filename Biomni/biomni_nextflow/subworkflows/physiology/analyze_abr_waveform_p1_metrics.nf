#!/usr/bin/env nextflow
/*
 * biomni_physiology_analyze_abr_waveform_p1_metrics
 * Extracts P1 amplitude and latency from Auditory Brainstem Response (ABR) waveform data.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process ANALYZE_ABR_WAVEFORM_P1_METRICS {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("analyze_abr_waveform_p1_metrics_output.txt"), emit: output

    script:
    """
    # Tool: biomni_physiology_analyze_abr_waveform_p1_metrics
    # Runs in unified Docker container
    echo 'Running ANALYZE_ABR_WAVEFORM_P1_METRICS'
        touch analyze_abr_waveform_p1_metrics_output.txt
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

workflow BIOMNI_PHYSIOLOGY_ANALYZE_ABR_WAVEFORM_P1_METRICS {
    main:

    ANALYZE_ABR_WAVEFORM_P1_METRICS()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_PHYSIOLOGY_ANALYZE_ABR_WAVEFORM_P1_METRICS()
}