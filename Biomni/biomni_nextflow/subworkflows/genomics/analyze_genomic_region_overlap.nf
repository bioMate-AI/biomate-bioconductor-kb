#!/usr/bin/env nextflow
/*
 * biomni_genomics_analyze_genomic_region_overlap
 * Analyze overlaps between two or more sets of genomic regions.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process ANALYZE_GENOMIC_REGION_OVERLAP {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("analyze_genomic_region_overlap_output.txt"), emit: output

    script:
    """
    # Tool: biomni_genomics_analyze_genomic_region_overlap
    # Runs in unified Docker container
    echo 'Running ANALYZE_GENOMIC_REGION_OVERLAP'
        touch analyze_genomic_region_overlap_output.txt
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

workflow BIOMNI_GENOMICS_ANALYZE_GENOMIC_REGION_OVERLAP {
    main:

    ANALYZE_GENOMIC_REGION_OVERLAP()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_GENOMICS_ANALYZE_GENOMIC_REGION_OVERLAP()
}