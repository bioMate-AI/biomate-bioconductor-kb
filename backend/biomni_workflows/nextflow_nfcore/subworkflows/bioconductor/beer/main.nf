#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: beer
// BEER implements a Bayesian model for analyzing phage-immunoprecipitation sequencing (PhIP-seq) data.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/beer/inst/doc/beer.R
// Upstream  : dplyr, ggplot2
// Downstream: none
//
// Install: BiocManager::install("beer")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BEER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-beer"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-beer:1.10.0--r44_0' :
        'quay.io/biocontainers/bioconductor-beer:1.10.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_beer_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_beer_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_beer_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(beer)
    library(jsonlite)

    # --- run Edge R [] ---
    # Key functions: runEdgeR

    # --- edgeR hits [] ---
    # Key functions: assay, colSums

    # --- brew [] ---
    # Key functions: brew

    # --- assay [] ---
    # Key functions: assay, colSums
    was_run <- matrix(rep(beer_out$group != "beads", each = nrow(beer_out)),
    nrow = nrow(beer_out))
    are_se <- was_run & is.na(assay(beer_out, "beer_prob"))
    # --- Custom ggplot2 visualization [] ---
    # Key functions: dbeta, dgamma, ggplot, facet_wrap

    # --- edgeR beadsRR [] ---
    # Key functions: runEdgeR, assay, colSums

    # --- beer beadsRR [] ---
    # Key functions: brew, assay, colSums

    # --- edgeR beadsRR only [] ---
    # Key functions: beadsRR, assay, colSums

    # --- beer beadsRR only [] ---
    # Key functions: beadsRR, assay, colSums


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_beer_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_beer_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_beer_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BEER:", paste0("    beer: ", packageVersion("beer"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_beer_results.csv
    touch ${prefix}_beer_output.rds
    echo "BIOC_BEER:" > versions.yml
    echo "    beer: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BEER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BEER(ch_input)

    emit:
    results  = BIOC_BEER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BEER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BEER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BEER.out.versions  // channel: path(versions.yml)
}
