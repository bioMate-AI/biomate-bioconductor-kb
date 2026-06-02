#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MatrixQCvis
// Data quality assessment is an integral part of preparatory data analysis to ensure sound biological 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MatrixQCvis/inst/doc/MatrixQCvis.R
// Upstream  : ExperimentHub, knitr, limma
// Downstream: none
//
// Install: BiocManager::install("MatrixQCvis")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MATRIXQCVIS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-matrixqcvis"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-matrixqcvis:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-matrixqcvis:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_matrixqcvis_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_matrixqcvis_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_matrixqcvis_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MatrixQCvis)
    library(ECDF)
    library(ExperimentHub)
    library(MAplot)
    library(MAvalues)
    library(jsonlite)

    # --- Initial Quality Control ---
    # Key functions: hist_sample_num, hist_sample, mosaic, createBoxplot, driftPlot
    tbl_hist <- hist_sample_num(se = se, category = "type")
    p_hist <- hist_sample(tbl_hist, category = "type")
    se_tmp <- se
    se_tmp$arbitrary_values <- rep(c("A", "B"), length.out = ncol(se))
    p_mosaic <- mosaic(se = se_tmp, f1 = "type", f2 = "arbitrary_values")
    p_box <- createBoxplot(
        se,
        orderCategory = "sample",
        title = "raw",
        log = TRUE,
        violin = TRUE
    )
    p_drift <- driftPlot(
        se,
        aggregation = "median",
        category = "type",
        orderCategory = "type",
        level = "BRCA",
        method = "loess"
    )

    # --- Normalization and Imputation ---
    # Key functions: normalizeAssay, transformAssay, imputeAssay, cv, plotCV
    a_raw <- assay(se)
    a_norm <- normalizeAssay(a_raw, "sum")
    a_trans <- transformAssay(a_norm, "vsn")
    a_imp <- imputeAssay(a_trans, "MinDet")
    cv_raw <- cv(a_raw, "raw")
    cv_norm <- cv(a_norm, "normalized")
    cv_trans <- cv(a_trans, "transformed")
    cv_imp <- cv(a_imp, "imputed")
    df_cv <- data.frame(cv_raw, cv_norm, cv_trans, cv_imp)
    p_cv <- plotCV(df_cv)

    # --- Sample Distance Analysis ---
    # Key functions: distShiny, distSample, sumDistSample
    a_raw <- assay(se)
    dist_mat <- distShiny(a_raw)
    p_dist <- distSample(
        dist_mat,
        se,
        "type",
        use_raster = TRUE,
        raster_device = "jpeg"
    )
    p_sum_dist <- sumDistSample(dist_mat, title = "raw")

    # --- Feature Diagnostics ---
    # Key functions: MAvalues, MAplot, ECDF, createDfFeature, featurePlot
    tbl_ma <- MAvalues(se, group = "all")
    p_ma <- MAplot(
        tbl_ma,
        group = "all",
        plot = colnames(se)[1]
    )
    p_ecdf <- ECDF(se, colnames(se)[1], group = "all")
    l_assays <- list(raw = assay(se))
    df_feat <- createDfFeature(l_assays, feature = rownames(se)[1])
    p_feat <- featurePlot(df_feat)

    # --- Missingness and Differential Expression ---
    # Key functions: samplesMeasuredMissing, barplotSamplesMeasuredMissing, volcanoPlot
    tbl_missing <- samplesMeasuredMissing(se)
    p_missing <- barplotSamplesMeasuredMissing(tbl_missing, measured = TRUE)
    p_volcano <- volcanoPlot(tT, type = "ttest")


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_matrixqcvis_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_matrixqcvis_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_matrixqcvis_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MATRIXQCVIS:", paste0("    matrixqcvis: ", packageVersion("MatrixQCvis"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_matrixqcvis_results.csv
    touch ${prefix}_matrixqcvis_output.rds
    echo "BIOC_MATRIXQCVIS:" > versions.yml
    echo "    matrixqcvis: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MATRIXQCVIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MATRIXQCVIS(ch_input)

    emit:
    results  = BIOC_MATRIXQCVIS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MATRIXQCVIS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MATRIXQCVIS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MATRIXQCVIS.out.versions  // channel: path(versions.yml)
}
