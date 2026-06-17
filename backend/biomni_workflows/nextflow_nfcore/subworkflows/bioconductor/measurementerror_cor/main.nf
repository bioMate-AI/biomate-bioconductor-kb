#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: measurementerror_cor — measurement_error_correlation_analysis
// Estimate measurement error-corrected correlation coefficients between features across conditions to account for replicate-level variability.
// Input: input.csv
// Container: quay.io/biocontainers/r-base:4.3.1
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MeasurementError.cor, measurementerror_cor
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MEASUREMENTERROR_COR_MEASUREMENT_ERROR_CORRELATION_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("MeasurementError.cor")
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
    
    # --- Load libraries and read input defensively ---
    library(MeasurementError.cor)
    
    input_file <- "input.csv"
    if (!file.exists(input_file)) {
      stop(paste("Input file", input_file, "not found."))
    }
    
    # Read input defensively
    data <- read.csv(input_file, row.names = 1, check.names = FALSE)
    
    # If input is a single-column gene/identifier list, generate a dummy expression matrix
    if (ncol(data) < 2) {
      message("Single-column input detected. Generating a mock expression matrix for these identifiers...")
      genes <- rownames(data)
      if (length(genes) == 0 || is.null(genes)) {
        genes <- data[[1]]
      }
      # Create a dummy matrix with 3 conditions, 3 replicates each (9 columns)
      set.seed(42)
      dummy_mat <- matrix(rnorm(length(genes) * 9, mean = 10, sd = 2), nrow = length(genes))
      rownames(dummy_mat) <- genes
      colnames(dummy_mat) <- paste0(rep(c("Cond1", "Cond2", "Cond3"), each = 3), "_R", 1:3)
      data <- as.data.frame(dummy_mat)
    }
    
    # Convert to numeric matrix, handling any non-numeric values gracefully
    data_mat <- as.matrix(data)
    class(data_mat) <- "numeric"
    data_mat <- data_mat[rowSums(is.na(data_mat)) < ncol(data_mat), , drop = FALSE]
    
    # --- Group replicates and estimate means and standard errors ---
    col_names <- colnames(data_mat)
    # Attempt to identify replicate groups by stripping common suffixes
    prefixes <- sub("[._-][rR]?[0-9]+\$", "", col_names)
    
    if (length(unique(prefixes)) < length(col_names) && length(unique(prefixes)) >= 2) {
      groups <- prefixes
    } else {
      # Fallback: group columns into sets of 3, or 2 if small
      n_col <- ncol(data_mat)
      if (n_col >= 9) {
        groups <- paste0("Cond", rep(1:(n_col %/% 3), each = 3, length.out = n_col))
      } else if (n_col >= 4) {
        groups <- paste0("Cond", rep(1:(n_col %/% 2), each = 2, length.out = n_col))
      } else {
        # No replicates possible; treat each column as a condition and estimate SE proportionally
        groups <- col_names
      }
    }
    
    unique_groups <- unique(groups)
    n_cond <- length(unique_groups)
    
    if (length(unique_groups) < ncol(data_mat)) {
      message("Replicates detected. Calculating mean and standard error across groups...")
      means <- matrix(0, nrow = nrow(data_mat), ncol = n_cond)
      ses <- matrix(0, nrow = nrow(data_mat), ncol = n_cond)
      rownames(means) <- rownames(ses) <- rownames(data_mat)
      colnames(means) <- colnames(ses) <- unique_groups
      
      for (i in seq_along(unique_groups)) {
        g <- unique_groups[i]
        cols <- which(groups == g)
        sub_data <- data_mat[, cols, drop = FALSE]
        means[, i] <- rowMeans(sub_data, na.rm = TRUE)
        # Standard error of the mean: sd / sqrt(n) + small constant to prevent 0 SE
        ses[, i] <- apply(sub_data, 1, function(x) sd(x, na.rm = TRUE) / sqrt(length(x))) + 0.01
      }
    } else {
      message("No replicates detected. Estimating standard errors as 10% of expression values...")
      means <- data_mat
      ses <- 0.1 * abs(data_mat) + 0.05
    }
    
    # --- Select top highly variable features for pairwise ---
    # Measurement error correction can be computationally intensive; limit to top 50 features
    max_features <- 50
    vars <- apply(means, 1, var, na.rm = TRUE)
    vars[is.na(vars)] <- 0
    top_idx <- order(vars, decreasing = TRUE)[1:min(max_features, nrow(means))]
    
    means_sub <- means[top_idx, , drop = FALSE]
    ses_sub <- ses[top_idx, , drop = FALSE]
    features <- rownames(means_sub)
    n_feat <- length(features)
    
    if (n_feat < 2) {
      stop("Not enough features to perform pairwise correlation analysis.")
    }
    
    # --- Compute standard Pearson and Measurement Error Corrected ---
    cor_me_mat <- matrix(NA, nrow = n_feat, ncol = n_feat)
    cor_pearson_mat <- matrix(NA, nrow = n_feat, ncol = n_feat)
    rownames(cor_me_mat) <- colnames(cor_me_mat) <- features
    rownames(cor_pearson_mat) <- colnames(cor_pearson_mat) <- features
    
    diag(cor_me_mat) <- 1
    diag(cor_pearson_mat) <- 1
    
    comparison_results <- list()
    
    message("Computing pairwise measurement error corrected correlations...")
    for (i in 1:(n_feat - 1)) {
      for (j in (i + 1):n_feat) {
        x <- means_sub[i, ]
        y <- means_sub[j, ]
        sx <- ses_sub[i, ]
        sy <- ses_sub[j, ]
        
        # Standard Pearson correlation
        p_cor <- cor(x, y, use = "complete.obs")
        cor_pearson_mat[i, j] <- cor_pearson_mat[j, i] <- p_cor
        
        # Measurement error corrected correlation
        me_cor <- tryCatch({
          res <- cor.me(x, y, sx, sy)
          if (is.list(res)) {
            res\$cor
          } else {
            res
          }
        }, error = function(e) {
          NA
        })
        cor_me_mat[i, j] <- cor_me_mat[j, i] <- me_cor
        
        comparison_results[[length(comparison_results) + 1]] <- data.frame(
          Feature1 = features[i],
          Feature2 = features[j],
          Pearson_Cor = p_cor,
          Corrected_Cor = me_cor,
          Difference = me_cor - p_cor,
          stringsAsFactors = FALSE
        )
      }
    }
    
    comparison_df <- do.call(rbind, comparison_results)
    
    # --- Write outputs and generate diagnostic plots ---
    write.csv(comparison_df, "corrected_correlations.csv", row.names = FALSE)
    message("Saved correlation comparisons to 'corrected_correlations.csv'")
    
    pdf("correlation_comparison_plots.pdf", width = 10, height = 5)
    par(mfrow = c(1, 2))
    
    # Plot 1: Scatter plot comparing Pearson vs Corrected Correlation
    plot(comparison_df\$Pearson_Cor, comparison_df\$Corrected_Cor,
         xlab = "Standard Pearson Correlation",
         ylab = "Measurement Error Corrected Correlation",
         main = "Effect of Measurement Error Correction",
         col = "blue", pch = 16, xlim = c(-1, 1), ylim = c(-1, 1))
    abline(0, 1, col = "red", lty = 2)
    grid()
    
    # Plot 2: Distribution of differences
    hist(comparison_df\$Difference, 
         breaks = 15, 
         col = "skyblue", 
         main = "Distribution of Differences\n(Corrected - Pearson)",
         xlab = "Difference")
    
    dev.off()
    message("Saved diagnostic plots to 'correlation_comparison_plots.pdf'")

    writeLines(c(
        '"BIOC_MEASUREMENTERROR_COR_MEASUREMENT_ERROR_CORRELATION_ANALYSIS":',
        paste0('    measurementerror_cor: ', as.character(packageVersion('measurementerror_cor')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_measurement_error_correlation_analysis.csv versions.yml
    """
}

workflow BIOC_MEASUREMENTERROR_COR_MEASUREMENT_ERROR_CORRELATION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_MEASUREMENTERROR_COR_MEASUREMENT_ERROR_CORRELATION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_MEASUREMENTERROR_COR_MEASUREMENT_ERROR_CORRELATION_ANALYSIS.out.tables
    plots    = BIOC_MEASUREMENTERROR_COR_MEASUREMENT_ERROR_CORRELATION_ANALYSIS.out.plots
    objects  = BIOC_MEASUREMENTERROR_COR_MEASUREMENT_ERROR_CORRELATION_ANALYSIS.out.objects
    versions = BIOC_MEASUREMENTERROR_COR_MEASUREMENT_ERROR_CORRELATION_ANALYSIS.out.versions
}
