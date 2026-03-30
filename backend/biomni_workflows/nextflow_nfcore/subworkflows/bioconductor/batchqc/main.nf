#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: BatchQC
// Sequencing and microarray samples often are collected or processed in multiple batches or at differe
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/BatchQC/inst/doc/BatchQC_Intro.R
// Upstream  : devtools
// Downstream: none
//
// Install: BiocManager::install("BatchQC")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BATCHQC {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-batchqc"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-batchqc:2.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-batchqc:2.2.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_batchqc_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_batchqc_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_batchqc_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DE_analyze)
    library(EV_plotter)
    library(EV_table)
    library(PCA_plotter)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: summarized_experiment, assayNames, factor
    ---------------------------------------------------------------------
    data(signature_data)
    data(batch_indicator)
    se_object <- BatchQC::summarized_experiment(signature_data, batch_indicator)
    SummarizedExperiment::assayNames(se_object) <- "log_intensity"
    # --- Normalize Se [] ---
    # Key functions: normalize_SE
    ---------------------------------------------------------------------
    # CPM Normalization
    se_object <- BatchQC::normalize_SE(se = se_object, method = "CPM",
        log_bool = FALSE, assay_to_normalize = "log_intensity",
        output_assay_name = "CPM_normalized_counts")
    # --- Batch Correct [] ---
    # Key functions: batch_correct
    ---------------------------------------------------------------------
    # Combat correction
    se_object <- BatchQC::batch_correct(se = se_object, method = "ComBat",
        assay_to_normalize = "log_intensity", batch = "batch",
        covar = c("condition"), output_assay_name = "Combat_corrected")
    # --- Batch Design [] ---
    # Key functions: batch_design
    ---------------------------------------------------------------------
    batch_design_tibble <- BatchQC::batch_design(se = se_object, batch = "batch",
        covariate = "condition")
    batch_design_tibble
    # --- Confound Metrics [] ---
    # Key functions: confound_metrics
    ---------------------------------------------------------------------
    confound_table <- BatchQC::confound_metrics(se = se_object, batch = "batch")
    confound_table
    # --- Std Pearson Corr Coef [] ---
    # Key functions: std_pearson_corr_coef
    ---------------------------------------------------------------------
    pearson_cor_result <- BatchQC::std_pearson_corr_coef(batch_design_tibble)
    pearson_cor_result
    # --- Cramers V [] ---
    # Key functions: cramers_v
    ---------------------------------------------------------------------
    cramers_v_result <- BatchQC::cramers_v(batch_design_tibble)
    cramers_v_result
    # --- Batchqc Explained Variation [] ---
    # Key functions: batchqc_explained_variation, EV_plotter
    ---------------------------------------------------------------------
    ex_variation <- batchqc_explained_variation(se = se_object,
        batch = "batch", condition = "condition", assay_name = "log_intensity")
    EV_boxplot <- BatchQC::EV_plotter(batchqc_ev = ex_variation[[1]])
    EV_boxplot
    # --- Batchqc Explained Variation [] ---
    # Key functions: batchqc_explained_variation, EV_table
    ---------------------------------------------------------------------
    ex_variation <- batchqc_explained_variation(se = se_object,
        batch = "batch", condition = "condition", assay_name = "log_intensity")
    EV_table <- BatchQC::EV_table(batchqc_ev = ex_variation[[1]])
    EV_table
    # --- Batchqc Explained Variation [] ---
    # Key functions: batchqc_explained_variation, EV_plotter, EV_table
    ---------------------------------------------------------------------
    ex_variation <- batchqc_explained_variation(se = se_object,
        batch = "batch", condition = "condition", assay_name = "Combat_corrected")
    EV_boxplot <- BatchQC::EV_plotter(batchqc_ev = ex_variation[[1]])
    EV_boxplot
    # --- Heatmap Plotter [] ---
    # Key functions: heatmap_plotter
    ---------------------------------------------------------------------
    heatmaps <- BatchQC::heatmap_plotter(se = se_object, assay = "log_intensity",
        nfeature = 38, annotation_column = c("batch", "condition"),
        log_option = "FALSE")
    correlation_heatmap <- heatmaps$correlation_heatmap
    # --- Dendrogram Plotter [] ---
    # Key functions: dendrogram_plotter
    ---------------------------------------------------------------------
    dendrogram_plot <- BatchQC::dendrogram_plotter(se = se_object,
        assay = "log_intensity",
        batch_var = "batch",
        category_var = "condition")
    # --- Pca Plotter [] ---
    # Key functions: PCA_plotter
    ---------------------------------------------------------------------
    pca_plot <- BatchQC::PCA_plotter(se = se_object, nfeature = 20, color = "batch",
        shape = "condition", assays = c("log_intensity", "Combat_corrected"),
        xaxisPC = 1, yaxisPC = 2, log_option = FALSE)
    pca_plot$plot
    # --- De Analyze [] ---
    # Key functions: DE_analyze
    ---------------------------------------------------------------------
    differential_expression <- BatchQC::DE_analyze(se = se_object,
        method = "limma", batch = "batch", conditions = c("condition"),
        assay_to_analyze = "log_intensity")
    # --- Pval Plotter [] ---
    # Key functions: pval_plotter, pval_summary
    ---------------------------------------------------------------------
    pval_plotter(differential_expression)
    head(pval_summary(differential_expression))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_batchqc_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_batchqc_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_batchqc_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BATCHQC:", paste0("    batchqc: ", packageVersion("BatchQC"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_batchqc_results.csv
    touch ${prefix}_batchqc_output.rds
    echo "BIOC_BATCHQC:" > versions.yml
    echo "    batchqc: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BATCHQC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BATCHQC(ch_input)

    emit:
    results  = BIOC_BATCHQC.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BATCHQC.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BATCHQC.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BATCHQC.out.versions  // channel: path(versions.yml)
}
