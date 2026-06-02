#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: spillR
// Channel interference in mass cytometry can cause spillover and may result in miscounting of protein 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/spillR/inst/doc/spillR-vignette.R
// Upstream  : CATALYST, cowplot, dplyr, ggplot2
// Downstream: none
//
// Install: BiocManager::install("spillR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SPILLR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-spillr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-spillr:1.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-spillr:1.2.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_spillr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_spillr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_spillr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(spillR)
    library(jsonlite)

    # --- prep Data [] ---
    # Key functions: prepData, assignPrelim, applyCutoffs, computeSpillmat
    library(spillR)
    library(CATALYST)
    library(dplyr)
    # --- row Data [] ---
    # Key functions: rowData, as_tibble, compCytof, plot_grid
    rowData(sce_bead)[, c("channel_name", "is_bc")] |>
    as_tibble() |>
    dplyr::filter(is_bc == TRUE) |>
    # --- plot Diagnostics [] ---
    # Key functions: plotDiagnostics, plot_grid
    ps <- spillR::plotDiagnostics(sce_spillr, "Yb173Di")
    x_lim <- c(0, 7)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_spillr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_spillr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_spillr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SPILLR:", paste0("    spillr: ", packageVersion("spillR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_spillr_results.csv
    touch ${prefix}_spillr_output.rds
    echo "BIOC_SPILLR:" > versions.yml
    echo "    spillr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SPILLR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SPILLR(ch_input)

    emit:
    results  = BIOC_SPILLR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SPILLR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SPILLR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SPILLR.out.versions  // channel: path(versions.yml)
}
