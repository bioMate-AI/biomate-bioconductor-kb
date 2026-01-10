#!/usr/bin/env nextflow
/*
 * biomni_genomics_interspecies_gene_conversion
 * Convert ENSEMBL gene IDs between different species using BioMart homology mapping.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process INTERSPECIES_GENE_CONVERSION {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("interspecies_gene_conversion_output.txt"), emit: output

    script:
    """
    # Tool: biomni_genomics_interspecies_gene_conversion
    # Runs in unified Docker container
    echo 'Running INTERSPECIES_GENE_CONVERSION'
        touch interspecies_gene_conversion_output.txt
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

workflow BIOMNI_GENOMICS_INTERSPECIES_GENE_CONVERSION {
    main:

    INTERSPECIES_GENE_CONVERSION()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_GENOMICS_INTERSPECIES_GENE_CONVERSION()
}