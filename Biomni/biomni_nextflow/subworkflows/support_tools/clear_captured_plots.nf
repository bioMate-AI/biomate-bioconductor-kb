#!/usr/bin/env nextflow
/*
 * biomni_support_tools_clear_captured_plots
 * Clear all captured matplotlib plots.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process CLEAR_CAPTURED_PLOTS {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("clear_captured_plots_output.txt"), emit: output

    script:
    """
    # Tool: biomni_support_tools_clear_captured_plots
    # Runs in unified Docker container
    echo 'Running CLEAR_CAPTURED_PLOTS'
        touch clear_captured_plots_output.txt
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

workflow BIOMNI_SUPPORT_TOOLS_CLEAR_CAPTURED_PLOTS {
    main:

    CLEAR_CAPTURED_PLOTS()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_SUPPORT_TOOLS_CLEAR_CAPTURED_PLOTS()
}