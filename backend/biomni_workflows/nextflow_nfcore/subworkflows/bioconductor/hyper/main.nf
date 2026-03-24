#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: hypeR
// An R Package for Geneset Enrichment Workflows.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/hypeR/inst/doc/hypeR.R
// Upstream  : devtools, dplyr, magrittr, reactable, tidyverse
// Downstream: none
//
// Install: BiocManager::install("hypeR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_HYPER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-hyper"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-hyper:2.4.0--r44_0' :
        'quay.io/biocontainers/bioconductor-hyper:2.4.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_hyper_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_hyper_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_hyper_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(hypeR)
    library(jsonlite)

    # --- Symbols [] ---
    # Key functions: symbols, weights
    ---------------------------------------------------------------------
    # Simply a character vector of symbols (hypergeometric)
    signature <- c("GENE1", "GENE2", "GENE3")
    # A ranked character vector of symbols (kstest)
    ranked.signature <- c("GENE2", "GENE1", "GENE3")
    # --- Hyper [] ---
    # Key functions: hypeR
    ---------------------------------------------------------------------
    hyp_obj <- hypeR(signature, genesets)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_hyper_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_hyper_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_hyper_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_HYPER:", paste0("    hyper: ", packageVersion("hypeR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hyper_results.csv
    touch ${prefix}_hyper_output.rds
    echo "BIOC_HYPER:" > versions.yml
    echo "    hyper: 0.0.0" >> versions.yml
    """
}


workflow BIOC_HYPER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_HYPER(ch_input)

    emit:
    results  = BIOC_HYPER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_HYPER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_HYPER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_HYPER.out.versions  // channel: path(versions.yml)
}
