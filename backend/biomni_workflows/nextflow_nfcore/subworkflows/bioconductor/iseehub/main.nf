#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: iSEEhub
// This package defines a custom landing page for an iSEE app interfacing with the Bioconductor Experim
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/iSEEhub/inst/doc/contributing.R
// Upstream  : ExperimentHub, RefManageR, knitr, rmarkdown, sessioninfo
// Downstream: none
//
// Install: BiocManager::install("iSEEhub")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ISEEHUB {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-iseehub"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-iseehub:1.8.0--r44_0' :
        'quay.io/biocontainers/bioconductor-iseehub:1.8.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_iseehub_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_iseehub_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_iseehub_plots.pdf"),    emit: plots, optional: true
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
    system.time(render("iSEEhub.Rmd", "BiocStyle::html_document"))
    library("knitr")
    # --- diff [] ---
    # Key functions: diff
    totalTime <- diff(c(startTime, Sys.time()))
    round(totalTime, digits = 3)
    # --- session_info [] ---
    # Key functions: session_info
    library("sessioninfo")
    options(width = 120)
    session_info()
    # --- Print Bibliography [] ---
    # Key functions: PrintBibliography
    PrintBibliography(bib, .opts = list(hyperlink = "to.doc", style = "html"))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_iseehub_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_iseehub_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_iseehub_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ISEEHUB:", paste0("    iseehub: ", packageVersion("iSEEhub"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_iseehub_results.csv
    touch ${prefix}_iseehub_output.rds
    echo "BIOC_ISEEHUB:" > versions.yml
    echo "    iseehub: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ISEEHUB_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ISEEHUB(ch_input)

    emit:
    results  = BIOC_ISEEHUB.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ISEEHUB.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ISEEHUB.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ISEEHUB.out.versions  // channel: path(versions.yml)
}
