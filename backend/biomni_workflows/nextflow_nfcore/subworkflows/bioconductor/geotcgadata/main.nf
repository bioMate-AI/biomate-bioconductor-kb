#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GeoTcgaData — rna_seq_differential_analysis
// Perform differential expression analysis on RNA-seq count data using a Wilcoxon test or other methods.
// Input: df, group
// Container: quay.io/biocontainers/bioconductor-geotcgadata:2.10.0--r45hdfd78af_0
// R packages: S4Vectors, SummarizedExperiment, ChAMP, GeoTcgaData
// Bioconductor: 3.20 | R: 4.4
// Requires: GeoTcgaData, S4Vectors, SummarizedExperiment
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Prepare the count matrix and group vector (or construct a SummarizedExperiment object)
//  * 2. [Core Analysis] Run differential_RNA to identify differentially expressed genes

nextflow.enable.dsl = 2

process BIOC_GEOTCGADATA_RNA_SEQ_DIFFERENTIAL_ANALYSIS {
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
    .bm_deps <- c("S4Vectors", "SummarizedExperiment", "ChAMP", "GeoTcgaData")
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
    library(GeoTcgaData)
    library(SummarizedExperiment)
    library(S4Vectors)
    
    # 1. Prepare the count matrix and group vector
    # Read df (matrix or data frame of raw RNA-seq counts) from the working directory
    if (file.exists("df.csv")) {
      df <- read.csv("df.csv", row.names = 1, check.names = FALSE)
    } else if (file.exists("df.tsv")) {
      df <- read.delim("df.tsv", row.names = 1, check.names = FALSE)
    } else if (file.exists("df.rds")) {
      df <- readRDS("df.rds")
    } else {
      stop("Error: Could not find 'df.csv', 'df.tsv', or 'df.rds' in the working directory.")
    }
    
    # Read group (vector of sample group assignments) from the working directory
    if (file.exists("group.csv")) {
      group_data <- read.csv("group.csv", header = FALSE)
      group <- as.character(group_data[[1]])
    } else if (file.exists("group.txt")) {
      group <- readLines("group.txt")
    } else if (file.exists("group.rds")) {
      group <- readRDS("group.rds")
    } else {
      stop("Error: Could not find 'group.csv', 'group.txt', or 'group.rds' in the working directory.")
    }
    
    # Ensure df is a data frame
    df <- as.data.frame(df)
    
    # Validate dimensions
    if (ncol(df) != length(group)) {
      stop(sprintf("Dimension mismatch: df has %d columns, but group has %d elements.", ncol(df), length(group)))
    }
    
    # 2. Run differential_RNA to identify differentially expressed genes (Method 1: using data frame)
    result_df <- differential_RNA(counts = df, group = group, filte = FALSE, method = "Wilcoxon")
    
    # Save results from Method 1
    write.csv(result_df, "differential_RNA_results_df.csv", row.names = TRUE)
    
    # 3. Run differential_RNA to identify differentially expressed genes (Method 2: using SummarizedExperiment)
    colData <- S4Vectors::DataFrame(row.names = colnames(df), group = group)
    data <- SummarizedExperiment::SummarizedExperiment(
      assays = S4Vectors::SimpleList(counts = as.matrix(df)),
      colData = colData
    )
    
    result_se <- differential_RNA(counts = data, groupCol = "group", filte = FALSE, method = "Wilcoxon")
    
    # Save results from Method 2
    write.csv(result_se, "differential_RNA_results_se.csv", row.names = TRUE)
    saveRDS(result_se, "differential_RNA_results_se.rds")
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
      process = "BIOC_GEOTCGADATA_RNA_SEQ_DIFFERENTIAL_ANALYSIS",
      domain  = "bioconductor",
      declared_qc_steps = c("low-count filtering", "count normalization", "dispersion/size-factor estimation"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_GEOTCGADATA_RNA_SEQ_DIFFERENTIAL_ANALYSIS":',
        paste0('    GeoTcgaData: ', as.character(packageVersion('GeoTcgaData')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rna_seq_differential_analysis.csv versions.yml
    """
}

workflow BIOC_GEOTCGADATA_RNA_SEQ_DIFFERENTIAL_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ df, group ] ]

    main:
    BIOC_GEOTCGADATA_RNA_SEQ_DIFFERENTIAL_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_GEOTCGADATA_RNA_SEQ_DIFFERENTIAL_ANALYSIS.out.tables
    plots    = BIOC_GEOTCGADATA_RNA_SEQ_DIFFERENTIAL_ANALYSIS.out.plots
    objects  = BIOC_GEOTCGADATA_RNA_SEQ_DIFFERENTIAL_ANALYSIS.out.objects
    versions = BIOC_GEOTCGADATA_RNA_SEQ_DIFFERENTIAL_ANALYSIS.out.versions
}
