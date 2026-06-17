#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: parglms — parallel_glm_analysis
// Fit a parallelized generalized linear model (GLM) on high-dimensional genomic or feature data using chunked data registries to scale computations.
// Input: input.csv
// Container: 1.42.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BatchJobs, parglms
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PARGLMS_PARALLEL_GLM_ANALYSIS {
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
    .bm_deps <- c("BatchJobs", "parglms")
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
    library(BatchJobs)
    library(parglms)
    
    # ==========================================
    # --- Read and Preprocess Input Data ---
    # ==========================================
    
    if (!file.exists("input.csv")) {
      stop("Input file 'input.csv' not found.")
    }
    
    # Read input.csv (expected to be a feature-by-sample matrix)
    raw_data <- read.csv("input.csv", row.names = 1, check.names = FALSE)
    
    # Transpose to sample-by-feature (observations as rows, variables as columns)
    df <- as.data.frame(t(raw_data))
    
    # Clean data: remove columns with all NAs
    df <- df[, colSums(is.na(df)) < nrow(df), drop = FALSE]
    
    # Impute remaining NAs with column mean to ensure complete cases for GLM
    for (col in colnames(df)) {
      if (any(is.na(df[[col]]))) {
        df[[col]][is.na(df[[col]])] <- mean(df[[col]], na.rm = TRUE)
      }
    }
    
    # Ensure we only use numeric columns for the regression
    numeric_cols <- sapply(df, is.numeric)
    df <- df[, numeric_cols, drop = FALSE]
    
    if (ncol(df) < 2 || nrow(df) < 5) {
      stop("Insufficient data dimensions after filtering. Need at least 2 numeric features and 5 samples.")
    }
    
    # Define target variable (first feature) and predictor variables (next few features)
    target_var <- colnames(df)[1]
    max_predictors <- min(5, ncol(df) - 1)
    predictor_vars <- colnames(df)[2:(max_predictors + 1)]
    
    # Construct a robust formula using backticks to handle special characters in feature IDs
    formula_str <- paste0("`", target_var, "` ~ ", paste0("`", predictor_vars, "`", collapse = " + "))
    formula_obj <- as.formula(formula_str)
    
    # ==========================================
    # --- Set up BatchJobs Registry ---
    # ==========================================
    
    # Disable progress bar to keep logs clean
    options(BBmisc.ProgressBar.style = "off")
    
    # Create a temporary registry directory
    reg_dir <- tempfile("parglms_registry_")
    myr <- makeRegistry(id = "parglms_jobs", file.dir = reg_dir)
    
    # Chunk the dataset observations into parallelizable jobs
    n_obs <- nrow(df)
    n_chunks <- max(2, min(10, floor(n_obs / 4)))
    if (n_chunks > n_obs) n_chunks <- n_obs
    
    chs <- chunk(1:n_obs, n.chunks = n_chunks)
    
    # Define the mapping function to return data chunks
    chunk_func <- function(indices, data) {
      data[indices, , drop = FALSE]
    }
    
    # Map jobs to the registry with the dataset passed as an argument
    batchMap(myr, chunk_func, chs, more.args = list(data = df))
    
    # Submit jobs and wait for completion
    submitJobs(myr, progressbar = FALSE)
    waitForJobs(myr)
    
    # ==========================================
    # --- Fit Parallelized GLM ---
    # ==========================================
    
    # Initialize beta values (Intercept + predictors)
    num_coefs <- 1 + length(predictor_vars)
    binit_vals <- rep(0, num_coefs)
    
    # Fit the model using parGLM
    pp <- parGLM(
      formula = formula_obj,
      registry = myr,
      family = gaussian,
      binit = binit_vals,
      maxit = 20,
      tol = 0.001
    )
    
    # ==========================================
    # --- Extract Results and Export ---
    # ==========================================
    
    coefs <- pp\$coefficients
    eff_var <- pp\$eff.variance
    se <- sqrt(diag(eff_var))
    t_stat <- coefs / se
    p_val <- 2 * (1 - pnorm(abs(t_stat)))
    
    results_df <- data.frame(
      Feature = names(coefs),
      Estimate = as.numeric(coefs),
      Std_Error = se,
      t_value = t_stat,
      p_value = p_val,
      row.names = NULL
    )
    
    # Save results to CSV
    write.csv(results_df, "parglms_results.csv", row.names = FALSE)
    
    # ==========================================
    # --- Visualization ---
    # ==========================================
    
    pdf("parglms_coefficient_plot.pdf", width = 8, height = 6)
    par(mar = c(5, 12, 4, 2))
    
    # Calculate 95% confidence intervals
    ci_lower <- results_df\$Estimate - 1.96 * results_df\$Std_Error
    ci_upper <- results_df\$Estimate + 1.96 * results_df\$Std_Error
    
    xlims <- range(c(ci_lower, ci_upper))
    xlims <- xlims + c(-0.1, 0.1) * diff(xlims) # Add padding
    
    y_coords <- seq_along(results_df\$Feature)
    
    plot(
      results_df\$Estimate, y_coords,
      yaxt = "n", xlab = "Coefficient Estimate (with 95% CI)",
      ylab = "", main = paste("Parallel GLM Results for Target:", target_var),
      xlim = xlims, pch = 19, col = "blue"
    )
    
    axis(2, at = y_coords, labels = results_df\$Feature, las = 2)
    abline(v = 0, lty = 2, col = "red")
    segments(ci_lower, y_coords, ci_upper, y_coords, col = "blue", lwd = 2)
    
    dev.off()

    writeLines(c(
        '"BIOC_PARGLMS_PARALLEL_GLM_ANALYSIS":',
        paste0('    parglms: ', as.character(packageVersion('parglms')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_parallel_glm_analysis.csv versions.yml
    """
}

workflow BIOC_PARGLMS_PARALLEL_GLM_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_PARGLMS_PARALLEL_GLM_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_PARGLMS_PARALLEL_GLM_ANALYSIS.out.tables
    plots    = BIOC_PARGLMS_PARALLEL_GLM_ANALYSIS.out.plots
    objects  = BIOC_PARGLMS_PARALLEL_GLM_ANALYSIS.out.objects
    versions = BIOC_PARGLMS_PARALLEL_GLM_ANALYSIS.out.versions
}
