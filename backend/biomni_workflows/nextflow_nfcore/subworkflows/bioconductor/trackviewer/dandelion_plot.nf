#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: trackViewer — dandelion_plot
// Visualize high-density methylation or mutation data where standard lollipop plots would overlap excessively.
// Input: methy.bed, features.gr
// Container: quay.io/biocontainers/bioconductor-trackviewer:1.46.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
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

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("trackViewer", "rtracklayer", "GenomicRanges")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
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
