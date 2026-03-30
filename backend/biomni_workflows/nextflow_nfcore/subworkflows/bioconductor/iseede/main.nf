#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: iSEEde
// This package contains diverse functionality to extend the usage of the iSEE package, including addit
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/iSEEde/inst/doc/annotations.R
// Upstream  : DESeq2, RefManageR, airway, edgeR, iSEE
// Downstream: none
//
// Install: BiocManager::install("iSEEde")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ISEEDE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-iseede"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-iseede:1.4.0--r44_0' :
        'quay.io/biocontainers/bioconductor-iseede:1.4.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_iseede_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_iseede_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_iseede_plots.pdf"),    emit: plots, optional: true
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
    system.time(render("annotations.Rmd", "BiocStyle::html_document"))
    library("knitr")
    # --- Differential Expression [] ---
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
        write.csv(results_df, "${prefix}_iseede_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_iseede_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_iseede_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ISEEDE:", paste0("    iseede: ", packageVersion("iSEEde"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_iseede_results.csv
    touch ${prefix}_iseede_output.rds
    echo "BIOC_ISEEDE:" > versions.yml
    echo "    iseede: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ISEEDE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ISEEDE(ch_input)

    emit:
    results  = BIOC_ISEEDE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ISEEDE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ISEEDE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ISEEDE.out.versions  // channel: path(versions.yml)
}
