#!/usr/bin/env nextflow
/*
 * biomni_genomics_gene_set_enrichment_analysis
 * Perform enrichment analysis for a list of genes, with optional background gene set and plotting functionality.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.database = null

// Processes
process GENE_SET_ENRICHMENT_ANALYSIS {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(database)

    output:
    path("gene_set_enrichment_analysis_output.txt"), emit: output

    script:
    """
    # Tool: biomni_genomics_gene_set_enrichment_analysis
    # Runs in unified Docker container
    echo 'Running GENE_SET_ENRICHMENT_ANALYSIS'
        touch gene_set_enrichment_analysis_output.txt
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

workflow BIOMNI_GENOMICS_GENE_SET_ENRICHMENT_ANALYSIS {
    main:
    ch_database = Channel.fromPath(params.database)

    GENE_SET_ENRICHMENT_ANALYSIS(ch_database)
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_GENOMICS_GENE_SET_ENRICHMENT_ANALYSIS()
}