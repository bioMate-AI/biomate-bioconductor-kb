#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: tricycle
// The package contains functions to infer and visualize cell cycle process using Single Cell RNASeq da
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/tricycle/inst/doc/tricycle.R
// Upstream  : AnnotationDbi, Seurat, cowplot, ggplot2, scater
// Downstream: none
//
// Install: BiocManager::install("tricycle")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TRICYCLE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-tricycle"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-tricycle:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-tricycle:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_tricycle_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_tricycle_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_tricycle_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(tricycle)
    library(jsonlite)

    # --- Cell Cycle Position Estimation [] ---
    # Key functions: estimate_cycle_position
    sce_positioned <- estimate_cycle_position(
        sce_projected
    )
    positions <- sce_positioned$tricyclePosition


    # --- Cell Cycle Stage Assignment [] ---
    # Key functions: estimate_Schwabe_stage
    sce_staged <- estimate_Schwabe_stage(
        sce_positioned,
        gname.type = "ENSEMBL",
        species = "mouse"
    )
    stages <- sce_staged$CCStage


    # --- Periodic Expression Fitting [] ---
    # Key functions: fit_periodic_loess
    top2a_idx <- which(
        SummarizedExperiment::rowData(sce_staged)$Gene == "Top2a"
    )
    fit_results <- fit_periodic_loess(
        sce_staged$tricyclePosition,
        SummarizedExperiment::assay(sce_staged, "logcounts")[top2a_idx, ],
        plot = FALSE
    )


    # --- Cell Cycle Visualization [] ---
    # Key functions: plot_ccposition_den, plot_emb_circle_scale, circle_scale_legend
    density_plot <- plot_ccposition_den(
        sce_staged$tricyclePosition,
        sce_staged$sample,
        "sample",
        bw = 10,
        fig.title = "Kernel density of theta"
    )
    circle_plot <- plot_emb_circle_scale(
        sce_staged,
        dimred = 1,
        point.size = 3.5,
        point.alpha = 0.9
    )
    legend_plot <- circle_scale_legend(
        text.size = 5,
        alpha = 0.9
    )


    # --- Custom Reference Generation [] ---
    # Key functions: run_pca_cc_genes, estimate_cycle_position
    gocc_sce <- run_pca_cc_genes(
        sce_staged,
        exprs_values = "logcounts",
        species = "mouse"
    )
    new_ref <- attr(
        SingleCellExperiment::reducedDim(gocc_sce, "PCA"),
        "rotation"
    )[, seq_len(2)]
    sce_custom <- estimate_cycle_position(
        sce_staged,
        ref.m = new_ref,
        dimred = "tricycleEmbedding2"
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_tricycle_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_tricycle_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_tricycle_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TRICYCLE:", paste0("    tricycle: ", packageVersion("tricycle"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tricycle_results.csv
    touch ${prefix}_tricycle_output.rds
    echo "BIOC_TRICYCLE:" > versions.yml
    echo "    tricycle: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TRICYCLE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TRICYCLE(ch_input)

    emit:
    results  = BIOC_TRICYCLE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TRICYCLE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TRICYCLE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TRICYCLE.out.versions  // channel: path(versions.yml)
}
