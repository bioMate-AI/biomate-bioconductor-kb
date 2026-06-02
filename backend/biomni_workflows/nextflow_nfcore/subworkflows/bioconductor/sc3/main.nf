#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SC3
// A tool for unsupervised clustering and analysis of single cell RNA-Seq data.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SC3/inst/doc/SC3.R
// Upstream  : SingleCellExperiment, knitr, mclust, scater
// Downstream: none
//
// Install: BiocManager::install("SC3")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SC3 {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-sc3"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-sc3:1.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-sc3:1.34.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_sc3_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_sc3_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_sc3_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SC3)
    library(SingleCellExperiment)
    library(jsonlite)

    # --- Single-Cell Clustering [] ---
    # Key functions: sc3
    sce <- sc3(sce, ks = 2:4, biology = TRUE)
    col_data <- colData(sce)
    sc3_cols <- grep("sc3_", colnames(col_data), value = TRUE)
    cluster_results <- col_data[, sc3_cols]


    # --- Consensus and Stability Analysis [] ---
    # Key functions: sc3_plot_consensus, sc3_plot_silhouette, sc3_plot_cluster_stability
    sc3_plot_consensus(
        sce, k = 3,
        show_pdata = c("sc3_3_clusters", "sc3_3_log2_outlier_score")
    )
    sc3_plot_silhouette(sce, k = 3)
    sc3_plot_cluster_stability(sce, k = 3)


    # --- Biological Feature Analysis [] ---
    # Key functions: sc3_calc_biology, sc3_plot_de_genes, sc3_plot_markers
    sce <- sc3_calc_biology(sce, ks = 2:4)
    sc3_plot_de_genes(
        sce, k = 3,
        show_pdata = c("sc3_3_clusters", "sc3_3_log2_outlier_score")
    )
    sc3_plot_markers(sce, k = 3)


    # --- Hybrid SVM Clustering for Large Datasets [] ---
    # Key functions: sc3_run_svm, sc3_calc_biology
    sce <- sc3(sce, ks = 2:4, biology = TRUE, svm_num_cells = 50)
    sce <- sc3_run_svm(sce, ks = 2:4)
    metadata(sce)$sc3$svm_train_inds <- NULL
    sce <- sc3_calc_biology(sce, ks = 2:4)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_sc3_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_sc3_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_sc3_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SC3:", paste0("    sc3: ", packageVersion("SC3"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sc3_results.csv
    touch ${prefix}_sc3_output.rds
    echo "BIOC_SC3:" > versions.yml
    echo "    sc3: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SC3_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SC3(ch_input)

    emit:
    results  = BIOC_SC3.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SC3.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SC3.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SC3.out.versions  // channel: path(versions.yml)
}
