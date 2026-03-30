#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: squallms
// squallms is a Bioconductor R package that implements a "semi-labeled" approach to untargeted mass sp
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/squallms/inst/doc/intro_to_squallms.R
// Upstream  : dplyr, tidyr, tibble, ggplot2, xcms
// Downstream: none
//
// Install: BiocManager::install("squallms")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SQUALLMS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-squallms"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-squallms:1.0.0--r44_0' :
        'quay.io/biocontainers/bioconductor-squallms:1.0.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_squallms_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_squallms_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_squallms_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CentWaveParam)
    library(ObiwarpParam)
    library(PeakDensityParam)
    library(jsonlite)

    # --- Principal component analysis [] ---
    # Key functions: prcomp, rownames_to_column, ggplot, geom_vline, geom_hline
    prcomp() %>%
    as.data.frame() %>%
    rownames_to_column("feature") %>%
    # --- Custom ggplot2 visualization [] ---
    # Key functions: arrange, ggplot, geom_point, theme_bw, geom_tile, facet_wrap, scale_x_continuous, scale_y_discrete
    arrange(desc(med_snr)) %>%
    ggplot() +
    geom_point(aes(x = med_rt, y = med_mz, color = med_cor, size = med_snr), alpha = 0.5) +
    # --- Register analysis [] ---
    # Key functions: register, CentWaveParam, ObiwarpParam, PeakDensityParam, makeXcmsObjFlat, grabMSdata, extractChromMetrics, slice_sample
    msdata <- grabMSdata(unique(feat_peak_info$filepath), verbosity = 0)
    shape_metrics <- extractChromMetrics(feat_peak_info, ms1_data = msdata$MS1)
    knitr::kable(head(shape_metrics), caption = "Format of the output from extractChromMetrics")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_squallms_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_squallms_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_squallms_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SQUALLMS:", paste0("    squallms: ", packageVersion("squallms"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_squallms_results.csv
    touch ${prefix}_squallms_output.rds
    echo "BIOC_SQUALLMS:" > versions.yml
    echo "    squallms: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SQUALLMS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SQUALLMS(ch_input)

    emit:
    results  = BIOC_SQUALLMS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SQUALLMS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SQUALLMS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SQUALLMS.out.versions  // channel: path(versions.yml)
}
