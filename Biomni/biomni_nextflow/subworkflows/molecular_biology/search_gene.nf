#!/usr/bin/env nextflow
/*
 * biomni_molecular_biology_search_gene
 * Search for gene ID in NCBI database.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process SEARCH_GENE {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("search_gene_output.txt"), emit: output

    script:
    """
    # Tool: biomni_molecular_biology_search_gene
    # Runs in unified Docker container
    echo 'Running SEARCH_GENE'
        touch search_gene_output.txt
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

workflow BIOMNI_MOLECULAR_BIOLOGY_SEARCH_GENE {
    main:

    SEARCH_GENE()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_MOLECULAR_BIOLOGY_SEARCH_GENE()
}