#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: iSEEindex
// This package provides an interface to any collection of data sets within a single iSEE web-applicati
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/iSEEindex/inst/doc/header.R
// Upstream  : BiocFileCache, RefManageR, knitr, rmarkdown, sessioninfo
// Downstream: none
//
// Install: BiocManager::install("iSEEindex")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ISEEINDEX {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-iseeindex"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-iseeindex:1.4.0--r44_0' :
        'quay.io/biocontainers/bioconductor-iseeindex:1.4.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_iseeindex_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_iseeindex_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_iseeindex_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(PrintBibliography)
    library(jsonlite)

    # --- knit [] ---
    # Key functions: knit
    library("rmarkdown")
    system.time(render("header.Rmd", "BiocStyle::html_document"))
    library("knitr")
    # --- diff [] ---
    # Key functions: diff
    totalTime <- diff(c(startTime, Sys.time()))
    round(totalTime, digits = 3)
    # --- session_info [] ---
    # Key functions: session_info
    library("sessioninfo")
    options(width = 100)
    session_info()
    # --- Print Bibliography [] ---
    # Key functions: PrintBibliography
    PrintBibliography(bib, .opts = list(hyperlink = "to.doc", style = "html"))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_iseeindex_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_iseeindex_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_iseeindex_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ISEEINDEX:", paste0("    iseeindex: ", packageVersion("iSEEindex"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_iseeindex_results.csv
    touch ${prefix}_iseeindex_output.rds
    echo "BIOC_ISEEINDEX:" > versions.yml
    echo "    iseeindex: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ISEEINDEX_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ISEEINDEX(ch_input)

    emit:
    results  = BIOC_ISEEINDEX.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ISEEINDEX.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ISEEINDEX.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ISEEINDEX.out.versions  // channel: path(versions.yml)
}
