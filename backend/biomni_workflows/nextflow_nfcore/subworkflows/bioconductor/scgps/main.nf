#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: scGPS
// The package implements two main algorithms to answer two key questions: a SCORE (Stable Clustering a
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/scGPS/inst/doc/vignette.R
// Upstream  : DOSE, ReactomePA, clusterProfiler, dplyr, locfit
// Downstream: none
//
// Install: BiocManager::install("scGPS")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCGPS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-scgps"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-scgps:1.20.0--r44_0' :
        'quay.io/biocontainers/bioconductor-scgps:1.20.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_scgps_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_scgps_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_scgps_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(scGPS)
    library(CORE_bagging)
    library(CORE_clustering)
    library(jsonlite)

    # --- Subpopulation Prediction [] ---
    # Key functions: bootstrap_prediction
    c_selectID <- 1
    genes <- training_gene_sample$Merged_unique
    cluster_mixedpop1 <- colData(mixedpop1)[, 1]
    cluster_mixedpop2 <- colData(mixedpop2)[, 1]
    LSOLDA_dat <- bootstrap_prediction(
        nboots = 3, mixedpop1 = mixedpop1,
        mixedpop2 = mixedpop2, genes = genes,
        c_selectID = c_selectID, listData = list(),
        cluster_mixedpop1 = cluster_mixedpop1,
        cluster_mixedpop2 = cluster_mixedpop2,
        trainset_ratio = 0.7
    )


    # --- Prediction Evaluation [] ---
    # Key functions: summary_prediction_lda, summary_prediction_lasso, summary_accuracy, summary_deviance
    sum_pred_lda <- summary_prediction_lda(
        LSOLDA_dat = LSOLDA_dat, nPredSubpop = 4
    )
    sum_pred_lasso <- summary_prediction_lasso(
        LSOLDA_dat = LSOLDA_dat, nPredSubpop = 4
    )
    acc_summary <- summary_accuracy(object = LSOLDA_dat)
    dev_summary <- summary_deviance(object = LSOLDA_dat)


    # --- Clustering with CORE [] ---
    # Key functions: CORE_clustering, new_scGPS_object
    day5 <- day_5_cardio_cell_sample
    cellnames <- data.frame(
        "Cluster" = day5$dat5_clusters,
        "cellBarcodes" = colnames(day5$dat5_counts)
    )
    mixedpop2 <- new_scGPS_object(
        ExpressionMatrix = day5$dat5_counts,
        GeneMetadata = day5$dat5geneInfo, CellMetadata = cellnames
    )
    CORE_cluster <- CORE_clustering(
        mixedpop2, remove_outlier = c(0), PCA = FALSE
    )


    # --- Clustering with SCORE [] ---
    # Key functions: CORE_bagging, new_scGPS_object
    day5 <- day_5_cardio_cell_sample
    cellnames <- data.frame(
        "Cluster" = day5$dat5_clusters,
        "cellBarcodes" = colnames(day5$dat5_counts)
    )
    mixedpop2 <- new_scGPS_object(
        ExpressionMatrix = day5$dat5_counts,
        GeneMetadata = day5$dat5geneInfo, CellMetadata = cellnames
    )
    SCORE_test <- CORE_bagging(
        mixedpop2, remove_outlier = c(0), PCA = FALSE,
        bagging_run = 20, subsample_proportion = 0.8
    )


    # --- Dimensionality Reduction and Visualisation [] ---
    # Key functions: tSNE, plot_reduced, plot_CORE, plot_optimal_CORE
    t_results <- tSNE(expression.mat = assay(mixedpop2))
    p_reduced <- plot_reduced(
        t_results, color_fac = factor(colData(mixedpop2)[, 1]),
        palletes = 1:length(unique(colData(mixedpop2)[, 1]))
    )
    p_core <- plot_CORE(
        CORE_cluster$tree, CORE_cluster$Cluster,
        color_branch = c("#208eb7", "#6ce9d3", "#1c5e39")
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_scgps_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_scgps_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_scgps_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SCGPS:", paste0("    scgps: ", packageVersion("scGPS"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scgps_results.csv
    touch ${prefix}_scgps_output.rds
    echo "BIOC_SCGPS:" > versions.yml
    echo "    scgps: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SCGPS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SCGPS(ch_input)

    emit:
    results  = BIOC_SCGPS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SCGPS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SCGPS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SCGPS.out.versions  // channel: path(versions.yml)
}
