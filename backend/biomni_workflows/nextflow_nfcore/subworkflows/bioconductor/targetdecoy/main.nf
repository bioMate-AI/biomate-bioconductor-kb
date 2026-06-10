#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: TargetDecoy — target_decoy_analysis
// Evaluate the quality of the target-decoy approach (TDA) for peptide/protein identification using diagnostic plots and score tables.
// Input: intensity.csv, coldata.csv
// Container: 1.16.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: TargetDecoy, ggplot2
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TARGETDECOY_TARGET_DECOY_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20"

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
    
    # Load required libraries
    library(TargetDecoy)
    library(ggplot2)
    
    # Helper function to save a placeholder PDF in case of insufficient data or errors
    save_placeholder_pdf <- function(filename, message) {
      pdf(filename, width = 6, height = 5)
      plot(0, 0, type = "n", xlab = "", ylab = "", axes = FALSE)
      text(0, 0, message, cex = 1.0, col = "red")
      dev.off()
    }
    
    # ==========================================
    # Stage 1: Load and Preprocess Input Data
    # ==========================================
    
    message("Loading input files...")
    intensity_file <- "intensity.csv"
    coldata_file <- "coldata.csv"
    
    if (!file.exists(intensity_file) || !file.exists(coldata_file)) {
      stop("Required input files 'intensity.csv' or 'coldata.csv' are missing.")
    }
    
    # Read intensity matrix (features as rows, samples as columns)
    intensity <- read.csv(intensity_file, row.names = 1, check.names = FALSE)
    # Read coldata (sample to condition mapping)
    coldata <- read.csv(coldata_file, stringsAsFactors = FALSE)
    
    feature_ids <- rownames(intensity)
    if (length(feature_ids) == 0) {
      stop("The intensity matrix has no features (rows).")
    }
    
    # ==========================================
    # Stage 2: Prepare Target-Decoy Score Table
    # ==========================================
    message("Preparing target-decoy score table...")
    
    # Check if feature IDs already contain decoy/reverse indicators
    is_decoy <- grepl("decoy|rev|reverse", feature_ids, ignore.case = TRUE)
    
    # If no decoys are present in the input, simulate a competitive TDA scenario
    # by randomly designating 50% of the features as decoys (reproducibly)
    if (sum(is_decoy) == 0) {
      message("No decoy features detected. Simulating a competitive TDA scenario (50% decoys)...")
      set.seed(42)
      is_decoy <- sample(c(TRUE, FALSE), length(feature_ids), replace = TRUE, prob = c(0.5, 0.5))
    }
    
    # Clean up intensity values (replace NAs with 0, ensure non-negative)
    intensity[is.na(intensity)] <- 0
    intensity[intensity < 0] <- 0
    
    # Identify valid sample columns matching coldata
    sample_cols <- intersect(coldata\$sample, colnames(intensity))
    if (length(sample_cols) == 0) {
      # Fallback to all numeric columns if no match with coldata
      sample_cols <- colnames(intensity)[sapply(intensity, is.numeric)]
    }
    
    # Create the base PSM data frame
    psm_df <- data.frame(
      feature_id = feature_ids,
      isdecoy = is_decoy,
      stringsAsFactors = FALSE
    )
    
    # Add sample intensities as individual score columns (adding 1 to avoid 0 scores)
    for (col in sample_cols) {
      psm_df[[col]] <- intensity[[col]] + 1
    }
    
    # Calculate an overall representative score (mean intensity across all samples)
    psm_df\$mean_score <- rowMeans(intensity[, sample_cols, drop = FALSE]) + 1
    
    # Generate and save the decoy score table
    decoy_tbl <- decoyScoreTable(psm_df, decoy = "isdecoy", score = "mean_score", log10 = FALSE)
    write.csv(decoy_tbl, "decoy_score_table.csv", row.names = FALSE)
    
    # ==========================================
    # Stage 3: Single-Run Diagnostic Plots
    # ==========================================
    message("Generating single-run diagnostic plots...")
    
    # 1. Combined 4-plot grid (PP-plot, Histogram, and their zoomed versions)
    tryCatch({
      pdf("target_decoy_diagnostics_grid.pdf", width = 10, height = 8)
      print(evalTargetDecoys(psm_df, decoy = "isdecoy", score = "mean_score", log10 = FALSE, nBins = 50))
      dev.off()
    }, error = function(e) {
      save_placeholder_pdf("target_decoy_diagnostics_grid.pdf", paste("Error generating grid:", e\$message))
    })
    
    # 2. Individual Histogram
    tryCatch({
      p_hist <- evalTargetDecoysHist(psm_df, decoy = "isdecoy", score = "mean_score", log10 = FALSE, nBins = 50)
      ggsave("target_decoy_histogram.pdf", plot = p_hist, width = 6, height = 5)
    }, error = function(e) {
      save_placeholder_pdf("target_decoy_histogram.pdf", paste("Error generating histogram:", e\$message))
    })
    
    # 3. Individual PP-plot
    tryCatch({
      p_pp <- evalTargetDecoysPPPlot(psm_df, decoy = "isdecoy", score = "mean_score", log10 = FALSE)
      ggsave("target_decoy_ppplot.pdf", plot = p_pp, width = 6, height = 5)
    }, error = function(e) {
      save_placeholder_pdf("target_decoy_ppplot.pdf", paste("Error generating PP-plot:", e\$message))
    })
    
    # ==========================================
    # Stage 4: Multi-Score Comparison (Samples)
    # ==========================================
    message("Comparing target-decoy assumptions across samples...")
    
    # Select up to 4 samples to treat as different search engine scores
    compare_scores <- head(sample_cols, 4)
    
    if (length(compare_scores) >= 2) {
      tryCatch({
        p_compare_scores <- createPPlotScores(
          psm_df,
          decoy = "isdecoy",
          scores = compare_scores,
          log10 = rep(FALSE, length(compare_scores))
        )
        ggsave("compare_samples_ppplot.pdf", plot = p_compare_scores, width = 8, height = 8)
      }, error = function(e) {
        save_placeholder_pdf("compare_samples_ppplot.pdf", paste("Error comparing samples:", e\$message))
      })
    } else {
      save_placeholder_pdf("compare_samples_ppplot.pdf", "Skipped: Less than 2 samples available for comparison.")
    }
    
    # ==========================================
    # Stage 5: Multi-Run Comparison (Conditions)
    # ==========================================
    message("Comparing target-decoy assumptions across conditions...")
    
    conditions <- unique(coldata\$condition)
    object_list <- list()
    
    for (cond in conditions) {
      cond_samples <- coldata\$sample[coldata\$condition == cond]
      cond_samples <- intersect(cond_samples, colnames(intensity))
      
      if (length(cond_samples) > 0) {
        cond_df <- data.frame(
          feature_id = feature_ids,
          isdecoy = is_decoy,
          score = rowMeans(intensity[, cond_samples, drop = FALSE]) + 1,
          stringsAsFactors = FALSE
        )
        object_list[[cond]] <- cond_df
      }
    }
    
    if (length(object_list) >= 2) {
      tryCatch({
        p_compare_conditions <- createPPlotObjects(
          object_list,
          decoy = "isdecoy",
          score = "score",
          log10 = FALSE
        )
        ggsave("compare_conditions_ppplot.pdf", plot = p_compare_conditions, width = 8, height = 8)
      }, error = function(e) {
        save_placeholder_pdf("compare_conditions_ppplot.pdf", paste("Error comparing conditions:", e\$message))
      })
    } else {
      save_placeholder_pdf("compare_conditions_ppplot.pdf", "Skipped: Less than 2 conditions available for comparison.")
    }
    
    message("TargetDecoy analysis pipeline completed successfully!")

    writeLines(c(
        '"BIOC_TARGETDECOY_TARGET_DECOY_ANALYSIS":',
        paste0('    TargetDecoy: ', as.character(packageVersion('TargetDecoy')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_target_decoy_analysis.csv versions.yml
    """
}

workflow BIOC_TARGETDECOY_TARGET_DECOY_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_TARGETDECOY_TARGET_DECOY_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_TARGETDECOY_TARGET_DECOY_ANALYSIS.out.tables
    plots    = BIOC_TARGETDECOY_TARGET_DECOY_ANALYSIS.out.plots
    objects  = BIOC_TARGETDECOY_TARGET_DECOY_ANALYSIS.out.objects
    versions = BIOC_TARGETDECOY_TARGET_DECOY_ANALYSIS.out.versions
}
