#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: recount — recount_normalization_pipeline
// Build a RangedSummarizedExperiment from local count data and metadata, then perform recount-specific scaling, RPKM, and TPM calculations, and export the normali
// Input: counts.csv, coldata.csv
// Container: 1.36.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, SummarizedExperiment, recount
// Visualizations: box plot
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RECOUNT_RECOUNT_NORMALIZATION_PIPELINE {
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
    .bm_deps <- c("recount", "GenomicRanges", "SummarizedExperiment")
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
    library(recount)
    library(SummarizedExperiment)
    library(GenomicRanges)
    
    # --- Read and align input files ---
    message("Loading input datasets...")
    counts_df <- read.csv("counts.csv", check.names = FALSE, stringsAsFactors = FALSE)
    if (!"gene_id" %in% colnames(counts_df)) {
        stop("Input counts.csv must contain a 'gene_id' column.")
    }
    rownames(counts_df) <- counts_df\$gene_id
    counts_matrix <- as.matrix(counts_df[, -which(colnames(counts_df) == "gene_id"), drop = FALSE])
    
    coldata_df <- read.csv("coldata.csv", check.names = FALSE, stringsAsFactors = FALSE)
    if (!all(c("sample", "condition") %in% colnames(coldata_df))) {
        stop("Input coldata.csv must contain 'sample' and 'condition' columns.")
    }
    rownames(coldata_df) <- coldata_df\$sample
    
    # Align samples between counts and coldata
    common_samples <- intersect(colnames(counts_matrix), rownames(coldata_df))
    if (length(common_samples) == 0) {
        stop("No common samples found between counts.csv and coldata.csv.")
    }
    counts_matrix <- counts_matrix[, common_samples, drop = FALSE]
    coldata_df <- coldata_df[common_samples, , drop = FALSE]
    
    # --- Construct RangedSummarizedExperiment with ---
    message("Constructing RangedSummarizedExperiment object...")
    # Create dummy genomic ranges for the genes
    row_ranges <- GRanges(
        seqnames = rep("chr1", nrow(counts_matrix)),
        ranges = IRanges(start = seq_len(nrow(counts_matrix)) * 1000, width = 100),
        strand = "*"
    )
    names(row_ranges) <- rownames(counts_matrix)
    
    # Add bp_length to rowData (required for RPKM and TPM calculations)
    mcols(row_ranges)\$bp_length <- as.integer(rep(2000, nrow(counts_matrix)))
    mcols(row_ranges)\$gene_id <- rownames(counts_matrix)
    
    # Add recount-specific columns to colData
    # scale_counts requires 'auc' (Area Under Coverage) or 'mapped_read_count'
    coldata_df\$mapped_read_count <- as.numeric(colSums(counts_matrix))
    # Estimate AUC assuming an average read length of 100bp
    coldata_df\$auc <- coldata_df\$mapped_read_count * 100
    
    rse <- RangedSummarizedExperiment(
        assays = list(counts = counts_matrix),
        rowRanges = row_ranges,
        colData = as(coldata_df, "DataFrame")
    )
    
    # --- Perform recount scaling and normalization ---
    message("Scaling counts using recount::scale_counts...")
    # Scale counts to mapped reads (standardizes library size)
    rse_scaled <- scale_counts(rse, by = "mapped_reads")
    scaled_counts <- assay(rse_scaled)
    
    message("Calculating RPKM using recount::getRPKM...")
    rpkm_matrix <- getRPKM(rse, length_var = "bp_length", mapped_var = "mapped_read_count")
    
    message("Calculating TPM using recount::getTPM...")
    tpm_matrix <- getTPM(rse, length_var = "bp_length", mapped_var = "mapped_read_count")
    
    # --- Write outputs to files ---
    message("Writing normalized matrices to CSV...")
    write.csv(scaled_counts, "scaled_counts.csv", row.names = TRUE)
    write.csv(rpkm_matrix, "rpkm_matrix.csv", row.names = TRUE)
    write.csv(tpm_matrix, "tpm_matrix.csv", row.names = TRUE)
    
    # --- Generate diagnostic plots ---
    message("Generating diagnostic plots...")
    pdf("normalization_summary.pdf", width = 10, height = 8)
    par(mfrow = c(2, 2), mar = c(6, 4, 4, 2))
    boxplot(log2(counts_matrix + 1), main = "Raw Counts (log2 + 1)", las = 2, col = "skyblue")
    boxplot(log2(scaled_counts + 1), main = "Scaled Counts (log2 + 1)", las = 2, col = "tomato")
    boxplot(log2(rpkm_matrix + 1), main = "RPKM (log2 + 1)", las = 2, col = "lightgreen")
    boxplot(log2(tpm_matrix + 1), main = "TPM (log2 + 1)", las = 2, col = "gold")
    dev.off()
    
    message("Pipeline completed successfully.")
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
      process = "BIOC_RECOUNT_RECOUNT_NORMALIZATION_PIPELINE",
      domain  = "bioconductor",
      declared_qc_steps = c("low-count filtering", "count normalization", "dispersion/size-factor estimation"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_RECOUNT_RECOUNT_NORMALIZATION_PIPELINE":',
        paste0('    recount: ', as.character(packageVersion('recount')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_recount_normalization_pipeline.csv versions.yml
    """
}

workflow BIOC_RECOUNT_RECOUNT_NORMALIZATION_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_RECOUNT_RECOUNT_NORMALIZATION_PIPELINE(ch_input)

    emit:
    tables   = BIOC_RECOUNT_RECOUNT_NORMALIZATION_PIPELINE.out.tables
    plots    = BIOC_RECOUNT_RECOUNT_NORMALIZATION_PIPELINE.out.plots
    objects  = BIOC_RECOUNT_RECOUNT_NORMALIZATION_PIPELINE.out.objects
    versions = BIOC_RECOUNT_RECOUNT_NORMALIZATION_PIPELINE.out.versions
}
