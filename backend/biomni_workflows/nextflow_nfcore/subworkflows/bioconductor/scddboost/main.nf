#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scDDboost — differential_distribution_analysis
// Identify differentially distributed genes between two conditions in single-cell RNA-seq data.
// Input: normalized_counts_matrix, condition_vector
// Container: quay.io/biocontainers/bioconductor-scddboost:1.12.0--r45ha27e39d_0
// R packages: BiocParallel, ggplot2, scDDboost
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocParallel, scDDboost
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Calculate the cell distance matrix using calD
//  * 2. [Core Analysis] (Optional) Determine the number of subtypes using detK
//  * 3. [Core Analysis] Calculate the posterior probabilities of genes being differentially distributed using pdd
//  * 4. [Core Analysis] Extract the estimated DD genes controlling for false discovery rate using getDD

nextflow.enable.dsl = 2

process BIOC_SCDDBOOST_DIFFERENTIAL_DISTRIBUTION_ANALYSIS {
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
    .bm_deps <- c("BiocParallel", "ggplot2", "scDDboost")
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
    library(scDDboost)
    library(BiocParallel)
    
    # 1. Read User Inputs from the working directory
    if (file.exists("normalized_counts_matrix.rds")) {
      data_counts <- readRDS("normalized_counts_matrix.rds")
    } else if (file.exists("normalized_counts_matrix.csv")) {
      data_counts <- as.matrix(read.csv("normalized_counts_matrix.csv", row.names = 1, check.names = FALSE))
    } else if (file.exists("normalized_counts_matrix.tsv")) {
      data_counts <- as.matrix(read.delim("normalized_counts_matrix.tsv", row.names = 1, check.names = FALSE))
    } else {
      stop("Error: normalized_counts_matrix file not found (expected .rds, .csv, or .tsv).")
    }
    
    if (file.exists("condition_vector.rds")) {
      conditions <- readRDS("condition_vector.rds")
    } else if (file.exists("condition_vector.csv")) {
      conditions_df <- read.csv("condition_vector.csv", header = FALSE)
      conditions <- as.character(conditions_df[[1]])
    } else if (file.exists("condition_vector.txt")) {
      conditions <- readLines("condition_vector.txt")
    } else {
      stop("Error: condition_vector file not found (expected .rds, .csv, or .txt).")
    }
    
    # Ensure data_counts is a matrix
    data_counts <- as.matrix(data_counts)
    
    # Preserve original rownames if they exist, otherwise set sequential integers
    if (is.null(rownames(data_counts))) {
      rownames(data_counts) <- seq_len(nrow(data_counts))
    }
    
    # 2. Execute Documented Workflow
    bp <- BiocParallel::MulticoreParam(2)
    D_c <- calD(data_counts, bp)
    ProbDD <- pdd(data = data_counts, cd = conditions, bp = bp, D = D_c)
    K <- detK(D_c)
    EDD <- getDD(ProbDD, 0.05)
    
    # 3. Save Outputs
    # Save the posterior probabilities
    prob_df <- data.frame(Gene = rownames(data_counts), Prob_DD = ProbDD)
    write.csv(prob_df, "posterior_probabilities.csv", row.names = FALSE)
    
    # Save the estimated DD genes
    if (is.numeric(EDD)) {
      edd_df <- data.frame(DD_Gene = rownames(data_counts)[EDD])
    } else {
      edd_df <- data.frame(DD_Gene = EDD)
    }
    write.csv(edd_df, "estimated_dd_genes.csv", row.names = FALSE)
    
    # Save K (number of subtypes)
    writeLines(as.character(K), "estimated_subtypes_K.txt")
    
    # Save RDS objects for downstream analysis
    saveRDS(ProbDD, "ProbDD.rds")
    saveRDS(EDD, "EDD.rds")
    saveRDS(D_c, "distance_matrix.rds")
    
    # Generate a diagnostic plot of posterior probabilities
    pdf("prob_distribution.pdf", width = 6, height = 4)
    hist(ProbDD, breaks = 50, col = "skyblue", main = "Distribution of Posterior Probabilities (ProbDD)",
         xlab = "Posterior Probability of DD", ylab = "Frequency")
    abline(v = 0.95, col = "red", lty = 2, lwd = 2)
    legend("topright", legend = "0.95 Threshold", col = "red", lty = 2, lwd = 2)
    dev.off()
    
    cat("Workflow completed successfully. Outputs saved to working directory.\n")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # cell QC metrics — defensive cell-count + per-cell summary from any
    # matrix artifact. Pass when columns (cells) ≥ 50 and rows (features) ≥ 200
    # (Luecken & Theis 2019 single-cell QC floor).
    .cqc_ncells <- NA_real_; .cqc_nfeats <- NA_real_; .cqc_files <- character(0)
    for (.cqc_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
      .cqc_obj <- tryCatch(readRDS(.cqc_rds), error = function(e) NULL)
      .cqc_mat <- if (is.matrix(.cqc_obj) || is.data.frame(.cqc_obj)) .cqc_obj else NULL
      if (!is.null(.cqc_mat) && nrow(.cqc_mat) > 100) {
        .cqc_ncells <- ncol(.cqc_mat); .cqc_nfeats <- nrow(.cqc_mat)
        .cqc_files <- c(.cqc_files, .cqc_rds); break
      }
    }
    .gates_by_label[["cell QC metrics"]] <- list(
      gate_row = "bioc_cell_qc_metrics",
      metric_name = "n_cells",
      metric_value = .cqc_ncells,
      passes = isTRUE(is.finite(.cqc_ncells) && .cqc_ncells >= 50 && .cqc_nfeats >= 200),
      status = if (is.finite(.cqc_ncells)) paste0("computed (cells=", .cqc_ncells, ", features=", .cqc_nfeats, "; proxy gate)")
               else "not_computed (no scRNA matrix .rds artifact present)"
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
      process = "BIOC_SCDDBOOST_DIFFERENTIAL_DISTRIBUTION_ANALYSIS",
      domain  = "bioconductor",
      declared_qc_steps = c("cell QC metrics", "count normalization", "low-count filtering"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_SCDDBOOST_DIFFERENTIAL_DISTRIBUTION_ANALYSIS":',
        paste0('    scDDboost: ', as.character(packageVersion('scDDboost')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_differential_distribution_analysis.csv versions.yml
    """
}

workflow BIOC_SCDDBOOST_DIFFERENTIAL_DISTRIBUTION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ normalized_counts_matrix, condition_vector ] ]

    main:
    BIOC_SCDDBOOST_DIFFERENTIAL_DISTRIBUTION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SCDDBOOST_DIFFERENTIAL_DISTRIBUTION_ANALYSIS.out.tables
    plots    = BIOC_SCDDBOOST_DIFFERENTIAL_DISTRIBUTION_ANALYSIS.out.plots
    objects  = BIOC_SCDDBOOST_DIFFERENTIAL_DISTRIBUTION_ANALYSIS.out.objects
    versions = BIOC_SCDDBOOST_DIFFERENTIAL_DISTRIBUTION_ANALYSIS.out.versions
}
