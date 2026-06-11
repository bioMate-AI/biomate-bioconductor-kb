#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: densvis — density_preserving_tsne
// Perform density-preserving t-SNE dimensionality reduction on high-dimensional data.
// Input: data[, 1:2]
// Container: quay.io/biocontainers/bioconductor-densvis:1.20.1--r45ha27e39d_0
// R packages: BiocStyle, densvis, ggplot2
// Bioconductor: 3.20 | R: 4.4
// Requires: densvis, ggplot2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run density-preserving t-SNE using densne
//  * 2. [Visualization & Output] Extract the low-dimensional coordinates for visualization

nextflow.enable.dsl = 2

process BIOC_DENSVIS_DENSITY_PRESERVING_TSNE {
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
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("BiocStyle", "densvis", "ggplot2")
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
    library(densvis)
    library(ggplot2)
    
    # Set seed for reproducibility
    set.seed(14)
    
    # Read user input file from the working directory
    input_file <- "data.csv"
    if (!file.exists(input_file)) {
      stop(paste("Error: Input file", input_file, "not found in the working directory."))
    }
    
    # Read the data
    data <- read.csv(input_file, header = TRUE)
    
    # Ensure data has at least 2 columns
    if (ncol(data) < 2) {
      stop("Error: Input data must have at least 2 columns for t-SNE dimensionality reduction.")
    }
    
    # Run density-preserving t-SNE using densne (EXACTLY as documented)
    fit1 <- densne(data[, 1:2], dens_frac = 0.5, dens_lambda = 0.5)
    
    # Extract the low-dimensional coordinates and save to CSV
    coords_df <- data.frame(tSNE_1 = fit1[, 1], tSNE_2 = fit1[, 2])
    write.csv(coords_df, "densne_coordinates.csv", row.names = FALSE)
    
    # Save the raw fit object as RDS
    saveRDS(fit1, "densne_fit.rds")
    
    # Determine coloring for the plot
    if ("class" %in% colnames(data)) {
      plot_color <- data\$class
    } else if (ncol(data) >= 3) {
      plot_color <- data[, 3]
    } else {
      plot_color <- "Density-Preserving t-SNE"
    }
    
    # Generate and save the visualization plot
    p <- ggplot() +
      aes(fit1[, 1], fit1[, 2], colour = plot_color) +
      geom_point(pch = 19, alpha = 0.7) +
      scale_colour_discrete(name = "Group") +
      ggtitle("Density-preserving t-SNE") +
      labs(x = "t-SNE 1", y = "t-SNE 2") +
      theme_bw()
    
    ggsave("densne_plot.pdf", plot = p, width = 7, height = 6)

    writeLines(c(
        '"BIOC_DENSVIS_DENSITY_PRESERVING_TSNE":',
        paste0('    densvis: ', as.character(packageVersion('densvis')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_density_preserving_tsne.csv versions.yml
    """
}

workflow BIOC_DENSVIS_DENSITY_PRESERVING_TSNE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ data[, 1:2] ] ]

    main:
    BIOC_DENSVIS_DENSITY_PRESERVING_TSNE(ch_input)

    emit:
    tables   = BIOC_DENSVIS_DENSITY_PRESERVING_TSNE.out.tables
    plots    = BIOC_DENSVIS_DENSITY_PRESERVING_TSNE.out.plots
    objects  = BIOC_DENSVIS_DENSITY_PRESERVING_TSNE.out.objects
    versions = BIOC_DENSVIS_DENSITY_PRESERVING_TSNE.out.versions
}
