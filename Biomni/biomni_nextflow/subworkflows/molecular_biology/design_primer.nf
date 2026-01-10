#!/usr/bin/env nextflow
/*
 * biomni_molecular_biology_design_primer
 * Design a single primer within the given sequence window.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process DESIGN_PRIMER {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("design_primer_output.txt"), emit: output

    script:
    """
    # Tool: biomni_molecular_biology_design_primer
    # Runs in unified Docker container
    echo 'Running DESIGN_PRIMER'
        touch design_primer_output.txt
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

workflow BIOMNI_MOLECULAR_BIOLOGY_DESIGN_PRIMER {
    main:

    DESIGN_PRIMER()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_MOLECULAR_BIOLOGY_DESIGN_PRIMER()
}