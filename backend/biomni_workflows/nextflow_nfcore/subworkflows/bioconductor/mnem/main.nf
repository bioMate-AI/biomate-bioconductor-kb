#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: mnem
// Mixture Nested Effects Models (mnem) is an extension of Nested Effects Models and allows for the ana
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/mnem/inst/doc/mnem.R
// Upstream  : none
// Downstream: nempi
//
// Install: BiocManager::install("mnem")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MNEM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mnem"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mnem:1.22.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mnem:1.22.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mnem_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mnem_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mnem_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(mnem)
    library(jsonlite)


    # --- Global Options [] ---
    # Key functions: set, center
    knitr::opts_chunk$set(message=FALSE, out.width="125%", fig.align="center",
                          strip.white=TRUE, warning=FALSE, tidy=TRUE,
                          #out.extra='style="display:block; margin:auto;"',
                          fig.height = 4, fig.width = 8, error=FALSE)
    fig.cap0 <- "Heatmap of the simulated log odds. Effects are blue and no effects
    are red. Rows denote the observed E-genes and columns the S-genes. Each S-gene
    has been perturbed in many cells. The E-genes are annotated as how they are
    attached in the ground truth. E.g. E-genes named '1' are attached to S-gene
    '1' in the ground truth."
    fig.cap01 <- "Mixture NEM result for the simulated data. On top we show
    the cell assignment percentages for hard clustering and the mixture weights.
    The large circular vertices depict the S-genes, the small ones the
    responsibility for the best fitting cell, the diamonds the number of assigned
    cells and the boxes the number of assigned E-genes."
    fig.cap0em <- "EM Convergence. Convergence plot for the different starts of the

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mnem_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mnem_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mnem_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MNEM:", paste0("    mnem: ", packageVersion("mnem"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mnem_results.csv
    touch ${prefix}_mnem_output.rds
    echo "BIOC_MNEM:" > versions.yml
    echo "    mnem: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MNEM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MNEM(ch_input)

    emit:
    results  = BIOC_MNEM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MNEM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MNEM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MNEM.out.versions  // channel: path(versions.yml)
}
