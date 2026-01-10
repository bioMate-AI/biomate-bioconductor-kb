#!/usr/bin/env nextflow
/*
 * biomni_immunology_analyze_atac_seq_differential_accessibility
 * Perform ATAC-seq peak calling and differential accessibility analysis using MACS2.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process ANALYZE_ATAC_SEQ_DIFFERENTIAL_ACCESSIBILITY {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("analyze_atac_seq_differential_accessibility_output.txt"), emit: output

    script:
    """
    # Tool: biomni_immunology_analyze_atac_seq_differential_accessibility
    # Runs in unified Docker container
    echo 'Running ANALYZE_ATAC_SEQ_DIFFERENTIAL_ACCESSIBILITY'
        touch analyze_atac_seq_differential_accessibility_output.txt
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

workflow BIOMNI_IMMUNOLOGY_ANALYZE_ATAC_SEQ_DIFFERENTIAL_ACCESSIBILITY {
    main:

    ANALYZE_ATAC_SEQ_DIFFERENTIAL_ACCESSIBILITY()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_IMMUNOLOGY_ANALYZE_ATAC_SEQ_DIFFERENTIAL_ACCESSIBILITY()
}