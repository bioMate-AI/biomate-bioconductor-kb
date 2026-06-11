#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: antiProfiles — anti_profiles_analysis
// Build and evaluate a gene expression anti-profile to distinguish cancer samples from normal controls based on expression variance heterogeneity.
// Input: counts.csv, coldata.csv
// Container: 1.50.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: antiProfiles
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ANTIPROFILES_ANTI_PROFILES_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # --- Load required libraries ---
    library(antiProfiles)
    
    # --- Load and preprocess input data ---
    if (!file.exists("counts.csv") || !file.exists("coldata.csv")) {
      stop("Required input files 'counts.csv' and/or 'coldata.csv' are missing.")
    }
    
    # Read expression matrix (microarray normalized expression or log-transformed counts)
    exprs_df <- read.csv("counts.csv", row.names = 1, check.names = FALSE)
    coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
    
    # Align samples between expression matrix and metadata
    common_samples <- intersect(colnames(exprs_df), coldata\$sample)
    if (length(common_samples) == 0) {
      stop("No matching samples found between counts.csv and coldata.csv.")
    }
    
    exprs_mat <- as.matrix(exprs_df[, common_samples, drop = FALSE])
    coldata <- coldata[match(common_samples, coldata\$sample), , drop = FALSE]
    
    # If data appears to be raw counts (non-log scale), apply log2 transformation
    if (max(exprs_mat, na.rm = TRUE) > 50) {
      message("Data values are large; applying log2(x + 1) transformation...")
      exprs_mat <- log2(exprs_mat + 1)
    }
    
    # --- Define binary status (0 = Normal/Control, 1 = Cancer/Case) ---
    status <- rep(1, nrow(coldata))
    normal_idx <- grep("normal|control|ctrl", coldata\$condition, ignore.case = TRUE)
    if (length(normal_idx) > 0) {
      status[normal_idx] <- 0
    } else {
      # Fallback: assign the first alphabetical condition to 0 (Normal)
      levels_cond <- sort(unique(coldata\$condition))
      status[coldata\$condition == levels_cond[1]] <- 0
      message(paste0("No explicit 'normal' or 'control' condition found. Mapping '", 
                     levels_cond[1], "' to 0 (Normal) and others to 1 (Cancer)."))
    }
    
    # --- Partition data into Training and Testing sets ---
    # Anti-profiles must be trained on a subset and tested on independent samples
    set.seed(123)
    normal_samples <- which(status == 0)
    cancer_samples <- which(status == 1)
    
    if (length(normal_samples) < 2 || length(cancer_samples) < 2) {
      stop("Analysis requires at least 2 normal and 2 cancer samples.")
    }
    
    # Use a 60/40 split if sample size permits, otherwise use all samples for both (with warning)
    if (length(normal_samples) >= 4 && length(cancer_samples) >= 4) {
      train_normal <- sample(normal_samples, floor(length(normal_samples) * 0.6))
      train_cancer <- sample(cancer_samples, floor(length(cancer_samples) * 0.6))
      train_idx <- c(train_normal, train_cancer)
      test_idx <- setdiff(seq_along(status), train_idx)
      message("Data successfully split into training and testing sets.")
    } else {
      train_idx <- seq_along(status)
      test_idx <- seq_along(status)
      message("Sample size too small for independent split; using all samples for both training and testing.")
    }
    
    # --- Compute variance statistics (apStats) ---
    # minL is the minimum number of normal samples required
    n_normal_train <- sum(status[train_idx] == 0)
    minL_val <- max(2, n_normal_train)
    
    message("Computing variance ratios and probe statistics...")
    colonStats <- apStats(exprs_mat[, train_idx, drop = FALSE], 
                          status[train_idx], 
                          minL = minL_val)
    
    probe_stats <- getProbeStats(colonStats)
    write.csv(probe_stats, "probe_stats.csv", row.names = TRUE)
    
    # --- Build the Anti-Profile ---
    # Select the most hyper-variable probesets (defaulting to 100 or total features if less)
    sigsize_val <- max(5, min(100, nrow(exprs_mat)))
    message(paste("Building anti-profile with signature size:", sigsize_val))
    ap <- buildAntiProfile(colonStats, tissueSpec = FALSE, sigsize = sigsize_val)
    
    # Export anti-profile details
    probeset_ids <- getProbesetIds(ap)
    write.csv(data.frame(probeset_id = probeset_ids), "antiprofile_probesets.csv", row.names = FALSE)
    
    normal_regions <- getNormalRegions(ap)
    write.csv(as.data.frame(normal_regions), "normal_regions.csv", row.names = TRUE)
    
    # --- Compute Anti-Profile Scores for Test Samples ---
    message("Computing anti-profile scores for test samples...")
    counts_score <- apCount(ap, exprs_mat[, test_idx, drop = FALSE])
    
    results <- data.frame(
      sample = coldata\$sample[test_idx],
      condition = coldata\$condition[test_idx],
      status = status[test_idx],
      antiprofile_score = counts_score
    )
    write.csv(results, "antiprofile_scores.csv", row.names = FALSE)
    
    # --- Generate Diagnostic Visualizations ---
    message("Generating diagnostic plots...")
    pdf("antiprofiles_plots.pdf", width = 12, height = 6)
    par(mfrow = c(1, 2))
    
    # Plot 1: Histogram of log variance ratios
    hist(probe_stats\$stat, nc = 50, 
         main = "Histogram of Log Variance Ratio", 
         xlab = "log2 variance ratio (Cancer / Normal)", 
         col = "skyblue", border = "white")
    
    # Plot 2: Dotchart of anti-profile scores
    o <- order(counts_score)
    plot_colors <- ifelse(status[test_idx][o] == 1, "#D55E00", "#0072B2") # Colorblind-friendly red/blue
    dotchart(counts_score[o], 
             col = plot_colors,
             labels = coldata\$sample[test_idx][o], 
             pch = 19, 
             xlab = "Anti-profile score (deviation count)", 
             ylab = "Samples", 
             main = "Anti-profile Scores",
             cex = 0.8)
    legend("bottomright", legend = c("Cancer/Case", "Normal/Control"), pch = 19, col = c("#D55E00", "#0072B2"))
    
    dev.off()
    
    message("Pipeline completed successfully. Outputs written to working directory.")

    writeLines(c(
        '"BIOC_ANTIPROFILES_ANTI_PROFILES_ANALYSIS":',
        paste0('    antiProfiles: ', as.character(packageVersion('antiProfiles')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_anti_profiles_analysis.csv versions.yml
    """
}

workflow BIOC_ANTIPROFILES_ANTI_PROFILES_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_ANTIPROFILES_ANTI_PROFILES_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_ANTIPROFILES_ANTI_PROFILES_ANALYSIS.out.tables
    plots    = BIOC_ANTIPROFILES_ANTI_PROFILES_ANALYSIS.out.plots
    objects  = BIOC_ANTIPROFILES_ANTI_PROFILES_ANALYSIS.out.objects
    versions = BIOC_ANTIPROFILES_ANTI_PROFILES_ANALYSIS.out.versions
}
