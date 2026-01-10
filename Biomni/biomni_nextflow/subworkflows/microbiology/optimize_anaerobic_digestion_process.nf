#!/usr/bin/env nextflow
/*
 * biomni_microbiology_optimize_anaerobic_digestion_process
 * Optimize anaerobic digestion process conditions to maximize VFA production or methane yield.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process OPTIMIZE_ANAEROBIC_DIGESTION_PROCESS {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("optimize_anaerobic_digestion_process_output.txt"), emit: output

    script:
    """
    # Tool: biomni_microbiology_optimize_anaerobic_digestion_process
    # Runs in unified Docker container
    echo 'Running OPTIMIZE_ANAEROBIC_DIGESTION_PROCESS'
        touch optimize_anaerobic_digestion_process_output.txt
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

workflow BIOMNI_MICROBIOLOGY_OPTIMIZE_ANAEROBIC_DIGESTION_PROCESS {
    main:

    OPTIMIZE_ANAEROBIC_DIGESTION_PROCESS()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_MICROBIOLOGY_OPTIMIZE_ANAEROBIC_DIGESTION_PROCESS()
}