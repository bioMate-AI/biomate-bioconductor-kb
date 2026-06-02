#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: factDesign
// This package provides a set of tools for analyzing data from a factorial designed microarray experim
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/factDesign/inst/doc/factDesign.R
// Upstream  : Biobase, affy, multtest, stats
// Downstream: none
//
// Install: BiocManager::install("factDesign")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FACTDESIGN {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-factdesign"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-factdesign:1.82.0--r44_0' :
        'quay.io/biocontainers/bioconductor-factdesign:1.82.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_factdesign_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_factdesign_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_factdesign_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(factDesign)
    library(jsonlite)

    # --- Linear Modeling [] ---
    # Key functions: esApply
    data(estrogen, package = "factDesign")
    lm.full <- function(y) lm(y ~ ES + TIME + ES:TIME)
    lm.time <- function(y) lm(y ~ TIME)
    lm.f <- esApply(estrogen, 1, lm.full)
    lm.t <- esApply(estrogen, 1, lm.time)


    # --- Contrast Testing [] ---
    # Key functions: par2lambda, contrastTest
    data(estrogen, package = "factDesign")
    lm.full <- function(y) lm(y ~ ES + TIME + ES:TIME)
    lm.f <- esApply(estrogen, 1, lm.full)
    betaNames <- names(coef(lm.f[[1]]))
    lambda <- par2lambda(betaNames, c("ESP"), c(1))
    mainES <- function(x) contrastTest(x, lambda, p = 0.05)[[1]]
    mainESgenes <- sapply(lm.f, FUN = mainES)


    # --- Fold Change Estimation [] ---
    # Key functions: par2lambda, findFC
    data(estrogen, package = "factDesign")
    lm.full <- function(y) lm(y ~ ES + TIME + ES:TIME)
    lm.f <- esApply(estrogen, 1, lm.full)
    betaNames <- names(coef(lm.f[[1]]))
    lambdaNum <- par2lambda(
        betaNames,
        list(c("(Intercept)", "ESP")),
        list(c(1, 1))
    )
    lambdaDenom <- par2lambda(betaNames, list(c("(Intercept)")), list(c(1)))
    FCvals <- lapply(
        lm.f,
        FUN = findFC,
        lambdaNum,
        lambdaDenom,
        logbase = 2
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_factdesign_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_factdesign_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_factdesign_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FACTDESIGN:", paste0("    factdesign: ", packageVersion("factDesign"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_factdesign_results.csv
    touch ${prefix}_factdesign_output.rds
    echo "BIOC_FACTDESIGN:" > versions.yml
    echo "    factdesign: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FACTDESIGN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_FACTDESIGN(ch_input)

    emit:
    results  = BIOC_FACTDESIGN.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FACTDESIGN.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FACTDESIGN.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FACTDESIGN.out.versions  // channel: path(versions.yml)
}
