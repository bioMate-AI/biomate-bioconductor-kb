#!/usr/bin/env nextflow
/*
 * biomni_support_tools_get_captured_plots
 * Get all captured matplotlib plots.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process GET_CAPTURED_PLOTS {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("get_captured_plots_output.txt"), emit: output

    script:
    """
    # Tool: biomni_support_tools_get_captured_plots
    # Runs in unified Docker container
    echo 'Running GET_CAPTURED_PLOTS'
        touch get_captured_plots_output.txt
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

workflow BIOMNI_SUPPORT_TOOLS_GET_CAPTURED_PLOTS {
    main:

    GET_CAPTURED_PLOTS()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_SUPPORT_TOOLS_GET_CAPTURED_PLOTS()
}