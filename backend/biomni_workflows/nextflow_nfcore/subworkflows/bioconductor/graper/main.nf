#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: graper
// This package enables regression and classification on high-dimensional data with different relative 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/graper/inst/doc/example_linear.R
// Upstream  : ggplot2
// Downstream: none
//
// Install: BiocManager::install("graper")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GRAPER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-graper"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-graper:1.22.0--r44_0' :
        'quay.io/biocontainers/bioconductor-graper:1.22.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_graper_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_graper_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_graper_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(graper)
    library(jsonlite)

    # --- Graper [] ---
    # Key functions: graper
    ---------------------------------------------------------------------
    fit <- graper(Xtrain, ytrain, annot,
                n_rep=3, verbose=FALSE, th=0.001)
    fit
    # --- Plotelbo [] ---
    # Key functions: plotELBO
    ---------------------------------------------------------------------
    plotELBO(fit)
    # --- Plotposterior [] ---
    # Key functions: plotPosterior
    ---------------------------------------------------------------------
    plotPosterior(fit, "gamma", gamma0=data$gammas, range=c(0, 20))
    plotPosterior(fit, "pi", pi0=data$pis)
    # --- Coefficients [] ---
    # Key functions: coefficients, coef, qplot, coord_fixed, theme_bw
    ---------------------------------------------------------------------
    # get coefficients (without the intercept)
    beta <- coef(fit, include_intercept=FALSE)
    # beta <- fit$EW_beta
    # plot estimated versus true beta
    # --- Getpips [] ---
    # Key functions: getPIPs, frame, ggplot, aes, geom_jitter, theme_bw, ylab
    ---------------------------------------------------------------------
    # get estimated posterior inclusion probabilities per feature
    pips <- getPIPs(fit)
    # plot pips for zero versus non-zero features
    df <- data.frame(pips = pips,
    # --- Plotgrouppenalties [] ---
    # Key functions: plotGroupPenalties
    ---------------------------------------------------------------------
    plotGroupPenalties(fit)
    # --- Predict [] ---
    # Key functions: predict, qplot, coord_fixed, theme_bw
    ---------------------------------------------------------------------
    preds <- predict(fit, Xtest)
    qplot(preds, ytest) +
        coord_fixed() + theme_bw()

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_graper_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_graper_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_graper_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GRAPER:", paste0("    graper: ", packageVersion("graper"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_graper_results.csv
    touch ${prefix}_graper_output.rds
    echo "BIOC_GRAPER:" > versions.yml
    echo "    graper: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GRAPER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GRAPER(ch_input)

    emit:
    results  = BIOC_GRAPER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GRAPER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GRAPER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GRAPER.out.versions  // channel: path(versions.yml)
}
