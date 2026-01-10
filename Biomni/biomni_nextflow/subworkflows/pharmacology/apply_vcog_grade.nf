#!/usr/bin/env nextflow
/*
 * biomni_pharmacology_apply_vcog_grade
 * Apply VCOG-CTCAE grading criteria to an adverse event.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process APPLY_VCOG_GRADE {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("apply_vcog_grade_output.txt"), emit: output

    script:
    """
    # Tool: biomni_pharmacology_apply_vcog_grade
    # Runs in unified Docker container
    echo 'Running APPLY_VCOG_GRADE'
        touch apply_vcog_grade_output.txt
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

workflow BIOMNI_PHARMACOLOGY_APPLY_VCOG_GRADE {
    main:

    APPLY_VCOG_GRADE()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_PHARMACOLOGY_APPLY_VCOG_GRADE()
}