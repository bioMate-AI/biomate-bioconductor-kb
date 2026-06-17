#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: metaSeq — non_noiseq_meta_analysis
// Perform meta-analysis using one-sided p-values generated from non-NOISeq methods (e.g., DESeq, edgeR, Cuffdiff).
// Input: upper, lower, weight
// Container: quay.io/biocontainers/bioconductor-metaseq:1.50.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: metaSeq
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Format the custom p-value matrices and weights using other.oneside.pvalues
//  * 2. [Core Analysis] Combine the p-values using Fisher.test and Stouffer.test

nextflow.enable.dsl = 2

process BIOC_METASEQ_NON_NOISEQ_META_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("metaSeq")
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
    library(metaSeq)
    
    # Helper function to read matrix input robustly
    read_input_matrix <- function(filepath) {
      if (!file.exists(filepath)) {
        exts <- c(".csv", ".tsv", ".txt")
        found <- FALSE
        for (ext in exts) {
          if (file.exists(paste0(filepath, ext))) {
            filepath <- paste0(filepath, ext)
            found <- TRUE
            break
          }
        }
        if (!found) {
          stop(paste("Error: Input matrix file not found for prefix:", filepath))
        }
      }
      
      # Attempt reading as CSV first, then TSV
      mat <- tryCatch({
        as.matrix(read.csv(filepath, row.names = 1, check.names = FALSE))
      }, error = function(e) {
        tryCatch({
          as.matrix(read.table(filepath, header = TRUE, row.names = 1, sep = "\t", check.names = FALSE))
        }, error = function(e2) {
          as.matrix(read.table(filepath, header = TRUE, row.names = 1, check.names = FALSE))
        })
      })
      return(mat)
    }
    
    # Helper function to read vector input robustly
    read_input_vector <- function(filepath) {
      if (!file.exists(filepath)) {
        exts <- c(".csv", ".tsv", ".txt")
        found <- FALSE
        for (ext in exts) {
          if (file.exists(paste0(filepath, ext))) {
            filepath <- paste0(filepath, ext)
            found <- TRUE
            break
          }
        }
        if (!found) {
          stop(paste("Error: Input vector file not found for prefix:", filepath))
        }
      }
      
      # Attempt reading as simple scan, then CSV row
      vec <- tryCatch({
        as.numeric(scan(filepath, quiet = TRUE))
      }, error = function(e) {
        tryCatch({
          as.numeric(read.csv(filepath, header = FALSE)[1, ])
        }, error = function(e2) {
          stop(paste("Error reading vector from file:", filepath))
        })
      })
      return(vec)
    }
    
    # 1. Read User Inputs
    upper <- read_input_matrix("upper")
    lower <- read_input_matrix("lower")
    weight <- read_input_vector("weight")
    
    # 2. Format the custom p-value matrices and weights
    result <- other.oneside.pvalues(upper, lower, weight)
    
    # 3. Combine the p-values using Fisher's method
    F <- Fisher.test(result)
    str(F)
    head(F\$Upper)
    head(F\$Lower)
    F\$Weight
    
    # 4. Combine the p-values using Stouffer's method
    S <- Stouffer.test(result)
    str(S)
    head(S\$Upper)
    head(S\$Lower)
    S\$Weight
    
    # 5. Write meaningful output files
    # Save Fisher's test results
    fisher_df <- data.frame(
      Gene = names(F\$Upper),
      Fisher_Upper = F\$Upper,
      Fisher_Lower = F\$Lower,
      stringsAsFactors = FALSE
    )
    write.csv(fisher_df, file = "fisher_test_results.csv", row.names = FALSE)
    
    # Save Stouffer's test results
    stouffer_df <- data.frame(
      Gene = names(S\$Upper),
      Stouffer_Upper = S\$Upper,
      Stouffer_Lower = S\$Lower,
      stringsAsFactors = FALSE
    )
    write.csv(stouffer_df, file = "stouffer_test_results.csv", row.names = FALSE)
    
    # Save RDS objects for downstream analysis
    saveRDS(F, file = "fisher_test_object.rds")
    saveRDS(S, file = "stouffer_test_object.rds")
    
    # Optional: Generate a comparison plot of Fisher vs Stouffer p-values
    tryCatch({
      pdf("pvalue_comparison_plots.pdf", width = 10, height = 5)
      par(mfrow = c(1, 2))
      plot(F\$Upper, S\$Upper, 
           xlab = "Fisher's Method (Upper)", 
           ylab = "Stouffer's Method (Upper)", 
           main = "Upper-regulated P-values",
           col = "blue", pch = 20)
      abline(0, 1, col = "red", lty = 2)
      
      plot(F\$Lower, S\$Lower, 
           xlab = "Fisher's Method (Lower)", 
           ylab = "Stouffer's Method (Lower)", 
           main = "Lower-regulated P-values",
           col = "darkgreen", pch = 20)
      abline(0, 1, col = "red", lty = 2)
      dev.off()
    }, error = function(e) {
      warning("Could not generate comparison plots: ", e\$message)
    })
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # low-count filtering — fraction of genes retained (heuristic on matrix artifacts).
    # Pass band 30-60% per Chen 2016 F1000 (edgeR filterByExpr convention).
    .lcf_kept_fractions <- numeric(0)
    .lcf_scanned <- character(0)
    for (.lcf_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
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
    for (.cn_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
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
    for (.dsf_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
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
      process = "BIOC_METASEQ_NON_NOISEQ_META_ANALYSIS",
      domain  = "bioconductor",
      declared_qc_steps = c("low-count filtering", "count normalization", "dispersion/size-factor estimation"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_METASEQ_NON_NOISEQ_META_ANALYSIS":',
        paste0('    metaSeq: ', as.character(packageVersion('metaSeq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_non_noiseq_meta_analysis.csv versions.yml
    """
}

workflow BIOC_METASEQ_NON_NOISEQ_META_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ upper, lower, weight ] ]

    main:
    BIOC_METASEQ_NON_NOISEQ_META_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_METASEQ_NON_NOISEQ_META_ANALYSIS.out.tables
    plots    = BIOC_METASEQ_NON_NOISEQ_META_ANALYSIS.out.plots
    objects  = BIOC_METASEQ_NON_NOISEQ_META_ANALYSIS.out.objects
    versions = BIOC_METASEQ_NON_NOISEQ_META_ANALYSIS.out.versions
}
