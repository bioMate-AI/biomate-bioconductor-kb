#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: esetVis — tsne_visualization
// Perform t-SNE dimensionality reduction on expression data and visualize sample distributions with metadata aesthetics.
// Input: expression_data.RData
// Container: quay.io/biocontainers/bioconductor-esetvis:1.36.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, SummarizedExperiment, esetVis, ggplot2
// Visualizations: t-SNE plot
// QC: missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load User Input
//  * 2. [Visualization & Output] Robustly prepare metadata columns to match documented
//  * 3. [Visualization & Output] Run t-SNE and plot using esetTsne (Stage 1)
//  * 4. [Visualization & Output] Run t-SNE with custom data pre-transformation (Stage 2)

nextflow.enable.dsl = 2

process BIOC_ESETVIS_TSNE_VISUALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("esetVis", "Biobase", "ggplot2", "SummarizedExperiment")
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
    library(esetVis)
    library(SummarizedExperiment)
    library(Biobase)
    library(ggplot2)
    
    # --- Load User Input ---
    if (!file.exists("expression_data.RData")) {
      stop("Input file 'expression_data.RData' not found in the working directory.")
    }
    
    loaded_objs <- load("expression_data.RData")
    
    # Find the ExpressionSet or SummarizedExperiment object
    eset_obj_name <- NULL
    for (obj_name in loaded_objs) {
      obj <- get(obj_name)
      if (inherits(obj, "ExpressionSet") || inherits(obj, "SummarizedExperiment")) {
        eset_obj_name <- obj_name
        break
      }
    }
    
    if (is.null(eset_obj_name)) {
      stop("No ExpressionSet or SummarizedExperiment object found in 'expression_data.RData'.")
    }
    
    ALL <- get(eset_obj_name)
    
    # --- Robustly prepare metadata columns to match documented ---
    get_pData <- function(obj) {
      if (inherits(obj, "SummarizedExperiment")) {
        as.data.frame(SummarizedExperiment::colData(obj))
      } else {
        Biobase::pData(obj)
      }
    }
    
    df <- get_pData(ALL)
    
    # Dynamically select aesthetics based on available columns
    aes_args <- list()
    if (ncol(df) > 0) {
      cols <- colnames(df)
      
      # Color variable
      aes_args\$colorVar <- cols[1]
      color_col <- df[[cols[1]]]
      
      if (!is.numeric(color_col)) {
        groupingVariable <- as.factor(color_col)
        colorPalette <- c("dodgerblue", 
                          colorRampPalette(c("white","dodgerblue2", "darkblue"))(5)[-1], 
                          "red", colorRampPalette(c("white", "red3", "darkred"))(5)[-1])
        
        n_levels <- length(levels(groupingVariable))
        if (n_levels > 0) {
          if (n_levels > length(colorPalette)) {
            colorPalette <- colorRampPalette(colorPalette)(n_levels)
          } else {
            colorPalette <- colorPalette[1:n_levels]
          }
          names(colorPalette) <- levels(groupingVariable)
          aes_args\$color <- colorPalette
        }
      }
      
      # Shape variable (<= 6 levels for ggplot2 shapes)
      shape_cols <- cols[sapply(cols, function(x) length(unique(na.omit(df[[x]]))) <= 6)]
      if (length(shape_cols) > 0) {
        shape_cand <- setdiff(shape_cols, aes_args\$colorVar)
        if (length(shape_cand) > 0) {
          aes_args\$shapeVar <- shape_cand[1]
        } else {
          aes_args\$shapeVar <- shape_cols[1]
        }
      }
      
      # Size variable (numeric)
      size_cols <- cols[sapply(cols, function(x) is.numeric(df[[x]]))]
      if (length(size_cols) > 0) {
        aes_args\$sizeVar <- size_cols[1]
        aes_args\$sizeRange <- c(2, 6)
      }
      
      # Alpha variable
      alpha_cand <- setdiff(cols, c(aes_args\$colorVar, aes_args\$shapeVar, aes_args\$sizeVar))
      if (length(alpha_cand) > 0) {
        aes_args\$alphaVar <- alpha_cand[1]
        if (is.numeric(df[[aes_args\$alphaVar]])) {
          aes_args\$alphaRange <- c(0.3, 0.9)
        }
      }
    }
    
    # Calculate perplexity for Rtsne
    n_samples <- ncol(ALL)
    if (n_samples < 5) {
      stop("Dataset must have at least 5 samples to perform t-SNE.")
    }
    # Rtsne requires 3 * perplexity < n_samples - 1
    perplexity_val <- min(30, max(1, floor((n_samples - 2) / 3)))
    
    tsne_base_args <- list(
      eset = ALL,
      title = "t-SNE Visualization",
      Rtsne.args = list(perplexity = perplexity_val)
    )
    
    # Open PDF device to save plots
    pdf("tsne_visualization_plots.pdf", width = 8, height = 7)
    
    # --- Run t-SNE and plot using esetTsne (Stage 1) ---
    args_p1 <- c(tsne_base_args, aes_args)
    p1 <- do.call(esetTsne, args_p1)
    print(p1)
    
    # --- Run t-SNE with custom data pre-transformation (Stage 2) ---
    args_p2 <- c(tsne_base_args, aes_args, list(fctTransformDataForInputTsne = function(mat) as.dist((1 - cor(mat))/2)))
    p2 <- do.call(esetTsne, args_p2)
    print(p2)
    
    dev.off()
    
    # Save the plot objects to RDS for downstream use
    saveRDS(list(tsne_standard = p1, tsne_pretransformed = p2), "tsne_plots.rds")
    
    # Extract and save coordinates if available in the ggplot data structure
    if (!is.null(p1\$data)) {
      write.csv(p1\$data, "tsne_coordinates_standard.csv", row.names = TRUE)
    }
    if (!is.null(p2\$data)) {
      write.csv(p2\$data, "tsne_coordinates_pretransformed.csv", row.names = TRUE)
    }
    
    message("Pipeline completed successfully. Outputs saved to 'tsne_visualization_plots.pdf', 'tsne_plots.rds', and coordinate CSV files.")
    # ── BIOC_QC_HARNESS — Phase 3c bulk adoption (missing-value handling) ───
    # Defensive scan: list every *.rds the workflow produced, load each one,
    # compute NA fraction across numeric cells where the artifact is a
    # matrix or data.frame. Report max NA fraction across artifacts.
    # Threshold from bioc_missing_value_handling: < 5% pass.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()
    .na_fracs <- numeric(0)
    .scanned_files <- character(0)
    for (.rds_file in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .obj <- tryCatch(readRDS(.rds_file), error = function(e) NULL)
      .mat <- if (is.matrix(.obj) || is.data.frame(.obj)) .obj else NULL
      if (!is.null(.mat)) {
        .vals <- suppressWarnings(as.numeric(as.matrix(.mat)))
        if (length(.vals) > 0) {
          .na_fracs <- c(.na_fracs, mean(is.na(.vals)))
          .scanned_files <- c(.scanned_files, .rds_file)
        }
      }
    }
    .na_max <- if (length(.na_fracs) > 0) round(max(.na_fracs), 4) else NA_real_
    .gates_by_label[["missing-value handling"]] <- list(
      gate_row = "bioc_missing_value_handling",
      metric_name = "na_fraction_remaining",
      metric_value = .na_max,
      passes = isTRUE(is.finite(.na_max) && .na_max < 0.05),
      status = if (is.finite(.na_max)) paste0("computed (scanned ", length(.scanned_files), " rds files)")
               else "not_computed (no matrix/data.frame .rds artifact present)"
    )
    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_ESETVIS_TSNE_VISUALIZATION",
      domain  = "bioconductor",
      declared_qc_steps = c("missing-value handling"),
      gates_by_label = .gates_by_label,
      evidence_tier = "SILVER (Lazar 2013 NAR; <5% community convention)",
      harness_version = "0.1.0-bulk-mv"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_ESETVIS_TSNE_VISUALIZATION":',
        paste0('    esetVis: ', as.character(packageVersion('esetVis')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tsne_visualization.csv versions.yml
    """
}

workflow BIOC_ESETVIS_TSNE_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_data.RData ] ]

    main:
    BIOC_ESETVIS_TSNE_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_ESETVIS_TSNE_VISUALIZATION.out.tables
    plots    = BIOC_ESETVIS_TSNE_VISUALIZATION.out.plots
    objects  = BIOC_ESETVIS_TSNE_VISUALIZATION.out.objects
    versions = BIOC_ESETVIS_TSNE_VISUALIZATION.out.versions
}
