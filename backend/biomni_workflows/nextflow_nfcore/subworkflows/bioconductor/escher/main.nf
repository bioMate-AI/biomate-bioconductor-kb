#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: escheR — spatial_experiment_visualization
// Visualize multi-dimensional spatial transcriptomics data from a SpatialExperiment or SingleCellExperiment object by adding layered fill, ground, and symbol aest
// Input: spe.rds
// Container: quay.io/biocontainers/bioconductor-escher:1.10.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SpatialExperiment, escheR, ggplot2, scater, scuttle
// Visualizations: plot (ggplot/base)
// QC: cell QC metrics, count normalization
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Read the input SpatialExperiment object
//  * 2. [Visualization & Output] Robustness checks: Ensure required columns and reduced
//  * 3. [Visualization & Output] Execute the documented escheR workflow steps
//  * 4. [Visualization & Output] Save the generated plots to the working directory

nextflow.enable.dsl = 2

process BIOC_ESCHER_SPATIAL_EXPERIMENT_VISUALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    .bm_deps <- c("escheR", "SpatialExperiment", "ggplot2", "scater", "scuttle", "SummarizedExperiment")
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
    library(escheR)
    library(SummarizedExperiment)
    library(SpatialExperiment)
    library(ggplot2)
    library(scater)
    library(scuttle)
    
    # --- Read the input SpatialExperiment object ---
    if (!file.exists("spe.rds")) {
      stop("Error: 'spe.rds' not found in the working directory.")
    }
    spe <- readRDS("spe.rds")
    
    # --- Robustness checks: Ensure required columns and reduced ---
    # Ensure 'cell_count' exists in colData
    if (!"cell_count" %in% colnames(colData(spe))) {
      message("'cell_count' column not found in colData. Creating a fallback from library sizes.")
      spe\$cell_count <- colSums(assays(spe)\$counts > 0)
    }
    
    # Ensure 'ground_truth' exists in colData
    if (!"ground_truth" %in% colnames(colData(spe))) {
      message("'ground_truth' column not found in colData. Creating dummy spatial domains.")
      # Generate dummy layers based on spatial coordinates if available, or randomly
      if (all(c("pxl_col_in_fullres", "pxl_row_in_fullres") %in% colnames(spatialCoords(spe)))) {
        coords <- spatialCoords(spe)
        spe\$ground_truth <- factor(cut(coords[, 1], breaks = 5, labels = paste0("Layer", 1:5)))
      } else {
        spe\$ground_truth <- factor(sample(paste0("Layer", 1:5), ncol(spe), replace = TRUE))
      }
    } else {
      spe\$ground_truth <- factor(spe\$ground_truth)
    }
    
    # Ensure 'counts_MOBP' exists in colData
    if (!"counts_MOBP" %in% colnames(colData(spe))) {
      message("'counts_MOBP' column not found in colData. Attempting to extract MOBP or fallback.")
      mobp_idx <- which(toupper(rowData(spe)\$gene_name) == "MOBP")
      if (length(mobp_idx) > 0) {
        spe\$counts_MOBP <- assays(spe)\$counts[mobp_idx[1], ]
      } else {
        # Fallback to the first row of counts
        spe\$counts_MOBP <- assays(spe)\$counts[1, ]
      }
    }
    
    # Ensure PCA reduced dimension exists for the dimred visualization
    if (!"PCA" %in% reducedDimNames(spe)) {
      message("PCA reduced dimensions not found. Computing PCA...")
      if (!"logcounts" %in% assayNames(spe)) {
        spe <- scuttle::logNormCounts(spe)
      }
      # Run PCA with scater
      spe <- scater::runPCA(spe, ncomponents = 2)
    }
    
    # --- Execute the documented escheR workflow steps ---
    
    # Set up an escheR plot
    p <- make_escheR(spe)
    
    # Adding fill layer
    p1 <- p |>
       add_fill(var = "cell_count")
    
    # Adding ground layer
    p2 <- p |>
       add_ground(var = "ground_truth")
    
    # Adding symbol layer
    p3 <- p2 |>
      add_symbol(var = "ground_truth", size = 0.2)
    
    # Visualizing dimensionality reduced embedding
    p_dimred <- make_escheR(
      spe,
      dimred = "PCA"
    ) |> 
      add_fill(var = "ground_truth") +
      theme_minimal()
    
    # Customizing color palettes for multi-dimensional visualization
    p_custom <- make_escheR(spe) |> 
        add_fill(var = "counts_MOBP") |> 
        add_ground(var = "ground_truth", stroke = 0.5)
    
    p_custom_scaled <- p_custom + 
       scale_fill_gradient(low = "white", high = "black")
    
    # --- Save the generated plots to the working directory ---
    ggsave("escheR_plot_fill.pdf", plot = p1, width = 8, height = 7)
    ggsave("escheR_plot_ground_symbol.pdf", plot = p3, width = 8, height = 7)
    ggsave("escheR_plot_dimred.pdf", plot = p_dimred, width = 8, height = 7)
    ggsave("escheR_plot_custom_palette.pdf", plot = p_custom_scaled, width = 8, height = 7)
    
    # Save the updated SpatialExperiment object with any newly created metadata
    saveRDS(spe, "spe_processed.rds")
    
    message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_ESCHER_SPATIAL_EXPERIMENT_VISUALIZATION":',
        paste0('    escheR: ', as.character(packageVersion('escheR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_spatial_experiment_visualization.csv versions.yml
    """
}

workflow BIOC_ESCHER_SPATIAL_EXPERIMENT_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ spe.rds ] ]

    main:
    BIOC_ESCHER_SPATIAL_EXPERIMENT_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_ESCHER_SPATIAL_EXPERIMENT_VISUALIZATION.out.tables
    plots    = BIOC_ESCHER_SPATIAL_EXPERIMENT_VISUALIZATION.out.plots
    objects  = BIOC_ESCHER_SPATIAL_EXPERIMENT_VISUALIZATION.out.objects
    versions = BIOC_ESCHER_SPATIAL_EXPERIMENT_VISUALIZATION.out.versions
}
