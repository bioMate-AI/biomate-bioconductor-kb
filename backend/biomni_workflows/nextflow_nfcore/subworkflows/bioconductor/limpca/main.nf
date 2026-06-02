#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: limpca
// This package has for objectives to provide a method to make Linear Models for high-dimensional desig
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/limpca/inst/doc/Trout.R
// Upstream  : SummarizedExperiment, car, ggplot2, gridExtra, pander
// Downstream: none
//
// Install: BiocManager::install("limpca")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_LIMPCA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-limpca"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-limpca:1.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-limpca:1.2.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_limpca_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_limpca_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_limpca_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(limpca)
    library(Anova)
    library(jsonlite)

    # --- Exploratory PCA [] ---
    # Key functions: pcaBySvd, pcaScreePlot, pcaScorePlot
    data("trout")
    resPCA <- limpca::pcaBySvd(trout$outcomes)
    limpca::pcaScreePlot(resPCA, nPC = 8)
    limpca::pcaScorePlot(
        resPcaBySvd = resPCA, axes = c(1, 2),
        title = "Score plot of original data ",
        design = trout$design, color = "Aquarium",
        points_labs_rn = TRUE
    )


    # --- Data Preprocessing and Outlier Removal [] ---
    # Key functions: pcaBySvd, pcaScorePlot
    data("trout")
    trout_log <- trout
    trout_log$outcomes <- as.matrix(log10(trout$outcomes))
    outliers <- match(
        c("D72EPA2.1", "D28EPA2.2"), 
        rownames(trout_log$outcomes)
    )
    trout_clean <- trout_log
    trout_clean$outcomes <- trout_log$outcomes[-outliers, ]
    trout_clean$design <- trout_log$design[-outliers, ]
    resPCA2 <- limpca::pcaBySvd(trout_clean$outcomes)
    limpca::pcaScorePlot(
        resPcaBySvd = resPCA2, axes = c(1, 2),
        title = "Score plot without outliers",
        design = trout_clean$design, color = "Aquarium",
        drawShapes = "polygon", points_labs_rn = FALSE
    )


    # --- Aggregated PCA and Loadings [] ---
    # Key functions: plotLine, pcaBySvd, pcaScorePlot, pcaLoading1dPlot, pcaLoading2dPlot
    data("trout")
    trout_mean_outcomes <- scale(
        trout$outcomes[1:24, ], 
        center = TRUE, 
        scale = TRUE
    )
    trout_mean_design <- trout$design[1:24, 1:3]
    limpca::plotLine(
        trout_mean_outcomes, rows = c(1, 24),
        xaxis_type = "character", type = "s"
    )
    resPCA_mean <- limpca::pcaBySvd(trout_mean_outcomes)
    limpca::pcaScorePlot(
        resPcaBySvd = resPCA_mean, axes = c(1, 2),
        title = "PCA score plot by Exposure and Day",
        design = trout_mean_design, shape = "Exposure", color = "Day",
        points_labs_rn = FALSE
    )
    limpca::pcaLoading1dPlot(
        resPcaBySvd = resPCA_mean, axes = c(1, 2),
        title = "PCA loadings plot trout", xlab = " ",
        ylab = "Expression", xaxis_type = "character", type = "s"
    )
    limpca::pcaLoading2dPlot(
        resPcaBySvd = resPCA_mean, axes = c(1, 2),
        title = "PCA loadings plot trout", addRownames = TRUE
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_limpca_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_limpca_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_limpca_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_LIMPCA:", paste0("    limpca: ", packageVersion("limpca"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_limpca_results.csv
    touch ${prefix}_limpca_output.rds
    echo "BIOC_LIMPCA:" > versions.yml
    echo "    limpca: 0.0.0" >> versions.yml
    """
}


workflow BIOC_LIMPCA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_LIMPCA(ch_input)

    emit:
    results  = BIOC_LIMPCA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_LIMPCA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_LIMPCA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_LIMPCA.out.versions  // channel: path(versions.yml)
}
