#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: barcodetrackR
// barcodetrackR is an R package developed for the analysis and visualization of clonal tracking data. 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/barcodetrackR/inst/doc/Introduction_to_barcodetrackR.R
// Upstream  : SummarizedExperiment, magrittr
// Downstream: none
//
// Install: BiocManager::install("barcodetrackR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BARCODETRACKR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-barcodetrackr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-barcodetrackr:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-barcodetrackr:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_barcodetrackr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_barcodetrackr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_barcodetrackr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(barcodetrackR)
    library(jsonlite)

    # --- Threshold Estimation and Filtering [] ---
    # Key functions: estimate_barcode_threshold, threshold_SE
    my_thresh <- estimate_barcode_threshold(
        capture_efficiency = 0.4,
        population_size = 500000,
        proportion_labeled = 0.3,
        confidence_level = 0.95,
        verbose = FALSE
    )
    wu_thresh <- threshold_SE(
        your_SE = wu_SE,
        threshold_value = 0.005,
        threshold_type = "relative",
        verbose = FALSE
    )


    # --- Correlation and Distance Analysis [] ---
    # Key functions: cor_plot, dist_plot
    wu_samples <- colData(wu_SE)$SAMPLENAME[1:10]
    cor_plot(
        your_SE = wu_SE[, wu_samples],
        method_corr = "pearson",
        plot_type = "color",
        assay = "proportions"
    )
    dist_plot(
        your_SE = wu_SE[, wu_samples],
        dist_method = "cosine",
        plot_type = "color",
        assay = "logs",
        cluster_tree = TRUE
    )


    # --- Heatmap Visualization [] ---
    # Key functions: barcode_ggheatmap
    wu_samples <- colData(wu_SE)$SAMPLENAME[1:10]
    barcode_ggheatmap(
        your_SE = wu_SE[, wu_samples],
        n_clones = 10,
        grid = FALSE,
        label_size = 14,
        cellnote_size = 4
    )


    # --- Statistical Testing [] ---
    # Key functions: barcode_stat_test, barcode_ggheatmap_stat
    wu_CD16_NK_order <- colnames(wu_SE)[17:20]
    sample_size <- rep(40000, length(wu_CD16_NK_order))
    wu_stats <- barcode_stat_test(
        your_SE = wu_SE[, wu_CD16_NK_order],
        sample_size = sample_size,
        stat_test = "chi-squared",
        stat_option = "subsequent",
        bc_threshold = 0.01
    )
    barcode_ggheatmap_stat(
        your_SE = wu_SE[, wu_CD16_NK_order],
        sample_size = sample_size,
        stat_test = "chi-squared",
        stat_option = "subsequent",
        p_threshold = 0.05,
        n_clones = 10,
        cellnote_assay = "stars",
        cellnote_size = 6
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_barcodetrackr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_barcodetrackr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_barcodetrackr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BARCODETRACKR:", paste0("    barcodetrackr: ", packageVersion("barcodetrackR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_barcodetrackr_results.csv
    touch ${prefix}_barcodetrackr_output.rds
    echo "BIOC_BARCODETRACKR:" > versions.yml
    echo "    barcodetrackr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BARCODETRACKR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BARCODETRACKR(ch_input)

    emit:
    results  = BIOC_BARCODETRACKR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BARCODETRACKR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BARCODETRACKR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BARCODETRACKR.out.versions  // channel: path(versions.yml)
}
