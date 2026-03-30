#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SPONGE
// This package provides methods to efficiently detect competitive endogeneous RNA interactions between
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SPONGE/inst/doc/SPONGE.R
// Upstream  : doParallel, dplyr, foreach
// Downstream: none
//
// Install: BiocManager::install("SPONGE")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SPONGE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-sponge"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-sponge:1.28.0--r44_0' :
        'quay.io/biocontainers/bioconductor-sponge:1.28.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_sponge_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_sponge_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_sponge_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SPONGE)
    library(jsonlite)

    # --- Sponge Plot Network [] ---
    # Key functions: sponge_plot_network
    ---------------------------------------------------------------------
    sponge_plot_network(ceRNA_interactions_fdr, genes_miRNA_candidates)
    # --- Sponge Node Centralities [] ---
    # Key functions: sponge_node_centralities
    ---------------------------------------------------------------------
    network_centralities <- sponge_node_centralities(ceRNA_interactions_fdr)
    # --- Log10 [] ---
    # Key functions: sponge_node_centralities
    ---------------------------------------------------------------------
    ceRNA_interactions_fdr_weight <- ceRNA_interactions_fdr
    ceRNA_interactions_fdr_weight$weight <- -log10(ceRNA_interactions_fdr$p.adj)
    weighted_network_centralities <- sponge_node_centralities(ceRNA_interactions_fdr)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_sponge_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_sponge_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_sponge_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SPONGE:", paste0("    sponge: ", packageVersion("SPONGE"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sponge_results.csv
    touch ${prefix}_sponge_output.rds
    echo "BIOC_SPONGE:" > versions.yml
    echo "    sponge: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SPONGE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SPONGE(ch_input)

    emit:
    results  = BIOC_SPONGE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SPONGE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SPONGE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SPONGE.out.versions  // channel: path(versions.yml)
}
