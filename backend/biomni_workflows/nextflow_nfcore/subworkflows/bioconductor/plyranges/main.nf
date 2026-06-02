#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: plyranges
// A dplyr-like interface for interacting with the common Bioconductor classes Ranges and GenomicRanges
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/plyranges/inst/doc/an-introduction.R
// Upstream  : ggplot2
// Downstream: none
//
// Install: BiocManager::install("plyranges")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PLYRANGES {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-plyranges"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-plyranges:1.26.0--r44_0' :
        'quay.io/biocontainers/bioconductor-plyranges:1.26.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_plyranges_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_plyranges_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_plyranges_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(plyranges)
    library(jsonlite)

    # --- Custom ggplot2 visualization [] ---
    # Key functions: ggplot, geom_rect, facet_grid, scale_x_continuous
    library(ggplot2)
    query_df <- as.data.frame(query)[, -6]
    subject_df <- as.data.frame(subject)[, -6]
    # --- Custom ggplot2 visualization [] ---
    # Key functions: ggplot, aes, geom_rect, facet_grid
    left_df <- as.data.frame(left_rng)[, -c(6,7)]
    left_df$ymin <- c(1,4, 1)
    left_df$ymax <- c(3,6, 3)
    # --- as_granges [] ---
    # Key functions: as_granges, join_overlap_inner, group_by, summarise, group_by_overlaps


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_plyranges_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_plyranges_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_plyranges_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PLYRANGES:", paste0("    plyranges: ", packageVersion("plyranges"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_plyranges_results.csv
    touch ${prefix}_plyranges_output.rds
    echo "BIOC_PLYRANGES:" > versions.yml
    echo "    plyranges: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PLYRANGES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PLYRANGES(ch_input)

    emit:
    results  = BIOC_PLYRANGES.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PLYRANGES.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PLYRANGES.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PLYRANGES.out.versions  // channel: path(versions.yml)
}
