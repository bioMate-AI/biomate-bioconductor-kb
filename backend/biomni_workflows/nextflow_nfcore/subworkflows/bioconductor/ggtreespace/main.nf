#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ggtreeSpace
// This package is a comprehensive visualization tool specifically designed for exploring phylomorphosp
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ggtreeSpace/inst/doc/ggtreeSpace.R
// Upstream  : BiocManager, ggtree, phytools, ggplot2, dplyr
// Downstream: none
//
// Install: BiocManager::install("ggtreeSpace")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GGTREESPACE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ggtreespace"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ggtreespace:1.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ggtreespace:1.2.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ggtreespace_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ggtreespace_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ggtreespace_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ggtreeSpace)
    library(jsonlite)

    # --- Tree Space Initialization ---
    # Key functions: ggtreespace
    tr <- ape::rtree(15)
    td <- phytools::fastBM(tr, nsim = 2)
    p_space <- ggtreespace(tr, td)

    # --- Visualizing Tree Space with Tip Points ---
    # Key functions: ggtreespace, geom_tippoint
    tr <- ape::rtree(15)
    td <- phytools::fastBM(tr, nsim = 2)
    p_tips <- ggtreespace(tr, td) +
        geom_tippoint()

    # --- Alternative ggplot Integration ---
    # Key functions: geom_treespace
    tr1 <- ape::rtree(15)
    td1 <- phytools::fastBM(tr1, nsim = 2)
    p_custom <- ggplot2::ggplot() +
        geom_treespace(tr1, td1)

    # --- Trait Heatmap Projection ---
    # Key functions: ggtreespace, geom_tsheatmap, theme_treespace2
    tr <- ape::rtree(15)
    td <- phytools::fastBM(tr, nsim = 2, bounds = c(0, Inf))
    tdex <- data.frame(
        z = phytools::fastBM(tr, nsim = 1, bounds = c(0, Inf)),
        node = 1:15
    )
    p_base <- ggtreespace(tr, td)
    p_heatmap <- p_base %<+% tdex +
        geom_tsheatmap(
            trait = "z",
            alpha = 0.7,
            resolution = 0.01,
            bin = 24
        ) +
        theme_treespace2()


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ggtreespace_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ggtreespace_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ggtreespace_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GGTREESPACE:", paste0("    ggtreespace: ", packageVersion("ggtreeSpace"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ggtreespace_results.csv
    touch ${prefix}_ggtreespace_output.rds
    echo "BIOC_GGTREESPACE:" > versions.yml
    echo "    ggtreespace: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GGTREESPACE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GGTREESPACE(ch_input)

    emit:
    results  = BIOC_GGTREESPACE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GGTREESPACE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GGTREESPACE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GGTREESPACE.out.versions  // channel: path(versions.yml)
}
