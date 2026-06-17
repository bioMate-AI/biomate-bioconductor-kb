#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scDesign3 — scrna_trajectory_simulation
// Simulate a single-cell RNA-seq dataset with a continuous developmental trajectory from a reference dataset and visualize the simulation quality.
// Input: counts.csv (reference scRNA-seq count matrix; genes x cells), pseudotime.csv (per-cell pseudotime vector)
// Container: quay.io/biocontainers/bioconductor-scdesign3:1.8.0--r45hdfd78af_0
// R packages: ggplot2, scDesign3, SingleCellExperiment
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, ggplot2, scDesign3
// Visualizations: UMAP plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Read user input files
//  * 2. [Visualization & Output] Run scDesign3 simulation
//  * 3. [Visualization & Output] Construct simulated SingleCellExperiment object
//  * 4. [Visualization & Output] Visualization and comparison

nextflow.enable.dsl = 2

process BIOC_SCDESIGN3_SCRNA_TRAJECTORY_SIMULATION {
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
    .bm_deps <- c("ggplot2", "scDesign3", "SingleCellExperiment", "SummarizedExperiment")
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
    library(scDesign3)
    library(SummarizedExperiment)
    library(ggplot2)
    
    # Set ggplot2 theme
    theme_set(theme_bw())
    
    # Helper function to robustly load user input files from the working directory
    load_data <- function(name) {
      extensions <- c(".rds", ".csv", ".txt", "")
      for (ext in extensions) {
        file_path <- paste0(name, ext)
        if (file.exists(file_path)) {
          if (ext == ".rds") {
            return(readRDS(file_path))
          } else if (ext == ".csv") {
            df <- read.csv(file_path, header = TRUE, row.names = 1)
            if (ncol(df) == 0) {
              df <- read.csv(file_path, header = FALSE)
            }
            if (ncol(df) == 1) {
              return(df[[1]])
            }
            return(as.matrix(df))
          } else if (ext == ".txt") {
            val <- tryCatch(scan(file_path, quiet = TRUE), error = function(e) NULL)
            if (!is.null(val)) return(val)
            return(as.matrix(read.table(file_path)))
          } else {
            val <- tryCatch(readRDS(file_path), error = function(e) NULL)
            if (!is.null(val)) return(val)
            val <- tryCatch(as.matrix(read.table(file_path)), error = function(e) NULL)
            if (!is.null(val)) return(val)
          }
        }
      }
      stop(paste("Error: Could not find input file for", name, "in the working directory."))
    }
    
    # --- Read user input files ---
    message("Loading input datasets...")
    ref_count <- load_data("counts")
    pseudotime <- load_data("pseudotime")

    # Ensure correct data types
    if (!is.matrix(ref_count)) {
      ref_count <- as.matrix(ref_count)
    }
    pseudotime <- as.numeric(pseudotime)

    # Construct the reference SingleCellExperiment object
    ref_sce <- SingleCellExperiment::SingleCellExperiment(
      assays = list(counts = ref_count, logcounts = log1p(ref_count)),
      colData = DataFrame(pseudotime = pseudotime)
    )

    # --- Run scDesign3 simulation ---
    message("Running scDesign3 simulation...")
    set.seed(123)
    ref_simu <- scdesign3(
      sce = ref_sce,
      assay_use = "counts",
      celltype = NULL,
      pseudotime = "pseudotime",
      spatial = NULL,
      other_covariates = NULL,
      mu_formula = "s(pseudotime, k = 10, bs = 'cr')",
      sigma_formula = "1",
      family_use = "nb",
      n_cores = 2,
      usebam = FALSE,
      corr_formula = "1",
      copula = "gaussian",
      DT = TRUE,
      pseudo_obs = FALSE,
      return_model = FALSE,
      nonzerovar = FALSE
    )
    
    # Print dimensions of simulated count matrix
    message("Simulated count matrix dimensions:")
    print(dim(ref_simu\$new_count))

    # --- Construct simulated SingleCellExperiment object ---
    message("Processing simulated dataset...")
    logcounts(ref_sce) <- log1p(counts(ref_sce))

    # Handle potential NULL in new_covariate if ncell was default
    simu_covariate <- ref_simu\$new_covariate
    if (is.null(simu_covariate)) {
      simu_covariate <- colData(ref_sce)
    }

    simu_sce <- SingleCellExperiment(
      list(counts = ref_simu\$new_count),
      colData = as(simu_covariate, "DataFrame")
    )
    logcounts(simu_sce) <- log1p(counts(simu_sce))

    # --- Visualization and comparison ---
    message("Generating dimensionality reduction comparison plot...")
    set.seed(123)
    compare_figure <- plot_reduceddim(
      ref_sce = ref_sce,
      sce_list = list(simu_sce),
      name_vec = c("Reference", "scDesign3"),
      assay_use = "logcounts",
      if_plot = TRUE,
      color_by = "pseudotime",
      n_pc = 20
    )

    # Save outputs to working directory
    message("Saving results...")
    write.csv(as.matrix(ref_simu\$new_count), "scdesign3_simulated_counts.csv", row.names = TRUE)
    saveRDS(simu_sce, "scdesign3_simulated_sce.rds")
    
    # Save comparison plot
    ggsave("umap_comparison.pdf", plot = compare_figure\$p_umap, width = 10, height = 8)
    ggsave("umap_comparison.png", plot = compare_figure\$p_umap, width = 10, height = 8, dpi = 300)
    
    message("Pipeline completed successfully. Outputs saved: 'scdesign3_simulated_counts.csv', 'scdesign3_simulated_sce.rds', 'umap_comparison.pdf', 'umap_comparison.png'.")

    writeLines(c(
        '"BIOC_SCDESIGN3_SCRNA_TRAJECTORY_SIMULATION":',
        paste0('    scDesign3: ', as.character(packageVersion('scDesign3')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scrna_trajectory_simulation.csv versions.yml
    """
}

workflow BIOC_SCDESIGN3_SCRNA_TRAJECTORY_SIMULATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ counts, pseudotime ] ]

    main:
    BIOC_SCDESIGN3_SCRNA_TRAJECTORY_SIMULATION(ch_input)

    emit:
    tables   = BIOC_SCDESIGN3_SCRNA_TRAJECTORY_SIMULATION.out.tables
    plots    = BIOC_SCDESIGN3_SCRNA_TRAJECTORY_SIMULATION.out.plots
    objects  = BIOC_SCDESIGN3_SCRNA_TRAJECTORY_SIMULATION.out.objects
    versions = BIOC_SCDESIGN3_SCRNA_TRAJECTORY_SIMULATION.out.versions
}
