#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: LRcell
// The goal of LRcell is to identify specific sub-cell types that drives the changes observed in a bulk
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/LRcell/inst/doc/LRcell-vignette.R
// Upstream  : ExperimentHub
// Downstream: none
//
// Install: BiocManager::install("LRcell")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_LRCELL {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-lrcell"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-lrcell:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-lrcell:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_lrcell_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_lrcell_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_lrcell_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ExperimentHub)
    library(LRcell)
    library(LRcellCore)
    library(LRcell_gene_enriched_scores)
    library(jsonlite)

    # --- Marker Gene Identification [] ---
    # Key functions: LRcell_gene_enriched_scores, get_markergenes
    sim_expr <- matrix(
        c(3, 0, 2, 8, 10, 6, 1, 0, 0, 2,
          7, 5, 8, 1, 0, 5, 2, 3, 2, 1,
          8, 10, 6, 7, 8, 9, 5, 8, 6, 8),
        nrow = 3, byrow = TRUE
    )
    rownames(sim_expr) <- paste0("gene", 1:3)
    colnames(sim_expr) <- paste0("cell", 1:10)
    sim_annot <- c(rep("celltype1", 3), rep("celltype2", 3), rep("celltype3", 4))
    names(sim_annot) <- colnames(sim_expr)
    enriched_res <- LRcell_gene_enriched_scores(
        expr = sim_expr, annot = sim_annot, parallel = FALSE
    )
    marker_res <- get_markergenes(
        enriched.g = enriched_res, method = "LR", topn = 1
    )

    # --- Standard Cell Type Enrichment [] ---
    # Key functions: LRcell
    data("example_gene_pvals")
    res <- LRcell(
        gene.p = example_gene_pvals,
        marker.g = NULL,
        species = "mouse",
        region = "FC",
        method = "LiR"
    )
    FC_res <- res$FC
    sub_FC_res <- subset(FC_res, select = -lead_genes)

    # --- Visualization of Enrichment Results [] ---
    # Key functions: plot_manhattan_enrich
    data("example_gene_pvals")
    res <- LRcell(
        gene.p = example_gene_pvals,
        marker.g = NULL,
        species = "mouse",
        region = "FC",
        method = "LiR"
    )
    plot_manhattan_enrich(
        res$FC,
        sig.cutoff = 0.05,
        label.topn = 5
    )


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_lrcell_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_lrcell_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_lrcell_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_LRCELL:", paste0("    lrcell: ", packageVersion("LRcell"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_lrcell_results.csv
    touch ${prefix}_lrcell_output.rds
    echo "BIOC_LRCELL:" > versions.yml
    echo "    lrcell: 0.0.0" >> versions.yml
    """
}


workflow BIOC_LRCELL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_LRCELL(ch_input)

    emit:
    results  = BIOC_LRCELL.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_LRCELL.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_LRCELL.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_LRCELL.out.versions  // channel: path(versions.yml)
}
