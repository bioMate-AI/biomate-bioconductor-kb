#!/usr/bin/env nextflow
/*
 * biomni_systems_biology_dimerization_odes
 * 
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process DIMERIZATION_ODES {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("dimerization_odes_output.txt"), emit: output

    script:
    """
    # Tool: biomni_systems_biology_dimerization_odes
    # Runs in unified Docker container
    echo 'Running DIMERIZATION_ODES'
        touch dimerization_odes_output.txt
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

workflow BIOMNI_SYSTEMS_BIOLOGY_DIMERIZATION_ODES {
    main:

    DIMERIZATION_ODES()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_SYSTEMS_BIOLOGY_DIMERIZATION_ODES()
}