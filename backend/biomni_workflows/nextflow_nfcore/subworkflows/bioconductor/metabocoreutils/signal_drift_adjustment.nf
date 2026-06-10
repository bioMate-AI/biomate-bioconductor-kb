#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MetaboCoreUtils — signal_drift_adjustment
// Model and adjust for injection-order-dependent signal drift in LC-MS feature abundances using linear models fitted on QC samples.
// Input: feature_values.txt
// Container: quay.io/biocontainers/bioconductor-metabocoreutils:1.18.1--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MetaboCoreUtils
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load abundance matrix and define injection index and QC sample indices
//  * 2. [Core Analysis] Fit row-wise linear models on log2-transformed QC abundances using fit_lm
//  * 3. [Core Analysis] Filter out unstable models (e.g., p-value > 0.05)
//  * 4. [Core Analysis] Adjust all sample abundances using adjust_lm and convert back to natural scale

nextflow.enable.dsl = 2

process BIOC_METABOCOREUTILS_SIGNAL_DRIFT_ADJUSTMENT {
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
                
                # Load required library
                library(MetaboCoreUtils)
                
                # 1. Load abundance matrix and define injection index and QC sample indices
                if (!file.exists("feature_values.txt")) {
                  stop("Error: 'feature_values.txt' not found in the working directory.")
                }
                
                vals <- read.table("feature_values.txt", sep = "\t", header = TRUE, row.names = 1)
                vals <- as.matrix(vals)
                
                # Define a data frame with the injection index
                sdata <- data.frame(injection_index = seq_len(ncol(vals)))
                
                # Identify columns representing QC samples
                # Allow user to specify a regex pattern for QC samples via command-line arguments
                args <- commandArgs(trailingOnly = TRUE)
                qc_pattern <- if (length(args) > 0) args[1] else "^POOL"
                qc_index <- grep(qc_pattern, colnames(vals), ignore.case = TRUE)
                
                if (length(qc_index) == 0) {
                  # Fallback to common QC naming if the default/provided pattern yields no matches
                  qc_index <- grep("QC|POOL", colnames(vals), ignore.case = TRUE)
                }
                
                if (length(qc_index) == 0) {
                  stop("Error: No QC samples found. Please ensure QC columns are named appropriately or provide a regex pattern as an argument.")
                }
                
                # 2. Fit row-wise linear models on log2-transformed QC abundances using fit_lm
                qc_lm <- fit_lm(y ~ injection_index,
                                data = sdata[qc_index, , drop = FALSE],
                                y = log2(vals[, qc_index]))
                
                # 3. Filter out unstable models (e.g., p-value > 0.05)
                qc_lm_summary <- lapply(qc_lm, function(z) {
                    if (length(z) > 1) {
                        s <- summary(z)
                        c(slope = coefficients(s)[2, "Estimate"],
                          p.value = coefficients(s)[2, 4],
                          adj.r.squared = s\$adj.r.squared)
                    } else c(slope = NA_real_, p.value = NA_real_,
                             adj.r.squared = NA_real_) # returning NA for skipped models
                }) |> do.call(what = rbind)
                
                # Save the summary table of the fitted models
                write.csv(qc_lm_summary, file = "qc_lm_summary.csv", row.names = TRUE)
                
                # Filter out models with p-value > 0.05 (using which() to safely ignore NAs)
                qc_lm[which(qc_lm_summary[, "p.value"] > 0.05)] <- NA
                
                # 4. Adjust all sample abundances using adjust_lm and convert back to natural scale
                vals_adj <- adjust_lm(log2(vals), data = sdata, lm = qc_lm)
                vals_adj <- 2^vals_adj
                
                # Save the adjusted feature values
                write.table(vals_adj, file = "adjusted_feature_values.txt", sep = "\t", col.names = NA)
                
                # Save R objects for downstream analysis
                saveRDS(qc_lm, file = "qc_lm_models.rds")
                saveRDS(vals_adj, file = "vals_adjusted.rds")
                
                # 5. Generate diagnostic plots and save to PDF
                pdf("signal_drift_diagnostics.pdf", width = 8, height = 8)
                
                # Plot 1: Raw abundance of feature 2 along injection index with fitted model
                if (nrow(vals) >= 2 && length(qc_lm[[2]]) > 1) {
                  plot(x = sdata\$injection_index, y = log2(vals[2, ]),
                       xlab = "injection_index", ylab = expression(log[2]~abundance),
                       main = "Feature 2: Raw Abundance & Fitted Model")
                  points(x = sdata\$injection_index[qc_index],
                         y = log2(vals[2, qc_index]), pch = 16, col = "#00000080")
                  grid()
                  abline(qc_lm[[2]])
                }
                
                # Plot 2: Feature abundances before and after adjustment for feature 2
                if (nrow(vals) >= 2 && length(qc_lm[[2]]) > 1) {
                  plot(x = sdata\$injection_index, y = log2(vals[2, ]),
                       xlab = "injection_index", ylab = expression(log[2]~abundance),
                       col = "#00000080", main = "Feature 2: Before (open) and After (filled) Adjustment")
                  points(x = sdata\$injection_index, y = log2(vals_adj[2, ]),
                         pch = 16, col = "#00000080")
                  grid()
                  abline(qc_lm[[2]], col = "grey", lty = 2)
                
                  # Fit a model to the QC samples of the adjusted data
                  l <- lm(log2(vals_adj[2, qc_index]) ~ sdata\$injection_index[qc_index])
                  abline(l, col = "grey")
                }
                
                # Plot 3: Global correlation evaluation before and after adjustment
                fts_adj <- which(!is.na(qc_lm))
                cor_fun <- function(i, y) {
                    values <- y[i, qc_index]
                    if (sum(!is.na(values)) >= max(3, length(qc_index) * 0.75))
                        cor(values, sdata\$injection_index[qc_index],
                            method = "spearman", use = "pairwise.complete.obs")
                    else NA_real_
                }
                cor_raw <- vapply(seq_along(qc_lm), cor_fun, numeric(1), y = vals)
                cor_adj <- vapply(seq_along(qc_lm), cor_fun, numeric(1), y = vals_adj)
                
                plot(sort(cor_raw), col = "#00000080", main = "QC samples: Correlation with Injection Index",
                     ylab = "rho", xlab = "rank")
                idx <- order(cor_adj)
                bg <- rep(NA, length(cor_adj))
                bg[fts_adj] <- "#ff000040"
                points(cor_adj[idx], pch = 21, col = "#ff000080", bg = bg[idx])
                legend("topleft", legend = c("Raw", "Adjusted"), col = c("black", "red"), pch = c(1, 21))
                
                dev.off()

    writeLines(c(
        '"BIOC_METABOCOREUTILS_SIGNAL_DRIFT_ADJUSTMENT":',
        paste0('    MetaboCoreUtils: ', as.character(packageVersion('MetaboCoreUtils')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_signal_drift_adjustment.csv versions.yml
    """
}

workflow BIOC_METABOCOREUTILS_SIGNAL_DRIFT_ADJUSTMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ feature_values.txt ] ]

    main:
    BIOC_METABOCOREUTILS_SIGNAL_DRIFT_ADJUSTMENT(ch_input)

    emit:
    tables   = BIOC_METABOCOREUTILS_SIGNAL_DRIFT_ADJUSTMENT.out.tables
    plots    = BIOC_METABOCOREUTILS_SIGNAL_DRIFT_ADJUSTMENT.out.plots
    objects  = BIOC_METABOCOREUTILS_SIGNAL_DRIFT_ADJUSTMENT.out.objects
    versions = BIOC_METABOCOREUTILS_SIGNAL_DRIFT_ADJUSTMENT.out.versions
}
