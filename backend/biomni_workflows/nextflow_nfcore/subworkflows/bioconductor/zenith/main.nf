#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: zenith
// Zenith performs gene set analysis on the result of differential expression using linear (mixed) mode
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/zenith/inst/doc/loading_genesets.R
// Upstream  : EnrichmentBrowser, edgeR, kableExtra, knitr, tweeDEseqCountData
// Downstream: none
//
// Install: BiocManager::install("zenith")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ZENITH {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-zenith"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-zenith:1.8.0--r44_0' :
        'quay.io/biocontainers/bioconductor-zenith:1.8.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_zenith_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_zenith_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_zenith_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(zenith)
    library(jsonlite)

    # --- render [] ---
    # Key functions: render
    library(knitr)
    knitr::opts_chunk$set(
    rmarkdown::render("loading_genesets.Rmd")
    # --- get Genesets [] ---
    # Key functions: getGenesets
    gmt.file <- system.file("extdata/hsa_kegg_gs.gmt",
    gs <- getGenesets(gmt.file)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_zenith_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_zenith_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_zenith_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ZENITH:", paste0("    zenith: ", packageVersion("zenith"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_zenith_results.csv
    touch ${prefix}_zenith_output.rds
    echo "BIOC_ZENITH:" > versions.yml
    echo "    zenith: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ZENITH_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ZENITH(ch_input)

    emit:
    results  = BIOC_ZENITH.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ZENITH.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ZENITH.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ZENITH.out.versions  // channel: path(versions.yml)
}
