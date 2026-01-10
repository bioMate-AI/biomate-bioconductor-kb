#!/usr/bin/env nextflow
/*
 * biomni_physiology_perform_cosinor_analysis
 * Performs cosinor analysis on physiological time series data to characterize circadian rhythms.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.time_data = null
params.physiological_data = null

// Processes
process PERFORM_COSINOR_ANALYSIS {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(time_data)
    path(physiological_data)

    output:
    path("perform_cosinor_analysis_output.txt"), emit: output

    script:
    """
    # Tool: biomni_physiology_perform_cosinor_analysis
    # Runs in unified Docker container
    echo 'Running PERFORM_COSINOR_ANALYSIS'
        touch perform_cosinor_analysis_output.txt
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

workflow BIOMNI_PHYSIOLOGY_PERFORM_COSINOR_ANALYSIS {
    main:
    ch_time_data = Channel.fromPath(params.time_data)
    ch_physiological_data = Channel.fromPath(params.physiological_data)

    PERFORM_COSINOR_ANALYSIS(ch_time_data, ch_physiological_data)
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_PHYSIOLOGY_PERFORM_COSINOR_ANALYSIS()
}