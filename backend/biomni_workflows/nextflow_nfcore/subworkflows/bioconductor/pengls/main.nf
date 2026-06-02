#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: pengls
// Combine generalised least squares methodology from the nlme package for dealing with autocorrelation
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/pengls/inst/doc/penglsVignette.R
// Upstream  : BiocManager, BiocParallel, nlme
// Downstream: none
//
// Install: BiocManager::install("pengls")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PENGLS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-pengls"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-pengls:1.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-pengls:1.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_pengls_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_pengls_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_pengls_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(pengls)
    library(jsonlite)


    # --- Load Rcmpackage [] ---
    # Key functions: suppressPackageStartupMessages, packageVersion, pengls, expand.grid, sample, rnorm, rbinom
    suppressPackageStartupMessages(library(pengls))
    cat("pengls package version", as.character(packageVersion("pengls")), "\n")
    library(nlme)
    n <- 25 #Sample size
    p <- 50 #Number of features
    g <- 15 #Size of the grid
    #Generate grid
    Grid <- expand.grid("x" = seq_len(g), "y" = seq_len(g))
    # Sample points from grid without replacement
    GridSample <- Grid[sample(nrow(Grid), n, replace = FALSE),]
    #Generate outcome and regressors
    b <- matrix(rnorm(p*n), n , p)

    # --- Spatial Correlation [] ---
    # Key functions: structure, corGaus, nugget, pengls
    # Define the correlation structure (see ?nlme::gls), with initial nugget 0.5 and range 5
    corStruct <- corGaus(form = ~ x + y, nugget = TRUE, value = c("range" = 5, "nugget" = 0.5))
    #Fit the pengls model, for simplicity for a simple lambda
    penglsFit <- pengls(data = df, outVar = "a", xNames = grep(names(df), pattern = "b", value =TRUE), glsSt = corStruct, lambda = 0.2, verbose = TRUE)

    # --- Standard Extract [] ---
    # Key functions: predict, rnorm, rbinom, corAR1
    penglsFit
    penglsCoef <- coef(penglsFit)
    penglsPred <- predict(penglsFit)
    set.seed(354509)
    n <- 100 #Sample size
    p <- 10 #Number of features
    #Generate outcome and regressors
    b <- matrix(rnorm(p*n), n , p)
    a <- rnorm(n, mean = b %*% rbinom(p, size = 1, p = 0.25), sd = 0.1) #25% signal
    #Compile to a matrix
    dfTime <- data.frame("a" = a, "b" = b, "t" = seq_len(n))
    corStructTime <- corAR1(form = ~ t, value = 0.5)

    # --- Time Fit [] ---
    # Key functions: pengls, register, MulticoreParam
    penglsFitTime <- pengls(data = dfTime, outVar = "a", verbose = TRUE,
    xNames = grep(names(dfTime), pattern = "b", value =TRUE),
    glsSt = corStructTime, nfolds = 5, alpha = 0.5)

    ## -----------------------------------------------------------------------------
    penglsFitTime
    library(BiocParallel)
    register(MulticoreParam(3)) #Prepare multithereading

    # --- Nfolds [] ---
    # Key functions: cv.pengls
    nfolds <- 3 #Number of cross-validation folds
    penglsFitCV <- cv.pengls(data = df, outVar = "a", xNames = grep(names(df), pattern = "b", value =TRUE), glsSt = corStruct, nfolds = nfolds)

    # --- Print Cv [] ---
    # Key functions: pengls
    penglsFitCV
    penglsFitCV$lambda.1se #Lambda for 1 standard error rule
    penglsFitCV$cvOpt #Corresponding R2

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_pengls_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_pengls_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_pengls_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PENGLS:", paste0("    pengls: ", packageVersion("pengls"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pengls_results.csv
    touch ${prefix}_pengls_output.rds
    echo "BIOC_PENGLS:" > versions.yml
    echo "    pengls: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PENGLS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PENGLS(ch_input)

    emit:
    results  = BIOC_PENGLS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PENGLS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PENGLS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PENGLS.out.versions  // channel: path(versions.yml)
}
