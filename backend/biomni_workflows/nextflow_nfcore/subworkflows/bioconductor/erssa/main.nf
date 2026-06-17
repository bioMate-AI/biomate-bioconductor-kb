#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ERSSA — erssa_sample_size_analysis
// Perform empirical RNA-seq sample size analysis by subsampling and running differential expression to determine replicate sufficiency.
// Input: count_table, condition_table
// Container: quay.io/biocontainers/bioconductor-erssa:1.28.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ERSSA, ggplot2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the ERSSA package and prepare count and condition tables
//  * 2. [Core Analysis] Set a random seed for reproducible subsampling
//  * 3. [Core Analysis] Run the main erssa function to filter counts, generate subsamples, perform DE analysis, and identify DEGs
//  * 4. [Visualization & Output] Customize and save the resulting diagnostic plots (e.g., dot plot, marginal plot, intersect plot, TPR/FPR plot)

nextflow.enable.dsl = 2

process BIOC_ERSSA_ERSSA_SAMPLE_SIZE_ANALYSIS {
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
    .bm_deps <- c("ERSSA", "ggplot2")
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
        library(ERSSA)
        library(ggplot2)
        
        # ==========================================
        # 1. Load and Prepare Count and Condition Tables
        # ==========================================
        
        # Load count table from the working directory
        if (file.exists("count_table.rds")) {
          count_table = readRDS("count_table.rds")
        } else if (file.exists("count_table.csv")) {
          count_table = read.csv("count_table.csv", row.names = 1, check.names = FALSE)
        } else if (file.exists("count_table.tsv")) {
          count_table = read.delim("count_table.tsv", row.names = 1, check.names = FALSE)
        } else {
          stop("Error: count_table file (RDS, CSV, or TSV) not found in the working directory!")
        }
        
        # Load condition table from the working directory
        if (file.exists("condition_table.rds")) {
          condition_table = readRDS("condition_table.rds")
        } else if (file.exists("condition_table.csv")) {
          condition_table = read.csv("condition_table.csv", check.names = FALSE)
        } else if (file.exists("condition_table.tsv")) {
          condition_table = read.delim("condition_table.tsv", check.names = FALSE)
        } else {
          stop("Error: condition_table file (RDS, CSV, or TSV) not found in the working directory!")
        }
        
        # Ensure standard column names for the condition table
        colnames(condition_table) = c("name", "condition")
        
        # Identify the control condition to use in the ERSSA function call
        unique_conds = unique(condition_table\$condition)
        if (length(unique_conds) >= 1) {
          ctrl_val = unique_conds[1]
        }
        
        # Display preview of the loaded data
        cat("--- Count Table Preview ---\n")
        print(head(count_table[, 1:min(2, ncol(count_table)), drop = FALSE]))
        cat("\n--- Condition Table Preview ---\n")
        print(condition_table)
        cat("\n")
        
        # ==========================================
        # 2. Set Random Seed for Reproducibility
        # ==========================================
        set.seed(1) # for reproducible subsample generation
        
        # ==========================================
        # 3. Run ERSSA Sample Size Analysis
        # ==========================================
        ssa = erssa(count_table, condition_table, DE_ctrl_cond=ctrl_val)
        
        # ==========================================
        # 4. Customize and Save Diagnostic Plots
        # ==========================================
        
        # Parse out plot 1 (Number of DE genes)
        de_plot = ssa\$gg.dotPlot.obj\$gg_object 
        
        # Change y-axis label to be more descriptive
        de_plot = de_plot + ylab('Number of differentially expressed genes')
        
        # Save the plot in the current working directory with new dimensions and a lower resolution.
        ggsave(filename='ERSSA_plot_1_NumOfDEGenes.png',
             plot=de_plot, dpi=100, width = 15,
             height = 10, units = "cm")
        
        # Save other diagnostic plots if they are generated and available in the ssa object
        if (!is.null(ssa\$gg.marginPlot.obj\$gg_object)) {
          ggsave(filename='ERSSA_plot_2_MarginalNumOfDEGenes.png',
                 plot=ssa\$gg.marginPlot.obj\$gg_object, dpi=100, width = 15,
                 height = 10, units = "cm")
        }
        
        if (!is.null(ssa\$gg.intersectPlot.obj\$gg_object)) {
          ggsave(filename='ERSSA_plot_3_IntersectDEGenes.png',
                 plot=ssa\$gg.intersectPlot.obj\$gg_object, dpi=100, width = 15,
                 height = 10, units = "cm")
        }
        
        if (!is.null(ssa\$gg.TPR_FPRPlot.obj\$gg_object)) {
          ggsave(filename='ERSSA_plot_4_FPRvTPRPlot.png',
                 plot=ssa\$gg.TPR_FPRPlot.obj\$gg_object, dpi=100, width = 15,
                 height = 10, units = "cm")
        }
        
        # Save the full ssa results object for downstream analysis
        saveRDS(ssa, file = "ERSSA_ssa_results.rds")
        
        cat("ERSSA pipeline completed successfully. Results and plots saved to the working directory.\n")
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
      process = "BIOC_ERSSA_ERSSA_SAMPLE_SIZE_ANALYSIS",
      domain  = "bioconductor",
      declared_qc_steps = c("low-count filtering", "count normalization", "dispersion/size-factor estimation"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_ERSSA_ERSSA_SAMPLE_SIZE_ANALYSIS":',
        paste0('    ERSSA: ', as.character(packageVersion('ERSSA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_erssa_sample_size_analysis.csv versions.yml
    """
}

workflow BIOC_ERSSA_ERSSA_SAMPLE_SIZE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ count_table, condition_table ] ]

    main:
    BIOC_ERSSA_ERSSA_SAMPLE_SIZE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_ERSSA_ERSSA_SAMPLE_SIZE_ANALYSIS.out.tables
    plots    = BIOC_ERSSA_ERSSA_SAMPLE_SIZE_ANALYSIS.out.plots
    objects  = BIOC_ERSSA_ERSSA_SAMPLE_SIZE_ANALYSIS.out.objects
    versions = BIOC_ERSSA_ERSSA_SAMPLE_SIZE_ANALYSIS.out.versions
}
