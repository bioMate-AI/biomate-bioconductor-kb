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

    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    data("timeOmics.simdata")
    sim.data <- timeOmics.simdata$sim
    dim(sim.data)
    head(sim.data[,1:6])
    # --- Function [] ---
    # Key functions: unlist, frame
    ---------------------------------------------------------------------
    # --- Frame [] ---
    # Key functions: frame, rownames_to_column, mutate, pivot_longer, ggplot, aes, geom_line
    ---------------------------------------------------------------------
    # gather data
    data.gathered <- modelled.data %>% as.data.frame() %>%
      rownames_to_column("time") %>%
      mutate(time = as.numeric(time)) %>%
    # --- Pca [] ---
    # Key functions: pca, getNcomp
    ---------------------------------------------------------------------
    # run pca
    pca.res <- pca(X = profile.filtered, ncomp = 5, scale=FALSE, center=FALSE)
    # tuning ncomp
    # --- Pca [] ---
    # Key functions: pca
    ---------------------------------------------------------------------
    # final model
    pca.res <- pca(X = profile.filtered, ncomp = 2, scale = FALSE, center=FALSE)
    # --- Getcluster [] ---
    # Key functions: getCluster
    ---------------------------------------------------------------------
    # extract cluster
    pca.cluster <- getCluster(pca.res)
    head(pca.cluster)
    # --- Plotindiv [] ---
    # Key functions: plotIndiv
    ---------------------------------------------------------------------
    plotIndiv(pca.res)
    # --- Plotvar [] ---
    # Key functions: plotVar
    ---------------------------------------------------------------------
    plotVar(pca.res)
    # --- Plotloadings [] ---
    # Key functions: plotLoadings
    ---------------------------------------------------------------------
    plotLoadings(pca.res)
    # --- Plotlong [] ---
    # Key functions: plotLong
    ---------------------------------------------------------------------
    plotLong(pca.res, scale = FALSE, center = FALSE,
             title = "PCA longitudinal clustering")
    # --- Spca [] ---
    # Key functions: spca
    ---------------------------------------------------------------------
    tune.spca.res <- tuneCluster.spca(X = profile.filtered, ncomp = 2,
                                      test.keepX = c(2:10))
    # selected features in each component
    tune.spca.res$choice.keepX
    # --- Spca [] ---
    # Key functions: spca, plotLong
    ---------------------------------------------------------------------
    # final model
    spca.res <- spca(X = profile.filtered, ncomp = 2,
                     keepX = tune.spca.res$choice.keepX, scale = FALSE)
    plotLong(spca.res)
    # --- Pls [] ---
    # Key functions: pls, getNcomp
    ---------------------------------------------------------------------
    X <- profile.filtered
    Y <- timeOmics.simdata$Y
    pls.res <- pls(X,Y, ncomp = 5, scale = FALSE)
    pls.ncomp <- getNcomp(pls.res, max.ncomp = 5, X=X, Y=Y, scale = FALSE)
    # --- Pls [] ---
    # Key functions: pls, getCluster, plotLong
    ---------------------------------------------------------------------
    # final model
    pls.res <- pls(X,Y, ncomp = 2, scale = FALSE)
    # info cluster
    head(getCluster(pls.res))
    # --- Spls [] ---
    # Key functions: spls, getCluster, plotLong
    ---------------------------------------------------------------------
    tune.spls <- tuneCluster.spls(X, Y, ncomp = 2, test.keepX = c(4:10), test.keepY <- c(2,4,6))
    # selected features in each component on block X
    tune.spls$choice.keepX
    # selected features in each component on block Y

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
