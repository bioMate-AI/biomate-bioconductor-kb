#!/usr/bin/env nextflow
/*
 * biomni_support_tools_show_with_capture
 * Enhanced show function that captures plots before displaying them.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process SHOW_WITH_CAPTURE {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("show_with_capture_output.txt"), emit: output

    script:
    """
    # Tool: biomni_support_tools_show_with_capture
    # Runs in unified Docker container
    echo 'Running SHOW_WITH_CAPTURE'
        touch show_with_capture_output.txt
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

workflow BIOMNI_SUPPORT_TOOLS_SHOW_WITH_CAPTURE {
    main:

    SHOW_WITH_CAPTURE()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_SUPPORT_TOOLS_SHOW_WITH_CAPTURE()
}