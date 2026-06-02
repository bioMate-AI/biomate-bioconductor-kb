#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: tripr
// TRIP is a software framework that provides analytics services on antigen receptor (B cell receptor i
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/tripr/inst/doc/tripr_guide.R
// Upstream  : BiocStyle, RefManageR
// Downstream: none
//
// Install: BiocManager::install("tripr")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TRIPR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-tripr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-tripr:1.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-tripr:1.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_tripr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_tripr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_tripr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(tripr)
    library(jsonlite)


    # --- Vignette Setup [] ---
    # Key functions: Sys.time, citation, ggplot2, golem, plotly
    ## For links
    library("BiocStyle")
    ## Track time spent on making the vignette
    #startTime <- Sys.time()
    ## Bib setup
    library("RefManageR")
    ## Write bibliography information
    # --- Include = False [] ---
    # Key functions: set
    knitr::opts_chunk$set(
      collapse = TRUE,
        comment = "#>",
        error = FALSE,
        warning = FALSE,
        message = FALSE,
        crop = NULL
    )

    # --- 'citation' [] ---
    # Key functions: citation, tripr
    ## Citation info
    citation("tripr")

    # --- Vignette Biblio [] ---
    # Key functions: PrintBibliography, to.doc, html
    ## Print bibliography
    PrintBibliography(bib, .opts = list(hyperlink = "to.doc", style = "html"))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_tripr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_tripr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_tripr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TRIPR:", paste0("    tripr: ", packageVersion("tripr"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tripr_results.csv
    touch ${prefix}_tripr_output.rds
    echo "BIOC_TRIPR:" > versions.yml
    echo "    tripr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TRIPR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TRIPR(ch_input)

    emit:
    results  = BIOC_TRIPR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TRIPR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TRIPR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TRIPR.out.versions  // channel: path(versions.yml)
}
