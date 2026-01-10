#!/usr/bin/env nextflow
/*
 * biomni_genomics_gene_set_enrichment_analysis
 * Perform enrichment analysis for a list of genes, with optional background gene set and plotting functionality.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.genes = null

// Processes
process STEP_1__GGET_ENRICHR {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_1__gget_enrichr_output.txt"), emit: output

    script:
    """
    # Tool: python_gget_gget_enrichr
    # Runs in unified Docker container
    echo 'Running STEP_1__GGET_ENRICHR'
        touch step_1__gget_enrichr_output.txt
    """
}

workflow BIOMNI_GENOMICS_GENE_SET_ENRICHMENT_ANALYSIS {
    main:
    ch_genes = Channel.value(params.genes)

    STEP_1__GGET_ENRICHR(ch_genes)

    emit:
    output = STEP_1__GGET_ENRICHR.out.output
}

workflow {
    BIOMNI_GENOMICS_GENE_SET_ENRICHMENT_ANALYSIS()
}