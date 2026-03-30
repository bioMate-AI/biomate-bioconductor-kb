#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: powerTCR
// This package provides a model for the clone size distribution of the TCR repertoire. Further, it per
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/powerTCR/inst/doc/powerTCR.R
// Upstream  : magrittr, purrr, vegan
// Downstream: none
//
// Install: BiocManager::install("powerTCR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_POWERTCR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-powertcr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-powertcr:1.26.0--r44_0' :
        'quay.io/biocontainers/bioconductor-powertcr:1.26.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_powertcr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_powertcr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_powertcr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(powerTCR)
    library(jsonlite)

    # --- Get Mle [] ---
    # Key functions: get_mle, get_nllh
    ---------------------------------------------------------------------
    # Grab mles of fits:
    get_mle(fits)
    # Grab negative log likelihoods of fits
    get_nllh(fits)
    # --- List [] ---
    # Key functions: fdesponds
    ---------------------------------------------------------------------
    desponds_fits <- list()
    for(i in seq_along(repertoires)){
        desponds_fits[[i]] <- fdesponds(repertoires[[i]])
    }
    # --- Rdiscgammagpd [] ---
    # Key functions: rdiscgammagpd
    ---------------------------------------------------------------------
    bad <- rdiscgammagpd(1000, shape = 1, rate = 2, u = 25, sigma = 10,
                         xi = .5, shift = 1, phi = .2)
    plot(log(sort(bad, decreasing = TRUE)), log(seq_len(1000)), pch = 16,
         xlab = "log clone size", ylab = "log rank", main = "bad simulation")
    # --- List [] ---
    # Key functions: fdiscgammagpd, get_distances
    ---------------------------------------------------------------------
    # Fit model to the data at the true thresholds
    sim_fits <- list("s1" = fdiscgammagpd(s1, useq = 25),
                     "s2" = fdiscgammagpd(s2, useq = 26),
                     "s3" = fdiscgammagpd(s3, useq = 45))
    # --- Get Bootstraps [] ---
    # Key functions: get_bootstraps
    ---------------------------------------------------------------------
    boot <- get_bootstraps(fits, resamples = 5, cores = 1, gridStyle = "copy")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_powertcr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_powertcr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_powertcr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_POWERTCR:", paste0("    powertcr: ", packageVersion("powerTCR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_powertcr_results.csv
    touch ${prefix}_powertcr_output.rds
    echo "BIOC_POWERTCR:" > versions.yml
    echo "    powertcr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_POWERTCR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_POWERTCR(ch_input)

    emit:
    results  = BIOC_POWERTCR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_POWERTCR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_POWERTCR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_POWERTCR.out.versions  // channel: path(versions.yml)
}
