#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: sesame — sesame_differential_methylation
// Perform differential methylation locus (DML) and region (DMR) analysis on a beta-value matrix using the sesame package, including missing value imputation, leve
// Input: matrix.csv, coldata.csv
// Container: 1.28.1--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SummarizedExperiment, sesame
// Visualizations: volcano plot
// QC: missing-value handling
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SESAME_SESAME_DIFFERENTIAL_METHYLATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20"

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
    .bm_deps <- c("sesame", "SummarizedExperiment")
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
     library(SummarizedExperiment)
   library(sesame)
    
    # Print version info for reproducibility
    tryCatch({
      sesame_checkVersion()
    }, error = function(e) {
      message("Could not check sesame version: ", e\$message)
    })
    
    # ==========================================
    # --- Load and Align Input Data ---
    # ==========================================
    message("Loading input data...")
    
    # Read the beta value matrix
    matrix_df <- read.csv("matrix.csv", check.names = FALSE)
    if (!"feature_id" %in% colnames(matrix_df)) {
      stop("Input matrix.csv must contain a 'feature_id' column.")
    }
    rownames(matrix_df) <- matrix_df\$feature_id
    matrix_df\$feature_id <- NULL
    
    # Read the sample metadata
    coldata_df <- read.csv("coldata.csv", check.names = FALSE)
    if (!all(c("sample", "condition") %in% colnames(coldata_df))) {
      stop("Input coldata.csv must contain 'sample' and 'condition' columns.")
    }
    rownames(coldata_df) <- coldata_df\$sample
    
    # Align samples between matrix and metadata
    common_samples <- intersect(colnames(matrix_df), rownames(coldata_df))
    if (length(common_samples) == 0) {
      stop("No overlapping samples found between matrix.csv and coldata.csv.")
    }
    message(sprintf("Aligned %d samples for analysis.", length(common_samples)))
    
    matrix_df <- matrix_df[, common_samples, drop = FALSE]
    coldata_df <- coldata_df[common_samples, , drop = FALSE]
    
    # Convert matrix to numeric matrix
    beta_matrix <- as.matrix(matrix_df)
    class(beta_matrix) <- "numeric"
    
    # ==========================================
    # --- Preprocessing & Quality Control ---
    # ==========================================
    message("Preprocessing and imputing missing values...")
    
    # Impute missing beta values using mean imputation across neighbors/samples
    if (any(is.na(beta_matrix))) {
      message("Missing values detected. Performing imputation...")
      beta_matrix <- imputeBetasMatrixByMean(beta_matrix)
    }
    
    # Create SummarizedExperiment object
    se <- SummarizedExperiment(
      assays = list(beta = beta_matrix),
      colData = coldata_df
    )
    
    # Ensure condition is a factor
    colData(se)\$condition <- factor(colData(se)\$condition)
    
    # Filter out probes with insufficient variation or missing levels across conditions
    message("Checking levels and filtering probes...")
    se_ok <- checkLevels(assay(se), colData(se)\$condition)
    se <- se[se_ok, ]
    message(sprintf("%d probes passed level checking.", nrow(se)))
    
    if (nrow(se) == 0) {
      stop("No probes passed the level checking. Cannot proceed with DML modeling.")
    }
    
    # ==========================================
    # --- Differential Methylation Locus (DML) ---
    # ==========================================
    message("Running DML modeling...")
    
    # Fit linear models for each CpG locus
    smry <- DML(se, ~ condition)
    
    # Extract test statistics manually from the DMLSummary object
    probes <- names(smry)
    first_coefs <- smry[[1]]\$coefficients
    coef_names <- rownames(first_coefs)
    
    # Identify the contrast coefficient corresponding to the condition
    contrast_name <- coef_names[grep("condition", coef_names)][1]
    if (is.na(contrast_name)) {
      # Fallback to the second coefficient if naming convention differs
      contrast_name <- coef_names[2]
    }
    message(sprintf("Extracting statistics for contrast: %s", contrast_name))
    
    est <- sapply(smry, function(x) x\$coefficients[contrast_name, "Estimate"])
    pval <- sapply(smry, function(x) x\$coefficients[contrast_name, "Pr(>|t|)"])
    
    test_result <- data.frame(
      Probe_ID = probes,
      Estimate = est,
      Pval = pval,
      Pval_adj = p.adjust(pval, method = "BH"),
      stringsAsFactors = FALSE
    )
    
    # Sort by significance and save
    test_result <- test_result[order(test_result\$Pval), ]
    write.csv(test_result, "dml_results.csv", row.names = FALSE)
    message("DML results saved to dml_results.csv")
    
    # ==========================================
    # --- Differentially Methylated Regions (DMR) ---
    # ==========================================
    message("Running DMR analysis...")
    
    dmr_result <- data.frame(Message = "DMR analysis not run or failed")
    tryCatch({
      # Infer platform based on probe ID prefixes
      sample_probes <- rownames(se)
      platform <- "EPIC" # Default fallback
      if (any(grepl("^cg", sample_probes))) {
        platform <- "EPIC"
      } else if (any(grepl("^mu", sample_probes)) || any(grepl("^uk", sample_probes))) {
        platform <- "MM285"
      }
      
      message(sprintf("Using platform annotation: %s for DMR merging", platform))
      
      # Merge neighboring CpGs into regions
      merged <- DMR(se, smry, contrast_name, platform = platform)
      if (!is.null(merged) && nrow(merged) > 0) {
        dmr_result <- as.data.frame(merged)
        message(sprintf("Successfully identified %d DMRs.", nrow(dmr_result)))
      } else {
        message("No significant DMRs identified.")
        dmr_result <- data.frame(Message = "No significant DMRs found")
      }
    }, error = function(e) {
      message("DMR analysis failed: ", e\$message)
      dmr_result <<- data.frame(Error = e\$message)
    })
    
    write.csv(dmr_result, "dmr_results.csv", row.names = FALSE)
    
    # ==========================================
    # --- Visualization ---
    # ==========================================
    message("Generating diagnostic plots...")
    
    pdf("dml_volcano.pdf", width = 6, height = 6)
    if (nrow(test_result) > 0) {
      # Define colors based on significance
      signif_cutoff <- 0.05
      point_colors <- ifelse(test_result\$Pval_adj < signif_cutoff, "red", "black")
      
      plot(
        test_result\$Estimate, 
        -log10(test_result\$Pval),
        xlab = paste("Estimate (", contrast_name, ")", sep = ""),
        ylab = "-log10(P-value)",
        main = "Volcano Plot of Differential Methylation",
        col = point_colors,
        pch = 20,
        cex = 0.8
      )
      # Add horizontal line for significance threshold
      if (any(test_result\$Pval_adj < signif_cutoff)) {
        max_non_sig_pval <- max(test_result\$Pval[test_result\$Pval_adj >= signif_cutoff], na.rm = TRUE)
        abline(h = -log10(max_non_sig_pval), col = "blue", lty = 2)
      }
    } else {
      plot(1, 1, type = "n", xlab = "", ylab = "", main = "No DML results to plot")
    }
    dev.off()
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_SESAME_SESAME_DIFFERENTIAL_METHYLATION":',
        paste0('    sesame: ', as.character(packageVersion('sesame')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sesame_differential_methylation.csv versions.yml
    """
}

workflow BIOC_SESAME_SESAME_DIFFERENTIAL_METHYLATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_SESAME_SESAME_DIFFERENTIAL_METHYLATION(ch_input)

    emit:
    tables   = BIOC_SESAME_SESAME_DIFFERENTIAL_METHYLATION.out.tables
    plots    = BIOC_SESAME_SESAME_DIFFERENTIAL_METHYLATION.out.plots
    objects  = BIOC_SESAME_SESAME_DIFFERENTIAL_METHYLATION.out.objects
    versions = BIOC_SESAME_SESAME_DIFFERENTIAL_METHYLATION.out.versions
}
