#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: mixOmics
// Multivariate methods are well suited to large omics data sets where the number of variables (e.g. ge
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/mixOmics/inst/doc/vignette.R
// Upstream  : igraph, kableExtra, knitr
// Downstream: timeOmics, mixKernel, sgPLS
//
// Install: BiocManager::install("mixOmics")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MIXOMICS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mixomics"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mixomics:6.30.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mixomics:6.30.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mixomics_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mixomics_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mixomics_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(mixOmics)
    library(X11)
    library(jsonlite)

    # --- Principal Component Analysis ---
    # Key functions: pca, color.mixo, plotVar, biplot
    data(liver.toxicity)
    X <- liver.toxicity$gene
    final.pca.multi <- pca(X, ncomp = 3, center = TRUE, scale = TRUE)
    col.var <- rep(color.mixo(1), ncol(X))
    names(col.var) <- colnames(X)
    plotVar(final.pca.multi, comp = c(1, 2), var.names = FALSE,
            col = list(col.var), cex = 3,
            title = 'Liver Toxicity PCA')
    biplot(final.pca.multi, group = liver.toxicity$treatment$Dose,
           legend.title = 'Dose')

    # --- Sparse PCA Tuning and Fitting ---
    # Key functions: tune.spca, spca, plotIndiv, plotLoadings
    grid.keepX <- c(seq(5, 30, 5))
    tune.spca.result <- tune.spca(X, ncomp = 2, folds = 3,
                                  test.keepX = grid.keepX,
                                  nrepeat = 2)
    keepX.select <- tune.spca.result$choice.keepX[1:2]
    final.spca.multi <- spca(X, ncomp = 2, keepX = keepX.select)
    plotIndiv(final.spca.multi, comp = c(1, 2), ind.names = TRUE,
              group = liver.toxicity$treatment$Dose,
              title = 'sPCA comp 1 - 2')
    plotLoadings(final.spca.multi, comp = 2)

    # --- PLS Performance Evaluation ---
    # Key functions: pls, perf
    y <- liver.toxicity$clinic[, "ALB.g.dL."]
    tune.pls1.liver <- pls(X = X, Y = y, ncomp = 3, mode = 'regression')
    Q2.pls1.liver <- perf(tune.pls1.liver, validation = 'Mfold',
                          folds = 5, nrepeat = 2)
    plot(Q2.pls1.liver, criterion = 'Q2')

    # --- Sparse PLS Tuning and Fitting ---
    # Key functions: tune.spls, spls, selectVar
    list.keepX <- c(5:10, seq(15, 30, 5))
    tune.spls1.MAE <- tune.spls(X, y, ncomp = 2,
                                test.keepX = list.keepX,
                                validation = 'Mfold', folds = 5,
                                nrepeat = 2, progressBar = FALSE,
                                measure = 'MAE')
    choice.ncomp <- tune.spls1.MAE$choice.ncomp$ncomp
    choice.keepX <- tune.spls1.MAE$choice.keepX[1:choice.ncomp]
    spls1.liver <- spls(X, y, ncomp = choice.ncomp,
                        keepX = choice.keepX, mode = "regression")
    selected.vars <- selectVar(spls1.liver, comp = 1)$X$name


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mixomics_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mixomics_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mixomics_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MIXOMICS:", paste0("    mixomics: ", packageVersion("mixOmics"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mixomics_results.csv
    touch ${prefix}_mixomics_output.rds
    echo "BIOC_MIXOMICS:" > versions.yml
    echo "    mixomics: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MIXOMICS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MIXOMICS(ch_input)

    emit:
    results  = BIOC_MIXOMICS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MIXOMICS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MIXOMICS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MIXOMICS.out.versions  // channel: path(versions.yml)
}
