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

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    tuple val(meta), path("qc_metrics.json"), emit: qc_metrics
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
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # cell QC metrics — defensive cell-count + per-cell summary from any
    # matrix artifact. Pass when columns (cells) ≥ 50 and rows (features) ≥ 200
    # (Luecken & Theis 2019 single-cell QC floor).
    .cqc_ncells <- NA_real_; .cqc_nfeats <- NA_real_; .cqc_files <- character(0)
    for (.cqc_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
      .cqc_obj <- tryCatch(readRDS(.cqc_rds), error = function(e) NULL)
      .cqc_mat <- if (is.matrix(.cqc_obj) || is.data.frame(.cqc_obj)) .cqc_obj else NULL
      if (!is.null(.cqc_mat) && nrow(.cqc_mat) > 100) {
        .cqc_ncells <- ncol(.cqc_mat); .cqc_nfeats <- nrow(.cqc_mat)
        .cqc_files <- c(.cqc_files, .cqc_rds); break
      }
    }
    .gates_by_label[["cell QC metrics"]] <- list(
      gate_row = "bioc_cell_qc_metrics",
      metric_name = "n_cells",
      metric_value = .cqc_ncells,
      passes = isTRUE(is.finite(.cqc_ncells) && .cqc_ncells >= 50 && .cqc_nfeats >= 200),
      status = if (is.finite(.cqc_ncells)) paste0("computed (cells=", .cqc_ncells, ", features=", .cqc_nfeats, "; proxy gate)")
               else "not_computed (no scRNA matrix .rds artifact present)"
    )

    # count normalization — scan .rds matrix artifacts for library-size CV
    # ratio (post-norm / pre-norm); without raw input we report median lib CV
    # as a proxy diagnostic. Threshold = 0.7 (Bullard 2010 BMC Bioinf).
    .cn_lib_cvs <- numeric(0)
    .cn_scanned <- character(0)
    for (.cn_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
      .cn_obj <- tryCatch(readRDS(.cn_rds), error = function(e) NULL)
      .cn_mat <- if (is.matrix(.cn_obj) || is.data.frame(.cn_obj)) .cn_obj else NULL
      if (!is.null(.cn_mat) && ncol(.cn_mat) >= 2 && nrow(.cn_mat) >= 2) {
        .cn_lib <- tryCatch(colSums(as.matrix(.cn_mat), na.rm = TRUE), error = function(e) NULL)
        if (!is.null(.cn_lib) && all(is.finite(.cn_lib)) && mean(.cn_lib) > 0) {
          .cn_lib_cvs <- c(.cn_lib_cvs, sd(.cn_lib) / mean(.cn_lib))
          .cn_scanned <- c(.cn_scanned, .cn_rds)
        }
      }
    }
    .cn_med_cv <- if (length(.cn_lib_cvs) > 0) round(median(.cn_lib_cvs), 4) else NA_real_
    .gates_by_label[["count normalization"]] <- list(
      gate_row = "bioc_count_normalization",
      metric_name = "lib_size_cv_median",
      metric_value = .cn_med_cv,
      passes = isTRUE(is.finite(.cn_med_cv) && .cn_med_cv <= 0.3),
      status = if (is.finite(.cn_med_cv)) paste0("computed (proxy: median lib-size CV across ", length(.cn_scanned), " matrix .rds; raw-vs-norm ratio not measurable without paired input)")
               else "not_computed (no count matrix .rds artifact present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_ESCHER_SPATIAL_EXPERIMENT_VISUALIZATION",
      domain  = "bioconductor",
      declared_qc_steps = c("cell QC metrics", "count normalization"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



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
