#!/usr/bin/env nextflow
/*
 * biomni_molecular_biology_is_position_covered
 * Check if a position is covered by any region.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process IS_POSITION_COVERED {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("is_position_covered_output.txt"), emit: output

    script:
    """
    # Tool: biomni_molecular_biology_is_position_covered
    # Runs in unified Docker container
    echo 'Running IS_POSITION_COVERED'
        touch is_position_covered_output.txt
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

workflow BIOMNI_MOLECULAR_BIOLOGY_IS_POSITION_COVERED {
    main:

    IS_POSITION_COVERED()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_MOLECULAR_BIOLOGY_IS_POSITION_COVERED()
}