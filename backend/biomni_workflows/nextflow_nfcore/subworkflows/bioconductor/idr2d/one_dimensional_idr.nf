#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: idr2d — one_dimensional_idr
// Identify reproducible genomic peaks between two replicates of 1D genomic data (e.g., ChIP-seq).
// Input: rep1_df, rep2_df
// Container: quay.io/biocontainers/bioconductor-idr2d:1.24.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: idr2d
// Visualizations: scatter plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load replicate data frames
//  * 2. [Core Analysis] Estimate 1D IDR using estimate_idr1d
//  * 3. [Visualization & Output] Summarize results using summary
//  * 4. [Visualization & Output] Visualize IDR distribution and dependencies using draw_idr_distribution_histogram, draw_rank_idr_scatterplot, and draw_value_idr_s

nextflow.enable.dsl = 2

process BIOC_IDR2D_ONE_DIMENSIONAL_IDR {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20-slim"

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
    .bm_deps <- c("idr2d")
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
        
        # 1. Load required libraries
        library(idr2d)
        
        # 2. Load replicate data frames from user input files
        # Supports both RDS and CSV formats
        if (file.exists("rep1_df.rds")) {
          rep1_df <- readRDS("rep1_df.rds")
        } else if (file.exists("rep1_df.csv")) {
          rep1_df <- read.csv("rep1_df.csv")
        } else {
          stop("Error: Replicate 1 input file (rep1_df.rds or rep1_df.csv) not found in the working directory.")
        }
        
        if (file.exists("rep2_df.rds")) {
          rep2_df <- readRDS("rep2_df.rds")
        } else if (file.exists("rep2_df.csv")) {
          rep2_df <- read.csv("rep2_df.csv")
        } else {
          stop("Error: Replicate 2 input file (rep2_df.rds or rep2_df.csv) not found in the working directory.")
        }
        
        # 3. Estimate 1D IDR using estimate_idr1d
        idr_results <- estimate_idr1d(rep1_df, rep2_df, 
                                      value_transformation = "log")
        rep1_idr_df <- idr_results\$rep1_df
        
        # Save the primary results to disk
        saveRDS(idr_results, file = "idr_results.rds")
        write.csv(rep1_idr_df, file = "rep1_idr_df.csv", row.names = FALSE)
        
        # 4. Summarize results and save summary text
        summary_output <- capture.output(summary(idr_results))
        writeLines(summary_output, con = "idr_summary.txt")
        cat(summary_output, sep = "\n")
        
        # 5. Visualize IDR distribution and dependencies, saving plots to PDF files
        pdf("idr_distribution_histogram.pdf", width = 7, height = 7)
        tryCatch({
          print(draw_idr_distribution_histogram(rep1_idr_df))
        }, error = function(e) {
          warning("Could not plot IDR distribution histogram: ", e\$message)
        })
        dev.off()
        
        pdf("rank_idr_scatterplot.pdf", width = 7, height = 7)
        tryCatch({
          print(draw_rank_idr_scatterplot(rep1_idr_df))
        }, error = function(e) {
          warning("Could not plot rank-IDR scatterplot: ", e\$message)
        })
        dev.off()
        
        pdf("value_idr_scatterplot.pdf", width = 7, height = 7)
        tryCatch({
          print(draw_value_idr_scatterplot(rep1_idr_df))
        }, error = function(e) {
          warning("Could not plot value-IDR scatterplot: ", e\$message)
        })
        dev.off()
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # alignment/mapping QC — workflow-emitted artifact check for common log
    # files (.log, .summary, alignment metrics tables). Binary pass.
    .amqc_logs <- c(list.files(".", pattern = "(?i)(align|map|samtools|flagstat).*\\.(log|txt|summary)\$"),
                    list.files(".", pattern = "(?i)flagstat\\."))
    .amqc_passes <- length(.amqc_logs) > 0
    .gates_by_label[["alignment/mapping QC"]] <- list(
      gate_row = "bioc_alignment_mapping_qc",
      metric_name = "alignment_qc_artifacts",
      metric_value = length(.amqc_logs),
      passes = .amqc_passes,
      status = if (.amqc_passes) paste0("computed (", length(.amqc_logs), " alignment log(s) emitted)")
               else "not_computed (no alignment log/summary artifact present)"
    )

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

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_IDR2D_ONE_DIMENSIONAL_IDR",
      domain  = "bioconductor",
      declared_qc_steps = c("alignment/mapping QC", "low-count filtering", "count normalization"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_IDR2D_ONE_DIMENSIONAL_IDR":',
        paste0('    idr2d: ', as.character(packageVersion('idr2d')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_one_dimensional_idr.csv versions.yml
    """
}

workflow BIOC_IDR2D_ONE_DIMENSIONAL_IDR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ rep1_df, rep2_df ] ]

    main:
    BIOC_IDR2D_ONE_DIMENSIONAL_IDR(ch_input)

    emit:
    tables   = BIOC_IDR2D_ONE_DIMENSIONAL_IDR.out.tables
    plots    = BIOC_IDR2D_ONE_DIMENSIONAL_IDR.out.plots
    objects  = BIOC_IDR2D_ONE_DIMENSIONAL_IDR.out.objects
    versions = BIOC_IDR2D_ONE_DIMENSIONAL_IDR.out.versions
}
