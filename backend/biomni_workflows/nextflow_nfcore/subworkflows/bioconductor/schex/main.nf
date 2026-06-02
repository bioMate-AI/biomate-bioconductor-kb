#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: schex
// Builds hexbin plots for variables and dimension reduction stored in single cell omics data such as S
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/schex/inst/doc/Seurat_to_SCE.R
// Upstream  : Seurat, dplyr, ggplot2
// Downstream: none
//
// Install: BiocManager::install("schex")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCHEX {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-schex"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-schex:1.20.0--r44_0' :
        'quay.io/biocontainers/bioconductor-schex:1.20.0--r44_0'}"

    input:
    tuple val(meta), path(seurat)

    output:
    tuple val(meta), path("${meta.id}_schex_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_schex_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_schex_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(RunUMAP)
    library(jsonlite)

    # --- UMAP embedding [] ---
    # Key functions: RunUMAP
    set.seed(10)
    pbmc_small <- RunUMAP(pbmc_small,
    # --- plot_hexbin_density [] ---
    # Key functions: plot_hexbin_density
    plot_hexbin_density(pbmc.sce)
    # --- plot_hexbin_meta [] ---
    # Key functions: plot_hexbin_meta
    plot_hexbin_meta(pbmc.sce, col = "nCount_RNA", action = "median")
    # --- plot_hexbin_feature [] ---
    # Key functions: plot_hexbin_feature
    schex::plot_hexbin_feature(pbmc.sce,
    title = paste0("Mean of ", gene_id)
    gg <- schex::plot_hexbin_feature(pbmc.sce,

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_schex_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_schex_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_schex_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SCHEX:", paste0("    schex: ", packageVersion("schex"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_schex_results.csv
    touch ${prefix}_schex_output.rds
    echo "BIOC_SCHEX:" > versions.yml
    echo "    schex: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SCHEX_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(seurat) ]

    main:
    BIOC_SCHEX(ch_input)

    emit:
    results  = BIOC_SCHEX.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SCHEX.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SCHEX.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SCHEX.out.versions  // channel: path(versions.yml)
}
