#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: corral
// Correspondence analysis (CA) is a matrix factorization method, and is similar to principal component
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/corral/inst/doc/corral_dimred.R
// Upstream  : CellBench, DuoClustering2018, MultiAssayExperiment, SingleCellExperiment, ggplot2
// Downstream: OSCA.advanced
//
// Install: BiocManager::install("corral")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CORRAL {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-corral"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-corral:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-corral:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_corral_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_corral_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_corral_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(corral)
    library(jsonlite)

    # --- Visualization of SCE Embedding [] ---
    # Key functions: plot_embedding_sce
    plot_embedding_sce(
        sce = zm4eq.sce,
        which_embedding = "corral",
        plot_title = "corral on Zhengmix4eq",
        color_attr = "phenoid",
        color_title = "cell type",
        saveplot = FALSE
    )


    # --- Correspondence Analysis on Matrix with Smoothing [] ---
    # Key functions: corral
    zm4eq.countmat <- SingleCellExperiment::assay(zm4eq.sce, "counts")
    zm4eq.countcorral <- corral(
        inp = zm4eq.countmat,
        fullout = TRUE,
        smooth = TRUE
    )


    # --- Visualization of Matrix Embedding [] ---
    # Key functions: plot_embedding
    celltype_vec <- zm4eq.sce$phenoid
    plot_embedding(
        embedding = zm4eq.countcorral$v,
        plot_title = "corral on Zhengmix4eq",
        color_vec = celltype_vec,
        color_title = "cell type",
        saveplot = FALSE
    )


    # --- Biplot Visualization [] ---
    # Key functions: biplot_corral
    gene_names <- SummarizedExperiment::rowData(zm4eq.sce)$symbol
    celltype_vec <- zm4eq.sce$phenoid
    biplot_corral(
        corral_obj = zm4eq.countcorral,
        color_vec = celltype_vec,
        text_vec = gene_names
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_corral_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_corral_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_corral_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CORRAL:", paste0("    corral: ", packageVersion("corral"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_corral_results.csv
    touch ${prefix}_corral_output.rds
    echo "BIOC_CORRAL:" > versions.yml
    echo "    corral: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CORRAL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CORRAL(ch_input)

    emit:
    results  = BIOC_CORRAL.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CORRAL.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CORRAL.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CORRAL.out.versions  // channel: path(versions.yml)
}
