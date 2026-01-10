#!/usr/bin/env nextflow
/*
 * biomni_support_tools_savefig_with_capture
 * Enhanced savefig function that captures plots after saving them.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process SAVEFIG_WITH_CAPTURE {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("savefig_with_capture_output.txt"), emit: output

    script:
    """
    # Tool: biomni_support_tools_savefig_with_capture
    # Runs in unified Docker container
    echo 'Running SAVEFIG_WITH_CAPTURE'
        touch savefig_with_capture_output.txt
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

workflow BIOMNI_SUPPORT_TOOLS_SAVEFIG_WITH_CAPTURE {
    main:

    SAVEFIG_WITH_CAPTURE()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_SUPPORT_TOOLS_SAVEFIG_WITH_CAPTURE()
}