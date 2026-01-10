#!/usr/bin/env nextflow
/*
 * biomni_cancer_biology_perform_gene_expression_nmf_analysis
 * Performs Non-negative Matrix Factorization (NMF) on gene expression data to extract
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.expression_data_path = null

// Processes
process PERFORM_GENE_EXPRESSION_NMF_ANALYSIS {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(expression_data_path)

    output:
    path("perform_gene_expression_nmf_analysis_output.txt"), emit: output

    script:
    """
    # Tool: biomni_cancer_biology_perform_gene_expression_nmf_analysis
    # Runs in unified Docker container
    echo 'Running PERFORM_GENE_EXPRESSION_NMF_ANALYSIS'
        touch perform_gene_expression_nmf_analysis_output.txt
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

workflow BIOMNI_CANCER_BIOLOGY_PERFORM_GENE_EXPRESSION_NMF_ANALYSIS {
    main:
    ch_expression_data_path = Channel.fromPath(params.expression_data_path)

    PERFORM_GENE_EXPRESSION_NMF_ANALYSIS(ch_expression_data_path)
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_CANCER_BIOLOGY_PERFORM_GENE_EXPRESSION_NMF_ANALYSIS()
}