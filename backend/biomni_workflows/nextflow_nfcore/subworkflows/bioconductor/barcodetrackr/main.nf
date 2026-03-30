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

    # --- Load Data [] ---
    # Key functions: delim, create_SE, factor
    system.file("extdata", "/WuC_etal_appdata/sample_data_ZJ31.txt", package = "barcodetrackR") %>%
      read.delim(row.names = 1) -> wu_dataframe
    system.file("extdata", "/WuC_etal_appdata/sample_metadata_ZJ31.txt", package = "barcodetrackR") %>%
      read.delim() -> wu_metadata
    wu_SE <- create_SE(your_data = wu_dataframe,
    # --- Estimate Threshold [] ---
    # Key functions: estimate_barcode_threshold
    my_thresh <- estimate_barcode_threshold(capture_efficiency = 0.4,
                                            population_size = 500000,
                                            proportion_labeled = 0.3,
                                            confidence_level = 0.95,
                                            verbose = TRUE)
    # --- Apply Thresholding [] ---
    # Key functions: threshold_SE
    wu_thresh <- threshold_SE(your_SE = wu_SE,
                              threshold_value = 0.005,
                              threshold_type = "relative",
                              verbose = TRUE)
    # --- Scatter Plot [] ---
    # Key functions: scatter_plot, plot_grid
    Gr_B_20 <- c("ZJ31_20m_Gr", "ZJ31_20m_B")
    Gr_T_20 <- c("ZJ31_20m_Gr", "ZJ31_20m_T")
    wu_scatterplot_1 <- scatter_plot(wu_SE[,Gr_B_20], your_title = "Gr vs B", assay = "proportions")
    wu_scatterplot_2 <- scatter_plot(wu_SE[,Gr_T_20], your_title = "Gr vs T", assay = "proportions")
    cowplot::plot_grid(wu_scatterplot_1, wu_scatterplot_2, ncol = 2)
    # --- Cor Plot 1 [] ---
    # Key functions: colData, cor_plot
    wu_cor_plot_sample_selection <- colData(wu_SE)$SAMPLENAME[1:20]
    cor_plot(wu_SE[,wu_cor_plot_sample_selection],
             method_corr = "pearson",
             plot_type = "color",
             assay = "proportions")
    # --- Cor Plot 2 [] ---
    # Key functions: colData, cor_plot
    wu_cor_plot_sample_selection <- colData(wu_SE)$SAMPLENAME[1:20]
    cor_plot(wu_SE[,wu_cor_plot_sample_selection],
             method_corr = "pearson",
             plot_type = "color",
             assay = "logs")
    # --- Cor Plot 3 [] ---
    # Key functions: cor_plot
    cor_plot(wu_SE[,wu_cor_plot_sample_selection],
             method_corr = "pearson",
             assay = "proportions",
             return_table = TRUE) %>% head
    # --- Cor Plot 4 [] ---
    # Key functions: cor_plot
    belderbos_wk_samples_PB <- c("wk9_U", "wk14_U", "wk20_U", "wk22_U")
    cor_plot(your_SE = belderbos_SE[,belderbos_wk_samples_PB],
             method_corr = "pearson",
             plot_type = "number",
             assay = "proportions",
    # --- Dist Plot 1 [] ---
    # Key functions: dist_plot
    dist_plot(wu_SE[,wu_cor_plot_sample_selection],
              dist_method =  "manhattan",
              plot_type = "color",
              assay = "logs")
    # --- Dist Plot 2 [] ---
    # Key functions: dist_plot
    dist_plot(wu_SE[,wu_cor_plot_sample_selection],
              dist_method =  "cosine",
              plot_type = "color",
              assay = "logs",
              color_pal = "Greens",
    # --- Barcode Ggheatmap Wu Se 1 [] ---
    # Key functions: barcode_ggheatmap
    barcode_ggheatmap(your_SE = wu_SE[,wu_cor_plot_sample_selection],
                      n_clones = 10,
                      grid = FALSE,
                      label_size = 14,
                      cellnote_size = 4)
    # --- Barcode Ggheatmap Six Se [] ---
    # Key functions: barcode_ggheatmap
    six_celltype_order <- c("m13_TCELLS", "m36_TCELLS", "m43_TCELLS",
                            "m55_TCELLS","m13_BCELLS", "m36_BCELLS",
                            "m43_BCELLS", "m55_BCELLS", "m13_NKCELLS",
                            "m36_NKCELLS", "m43_NKCELLS","m55_NKCELLS",
                            "m13_GRANULOCYTES", "m36_GRANULOCYTES",
    # --- Barcode Ggheatmap Stat Wu Se [] ---
    # Key functions: barcode_ggheatmap_stat
    wu_CD16_NK_order <- colnames(wu_SE)[17:20]
    barcode_ggheatmap_stat(your_SE = wu_SE[,wu_CD16_NK_order],
                           sample_size = rep(40000,length(wu_CD16_NK_order)),
                           stat_test = "chi-squared",
                           stat_option = "subsequent",
    # --- Barcode Stat Test Wu Se [] ---
    # Key functions: barcode_stat_test
    sample_size <- rep(40000,length(wu_CD16_NK_order))
    wu_CD16_NK_statistics <- barcode_stat_test(your_SE = wu_SE[,wu_CD16_NK_order],
                                               sample_size = sample_size,
                                               stat_test = "chi-squared",
                                               stat_option = "subsequent",
    # --- Binary Heat Map [] ---
    # Key functions: barcode_binary_heatmap
    barcode_binary_heatmap(your_SE = belderbos_SE[,belderbos_wk_samples_PB],
                           label_size = 12,
                           threshold = 0.01)

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
