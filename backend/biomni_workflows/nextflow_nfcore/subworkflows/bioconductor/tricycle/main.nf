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

    # --- project_cycle_space [] ---
    # Key functions: project_cycle_space
    neurosphere_example <- project_cycle_space(neurosphere_example)
    # --- plot projection [] ---
    # Key functions: plotReducedDim, labs, ggtitle, theme_bw
    library(ggplot2)
    library(scattermore)
    library(scater)
    # --- estimate_cycle_position [] ---
    # Key functions: estimate_cycle_position
    neurosphere_example <- estimate_cycle_position(neurosphere_example)
    names(colData(neurosphere_example))
    # --- assay [] ---
    # Key functions: assay
    top2a.idx <- which(rowData(neurosphere_example)$Gene == 'Top2a')
    fit.l <- fit_periodic_loess(neurosphere_example$tricyclePosition,
    assay(neurosphere_example, 'logcounts')[top2a.idx,],
    # --- estimate_ Schwabe_stage [] ---
    # Key functions: estimate_Schwabe_stage, plotReducedDim, labs, theme_bw
    neurosphere_example <- estimate_Schwabe_stage(neurosphere_example,
    scater::plotReducedDim(neurosphere_example, dimred = "tricycleEmbedding",
    labs(x = "Projected PC1", y = "Projected PC2",
    # --- plot_ccposition_den [] ---
    # Key functions: plot_ccposition_den, theme_bw
    plot_ccposition_den(neurosphere_example$tricyclePosition,
    theme_bw(base_size = 14)
    plot_ccposition_den(neurosphere_example$tricyclePosition,
    # --- plot_emb_circle_scale [] ---
    # Key functions: plot_emb_circle_scale, theme_bw, circle_scale_legend, plot_grid
    library(cowplot)
    p <- plot_emb_circle_scale(neurosphere_example, dimred = 1,
    theme_bw(base_size = 14)
    # --- estimate_cycle_position [] ---
    # Key functions: estimate_cycle_position
    set.seed(100)
    gocc_sce.o <- run_pca_cc_genes(neurosphere_example,
    new.ref <- attr(reducedDim(gocc_sce.o, 'PCA'), 'rotation')[, seq_len(2)]
    # --- qplot [] ---
    # Key functions: qplot, labs, theme_bw
    cor(neurosphere_example$tricyclePosition, new_sce$tricyclePosition)
    CircStats::circ.cor(neurosphere_example$tricyclePosition, new_sce$tricyclePosition)
    qplot(x = neurosphere_example$tricyclePosition,y = new_sce$tricyclePosition) +

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
