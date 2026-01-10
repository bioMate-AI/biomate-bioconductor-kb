#!/usr/bin/env nextflow
/*
 * biomni_genomics_check_ensembl_patterns
 * 
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process CHECK_ENSEMBL_PATTERNS {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("check_ensembl_patterns_output.txt"), emit: output

    script:
    """
    # Tool: biomni_genomics_check_ensembl_patterns
    # Runs in unified Docker container
    echo 'Running CHECK_ENSEMBL_PATTERNS'
        touch check_ensembl_patterns_output.txt
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

workflow BIOMNI_GENOMICS_CHECK_ENSEMBL_PATTERNS {
    main:

    CHECK_ENSEMBL_PATTERNS()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_GENOMICS_CHECK_ENSEMBL_PATTERNS()
}