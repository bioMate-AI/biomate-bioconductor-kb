#!/usr/bin/env nextflow
/*
 * biomni_molecular_biology_is_region_fully_covered
 * Check if the target region is fully covered.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process IS_REGION_FULLY_COVERED {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("is_region_fully_covered_output.txt"), emit: output

    script:
    """
    # Tool: biomni_molecular_biology_is_region_fully_covered
    # Runs in unified Docker container
    echo 'Running IS_REGION_FULLY_COVERED'
        touch is_region_fully_covered_output.txt
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

workflow BIOMNI_MOLECULAR_BIOLOGY_IS_REGION_FULLY_COVERED {
    main:

    IS_REGION_FULLY_COVERED()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_MOLECULAR_BIOLOGY_IS_REGION_FULLY_COVERED()
}