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
    library(CORE_bagging)
    library(CORE_clustering)
    library(jsonlite)

    # --- Scgps Object [] ---
    # Key functions: 1, new_scGPS_object, 2
    # load mixed population 1 (loaded from day_2_cardio_cell_sample dataset,
    # named it as day2)
    library(scGPS)
    day2 <- day_2_cardio_cell_sample
    mixedpop1 <- new_scGPS_object(ExpressionMatrix = day2$dat2_counts,
    # --- Prediction [] ---
    # Key functions: colData, training, bootstrap_prediction
    # select a subpopulation
    c_selectID <- 1
    # load gene list (this can be any lists of user selected genes)
    genes <- training_gene_sample
    genes <- genes$Merged_unique
    # --- Summarise Results [] ---
    # Key functions: summary_prediction_lda, summary_prediction_lasso, omit
    # summary results LDA
    sum_pred_lda <- summary_prediction_lda(LSOLDA_dat = LSOLDA_dat, nPredSubpop = 4)
    # summary results Lasso to show the percent of cells
    # classified as cells belonging
    sum_pred_lasso <- summary_prediction_lasso(LSOLDA_dat = LSOLDA_dat,
    # --- Core [] ---
    # Key functions: frame, new_scGPS_object, CORE_clustering, unname, unlist
    # find clustering information in an expresion data using CORE
    day5 <- day_5_cardio_cell_sample
    cellnames <- colnames(day5$dat5_counts)
    cluster <-day5$dat5_clusters
    cellnames <-data.frame("Cluster"=cluster, "cellBarcodes" = cellnames)
    # --- Score With Bagging [] ---
    # Key functions: frame, new_scGPS_object, CORE_bagging
    # find clustering information in an expresion data using SCORE
    day5 <- day_5_cardio_cell_sample
    cellnames <- colnames(day5$dat5_counts)
    cluster <-day5$dat5_clusters
    cellnames <-data.frame("Cluster"=cluster, "cellBarcodes" = cellnames)
    # --- Visualisation [] ---
    # Key functions: off, plot_CORE, plot_optimal_CORE, unlist
    dev.off()
    ##3.2.1 plot CORE clustering
    p1 <- plot_CORE(CORE_cluster$tree, CORE_cluster$Cluster,
        color_branch = c("#208eb7", "#6ce9d3", "#1c5e39", "#8fca40", "#154975",
            "#b1c8eb"))
    # --- Compare Clustering [] ---
    # Key functions: tSNE, assay, plot_reduced, factor, colData
    t <- tSNE(expression.mat=assay(mixedpop2))
    p2 <-plot_reduced(t, color_fac = factor(colData(mixedpop2)[,1]),
                          palletes =1:length(unique(colData(mixedpop2)[,1])))
    p2
    # --- Find Markers [] ---
    # Key functions: colData, unlist, find_markers, assay
    #load gene list (this can be any lists of user-selected genes)
    genes <-training_gene_sample
    genes <-genes$Merged_unique
    #the gene list can also be objectively identified by differential expression
    #analysis cluster information is requied for find_markers. Here, we use
    # --- Scgps Prediction [] ---
    # Key functions: colData, bootstrap_prediction
    #select a subpopulation, and input gene list
    c_selectID <- 1
    #note make sure the format for genes input here is the same to the format
    #for genes in the mixedpop1 and mixedpop2
    genes = DEgenes$id[1:500]
    # --- Summarise Prediction [] ---
    # Key functions: colData, summary_prediction_lda, summary_prediction_lasso, summary_deviance, summary_accuracy
    #get the number of rows for the summary matrix
    row_cluster <-length(unique(colData(mixedpop2)[,1]))
    #summary results LDA to to show the percent of cells classified as cells
    #belonging by LDA classifier
    summary_prediction_lda(LSOLDA_dat=LSOLDA_dat, nPredSubpop = row_cluster )
    # --- Prediction One Sample [] ---
    # Key functions: colData, bootstrap_prediction, reformat_LASSO
    #run prediction for 3 clusters
    cluster_mixedpop1 <- colData(mixedpop1)[,1]
    cluster_mixedpop2 <- colData(mixedpop2)[,1]
    #cluster_mixedpop2 <- as.numeric(as.vector(colData(mixedpop2)[,1]))
    c_selectID <- 1
    # --- Prediction Two Samples [] ---
    # Key functions: colData, bootstrap_prediction, reformat_LASSO
    #run prediction for 3 clusters
    cluster_mixedpop1 <- colData(mixedpop1)[,1]
    cluster_mixedpop2 <- colData(mixedpop2)[,1]
    row_cluster <-length(unique(colData(mixedpop2)[,1]))
    c_selectID <- 1

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
