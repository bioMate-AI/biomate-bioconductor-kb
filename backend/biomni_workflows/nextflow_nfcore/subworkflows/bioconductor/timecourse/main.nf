#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: timecourse — timecourse_analysis
// Perform longitudinal time-course microarray analysis to identify genes with significant temporal profile changes across one, two, or multiple biological conditi
// Input: counts.csv, coldata.csv
// Container: 1.82.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: timecourse
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TIMECOURSE_TIMECOURSE_ANALYSIS {
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
    .bm_deps <- c("timecourse")
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
    library(timecourse)
    
    # --- Read and align input data ---
    if (!file.exists("counts.csv") || !file.exists("coldata.csv")) {
      stop("Required input files 'counts.csv' and/or 'coldata.csv' are missing.")
    }
    
    # Read normalized expression matrix (probes/genes as rows, samples as columns)
    exprs_df <- read.csv("counts.csv", row.names = 1, check.names = FALSE)
    exprs_mat <- as.matrix(exprs_df)
    
    # Read sample metadata
    coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
    
    # Align samples between expression matrix and metadata
    common_samples <- intersect(colnames(exprs_mat), coldata\$sample)
    if (length(common_samples) == 0) {
      stop("No matching samples found between counts.csv and coldata.csv.")
    }
    exprs_mat <- exprs_mat[, common_samples, drop = FALSE]
    coldata <- coldata[match(common_samples, coldata\$sample), ]
    
    # --- Robustly parse and reconstruct experimental design ---
    # Ensure 'condition' column exists
    if (!"condition" %in% colnames(coldata)) {
      coldata\$condition <- "single_cond"
    }
    
    # Ensure 'time' column exists; if missing, synthesize sequential time points
    if (!"time" %in% colnames(coldata)) {
      message("'time' column missing in coldata.csv. Synthesizing sequential time points...")
      coldata\$time <- 1
      for (cond in unique(coldata\$condition)) {
        idx <- which(coldata\$condition == cond)
        n_cond <- length(idx)
        # Assume 3 replicates as default to distribute time points
        reps_assumed <- 3
        times_assumed <- ceiling(n_cond / reps_assumed)
        coldata\$time[idx] <- rep(1:times_assumed, each = reps_assumed)[1:n_cond]
      }
    }
    coldata\$time <- as.numeric(coldata\$time)
    
    # Ensure 'replicate' column exists; if missing, synthesize replicate IDs
    if (!"replicate" %in% colnames(coldata)) {
      message("'replicate' column missing in coldata.csv. Synthesizing replicate IDs...")
      cond_time <- paste(coldata\$condition, coldata\$time, sep = "_")
      coldata\$replicate <- ave(coldata\$sample, cond_time, FUN = seq_along)
    }
    coldata\$replicate <- as.character(coldata\$replicate)
    
    # Sort data by condition, replicate, and time to match timecourse package expectations
    order_idx <- order(coldata\$condition, coldata\$replicate, coldata\$time)
    coldata <- coldata[order_idx, ]
    exprs_mat <- exprs_mat[, coldata\$sample, drop = FALSE]
    
    # Determine experimental parameters
    u_conds <- sort(unique(coldata\$condition))
    n_conds <- length(u_conds)
    times_val <- length(unique(coldata\$time))
    
    message(paste("Detected", n_conds, "condition(s) and", times_val, "time point(s)."))
    
    # --- Run the appropriate timecourse analysis ---
    out_stats <- NULL
    analysis_type <- ""
    
    tryCatch({
      if (n_conds == 1) {
        # One-sample longitudinal analysis
        analysis_type <- "one-sample"
        # Calculate replicates per gene (handling potential missing values)
        reps_vec <- round(rowSums(!is.na(exprs_mat)) / times_val)
        reps_vec[reps_vec < 2] <- 2 # Minimum 2 replicates required
        
        out_stats <- mb.long(
          exprs_mat, 
          times = times_val, 
          reps = reps_vec, 
          rep.grp = coldata\$replicate, 
          time.grp = coldata\$time, 
          HotellingT2.only = FALSE
        )
        
      } else if (n_conds == 2) {
        # Two-sample longitudinal analysis (paired or independent)
        analysis_type <- "two-sample"
        method_param <- "2" # Default to independent two-sample
        
        # Calculate replicate matrix (ngenes x 2)
        reps_mat <- matrix(0, nrow = nrow(exprs_mat), ncol = 2)
        for (i in 1:2) {
          cond_cols <- which(coldata\$condition == u_conds[i])
          reps_mat[, i] <- round(rowSums(!is.na(exprs_mat[, cond_cols, drop = FALSE])) / times_val)
        }
        reps_mat[reps_mat < 2] <- 2
        
        out_stats <- mb.long(
          exprs_mat, 
          method = method_param, 
          times = times_val, 
          reps = reps_mat, 
          condition.grp = coldata\$condition, 
          rep.grp = coldata\$replicate, 
          time.grp = coldata\$time, 
          HotellingT2.only = FALSE
        )
        
      } else {
        # Multi-sample longitudinal analysis
        analysis_type <- "multi-sample"
        
        # Calculate replicate matrix (ngenes x D)
        reps_mat <- matrix(0, nrow = nrow(exprs_mat), ncol = n_conds)
        for (i in 1:n_conds) {
          cond_cols <- which(coldata\$condition == u_conds[i])
          reps_mat[, i] <- round(rowSums(!is.na(exprs_mat[, cond_cols, drop = FALSE])) / times_val)
        }
        reps_mat[reps_mat < 2] <- 2
        
        out_stats <- mb.MANOVA(
          exprs_mat, 
          times = times_val, 
          D = n_conds, 
          size = reps_mat, 
          rep.grp = coldata\$replicate, 
          condition.grp = coldata\$condition
        )
      }
    }, error = function(e) {
      stop(paste("Error during timecourse analysis execution:", e\$message))
    })
    
    # --- Extract and format results ---
    results_df <- data.frame(
      gene_id = rownames(exprs_mat),
      stringsAsFactors = FALSE
    )
    
    if (!is.null(out_stats)) {
      # Extract MB statistic if available
      if ("MB" %in% names(out_stats)) {
        results_df\$MB_stat <- out_stats\$MB
      } else {
        results_df\$MB_stat <- NA
      }
      
      # Extract Hotelling T2 statistic if available
      if ("HotellingT2" %in% names(out_stats)) {
        results_df\$HotellingT2 <- out_stats\$HotellingT2
      } else if ("Chisq" %in% names(out_stats)) {
        results_df\$HotellingT2 <- out_stats\$Chisq
      } else {
        results_df\$HotellingT2 <- NA
      }
      
      # Rank genes based on the primary statistic (MB if available, otherwise HotellingT2)
      if (any(!is.na(results_df\$MB_stat))) {
        results_df <- results_df[order(results_df\$MB_stat, decreasing = TRUE), ]
      } else if (any(!is.na(results_df\$HotellingT2))) {
        results_df <- results_df[order(results_df\$HotellingT2, decreasing = TRUE), ]
      }
      
      results_df\$rank <- 1:nrow(results_df)
    } else {
      results_df\$MB_stat <- NA
      results_df\$HotellingT2 <- NA
      results_df\$rank <- NA
    }
    
    # Write results table
    write.csv(results_df, "temporal_stats.csv", row.names = FALSE)
    message("Saved temporal statistics to 'temporal_stats.csv'.")
    
    # --- Generate temporal profile plots for top genes ---
    num_plots <- min(5, nrow(results_df))
    pdf("profile_plots.pdf", width = 8, height = 6)
    
    if (!is.null(out_stats)) {
      for (r in 1:num_plots) {
        tryCatch({
          # Determine appropriate stats parameter for plotProfile
          stat_to_plot <- if (analysis_type == "multi-sample") "MB" else NULL
          
          plotProfile(
            out_stats, 
            type = "b", 
            gnames = rownames(exprs_mat), 
            ranking = r, 
            xlab = "Time Point",
            stats = stat_to_plot
          )
        }, error = function(e) {
          warning(paste("Could not plot profile for rank", r, ":", e\$message))
        })
      }
    } else {
      # Fallback empty plot if analysis failed
      plot(1, type = "n", axes = FALSE, xlab = "", ylab = "")
      text(1, 1, "No profile plots generated due to analysis failure.")
    }
    
    dev.off()
    message("Saved temporal profile plots to 'profile_plots.pdf'.")

    writeLines(c(
        '"BIOC_TIMECOURSE_TIMECOURSE_ANALYSIS":',
        paste0('    timecourse: ', as.character(packageVersion('timecourse')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_timecourse_analysis.csv versions.yml
    """
}

workflow BIOC_TIMECOURSE_TIMECOURSE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_TIMECOURSE_TIMECOURSE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_TIMECOURSE_TIMECOURSE_ANALYSIS.out.tables
    plots    = BIOC_TIMECOURSE_TIMECOURSE_ANALYSIS.out.plots
    objects  = BIOC_TIMECOURSE_TIMECOURSE_ANALYSIS.out.objects
    versions = BIOC_TIMECOURSE_TIMECOURSE_ANALYSIS.out.versions
}
