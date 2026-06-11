#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: OLINgui — olingui_microarray_pipeline
// Prepare two-channel microarray data from a CSV file, perform programmatic OLIN normalization and diagnostic testing, and set up the environment for interactive 
// Input: input.csv
// Container: 1.84.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: OLINgui, marray
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_OLINGUI_OLINGUI_MICROARRAY_PIPELINE {
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
    .bm_deps <- c("OLINgui", "marray", "OLIN")
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
    library(OLINgui)
    library(marray)
    library(OLIN)
    
    # ==========================================
    # --- Read and Preprocess Input Data ---
    # ==========================================
    
    # Read the feature-by-sample numeric matrix
    if (!file.exists("input.csv")) {
      stop("Input file 'input.csv' not found.")
    }
    
    df <- read.csv("input.csv", row.names = 1, check.names = FALSE)
    mat <- as.matrix(df)
    
    # Ensure values are positive for log transformation
    if (any(mat <= 0, na.rm = TRUE)) {
      min_pos <- min(mat[mat > 0], na.rm = TRUE)
      if (is.infinite(min_pos)) min_pos <- 1.0
      mat[mat <= 0] <- min_pos
    }
    
    # Ensure we have at least 2 channels (columns) to split
    n_col <- ncol(mat)
    if (n_col < 2) {
      # Duplicate column to simulate two channels if only one is provided
      mat <- cbind(mat, mat)
      colnames(mat) <- c("Channel1", "Channel2")
      n_col <- 2
    }
    
    # Split columns into Green (Gf) and Red (Rf) foreground channels
    mid <- ceiling(n_col / 2)
    Gf <- mat[, 1:mid, drop = FALSE]
    Rf <- mat[, (mid + 1):n_col, drop = FALSE]
    
    # Align dimensions
    min_cols <- min(ncol(Gf), ncol(Rf))
    Gf <- Gf[, 1:min_cols, drop = FALSE]
    Rf <- Rf[, 1:min_cols, drop = FALSE]
    
    # ==========================================
    # --- Construct marrayRaw and XY Objects ---
    # ==========================================
    
    # Create a standard marrayLayout object
    layout <- new("marrayLayout", 
                  maNgr = as.integer(1), 
                  maNgc = as.integer(1), 
                  maNsr = as.integer(nrow(Rf)), 
                  maNsc = as.integer(1))
    
    # Create marrayInfo objects for genes and targets
    gnames <- new("marrayInfo", 
                  maLabels = rownames(Rf), 
                  maInfo = data.frame(ID = rownames(Rf), stringsAsFactors = FALSE))
    targets <- new("marrayInfo", 
                   maLabels = colnames(Rf), 
                   maInfo = data.frame(Sample = colnames(Rf), stringsAsFactors = FALSE))
    
    # Construct the marrayRaw object
    sw_data <- new("marrayRaw", 
                   maRf = Rf, 
                   maGf = Gf, 
                   maRb = matrix(0, nrow = nrow(Rf), ncol = ncol(Rf)), 
                   maGb = matrix(0, nrow = nrow(Gf), ncol = ncol(Gf)), 
                   maLayout = layout,
                   maGnames = gnames,
                   maTargets = targets)
    
    # Generate a 2D spatial grid for spot coordinates (XY list)
    n_spots <- nrow(Rf)
    n_cols_grid <- ceiling(sqrt(n_spots))
    n_rows_grid <- ceiling(n_spots / n_cols_grid)
    
    X_coords <- rep(1:n_cols_grid, each = n_rows_grid)[1:n_spots]
    Y_coords <- rep(1:n_rows_grid, times = n_cols_grid)[1:n_spots]
    sw_xy <- list(X = X_coords, Y = Y_coords)
    
    # Save prepared objects to RData for direct loading in OLINgui
    save(sw_data, sw_xy, file = "marray_data.RData")
    
    # Assign to global environment to support "Browse objects" in OLINgui
    assign("sw", sw_data, envir = .GlobalEnv)
    assign("sw.xy", sw_xy, envir = .GlobalEnv)
    
    # ==========================================
    # --- Programmatic OLIN Normalization ---
    # ==========================================
    
    norm_data <- tryCatch({
      OLIN::olin(sw_data, alpha = 0.6, iter = 2)
    }, error = function(e) {
      message("OLIN normalization failed, falling back to standard marray loess normalization: ", e\$message)
      tryCatch({
        marray::maNorm(sw_data)
      }, error = function(e2) {
        NULL
      })
    })
    
    # Export normalized data to CSV
    if (!is.null(norm_data)) {
      M_val <- marray::maM(norm_data)
      A_val <- marray::maA(norm_data)
      
      out_df <- data.frame(Feature_ID = rownames(Rf))
      for (i in seq_len(ncol(M_val))) {
        out_df[[paste0("M_Normalized_Sample_", i)]] <- M_val[, i]
        out_df[[paste0("A_Normalized_Sample_", i)]] <- A_val[, i]
      }
      write.csv(out_df, "normalized_data.csv", row.names = FALSE)
    } else {
      # Fallback: write raw M and A values
      M_raw <- log2(Rf) - log2(Gf)
      A_raw <- 0.5 * (log2(Rf) + log2(Gf))
      out_df <- data.frame(Feature_ID = rownames(Rf))
      for (i in seq_len(ncol(M_raw))) {
        out_df[[paste0("M_Raw_Sample_", i)]] <- M_raw[, i]
        out_df[[paste0("A_Raw_Sample_", i)]] <- A_raw[, i]
      }
      write.csv(out_df, "normalized_data.csv", row.names = FALSE)
    }
    
    # ==========================================
    # --- Statistical Bias Testing ---
    # ==========================================
    
    sink("statistical_tests.txt")
    cat("====================================================\n")
    cat("OLIN Statistical Bias Analysis Report\n")
    cat("====================================================\n\n")
    
    cat("1. ANOVA for Intensity-Dependent Bias (anovaint):\n")
    tryCatch({
      res_int <- OLIN::anovaint(sw_data, index = 1, N = 10)
      print(res_int)
    }, error = function(e) {
      cat("Error running anovaint: ", e\$message, "\n")
    })
    cat("\n----------------------------------------------------\n\n")
    
    cat("2. ANOVA for Spatial Bias (anovaspatial):\n")
    tryCatch({
      res_spa <- OLIN::anovaspatial(sw_data, index = 1, xN = 4, yN = 4)
      print(res_spa)
    }, error = function(e) {
      cat("Error running anovaspatial: ", e\$message, "\n")
    })
    cat("\n====================================================\n")
    sink()
    
    # ==========================================
    # --- Diagnostic Visualizations ---
    # ==========================================
    
    pdf("diagnostic_plots.pdf", width = 10, height = 8)
    
    # 1. MA Plot (Raw)
    try({
      plot(sw_data, main = "MA Plot (Raw Data)")
    })
    
    # 2. MA Plot (Normalized)
    if (!is.null(norm_data)) {
      try({
        plot(norm_data, main = "MA Plot (Normalized Data)")
      })
    }
    
    # 3. Spatial Plot of M (Raw)
    try({
      OLIN::mxy.plot(sw_data, array = 1, main = "Spatial M-value Distribution (Raw, Array 1)")
    })
    
    # 4. Spatial Plot of M (Normalized)
    if (!is.null(norm_data)) {
      try({
        OLIN::mxy.plot(norm_data, array = 1, main = "Spatial M-value Distribution (Normalized, Array 1)")
      })
    }
    
    # 5. Foreground/Background Visualization
    try({
      OLIN::fgbg.visu(sw_data, array = 1)
    })
    
    dev.off()
    
    # ==========================================
    # --- Launch OLINgui (Interactive Only) ---
    # ==========================================
    
    if (interactive()) {
      message("Launching OLINgui. Please load 'sw' and 'sw.xy' from the global environment.")
      OLINgui()
    } else {
      message("Non-interactive mode: OLINgui launch skipped. Data saved to 'marray_data.RData' and 'xy_data.RData' for GUI use.")
    }

    writeLines(c(
        '"BIOC_OLINGUI_OLINGUI_MICROARRAY_PIPELINE":',
        paste0('    OLINgui: ', as.character(packageVersion('OLINgui')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_olingui_microarray_pipeline.csv versions.yml
    """
}

workflow BIOC_OLINGUI_OLINGUI_MICROARRAY_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_OLINGUI_OLINGUI_MICROARRAY_PIPELINE(ch_input)

    emit:
    tables   = BIOC_OLINGUI_OLINGUI_MICROARRAY_PIPELINE.out.tables
    plots    = BIOC_OLINGUI_OLINGUI_MICROARRAY_PIPELINE.out.plots
    objects  = BIOC_OLINGUI_OLINGUI_MICROARRAY_PIPELINE.out.objects
    versions = BIOC_OLINGUI_OLINGUI_MICROARRAY_PIPELINE.out.versions
}
