#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ssize
// Functions for computing and displaying sample size information for gene expression arrays.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ssize/inst/doc/ssize.R
// Upstream  : gdata, xtable
// Downstream: none
//
// Install: BiocManager::install("ssize")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SSIZE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ssize"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ssize:1.80.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ssize:1.80.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ssize_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ssize_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ssize_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ssize)
    library(jsonlite)

    # --- Statistical Power Estimation [] ---
    # Key functions: pow, power.plot
    exp.sd <- runif(1000, 0.1, 1.5)
    fold.change <- 2
    sig.level <- 0.05
    n <- 10
    all.power <- pow(sd = exp.sd, n = n, delta = log2(fold.change),
                     sig.level = sig.level)
    power.plot(all.power, lwd = 2, col = "blue")
    title("Power to Detect 2-Fold Change")


    # --- Fold Change Estimation [] ---
    # Key functions: delta, delta.plot
    exp.sd <- runif(1000, 0.1, 1.5)
    sig.level <- 0.05
    power <- 0.8
    n <- 10
    all.delta <- delta(sd = exp.sd, power = power, n = n,
                       sig.level = sig.level)
    delta.plot(all.delta, lwd = 2, col = "magenta", xlim = c(1, 10),
               ylab = "Proportion of Genes with Power >= 80%")
    title("Fold Change to Achieve 80% Power")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ssize_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ssize_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ssize_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SSIZE:", paste0("    ssize: ", packageVersion("ssize"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ssize_results.csv
    touch ${prefix}_ssize_output.rds
    echo "BIOC_SSIZE:" > versions.yml
    echo "    ssize: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SSIZE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SSIZE(ch_input)

    emit:
    results  = BIOC_SSIZE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SSIZE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SSIZE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SSIZE.out.versions  // channel: path(versions.yml)
}
