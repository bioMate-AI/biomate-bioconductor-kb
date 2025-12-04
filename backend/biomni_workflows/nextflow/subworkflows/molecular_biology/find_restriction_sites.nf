#!/usr/bin/env nextflow
/*
 * biomni_molecular_biology_find_restriction_sites
 * Identifies restriction enzyme sites in a given DNA sequence for specified enzymes.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process FIND_RESTRICTION_SITES {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("find_restriction_sites_output.txt"), emit: output

    script:
    """
    # Tool: biomni_molecular_biology_find_restriction_sites
    # Runs in unified Docker container
    echo 'Running FIND_RESTRICTION_SITES'
        touch find_restriction_sites_output.txt
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

workflow BIOMNI_MOLECULAR_BIOLOGY_FIND_RESTRICTION_SITES {
    main:

    FIND_RESTRICTION_SITES()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_MOLECULAR_BIOLOGY_FIND_RESTRICTION_SITES()
}