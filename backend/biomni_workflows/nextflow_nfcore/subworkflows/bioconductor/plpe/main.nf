#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: PLPE — plpe_paired_analysis
// Perform paired high-throughput differential expression analysis using local pooled error (LPE) and weighted L-statistics with FDR estimation.
// Input: counts.csv, coldata.csv
// Container: 1.70.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: PLPE
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PLPE_PLPE_PAIRED_ANALYSIS {
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
    .bm_deps <- c("PLPE")
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
    library(PLPE)
    
    # --- Load input data ---
    if (!file.exists("counts.csv") || !file.exists("coldata.csv")) {
      stop("Required input files 'counts.csv' and/or 'coldata.csv' are missing.")
    }
    
    counts_df <- read.csv("counts.csv", check.names = FALSE)
    coldata <- read.csv("coldata.csv", check.names = FALSE)
    
    # Set row names for counts
    if ("gene_id" %in% colnames(counts_df)) {
      rownames(counts_df) <- counts_df\$gene_id
      counts_df\$gene_id <- NULL
    } else {
      rownames(counts_df) <- counts_df[, 1]
      counts_df <- counts_df[, -1, drop = FALSE]
    }
    
    # Align samples between expression matrix and metadata
    common_samples <- intersect(colnames(counts_df), coldata\$sample)
    if (length(common_samples) < 4) {
      stop("At least 4 matching samples (2 pairs) are required for paired analysis.")
    }
    counts_df <- counts_df[, common_samples, drop = FALSE]
    coldata <- coldata[match(common_samples, coldata\$sample), , drop = FALSE]
    
    # --- Preprocessing & Normalization ---
    x <- as.matrix(counts_df)
    # Apply log2 transformation if data is not already log-transformed
    if (max(x, na.rm = TRUE) > 50) {
      x[x < 0] <- 0
      x <- log2(x + 1)
    }
    
    # --- Design Matrix Construction ---
    cond_vals <- coldata\$condition
    unique_conds <- unique(cond_vals)
    if (length(unique_conds) < 2) {
      stop("PLPE requires exactly two conditions for paired analysis.")
    }
    cond <- as.numeric(factor(cond_vals, levels = unique_conds[1:2]))
    
    # Construct pairs: pair the i-th sample of condition 1 with the i-th sample of condition 2
    pair <- numeric(nrow(coldata))
    pair[cond == 1] <- 1:sum(cond == 1)
    pair[cond == 2] <- 1:sum(cond == 2)
    
    design <- cbind(cond, pair)
    
    # --- Run PLPE Analysis ---
    # Compute test statistics (L-statistic, t-statistic, and weighted Lw-statistic)
    out <- lpe.paired(x = x, design = design, q = 0.1, data.type = "ms")
    
    # Compute False Discovery Rates (FDRs) using resampling
    out.fdr <- lpe.paired.fdr(x, obj = out)
    
    # --- Export Results and Summaries ---
    results <- data.frame(
      Gene = rownames(x),
      out\$test.out,
      out.fdr\$FDR,
      stringsAsFactors = FALSE
    )
    write.csv(results, "plpe_results.csv", row.names = FALSE)
    
    # Write summaries to a text file
    sink("plpe_summary.txt")
    cat("=== PLPE Analysis Summary ===\n\n")
    cat("--- LPE Paired Object Summary ---\n")
    tryCatch({
      summary(out)
    }, error = function(e) {
      cat("Error summarizing LPE paired object: ", e\$message, "\n")
    })
    cat("\n--- LPE Paired FDR Object Summary ---\n")
    tryCatch({
      summary(out.fdr)
    }, error = function(e) {
      cat("Error summarizing LPE paired FDR object: ", e\$message, "\n")
    })
    sink()
    
    # --- Diagnostic Visualizations ---
    pdf("plpe_plots.pdf", width = 10, height = 5)
    par(mfrow = c(1, 2))
    
    # MA Plot
    plot(results\$A, results\$M, pch = 20, col = "grey",
         xlab = "A (Average Intensity)", ylab = "M (Log Ratio)",
         main = "MA Plot (L-statistic)")
    sig_L <- which(results\$FDR.L < 0.05)
    if (length(sig_L) > 0) {
      points(results\$A[sig_L], results\$M[sig_L], col = "red", pch = 20)
    }
    abline(h = 0, col = "blue", lty = 2)
    
    # Volcano Plot
    plot(results\$L.stat, -log10(results\$p.value.L), pch = 20, col = "grey",
         xlab = "L statistic", ylab = "-log10(p-value L)",
         main = "Volcano Plot (L-statistic)")
    if (length(sig_L) > 0) {
      points(results\$L.stat[sig_L], -log10(results\$p.value.L[sig_L]), col = "red", pch = 20)
    }
    
    dev.off()
    
    cat("PLPE pipeline completed successfully.\n")

    writeLines(c(
        '"BIOC_PLPE_PLPE_PAIRED_ANALYSIS":',
        paste0('    PLPE: ', as.character(packageVersion('PLPE')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_plpe_paired_analysis.csv versions.yml
    """
}

workflow BIOC_PLPE_PLPE_PAIRED_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_PLPE_PLPE_PAIRED_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_PLPE_PLPE_PAIRED_ANALYSIS.out.tables
    plots    = BIOC_PLPE_PLPE_PAIRED_ANALYSIS.out.plots
    objects  = BIOC_PLPE_PLPE_PAIRED_ANALYSIS.out.objects
    versions = BIOC_PLPE_PLPE_PAIRED_ANALYSIS.out.versions
}
