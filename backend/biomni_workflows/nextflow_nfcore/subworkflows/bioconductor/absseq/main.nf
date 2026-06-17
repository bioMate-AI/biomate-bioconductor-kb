#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ABSSeq — pairwise_de_analysis
// Perform pairwise differential expression analysis on RNA-Seq count data with replicates using either the standard ABSSeq model or the alternative aFold method.
// Input: counts.tsv, groups.csv
// Container: quay.io/biocontainers/bioconductor-absseq:1.64.0--r45hdfd78af_0
// R packages: ABSSeq
// Bioconductor: 3.20 | R: 4.4
// Requires: ABSSeq
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Construct the ABSDataSet object with counts and group factors
//  * 2. [Core Analysis] Run the differential expression analysis pipeline using the ABSSeq wrapper function (optionally enabling aFold)
//  * 3. [Core Analysis] Extract and view the results including fold-changes, p-values, and adjusted p-values

nextflow.enable.dsl = 2

process BIOC_ABSSEQ_PAIRWISE_DE_ANALYSIS {
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
    .bm_deps <- c("ABSSeq")
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
    
    # Load required library
    library(ABSSeq)
    
    # Check for required input files
    if (!file.exists("counts.tsv")) {
      stop("Error: 'counts.tsv' not found in the working directory.")
    }
    if (!file.exists("groups.csv")) {
      stop("Error: 'groups.csv' not found in the working directory.")
    }
    
    # Read raw integer counts
    counts <- as.matrix(read.delim("counts.tsv", row.names = 1, check.names = FALSE))
    storage.mode(counts) <- "integer"
    
    # Read group assignments
    groups_df <- read.csv("groups.csv", stringsAsFactors = FALSE)
    
    # Determine the group column and align with counts matrix columns if possible
    group_col <- if ("group" %in% colnames(groups_df)) {
      "group"
    } else if ("groups" %in% colnames(groups_df)) {
      "groups"
    } else {
      colnames(groups_df)[2]
    }
    
    sample_col <- colnames(groups_df)[1]
    if (all(colnames(counts) %in% groups_df[[sample_col]])) {
      rownames(groups_df) <- groups_df[[sample_col]]
      groups_vector <- groups_df[colnames(counts), group_col]
    } else {
      groups_vector <- groups_df[[group_col]]
    }
    
    # --- Workflow Stage 1: Standard ABSSeq Model ---
    
    # Construct the ABSDataSet object
    obj <- ABSDataSet(counts, factor(groups_vector))
    
    # Run the differential expression analysis pipeline
    obj <- ABSSeq(obj)
    
    # Extract and view the results
    res <- results(obj, c("Amean", "Bmean", "foldChange", "pvalue", "adj.pvalue"))
    head(res)
    
    # Write results to output files
    write.csv(res, "absseq_results_standard.csv", row.names = TRUE)
    
    # Generate diagnostic plot
    pdf("difftobase_plot_standard.pdf")
    tryCatch({
      plotDifftoBase(obj)
    }, error = function(e) {
      warning("Could not generate plotDifftoBase for standard model: ", e\$message)
    })
    dev.off()
    
    
    # --- Workflow Stage 2: Alternative aFold Method ---
    
    # Construct the ABSDataSet object using named arguments
    obj <- ABSDataSet(counts=counts, groups=factor(groups_vector))
    
    # Run the differential expression analysis pipeline with aFold enabled
    obj <- ABSSeq(obj, useaFold=TRUE)
    
    # Extract and view the results
    res <- results(obj, c("Amean", "Bmean", "foldChange", "pvalue", "adj.pvalue"))
    head(res)
    
    # Write results to output files
    write.csv(res, "absseq_results_afold.csv", row.names = TRUE)
    saveRDS(obj, "absseq_object_afold.rds")
    
    # Generate diagnostic plot
    pdf("difftobase_plot_afold.pdf")
    tryCatch({
      plotDifftoBase(obj)
    }, error = function(e) {
      warning("Could not generate plotDifftoBase for aFold model: ", e\$message)
    })
    dev.off()
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
      process = "BIOC_ABSSEQ_PAIRWISE_DE_ANALYSIS",
      domain  = "bioconductor",
      declared_qc_steps = c("low-count filtering", "count normalization", "dispersion/size-factor estimation"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_ABSSEQ_PAIRWISE_DE_ANALYSIS":',
        paste0('    ABSSeq: ', as.character(packageVersion('ABSSeq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pairwise_de_analysis.csv versions.yml
    """
}

workflow BIOC_ABSSEQ_PAIRWISE_DE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ counts.tsv, groups.csv ] ]

    main:
    BIOC_ABSSEQ_PAIRWISE_DE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_ABSSEQ_PAIRWISE_DE_ANALYSIS.out.tables
    plots    = BIOC_ABSSEQ_PAIRWISE_DE_ANALYSIS.out.plots
    objects  = BIOC_ABSSEQ_PAIRWISE_DE_ANALYSIS.out.objects
    versions = BIOC_ABSSEQ_PAIRWISE_DE_ANALYSIS.out.versions
}
