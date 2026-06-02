#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: timeOmics
// timeOmics is a generic data-driven framework to integrate multi-Omics longitudinal data measured on 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/timeOmics/inst/doc/vignette.R
// Upstream  : tidyverse
// Downstream: none
//
// Install: BiocManager::install("timeOmics")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TIMEOMICS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-timeomics"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-timeomics:1.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-timeomics:1.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_timeomics_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_timeomics_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_timeomics_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(timeOmics)
    library(jsonlite)

    # --- Longitudinal PCA [] ---
    # Key functions: pca, getNcomp, getCluster, plotLong
    pca.res <- pca(
        X = profile.filtered, ncomp = 5,
        scale = FALSE, center = FALSE
    )
    pca.ncomp <- getNcomp(
        pca.res, max.ncomp = 5, X = profile.filtered,
        scale = FALSE, center = FALSE
    )
    pca.final <- pca(
        X = profile.filtered, ncomp = pca.ncomp$choice.ncomp,
        scale = FALSE, center = FALSE
    )
    pca.cluster <- getCluster(pca.final)
    plotLong(pca.final, scale = FALSE, center = FALSE)


    # --- Sparse PCA Feature Selection [] ---
    # Key functions: tuneCluster.spca, spca, getCluster, plotLong
    tune.spca.res <- tuneCluster.spca(
        X = profile.filtered, ncomp = 2,
        test.keepX = c(2:10)
    )
    spca.res <- spca(
        X = profile.filtered, ncomp = 2,
        keepX = tune.spca.res$choice.keepX, scale = FALSE
    )
    spca.cluster <- getCluster(spca.res)
    plotLong(spca.res)


    # --- Partial Least Squares Integration [] ---
    # Key functions: pls, getNcomp, getCluster, plotLong
    Y <- timeOmics.simdata$Y
    pls.res <- pls(profile.filtered, Y, ncomp = 5, scale = FALSE)
    pls.ncomp <- getNcomp(
        pls.res, max.ncomp = 5, X = profile.filtered,
        Y = Y, scale = FALSE
    )
    pls.final <- pls(
        profile.filtered, Y, ncomp = pls.ncomp$choice.ncomp,
        scale = FALSE
    )
    pls.cluster <- getCluster(pls.final)
    plotLong(pls.final, title = "PLS longitudinal clustering")


    # --- Sparse PLS Integration [] ---
    # Key functions: tuneCluster.spls, spls, getCluster, plotLong
    Y <- timeOmics.simdata$Y
    tune.spls <- tuneCluster.spls(
        profile.filtered, Y, ncomp = 2,
        test.keepX = c(4:10), test.keepY = c(2,4,6)
    )
    spls.res <- spls(
        profile.filtered, Y, ncomp = 2, scale = FALSE,
        keepX = tune.spls$choice.keepX, keepY = tune.spls$choice.keepY
    )
    spls.cluster <- getCluster(spls.res)
    plotLong(spls.res, title = "sPLS clustering")


    # --- Multi-Omics Block PLS [] ---
    # Key functions: block.pls, getNcomp, getCluster, plotLong
    X_list <- list("X" = profile.filtered, "Z" = timeOmics.simdata$Z)
    Y_mat <- as.matrix(timeOmics.simdata$Y)
    block.pls.res <- block.pls(
        X = X_list, Y = Y_mat, ncomp = 5,
        scale = FALSE, mode = "canonical"
    )
    block.ncomp <- getNcomp(
        block.pls.res, X = X_list, Y = Y_mat,
        scale = FALSE, mode = "canonical"
    )
    block.final <- block.pls(
        X = X_list, Y = Y_mat, ncomp = block.ncomp$choice.ncomp,
        scale = FALSE, mode = "canonical"
    )
    block.cluster <- getCluster(block.final)
    plotLong(block.final)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_timeomics_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_timeomics_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_timeomics_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TIMEOMICS:", paste0("    timeomics: ", packageVersion("timeOmics"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_timeomics_results.csv
    touch ${prefix}_timeomics_output.rds
    echo "BIOC_TIMEOMICS:" > versions.yml
    echo "    timeomics: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TIMEOMICS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TIMEOMICS(ch_input)

    emit:
    results  = BIOC_TIMEOMICS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TIMEOMICS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TIMEOMICS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TIMEOMICS.out.versions  // channel: path(versions.yml)
}
