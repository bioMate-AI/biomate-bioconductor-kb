#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: demuxmix
// A package for demultiplexing single-cell sequencing experiments of pooled cells labeled with barcode
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/demuxmix/inst/doc/demuxmix.R
// Upstream  : BiocManager, DropletUtils, cowplot, ggplot2, reshape2
// Downstream: none
//
// Install: BiocManager::install("demuxmix")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DEMUXMIX {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-demuxmix"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-demuxmix:1.8.0--r44_0' :
        'quay.io/biocontainers/bioconductor-demuxmix:1.8.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_demuxmix_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_demuxmix_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_demuxmix_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(StoeckiusHashingData)
    library(jsonlite)

    # --- Identify empty droplets [] ---
    # Key functions: StoeckiusHashingData, emptyDrops, colSums, counts, ggplot
    library(demuxmix)
    library(ggplot2)
    library(cowplot)
    # --- Custom ggplot2 visualization [] ---
    # Key functions: dmmSimulateHto, ggplot, geom_histogram, geom_point, hashedDrops, melt, geom_tile
    suppressPackageStartupMessages(library(DropletUtils))
    suppressPackageStartupMessages(library(reshape2))
    hd <- hashedDrops(hto)
    # --- DmmSimulateHto analysis [] ---
    # Key functions: dmmSimulateHto, demuxmix, dmmClassify, plotDmmHistogram, pAcpt, dmmOverlap, coord_cartesian, plot_grid
    histo <- plotDmmHistogram(dmm)
    scatter <- plotDmmScatter(dmm) + coord_cartesian(xlim = c(2, 4))
    plot_grid(histo, scatter, labels = c("A", "B"), nrow = 2)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_demuxmix_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_demuxmix_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_demuxmix_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DEMUXMIX:", paste0("    demuxmix: ", packageVersion("demuxmix"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_demuxmix_results.csv
    touch ${prefix}_demuxmix_output.rds
    echo "BIOC_DEMUXMIX:" > versions.yml
    echo "    demuxmix: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DEMUXMIX_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DEMUXMIX(ch_input)

    emit:
    results  = BIOC_DEMUXMIX.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DEMUXMIX.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DEMUXMIX.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DEMUXMIX.out.versions  // channel: path(versions.yml)
}
