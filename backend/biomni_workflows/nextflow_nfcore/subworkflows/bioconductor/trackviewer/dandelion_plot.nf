#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: trackViewer — dandelion_plot
// Visualize high-density methylation or mutation data where standard lollipop plots would overlap excessively.
// Input: methy.bed, features.gr
// Container: quay.io/biocontainers/bioconductor-trackviewer:1.46.0--r45hdfd78af_0
// Requires: GenomicRanges, rtracklayer, trackViewer
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Import methylation data
//  * 2. [Input & Preparation] Build gene model features
//  * 3. [Visualization & Output] Plot using dandelion.plot with specified type ("pin", "fan", "pie", "circle")

nextflow.enable.dsl = 2

process BIOC_TRACKVIEWER_DANDELION_PLOT {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
    
    # Load required libraries
    library(trackViewer)
    library(rtracklayer)
    library(GenomicRanges)
    
    # 1. Import methylation data
    methy <- import("methy.bed", "BED")
    
    # 2. Build gene model features from user input
    features <- readRDS("features.gr")
    
    # Define the genomic range dynamically based on the features
    gr <- range(features)
    
    # Assign styling attributes to features as in the documented code
    if (length(features) >= 2) {
      features\$fill <- rep(c("lightblue", "mistyrose"), length.out = length(features))
      features\$height <- rep(c(.02, .04), length.out = length(features))
    } else {
      features\$fill <- "lightblue"
      features\$height <- 0.03
    }
    
    # 3. Plot using dandelion.plot with specified type ("pin", "fan", "pie", "circle")
    pdf("dandelion_plot.pdf", width = 10, height = 8)
    dandelion.plot(methy, features, ranges=gr, type="pin")
    dev.off()
    
    # Save outputs
    saveRDS(features, "dandelion_plot_features.rds")
    saveRDS(methy, "dandelion_plot_methy.rds")

    writeLines(c(
        '"BIOC_TRACKVIEWER_DANDELION_PLOT":',
        paste0('    trackViewer: ', as.character(packageVersion('trackViewer')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dandelion_plot.csv versions.yml
    """
}

workflow BIOC_TRACKVIEWER_DANDELION_PLOT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ methy.bed, features.gr ] ]

    main:
    BIOC_TRACKVIEWER_DANDELION_PLOT(ch_input)

    emit:
    tables   = BIOC_TRACKVIEWER_DANDELION_PLOT.out.tables
    plots    = BIOC_TRACKVIEWER_DANDELION_PLOT.out.plots
    objects  = BIOC_TRACKVIEWER_DANDELION_PLOT.out.objects
    versions = BIOC_TRACKVIEWER_DANDELION_PLOT.out.versions
}
