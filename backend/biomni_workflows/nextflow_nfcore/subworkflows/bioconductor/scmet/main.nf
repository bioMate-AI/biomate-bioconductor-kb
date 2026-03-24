#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: scMET
// High-throughput single-cell measurements of DNA methylomes can quantify methylation heterogeneity an
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/scMET/inst/doc/scMET_vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("scMET")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCMET {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-scmet"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-scmet:1.8.0--r44_0' :
        'quay.io/biocontainers/bioconductor-scmet:1.8.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_scmet_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_scmet_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_scmet_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(scMET)
    library(jsonlite)

    # --- Plot Synthetic [] ---
    # Key functions: expression
    par(mfrow = c(1,2))
    plot(scmet_dt$theta_true$mu, scmet_dt$theta_true$gamma, pch = 20,
         xlab = expression(paste("Mean methylation ",  mu)),
         ylab = expression(paste("Overdsispersion ",  gamma)))
    plot(scmet_dt$X[,2], scmet_dt$theta_true$mu, pch = 20,
    # --- Run Scmet Synthetic [] ---
    # Key functions: scmet
    # Run with seed for reproducibility
    fit_obj <- scmet(Y = scmet_dt$Y, X = scmet_dt$X, L = 4,
                     iter = 1000, seed = 12)
    # --- Mean Var Plot1 [] ---
    # Key functions: scmet_plot_mean_var, plot_grid
    gg1 <- scmet_plot_mean_var(obj = fit_obj, y = "gamma",
                               task = NULL, show_fit = TRUE)
    gg2 <- scmet_plot_mean_var(obj = fit_obj, y = "epsilon",
                               task = NULL, show_fit = TRUE)
    cowplot::plot_grid(gg1, gg2, ncol = 2)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_scmet_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_scmet_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_scmet_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SCMET:", paste0("    scmet: ", packageVersion("scMET"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scmet_results.csv
    touch ${prefix}_scmet_output.rds
    echo "BIOC_SCMET:" > versions.yml
    echo "    scmet: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SCMET_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SCMET(ch_input)

    emit:
    results  = BIOC_SCMET.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SCMET.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SCMET.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SCMET.out.versions  // channel: path(versions.yml)
}
