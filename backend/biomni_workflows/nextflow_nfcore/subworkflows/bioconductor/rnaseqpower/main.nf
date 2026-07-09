#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RNASeqPower — rnaseq_power_analysis
// Perform comprehensive sample size and power calculations for RNA-seq experimental design using pilot count data.
// Input: counts.csv, coldata.csv
// Container: 1.50.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: RNASeqPower
// Visualizations: plot (ggplot/base)
// QC: low-count filtering
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RNASEQPOWER_RNASEQ_POWER_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("RNASeqPower")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
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
    library(RNASeqPower)
    
    # ==========================================
    # --- Load and Align Input Data ---
    # ==========================================
    message("Loading input datasets...")
    if (!file.exists("counts.csv") || !file.exists("coldata.csv")) {
        stop("Required input files 'counts.csv' and/or 'coldata.csv' are missing.")
    }
    
    counts <- read.csv("counts.csv", row.names = 1, check.names = FALSE)
    coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
    
    # Align samples between counts and coldata
    common_samples <- intersect(coldata\$sample, colnames(counts))
    if (length(common_samples) == 0) {
        stop("No matching samples found between coldata.csv ('sample' column) and counts.csv column names.")
    }
    
    counts <- counts[, common_samples, drop = FALSE]
    coldata <- coldata[coldata\$sample %in% common_samples, ]
    
    # Identify experimental groups/conditions
    groups <- unique(coldata\$condition)
    if (length(groups) < 2) {
        stop("At least two distinct conditions are required in coldata.csv for comparative power analysis.")
    }
    
    g1 <- groups[1]
    g2 <- groups[2]
    g1_samples <- coldata\$sample[coldata\$condition == g1]
    g2_samples <- coldata\$sample[coldata\$condition == g2]
    
    n1 <- length(g1_samples)
    n2 <- length(g2_samples)
    
    message(sprintf("Found comparison: %s (n=%d) vs %s (n=%d)", g1, n1, g2, n2))
    
    # ==========================================
    # --- Estimate Parameters (Depth & CV) ---
    # ==========================================
    message("Estimating gene-wise mean depth and coefficient of variation (CV)...")
    
    # Filter out low-count genes to avoid noise in CV estimation
    mean_counts <- rowMeans(counts)
    keep <- mean_counts >= 5
    counts_filtered <- counts[keep, , drop = FALSE]
    
    if (nrow(counts_filtered) == 0) {
        stop("No genes passed the minimum mean count threshold of 5.")
    }
    
    # Calculate mean depth per gene across all samples
    gene_depths <- rowMeans(counts_filtered)
    
    # Calculate CV for each group
    calc_cv <- function(x) {
        m <- mean(x)
        if (m <= 0) return(NA)
        sd(x) / m
    }
    
    cv_g1 <- apply(counts_filtered[, g1_samples, drop = FALSE], 1, calc_cv)
    cv_g2 <- apply(counts_filtered[, g2_samples, drop = FALSE], 1, calc_cv)
    
    # Filter out genes with invalid CVs (e.g., zero variance or all zeros)
    valid_indices <- !is.na(cv_g1) & !is.na(cv_g2) & cv_g1 > 0 & cv_g2 > 0 & gene_depths > 0
    counts_filtered <- counts_filtered[valid_indices, , drop = FALSE]
    gene_depths <- gene_depths[valid_indices]
    cv_g1 <- cv_g1[valid_indices]
    cv_g2 <- cv_g2[valid_indices]
    
    # Calculate representative median values for global planning
    median_depth <- median(gene_depths)
    median_cv1 <- median(cv_g1)
    median_cv2 <- median(cv_g2)
    
    message(sprintf("Median Depth: %.2f, Median CV (%s): %.3f, Median CV (%s): %.3f", 
                    median_depth, g1, median_cv1, g2, median_cv2))
    
    # ==========================================
    # --- Global Power & Sample Size Analysis ---
    # ==========================================
    message("Performing global power and sample size calculations...")
    
    effects <- c(1.25, 1.5, 1.75, 2.0)
    powers <- c(0.8, 0.9)
    alpha <- 0.05
    
    # 1. Calculate required sample sizes for various effect sizes and power targets
    global_sample_sizes <- rnapower(
        depth = median_depth,
        cv = median_cv1,
        cv2 = median_cv2,
        effect = effects,
        alpha = alpha,
        power = powers
    )
    
    global_ss_df <- as.data.frame(global_sample_sizes)
    global_ss_df\$Effect_Size <- rownames(global_sample_sizes)
    global_ss_df <- global_ss_df[, c("Effect_Size", colnames(global_sample_sizes))]
    write.csv(global_ss_df, "global_sample_size_table.csv", row.names = FALSE)
    
    # 2. Calculate achieved power for the current sample size (n1, n2)
    global_power <- rnapower(
        depth = median_depth,
        cv = median_cv1,
        cv2 = median_cv2,
        effect = effects,
        alpha = alpha,
        n = n1,
        n2 = n2
    )
    
    global_power_df <- data.frame(
        Effect_Size = effects,
        Achieved_Power = global_power
    )
    write.csv(global_power_df, "global_achieved_power.csv", row.names = FALSE)
    
    # ==========================================
    # --- Gene-Specific Power Analysis ---
    # ==========================================
    message("Performing gene-specific power and sample size calculations...")
    
    # Calculate required sample size per gene to detect a 2-fold change with 80% power
    gene_sample_sizes <- rnapower(
        depth = gene_depths,
        cv = cv_g1,
        cv2 = cv_g2,
        effect = 2.0,
        alpha = 0.05,
        power = 0.8
    )
    
    # Calculate achieved power per gene under the current design for a 2-fold change
    gene_powers <- rnapower(
        depth = gene_depths,
        cv = cv_g1,
        cv2 = cv_g2,
        effect = 2.0,
        alpha = 0.05,
        n = n1,
        n2 = n2
    )
    
    gene_results <- data.frame(
        gene_id = rownames(counts_filtered),
        mean_depth = gene_depths,
        cv_group1 = cv_g1,
        cv_group2 = cv_g2,
        required_n_effect2_power80 = gene_sample_sizes,
        achieved_power_effect2 = gene_powers,
        stringsAsFactors = FALSE
    )
    write.csv(gene_results, "gene_power_analysis.csv", row.names = FALSE)
    
    # ==========================================
    # --- Visualization and Diagnostics ---
    # ==========================================
    message("Generating diagnostic plots...")
    
    pdf("power_analysis_plots.pdf", width = 10, height = 8)
    par(mfrow = c(2, 2), mar = c(5, 4, 4, 2) + 0.1)
    
    # Plot 1: CV vs Mean Depth (classic RNA-seq diagnostic)
    plot(gene_depths, cv_g1, log = "x", pch = 20, col = rgb(0, 0, 1, 0.2),
         xlab = "Mean Depth (log scale)", ylab = "Coefficient of Variation (CV)",
         main = "CV vs Mean Depth per Gene")
    points(gene_depths, cv_g2, pch = 20, col = rgb(1, 0, 0, 0.1))
    legend("topright", legend = c(g1, g2), col = c("blue", "red"), pch = 20)
    
    # Plot 2: Distribution of required sample sizes
    capped_n <- pmin(gene_sample_sizes, 100)
    hist(capped_n, breaks = 30, col = "skyblue", border = "white",
         xlab = "Required Sample Size (capped at 100)",
         main = "Required N per Group\n(Effect = 2.0, Power = 0.8)")
    abline(v = max(n1, n2), col = "red", lty = 2, lwd = 2)
    legend("topright", legend = paste("Current Max N (", max(n1, n2), ")", sep=""), 
           col = "red", lty = 2, lwd = 2)
    
    # Plot 3: Distribution of achieved power
    hist(gene_powers, breaks = 20, col = "lightgreen", border = "white",
         xlab = "Achieved Power",
         main = "Achieved Power per Gene\n(Effect = 2.0, Current N)")
    abline(v = 0.8, col = "darkgreen", lty = 2, lwd = 2)
    
    # Plot 4: Power vs Depth stratified by CV
    cv_groups <- cut(cv_g1, breaks = quantile(cv_g1, probs = c(0, 0.33, 0.66, 1)),
                     labels = c("Low CV", "Med CV", "High CV"), include.lowest = TRUE)
    plot(gene_depths, gene_powers, log = "x", col = as.numeric(cv_groups) + 1,
         pch = 20, xlab = "Mean Depth (log scale)", ylab = "Achieved Power",
         main = "Achieved Power vs Depth by CV Group")
    legend("bottomright", legend = levels(cv_groups), col = 2:4, pch = 20)
    
    dev.off()
    
    message("Analysis complete. Outputs written successfully.")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # low-count filtering — fraction of genes retained (heuristic on matrix artifacts).
    # Pass band 30-60% per Chen 2016 F1000 (edgeR filterByExpr convention).
    .lcf_kept_fractions <- numeric(0)
    .lcf_scanned <- character(0)
    for (.lcf_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
      .lcf_obj <- tryCatch(readRDS(.lcf_rds), error = function(e) NULL)
      .lcf_mat <- if (is.matrix(.lcf_obj) || is.data.frame(.lcf_obj)) .lcf_obj else NULL
      if (!is.null(.lcf_mat) && nrow(.lcf_mat) > 100) {
        .lcf_m <- tryCatch(as.matrix(.lcf_mat), error = function(e) NULL)
        if (!is.null(.lcf_m)) {
          .lcf_row_med <- suppressWarnings(apply(.lcf_m, 1, function(r) median(as.numeric(r), na.rm = TRUE)))
          .lcf_kept <- sum(is.finite(.lcf_row_med) & .lcf_row_med >= 1) / nrow(.lcf_m)
          .lcf_kept_fractions <- c(.lcf_kept_fractions, .lcf_kept)
          .lcf_scanned <- c(.lcf_scanned, .lcf_rds)
        }
      }
    }
    .lcf_kept <- if (length(.lcf_kept_fractions) > 0) round(median(.lcf_kept_fractions), 4) else NA_real_
    .gates_by_label[["low-count filtering"]] <- list(
      gate_row = "bioc_low_count_filtering",
      metric_name = "genes_kept_fraction",
      metric_value = .lcf_kept,
      passes = isTRUE(is.finite(.lcf_kept) && .lcf_kept >= 0.3 && .lcf_kept <= 0.6),
      status = if (is.finite(.lcf_kept)) paste0("computed (proxy: rows w/ median count >=1 across ", length(.lcf_scanned), " matrix .rds)")
               else "not_computed (no count matrix .rds artifact present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_RNASEQPOWER_RNASEQ_POWER_ANALYSIS",
      domain  = "bioconductor",
      declared_qc_steps = c("low-count filtering"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_RNASEQPOWER_RNASEQ_POWER_ANALYSIS":',
        paste0('    RNASeqPower: ', as.character(packageVersion('RNASeqPower')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rnaseq_power_analysis.csv versions.yml
    """
}

workflow BIOC_RNASEQPOWER_RNASEQ_POWER_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_RNASEQPOWER_RNASEQ_POWER_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_RNASEQPOWER_RNASEQ_POWER_ANALYSIS.out.tables
    plots    = BIOC_RNASEQPOWER_RNASEQ_POWER_ANALYSIS.out.plots
    objects  = BIOC_RNASEQPOWER_RNASEQ_POWER_ANALYSIS.out.objects
    versions = BIOC_RNASEQPOWER_RNASEQ_POWER_ANALYSIS.out.versions
}
