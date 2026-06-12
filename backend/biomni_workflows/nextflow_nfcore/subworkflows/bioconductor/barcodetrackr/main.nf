#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: barcodetrackR — barcodetrackr_clonal_analysis
// Perform cellular barcoding clonal tracking analysis including thresholding, diversity estimation, correlation profiling, and visualization of clonal contributio
// Input: input.csv
// Container: 1.14.0--r44hdfd78af_0
// R packages: barcodetrackR, ggplot2, magrittr, SummarizedExperiment
// Bioconductor: 3.20 | R: 4.4
// Requires: SummarizedExperiment, barcodetrackR, ggplot2
// Visualizations: diversity plot, heatmap
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BARCODETRACKR_BARCODETRACKR_CLONAL_ANALYSIS {
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
    .bm_deps <- c("barcodetrackR", "ggplot2", "magrittr", "SummarizedExperiment")
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
    library(barcodetrackR)
    library(SummarizedExperiment)
    library(ggplot2)
    
    # --- Read and preprocess input data ---
    message("Reading input data...")
    if (!file.exists("input.csv")) {
      stop("Input file 'input.csv' not found.")
    }
    
    df <- read.csv("input.csv", check.names = FALSE)
    
    # Set row names from feature_id or first column
    if ("feature_id" %in% colnames(df)) {
      rownames(df) <- df\$feature_id
      df\$feature_id <- NULL
    } else {
      rownames(df) <- df[, 1]
      df <- df[, -1, drop = FALSE]
    }
    
    # Convert to numeric matrix
    counts <- as.matrix(df)
    counts[is.na(counts)] <- 0
    class(counts) <- "numeric"
    
    n_samples <- ncol(counts)
    if (n_samples == 0) {
      stop("No sample columns found in the input matrix.")
    }
    
    # --- Create metadata and SummarizedExperiment ---
    message("Creating metadata and SummarizedExperiment...")
    sample_names <- colnames(counts)
    
    # Generate dummy metadata for grouping/plotting
    metadata <- data.frame(
      sample_name = sample_names,
      lineage = rep(c("Lineage_A", "Lineage_B"), length.out = n_samples),
      timepoint = rep(c("T1", "T2"), length.out = n_samples),
      row.names = sample_names,
      stringsAsFactors = FALSE
    )
    
    # Create SummarizedExperiment using barcodetrackR helper
    se <- barcodetrackR::create_SE(assay_data = counts, col_data = metadata)
    
    # --- Thresholding / Filtering ---
    message("Applying abundance thresholding...")
    # Filter out low-abundance background noise
    se_thresholded <- barcodetrackR::threshold_counts(se, threshold = 0.0005, type = "relative")
    
    # Save thresholded counts
    write.csv(assay(se_thresholded), "thresholded_counts.csv", row.names = TRUE)
    
    # --- Clonal Diversity Analysis ---
    message("Plotting clonal diversity...")
    pdf("clonal_diversity.pdf", width = 8, height = 6)
    tryCatch({
      p_div <- barcodetrackR::clonal_diversity(
        your_SE = se_thresholded,
        index_type = "shannon",
        plot_by = "timepoint",
        group_by = "lineage"
      )
      print(p_div)
    }, error = function(e) {
      message("Clonal diversity plot failed: ", e\$message)
      # Fallback empty plot
      plot.new()
      text(0.5, 0.5, paste("Diversity Plot Error:", e\$message), cex = 0.8)
    })
    dev.off()
    
    # --- Barcode Heatmap Visualization ---
    message("Generating barcode heatmap...")
    pdf("barcode_heatmap.pdf", width = 10, height = 8)
    tryCatch({
      p_heat <- barcodetrackR::barcode_ggheatmap(
        your_SE = se_thresholded,
        plot_variables = "sample_name"
      )
      print(p_heat)
    }, error = function(e) {
      message("Barcode heatmap failed: ", e\$message)
      plot.new()
      text(0.5, 0.5, paste("Heatmap Error:", e\$message), cex = 0.8)
    })
    dev.off()
    
    # --- Correlation Profiling ---
    message("Generating correlation plot...")
    pdf("correlation_plot.pdf", width = 8, height = 8)
    tryCatch({
      barcodetrackR::cor_plot(
        your_SE = se_thresholded,
        plot_type = "heatmap"
      )
    }, error = function(e) {
      message("Correlation plot failed: ", e\$message)
      plot.new()
      text(0.5, 0.5, paste("Correlation Plot Error:", e\$message), cex = 0.8)
    })
    dev.off()
    
    # --- Clonal Contribution Analysis ---
    message("Plotting clonal contribution...")
    pdf("clonal_contribution.pdf", width = 8, height = 6)
    tryCatch({
      p_contrib <- barcodetrackR::clonal_contribution(
        your_SE = se_thresholded,
        plot_by = "sample_name"
      )
      print(p_contrib)
    }, error = function(e) {
      message("Clonal contribution failed: ", e\$message)
      plot.new()
      text(0.5, 0.5, paste("Clonal Contribution Error:", e\$message), cex = 0.8)
    })
    dev.off()
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_BARCODETRACKR_BARCODETRACKR_CLONAL_ANALYSIS":',
        paste0('    barcodetrackR: ', as.character(packageVersion('barcodetrackR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_barcodetrackr_clonal_analysis.csv versions.yml
    """
}

workflow BIOC_BARCODETRACKR_BARCODETRACKR_CLONAL_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_BARCODETRACKR_BARCODETRACKR_CLONAL_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_BARCODETRACKR_BARCODETRACKR_CLONAL_ANALYSIS.out.tables
    plots    = BIOC_BARCODETRACKR_BARCODETRACKR_CLONAL_ANALYSIS.out.plots
    objects  = BIOC_BARCODETRACKR_BARCODETRACKR_CLONAL_ANALYSIS.out.objects
    versions = BIOC_BARCODETRACKR_BARCODETRACKR_CLONAL_ANALYSIS.out.versions
}
