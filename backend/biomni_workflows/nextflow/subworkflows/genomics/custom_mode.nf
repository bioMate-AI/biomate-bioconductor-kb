#!/usr/bin/env nextflow
/*
 * biomni_genomics_custom_mode
 * 
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process CUSTOM_MODE {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("custom_mode_output.txt"), emit: output

    script:
    """
    # Tool: biomni_genomics_custom_mode
    # Runs in unified Docker container
    echo 'Running CUSTOM_MODE'
        touch custom_mode_output.txt
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

workflow BIOMNI_GENOMICS_CUSTOM_MODE {
    main:

    CUSTOM_MODE()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_GENOMICS_CUSTOM_MODE()
}