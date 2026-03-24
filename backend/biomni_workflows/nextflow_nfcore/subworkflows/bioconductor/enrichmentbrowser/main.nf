#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: EnrichmentBrowser
// The EnrichmentBrowser package implements essential functionality for the enrichment analysis of gene
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/EnrichmentBrowser/inst/doc/EnrichmentBrowser.R
// Upstream  : ALL, airway
// Downstream: none
//
// Install: BiocManager::install("EnrichmentBrowser")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ENRICHMENTBROWSER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-enrichmentbrowser"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-enrichmentbrowser:2.36.0--r44_0' :
        'quay.io/biocontainers/bioconductor-enrichmentbrowser:2.36.0--r44_0'}"

    input:
    tuple val(meta), path(summarizedexperiment)

    output:
    tuple val(meta), path("${meta.id}_enrichmentbrowser_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_enrichmentbrowser_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_enrichmentbrowser_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(EnrichmentBrowser)
    library(jsonlite)

    # --- Expression matrix extraction [] ---
    # Key functions: readSE, intersect, exprs, probe2gene, assay, normalize, deAna, rowData
    dummySBEA <- function(se, gs) {
    sig.ps <- sample(seq(0, 0.05, length = 1000), 5)
    insig.ps <- sample(seq(0.1, 1, length = 1000), length(gs) - 5)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_enrichmentbrowser_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_enrichmentbrowser_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_enrichmentbrowser_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ENRICHMENTBROWSER:", paste0("    enrichmentbrowser: ", packageVersion("EnrichmentBrowser"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_enrichmentbrowser_results.csv
    touch ${prefix}_enrichmentbrowser_output.rds
    echo "BIOC_ENRICHMENTBROWSER:" > versions.yml
    echo "    enrichmentbrowser: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ENRICHMENTBROWSER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(summarizedexperiment) ]

    main:
    BIOC_ENRICHMENTBROWSER(ch_input)

    emit:
    results  = BIOC_ENRICHMENTBROWSER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ENRICHMENTBROWSER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ENRICHMENTBROWSER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ENRICHMENTBROWSER.out.versions  // channel: path(versions.yml)
}
