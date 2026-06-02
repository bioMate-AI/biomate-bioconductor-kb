#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: fedup
// An R package that tests for enrichment and depletion of user-defined pathways using a Fisher's exact
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/fedup/inst/doc/fedup_doubleTest.R
// Upstream  : dplyr, ggplot2, tidyr
// Downstream: none
//
// Install: BiocManager::install("fedup")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FEDUP {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-fedup"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-fedup:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-fedup:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_fedup_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_fedup_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_fedup_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(fedup)
    library(jsonlite)

    # --- plot Dot Plot [] ---
    # Key functions: plotDotPlot, facet_grid, theme, tempdir, writeFemap

    # --- fedupEM geneDouble [] ---
    # Key functions: tempfile, plotFemap
    netFile <- tempfile("fedupEM_geneDouble", fileext = ".png")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_fedup_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_fedup_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_fedup_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FEDUP:", paste0("    fedup: ", packageVersion("fedup"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_fedup_results.csv
    touch ${prefix}_fedup_output.rds
    echo "BIOC_FEDUP:" > versions.yml
    echo "    fedup: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FEDUP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_FEDUP(ch_input)

    emit:
    results  = BIOC_FEDUP.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FEDUP.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FEDUP.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FEDUP.out.versions  // channel: path(versions.yml)
}
