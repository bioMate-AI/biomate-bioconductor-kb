#!/usr/bin/env nextflow
/*
 * biomni_pharmacology_analyze_fda_safety_signals
 * 
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process ANALYZE_FDA_SAFETY_SIGNALS {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("analyze_fda_safety_signals_output.txt"), emit: output

    script:
    """
    # Tool: biomni_pharmacology_analyze_fda_safety_signals
    # Runs in unified Docker container
    echo 'Running ANALYZE_FDA_SAFETY_SIGNALS'
        touch analyze_fda_safety_signals_output.txt
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

workflow BIOMNI_PHARMACOLOGY_ANALYZE_FDA_SAFETY_SIGNALS {
    main:

    ANALYZE_FDA_SAFETY_SIGNALS()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_PHARMACOLOGY_ANALYZE_FDA_SAFETY_SIGNALS()
}