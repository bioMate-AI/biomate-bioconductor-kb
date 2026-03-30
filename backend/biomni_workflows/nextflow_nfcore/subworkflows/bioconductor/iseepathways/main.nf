#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: iSEEpathways
// This package contains diverse functionality to extend the usage of the iSEE package, including addit
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/iSEEpathways/inst/doc/gene-ontology.R
// Upstream  : RefManageR, SummarizedExperiment, airway, edgeR, fgsea
// Downstream: none
//
// Install: BiocManager::install("iSEEpathways")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ISEEPATHWAYS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-iseepathways"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-iseepathways:1.4.0--r44_0' :
        'quay.io/biocontainers/bioconductor-iseepathways:1.4.0--r44_0'}"

    input:
    tuple val(meta), path(numeric)

    output:
    tuple val(meta), path("${meta.id}_iseepathways_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_iseepathways_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_iseepathways_plots.pdf"),    emit: plots, optional: true
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

    # --- "start" [] ---
    # Key functions: split, lengths, rnorm, fgsea
    library("org.Hs.eg.db")
    library("fgsea")
    pathways <- select(org.Hs.eg.db, keys(org.Hs.eg.db, "SYMBOL"), c("GOALL"), keytype = "SYMBOL")
    # --- knit [] ---
    # Key functions: knit
    library("rmarkdown")
    system.time(render("gene-ontology.Rmd", "BiocStyle::html_document"))
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
        write.csv(results_df, "${prefix}_iseepathways_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_iseepathways_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_iseepathways_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ISEEPATHWAYS:", paste0("    iseepathways: ", packageVersion("iSEEpathways"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_iseepathways_results.csv
    touch ${prefix}_iseepathways_output.rds
    echo "BIOC_ISEEPATHWAYS:" > versions.yml
    echo "    iseepathways: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ISEEPATHWAYS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(numeric) ]

    main:
    BIOC_ISEEPATHWAYS(ch_input)

    emit:
    results  = BIOC_ISEEPATHWAYS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ISEEPATHWAYS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ISEEPATHWAYS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ISEEPATHWAYS.out.versions  // channel: path(versions.yml)
}
