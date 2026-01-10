#!/usr/bin/env nextflow
/*
 * biomni_genomics_get_gene_set_enrichment_analysis_supported_database_list
 * 
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process GET_GENE_SET_ENRICHMENT_ANALYSIS_SUPPORTED_DATABASE_LIST {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("get_gene_set_enrichment_analysis_supported_database_list_output.txt"), emit: output

    script:
    """
    # Tool: biomni_genomics_get_gene_set_enrichment_analysis_supported_database_list
    # Runs in unified Docker container
    echo 'Running GET_GENE_SET_ENRICHMENT_ANALYSIS_SUPPORTED_DATABASE_LIST'
        touch get_gene_set_enrichment_analysis_supported_database_list_output.txt
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

workflow BIOMNI_GENOMICS_GET_GENE_SET_ENRICHMENT_ANALYSIS_SUPPORTED_DATABASE_LIST {
    main:

    GET_GENE_SET_ENRICHMENT_ANALYSIS_SUPPORTED_DATABASE_LIST()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_GENOMICS_GET_GENE_SET_ENRICHMENT_ANALYSIS_SUPPORTED_DATABASE_LIST()
}