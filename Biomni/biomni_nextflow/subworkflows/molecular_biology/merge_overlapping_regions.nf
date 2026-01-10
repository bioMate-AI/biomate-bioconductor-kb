#!/usr/bin/env nextflow
/*
 * biomni_molecular_biology_merge_overlapping_regions
 * Merge overlapping regions in the list.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process MERGE_OVERLAPPING_REGIONS {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("merge_overlapping_regions_output.txt"), emit: output

    script:
    """
    # Tool: biomni_molecular_biology_merge_overlapping_regions
    # Runs in unified Docker container
    echo 'Running MERGE_OVERLAPPING_REGIONS'
        touch merge_overlapping_regions_output.txt
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

workflow BIOMNI_MOLECULAR_BIOLOGY_MERGE_OVERLAPPING_REGIONS {
    main:

    MERGE_OVERLAPPING_REGIONS()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_MOLECULAR_BIOLOGY_MERGE_OVERLAPPING_REGIONS()
}