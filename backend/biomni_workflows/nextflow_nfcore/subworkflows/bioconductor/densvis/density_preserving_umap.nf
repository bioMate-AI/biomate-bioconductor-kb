#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: densvis — density_preserving_umap
// Perform density-preserving UMAP dimensionality reduction on high-dimensional data.
// Input: data[, 1:2]
// Container: quay.io/biocontainers/bioconductor-densvis:1.20.1--r45ha27e39d_0
// R packages: densvis, ggplot2
// Bioconductor: 3.20 | R: 4.4
// Requires: densvis, ggplot2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run density-preserving UMAP using densmap
//  * 2. [Visualization & Output] Extract the low-dimensional coordinates for visualization

nextflow.enable.dsl = 2

process BIOC_DENSVIS_DENSITY_PRESERVING_UMAP {
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
    .bm_deps <- c("densvis", "ggplot2")
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
        
        # 1. Read User Input
        # The pipeline expects a file named "data.csv" in the working directory.
        # This file should contain the high-dimensional features.
        if (!file.exists("data.csv")) {
          stop("Error: 'data.csv' not found in the working directory. Please provide the input file.")
        }
        
        data <- read.csv("data.csv")
        
        # Ensure the data has at least 2 columns as required by the workflow
        if (ncol(data) < 2) {
          stop("Error: Input data must have at least 2 columns for the analysis.")
        }
        
        # 2. Run density-preserving UMAP using densmap
        # Exact documented code call:
        fit1 <- densmap(data[, 1:2], dens_frac = 0.5, dens_lambda = 0.5)
        
        # 3. Extract the low-dimensional coordinates and save results
        # Save the raw coordinates as an RDS object
        saveRDS(fit1, file = "densmap_fit.rds")
        
        # Save the coordinates as a CSV table
        output_coords <- data.frame(
          UMAP_1 = fit1[, 1],
          UMAP_2 = fit1[, 2]
        )
        write.csv(output_coords, file = "densmap_coordinates.csv", row.names = FALSE)
        
        # 4. Create and save visualization
        # If the input data has a 'class' or 'group' column (beyond the first two columns),
        # we can use it for coloring. Otherwise, we plot without color grouping.
        p <- ggplot(output_coords, aes(x = UMAP_1, y = UMAP_2))
        
        if (ncol(data) >= 3 && (is.character(data[[3]]) || is.factor(data[[3]]))) {
          output_coords\$Class <- data[[3]]
          p <- ggplot(output_coords, aes(x = UMAP_1, y = UMAP_2, colour = Class)) +
            geom_point(pch = 19, alpha = 0.7) +
            scale_colour_discrete(name = "Class")
        } else {
          p <- p + geom_point(pch = 19, alpha = 0.7, colour = "blue")
        }
        
        p <- p +
          theme_bw() +
          ggtitle("Density-preserving UMAP") +
          labs(x = "UMAP 1", y = "UMAP 2")
        
        # Save the plot as a PDF
        ggsave("densmap_plot.pdf", plot = p, width = 7, height = 6)

    writeLines(c(
        '"BIOC_DENSVIS_DENSITY_PRESERVING_UMAP":',
        paste0('    densvis: ', as.character(packageVersion('densvis')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_density_preserving_umap.csv versions.yml
    """
}

workflow BIOC_DENSVIS_DENSITY_PRESERVING_UMAP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ data[, 1:2] ] ]

    main:
    BIOC_DENSVIS_DENSITY_PRESERVING_UMAP(ch_input)

    emit:
    tables   = BIOC_DENSVIS_DENSITY_PRESERVING_UMAP.out.tables
    plots    = BIOC_DENSVIS_DENSITY_PRESERVING_UMAP.out.plots
    objects  = BIOC_DENSVIS_DENSITY_PRESERVING_UMAP.out.objects
    versions = BIOC_DENSVIS_DENSITY_PRESERVING_UMAP.out.versions
}
