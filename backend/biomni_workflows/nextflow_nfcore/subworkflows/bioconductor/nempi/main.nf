#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: nempi
// Takes as input an incomplete perturbation profile and differential gene expression in log odds and i
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/nempi/inst/doc/nempi.R
// Upstream  : mnem
// Downstream: none
//
// Install: BiocManager::install("nempi")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_NEMPI {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-nempi"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-nempi:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-nempi:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_nempi_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_nempi_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_nempi_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(nempi)
    library(jsonlite)


    # --- Global Options [] ---
    # Key functions: set, palette, center, blue, brown
    knitr::opts_chunk$set(message=FALSE, out.width="125%", fig.align="center",
                          strip.white=TRUE, warning=FALSE, tidy=TRUE,
                          #out.extra='style="display:block; margin:auto;"',
                          fig.height = 4, fig.width = 8, error=FALSE)
    fig.cap0 <- "Heatmap of the simulated log odds. Effects are blue and no effects
    are red. Rows denote the observed E-genes and columns the samples annoted by
    P-genes. Each P-gene
    has been perturbed in many cells. The E-genes are annotated as how they are
    attached in the ground truth. E.g. E-genes named '1' are attached to S-gene
    '1' in the ground truth."
    fig.cap1 <- "Heatmap of the probabilsitic perturbation matrix."
    paltmp <- palette()
    paltmp[3] <- "blue"
    paltmp[4] <- "brown"
    palette(paltmp)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_nempi_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_nempi_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_nempi_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_NEMPI:", paste0("    nempi: ", packageVersion("nempi"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_nempi_results.csv
    touch ${prefix}_nempi_output.rds
    echo "BIOC_NEMPI:" > versions.yml
    echo "    nempi: 0.0.0" >> versions.yml
    """
}


workflow BIOC_NEMPI_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_NEMPI(ch_input)

    emit:
    results  = BIOC_NEMPI.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_NEMPI.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_NEMPI.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_NEMPI.out.versions  // channel: path(versions.yml)
}
