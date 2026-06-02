#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: quantiseqr
// This package provides a streamlined workflow for the quanTIseq method, developed to perform the quan
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/quantiseqr/inst/doc/using_quantiseqr.R
// Upstream  : ExperimentHub, GEOquery, SummarizedExperiment, dplyr, ggplot2
// Downstream: none
//
// Install: BiocManager::install("quantiseqr")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_QUANTISEQR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-quantiseqr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-quantiseqr:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-quantiseqr:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(ggplot_object)

    output:
    tuple val(meta), path("${meta.id}_quantiseqr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_quantiseqr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_quantiseqr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(quantiseqr)
    library(ExperimentHub)
    library(jsonlite)

    # --- Tumour Deconvolution [quantiseqr] ---
    # Key functions: run_quantiseq
    ti_racle <- quantiseqr::run_quantiseq(
        expression_data = dataset_racle$expr_mat,
        signature_matrix = "TIL10",
        is_arraydata = FALSE,
        is_tumordata = TRUE,
        scale_mRNA = TRUE
    )

    # --- Visualisation of Immune Cell Fractions [quantiseqr] ---
    # Key functions: quantiplot
    cell_fraction_plot <- quantiplot(
        ti_racle
    )

    # --- SummarizedExperiment Deconvolution [quantiseqr] ---
    # Key functions: run_quantiseq, extract_ti_from_se
    se_deconv <- quantiseqr::run_quantiseq(
        expression_data = se_input,
        signature_matrix = "TIL10",
        is_arraydata = FALSE,
        is_tumordata = TRUE,
        scale_mRNA = TRUE
    )
    ti_fractions <- quantiseqr::extract_ti_from_se(
        se_deconv
    )


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_quantiseqr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_quantiseqr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_quantiseqr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_QUANTISEQR:", paste0("    quantiseqr: ", packageVersion("quantiseqr"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_quantiseqr_results.csv
    touch ${prefix}_quantiseqr_output.rds
    echo "BIOC_QUANTISEQR:" > versions.yml
    echo "    quantiseqr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_QUANTISEQR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(ggplot_object) ]

    main:
    BIOC_QUANTISEQR(ch_input)

    emit:
    results  = BIOC_QUANTISEQR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_QUANTISEQR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_QUANTISEQR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_QUANTISEQR.out.versions  // channel: path(versions.yml)
}
