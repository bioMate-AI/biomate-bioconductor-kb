#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mirTarRnaSeq — mirna_mrna_correlation_multi_timepoint
// Identify significant miRNA-mRNA correlations across three or more time points using fold change data and background distribution comparisons.
// Input: mRNA_timepoints.txt.gz, miRNA_timepoints.txt.gz
// Container: quay.io/biocontainers/bioconductor-mirtarrnaseq:1.18.0--r45hdfd78af_0
// R packages: dplyr, ggplot2, mirTarRnaSeq, reshape2, tidyr, viridis
// Bioconductor: 3.20 | R: 4.4
// Requires: dplyr, ggplot2, mirTarRnaSeq, reshape2, tidyr, viridis
// Visualizations: density plot, heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load time-point specific differential expression files for mRNA and miRNA
//  * 2. [Input & Preparation] Parse fold changes and filter mRNAs by p-value threshold using one2OneRnaMiRNA
//  * 3. [Core Analysis] Calculate Pearson correlation between mRNA and miRNA fold changes using corMirnaRna
//  * 4. [Core Analysis] Generate a background correlation distribution using sampCorRnaMirna
//  * 5. [Visualization & Output] Plot correlation density using mirRnaDensityCor
//  * 6. [Core Analysis] Identify significant correlations below a threshold using threshSig
//  * 7. [Core Analysis] Retrieve species-specific miRanda target predictions using getInputSpecies
//  * 8. [Core Analysis] Intersect significant correlations with miRanda predictions using corMirnaRnaMiranda or miRandaIntersect
//  * 9. [Visualization & Output] Visualize results with a heatmap using mirRnaHeatmap

nextflow.enable.dsl = 2

process BIOC_MIRTARRNASEQ_MIRNA_MRNA_CORRELATION_MULTI_TIMEPOINT {
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
    .bm_deps <- c("dplyr", "ggplot2", "mirTarRnaSeq", "reshape2", "tidyr", "viridis")
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
    library(mirTarRnaSeq)
    library(ggplot2)
    library(dplyr)
    library(reshape2)
    library(tidyr)
    library(viridis)
    
    # ==========================================
    # 1. Load and Parse User Input Files
    # ==========================================
    
    # Verify input files exist in the working directory
    if (!file.exists("mRNA_timepoints.txt.gz")) {
      stop("Error: 'mRNA_timepoints.txt.gz' not found in the working directory.")
    }
    if (!file.exists("miRNA_timepoints.txt.gz")) {
      stop("Error: 'miRNA_timepoints.txt.gz' not found in the working directory.")
    }
    
    # Read mRNA timepoints file
    mrna_raw <- read.table("mRNA_timepoints.txt.gz", header = TRUE, sep = "\t", as.is = TRUE)
    if (!is.character(mrna_raw[[1]])) {
      mrna_raw <- cbind(Gene = rownames(mrna_raw), mrna_raw)
    }
    
    # Split mRNA wide table into a list of data frames (one per timepoint)
    # Expected format per timepoint: Column 1 = Gene, Column 2 = FC, Column 3 = Pval
    mrna_files <- list()
    num_cols_mrna <- ncol(mrna_raw)
    i <- 2
    tp_idx <- 1
    while (i < num_cols_mrna) {
      fc_col <- i
      pval_col <- i + 1
      tp_name <- paste0("T", tp_idx)
      
      # Try to extract timepoint name from column header
      col_name <- colnames(mrna_raw)[fc_col]
      clean_name <- gsub("_FC|_foldchange|FC_|_foldchange_", "", col_name, ignore.case = TRUE)
      if (clean_name != "" && !clean_name %in% colnames(mrna_raw)[1]) {
        tp_name <- clean_name
      }
      
      mrna_files[[tp_name]] <- data.frame(
        Gene = mrna_raw[[1]],
        FC = mrna_raw[[fc_col]],
        Pval = mrna_raw[[pval_col]],
        stringsAsFactors = FALSE
      )
      i <- i + 2
      tp_idx <- tp_idx + 1
    }
    
    # Read miRNA timepoints file
    mirna_raw <- read.table("miRNA_timepoints.txt.gz", header = TRUE, sep = "\t", as.is = TRUE)
    if (!is.character(mirna_raw[[1]])) {
      mirna_raw <- cbind(miRNA = rownames(mirna_raw), mirna_raw)
    }
    
    # Split miRNA wide table into a list of data frames (one per timepoint)
    # Expected format per timepoint: Column 1 = miRNA, Column 2 = FC
    mirna_files <- list()
    num_cols_mirna <- ncol(mirna_raw)
    for (j in 2:num_cols_mirna) {
      tp_name <- paste0("T", j - 1)
      col_name <- colnames(mirna_raw)[j]
      clean_name <- gsub("_FC|_foldchange|FC_|_foldchange_", "", col_name, ignore.case = TRUE)
      if (clean_name != "" && !clean_name %in% colnames(mirna_raw)[1]) {
        tp_name <- clean_name
      }
      
      mirna_files[[tp_name]] <- data.frame(
        miRNA = mirna_raw[[1]],
        FC = mirna_raw[[j]],
        stringsAsFactors = FALSE
      )
    }
    
    # ==========================================
    # 2. Parse Fold Changes and Filter mRNAs
    # ==========================================
    mrna <- one2OneRnaMiRNA(mrna_files, pthreshold = 0.05)\$foldchanges
    mirna <- one2OneRnaMiRNA(mirna_files)\$foldchanges
    
    # ==========================================
    # 3. Calculate Pearson Correlation
    # ==========================================
    corr_0 <- corMirnaRna(mrna, mirna, method = "pearson")
    
    # ==========================================
    # 4. Generate Background Correlation Distribution
    # ==========================================
    outs <- sampCorRnaMirna(mrna, mirna, method = "pearson",
                            Shrounds = 100, Srounds = 1000)
    
    # ==========================================
    # 5. Plot Correlation Density
    # ==========================================
    pdf("correlation_density_plot.pdf", width = 6, height = 6)
    mirRnaDensityCor(corr_0, outs)
    dev.off()
    
    # ==========================================
    # 6. Identify Significant Correlations
    # ==========================================
    sig_corrs <- threshSig(corr_0, outs, pvalue = 0.05)
    write.csv(sig_corrs, "significant_correlations.csv", row.names = TRUE)
    
    # ==========================================
    # 7. Retrieve Species-Specific miRanda Predictions
    # ==========================================
    miRanda <- getInputSpecies("Mouse", threshold = 150)
    
    # ==========================================
    # 8. Intersect and Visualize Results
    # ==========================================
    # Extract target correlations based on miRanda and correlation threshold
    newcorr <- corMirnaRnaMiranda(mrna, mirna, -0.7, miRanda)
    
    pdf("heatmap_newcorr.pdf", width = 8, height = 8)
    mirRnaHeatmap(newcorr, upper_bound = -0.6)
    dev.off()
    
    # Intersect significant correlations with miRanda predictions
    results <- miRandaIntersect(sig_corrs, outs, mrna, mirna, miRanda)
    saveRDS(results, "miranda_intersect_results.rds")
    
    if (!is.null(results\$corr)) {
      write.csv(results\$corr, "intersected_correlations.csv", row.names = TRUE)
      
      # Draw final correlation heatmap
      pdf("heatmap_results.pdf", width = 8, height = 8)
      p <- mirRnaHeatmap(results\$corr, upper_bound = -0.99)
      if (!is.null(p)) {
        print(p)
      }
      dev.off()
    }
    
    message("Pipeline completed successfully. Outputs saved to the working directory.")
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

    # count normalization — scan .rds matrix artifacts for library-size CV
    # ratio (post-norm / pre-norm); without raw input we report median lib CV
    # as a proxy diagnostic. Threshold = 0.7 (Bullard 2010 BMC Bioinf).
    .cn_lib_cvs <- numeric(0)
    .cn_scanned <- character(0)
    for (.cn_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
      .cn_obj <- tryCatch(readRDS(.cn_rds), error = function(e) NULL)
      .cn_mat <- if (is.matrix(.cn_obj) || is.data.frame(.cn_obj)) .cn_obj else NULL
      if (!is.null(.cn_mat) && ncol(.cn_mat) >= 2 && nrow(.cn_mat) >= 2) {
        .cn_lib <- tryCatch(colSums(as.matrix(.cn_mat), na.rm = TRUE), error = function(e) NULL)
        if (!is.null(.cn_lib) && all(is.finite(.cn_lib)) && mean(.cn_lib) > 0) {
          .cn_lib_cvs <- c(.cn_lib_cvs, sd(.cn_lib) / mean(.cn_lib))
          .cn_scanned <- c(.cn_scanned, .cn_rds)
        }
      }
    }
    .cn_med_cv <- if (length(.cn_lib_cvs) > 0) round(median(.cn_lib_cvs), 4) else NA_real_
    .gates_by_label[["count normalization"]] <- list(
      gate_row = "bioc_count_normalization",
      metric_name = "lib_size_cv_median",
      metric_value = .cn_med_cv,
      passes = isTRUE(is.finite(.cn_med_cv) && .cn_med_cv <= 0.3),
      status = if (is.finite(.cn_med_cv)) paste0("computed (proxy: median lib-size CV across ", length(.cn_scanned), " matrix .rds; raw-vs-norm ratio not measurable without paired input)")
               else "not_computed (no count matrix .rds artifact present)"
    )

    # dispersion/size-factor estimation — object-type-aware. Try DESeq2
    # DESeqDataSet (mcols\$dispOutlier), then edgeR DGEList (common.dispersion).
    .dsf_value <- NA_real_; .dsf_kind <- "none"
    for (.dsf_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
      .dsf_obj <- tryCatch(readRDS(.dsf_rds), error = function(e) NULL)
      if (!is.null(.dsf_obj)) {
        if (inherits(.dsf_obj, "DESeqDataSet")) {
          .dsf_o <- tryCatch(mcols(.dsf_obj)\$dispOutlier, error = function(e) NULL)
          if (!is.null(.dsf_o)) { .dsf_value <- round(mean(.dsf_o, na.rm = TRUE), 4); .dsf_kind <- "deseq2"; break }
        } else if (inherits(.dsf_obj, "DGEList")) {
          .dsf_v <- tryCatch(.dsf_obj\$common.dispersion, error = function(e) NULL)
          if (!is.null(.dsf_v) && is.finite(.dsf_v)) { .dsf_value <- round(sqrt(.dsf_v), 4); .dsf_kind <- "edger_bcv"; break }
        }
      }
    }
    .gates_by_label[["dispersion/size-factor estimation"]] <- list(
      gate_row = "bioc_dispersion_size_factor",
      metric_name = if (.dsf_kind == "edger_bcv") "common_bcv" else "disp_outlier_fraction",
      metric_value = .dsf_value,
      passes = isTRUE(
        (.dsf_kind == "deseq2" && is.finite(.dsf_value) && .dsf_value <= 0.01) ||
        (.dsf_kind == "edger_bcv" && is.finite(.dsf_value) && .dsf_value > 0 && .dsf_value < 1.0)
      ),
      status = if (is.finite(.dsf_value)) paste0("computed (", .dsf_kind, ")")
               else "not_computed (no DESeqDataSet/DGEList .rds artifact present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_MIRTARRNASEQ_MIRNA_MRNA_CORRELATION_MULTI_TIMEPOINT",
      domain  = "bioconductor",
      declared_qc_steps = c("low-count filtering", "count normalization", "dispersion/size-factor estimation"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_MIRTARRNASEQ_MIRNA_MRNA_CORRELATION_MULTI_TIMEPOINT":',
        paste0('    mirTarRnaSeq: ', as.character(packageVersion('mirTarRnaSeq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mirna_mrna_correlation_multi_timepoint.csv versions.yml
    """
}

workflow BIOC_MIRTARRNASEQ_MIRNA_MRNA_CORRELATION_MULTI_TIMEPOINT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ mRNA_timepoints.txt.gz, miRNA_timepoints.txt.gz ] ]

    main:
    BIOC_MIRTARRNASEQ_MIRNA_MRNA_CORRELATION_MULTI_TIMEPOINT(ch_input)

    emit:
    tables   = BIOC_MIRTARRNASEQ_MIRNA_MRNA_CORRELATION_MULTI_TIMEPOINT.out.tables
    plots    = BIOC_MIRTARRNASEQ_MIRNA_MRNA_CORRELATION_MULTI_TIMEPOINT.out.plots
    objects  = BIOC_MIRTARRNASEQ_MIRNA_MRNA_CORRELATION_MULTI_TIMEPOINT.out.objects
    versions = BIOC_MIRTARRNASEQ_MIRNA_MRNA_CORRELATION_MULTI_TIMEPOINT.out.versions
}
