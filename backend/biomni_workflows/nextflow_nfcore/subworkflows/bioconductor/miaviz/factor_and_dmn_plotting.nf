#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: miaViz — factor_and_dmn_plotting
// Visualize relationships between categorical factors and evaluate Dirichlet Multinomial Mixtures (DMN) fit.
// Input: GlobalPatterns, dmn_se
// Container: quay.io/biocontainers/bioconductor-miaviz:1.18.0--r45hdfd78af_0
// R packages: ggplot2, miaViz
// Bioconductor: 3.20 | R: 4.4
// Requires: ggplot2, miaViz
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Plot categorical factor relationships using column tiles
//  * 2. [Visualization & Output] Plot DMN fit diagnostics (e.g., Laplace goodness of fit)

nextflow.enable.dsl = 2

process BIOC_MIAVIZ_FACTOR_AND_DMN_PLOTTING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metagenomics:3.20"

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
    .bm_deps <- c("ggplot2", "miaViz")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
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
    library(miaViz)
    library(ggplot2)
    
    # Helper function to robustly read RDS files with or without extension
    read_input <- function(filename) {
      if (file.exists(filename)) {
        return(readRDS(filename))
      } else if (file.exists(paste0(filename, ".rds"))) {
        return(readRDS(paste0(filename, ".rds")))
      } else {
        stop(paste("Required input file not found:", filename))
      }
    }
    
    # 1. Load User Inputs
    se <- read_input("GlobalPatterns")
    dmn_se <- read_input("dmn_se")
    
    # 2. Stage 1: Plot categorical factor relationships using column tiles
    p1 <- plotColTile(se, "SampleType", "Primer") +
        theme(axis.text.x.top = element_text(angle = 45, hjust = 0))
    
    # Save the column tile plot
    ggsave("col_tile_plot.pdf", plot = p1, width = 10, height = 8)
    
    # 3. Stage 2: Plot DMN fit diagnostics
    # Extract and save metadata names
    meta_names <- names(metadata(dmn_se))
    writeLines(meta_names, "dmn_metadata_names.txt")
    
    # Plot the DMN fit
    p2 <- plotDMNFit(dmn_se, type = "laplace")
    
    # Save the DMN fit plot
    ggsave("dmn_fit_plot.pdf", plot = p2, width = 8, height = 6)

    writeLines(c(
        '"BIOC_MIAVIZ_FACTOR_AND_DMN_PLOTTING":',
        paste0('    miaViz: ', as.character(packageVersion('miaViz')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_factor_and_dmn_plotting.csv versions.yml
    """
}

workflow BIOC_MIAVIZ_FACTOR_AND_DMN_PLOTTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ GlobalPatterns, dmn_se ] ]

    main:
    BIOC_MIAVIZ_FACTOR_AND_DMN_PLOTTING(ch_input)

    emit:
    tables   = BIOC_MIAVIZ_FACTOR_AND_DMN_PLOTTING.out.tables
    plots    = BIOC_MIAVIZ_FACTOR_AND_DMN_PLOTTING.out.plots
    objects  = BIOC_MIAVIZ_FACTOR_AND_DMN_PLOTTING.out.objects
    versions = BIOC_MIAVIZ_FACTOR_AND_DMN_PLOTTING.out.versions
}
