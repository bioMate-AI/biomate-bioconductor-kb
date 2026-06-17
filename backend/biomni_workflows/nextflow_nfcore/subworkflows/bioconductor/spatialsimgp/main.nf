#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: spatialSimGP — simulate_spatial_transcriptomics
// Simulate spatial transcriptomics count data with spatial variation using a Gaussian Process model based on user-provided spatial coordinates.
// Input: coords.csv
// Container: quay.io/biocontainers/bioconductor-spatialsimgp:1.4.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SpatialExperiment, ggplot2, spatialSimGP
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define or load spatial coordinates matrix
//  * 2. [Core Analysis] Set simulation parameters including gene count, noise proportion, variance range, mean range, and length scale
//  * 3. [Core Analysis] Run the simulation using spatial_simulate with either fixed or unique length scale options to generate a SpatialExperiment object

nextflow.enable.dsl = 2

process BIOC_SPATIALSIMGP_SIMULATE_SPATIAL_TRANSCRIPTOMICS {
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
    .bm_deps <- c("MASS", "SpatialExperiment", "ggplot2", "spatialSimGP")
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
    library(MASS)
    library(SpatialExperiment)
    library(ggplot2)
    library(spatialSimGP)
    
    # 1. Load spatial coordinates matrix from user-provided coords.csv
    if (!file.exists("coords.csv")) {
      stop("Error: 'coords.csv' not found in the working directory.")
    }
    
    coords_df <- read.csv("coords.csv")
    coords <- as.matrix(coords_df)
    
    # Ensure columns are named correctly for the simulation and plotting
    if (ncol(coords) >= 2) {
      colnames(coords)[1:2] <- c("pxl_col_in_fullres", "pxl_row_in_fullres")
      coords <- coords[, 1:2, drop = FALSE]
    } else {
      stop("Error: 'coords.csv' must contain at least two columns representing spatial dimensions.")
    }
    
    # 2. Set simulation parameters
    n_genes <- 5
    proportion <- 0.4
    range_sigma.sq <- c(1.5, 3)
    range_beta <- c(3, 7)
    
    # 3. Run the simulation using spatial_simulate with fixed length scale option
    length_scale <- 60
    
    set.seed(16)
    spe_fixed <- spatial_simulate(n_genes, proportion, coords,
                                  range_sigma.sq, range_beta,
                                  length_scale, length_scale_option = "fixed")
    
    # 4. Run the simulation using spatial_simulate with unique length scale option
    length_scale_unique <- c(60, 40, 20, 80, 100)
    
    set.seed(1)
    spe_unique <- spatial_simulate(n_genes, proportion, coords,
                                   range_sigma.sq, range_beta,
                                   length_scale_unique, length_scale_option = "unique")
    
    # 5. Save outputs
    # Save SpatialExperiment objects
    saveRDS(spe_fixed, "simulated_spe_fixed.rds")
    saveRDS(spe_unique, "simulated_spe_unique.rds")
    
    # Save simulated count matrices
    write.csv(as.matrix(counts(spe_fixed)), "simulated_counts_fixed.csv", row.names = TRUE)
    write.csv(as.matrix(counts(spe_unique)), "simulated_counts_unique.csv", row.names = TRUE)
    
    # Generate and save visualization plots
    pdf("simulated_spatial_expression_plots.pdf", width = 12, height = 6)
    
    # Plot for Fixed Length Scale (Gene 1)
    df_fixed <- as.data.frame(cbind(spatialCoords(spe_fixed), expr = counts(spe_fixed)[1, ]))
    p1 <- ggplot(df_fixed, aes(x = pxl_col_in_fullres, y = pxl_row_in_fullres, color = expr)) +
      geom_point(size = 2.2) +
      coord_fixed() +
      scale_y_reverse() +
      scale_color_gradient(low = "gray90", high = "blue", trans = "sqrt", breaks = range(df_fixed\$expr), name = "counts") +
      theme_bw() +
      labs(title = "Simulated Gene 1 (Fixed Length Scale = 60)") +
      theme(plot.title = element_text(face = "italic"),
            panel.grid = element_blank(),
            axis.title = element_blank(),
            axis.text = element_blank(),
            axis.ticks = element_blank())
    
    # Plot for Unique Length Scale (Gene 1)
    df_unique <- as.data.frame(cbind(spatialCoords(spe_unique), expr = counts(spe_unique)[1, ]))
    p2 <- ggplot(df_unique, aes(x = pxl_col_in_fullres, y = pxl_row_in_fullres, color = expr)) +
      geom_point(size = 2.2) +
      coord_fixed() +
      scale_y_reverse() +
      scale_color_gradient(low = "gray90", high = "blue", trans = "sqrt", breaks = range(df_unique\$expr), name = "counts") +
      theme_bw() +
      labs(title = "Simulated Gene 1 (Unique Length Scale = 60)") +
      theme(plot.title = element_text(face = "italic"),
            panel.grid = element_blank(),
            axis.title = element_blank(),
            axis.text = element_blank(),
            axis.ticks = element_blank())
    
    print(p1)
    print(p2)
    dev.off()
    
    message("Simulation completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_SPATIALSIMGP_SIMULATE_SPATIAL_TRANSCRIPTOMICS":',
        paste0('    spatialSimGP: ', as.character(packageVersion('spatialSimGP')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_simulate_spatial_transcriptomics.csv versions.yml
    """
}

workflow BIOC_SPATIALSIMGP_SIMULATE_SPATIAL_TRANSCRIPTOMICS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ coords.csv ] ]

    main:
    BIOC_SPATIALSIMGP_SIMULATE_SPATIAL_TRANSCRIPTOMICS(ch_input)

    emit:
    tables   = BIOC_SPATIALSIMGP_SIMULATE_SPATIAL_TRANSCRIPTOMICS.out.tables
    plots    = BIOC_SPATIALSIMGP_SIMULATE_SPATIAL_TRANSCRIPTOMICS.out.plots
    objects  = BIOC_SPATIALSIMGP_SIMULATE_SPATIAL_TRANSCRIPTOMICS.out.objects
    versions = BIOC_SPATIALSIMGP_SIMULATE_SPATIAL_TRANSCRIPTOMICS.out.versions
}
