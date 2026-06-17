#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DEFormats — deformats_interoperability_pipeline
// Convert RNA-seq count data between DESeq2 and edgeR formats using DEFormats to perform parallel differential expression analyses and compare results.
// Input: counts.csv, coldata.csv
// Container: 1.38.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: DEFormats, DESeq2, SummarizedExperiment, edgeR
// Visualizations: plot (ggplot/base)
// QC: dispersion/size-factor estimation
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DEFORMATS_DEFORMATS_INTEROPERABILITY_PIPELINE {
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
    .bm_deps <- c("DESeq2", "edgeR", "DEFormats", "SummarizedExperiment")
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
    
    # --- Load required libraries     library(SummarizedExperiment)
---
    library(DESeq2)
    library(edgeR)
    library(DEFormats)
    
    # --- Read and preprocess input data ---
    message("Reading input files...")
    counts_df <- read.csv("counts.csv", row.names = "gene_id", check.names = FALSE)
    counts_mat <- as.matrix(counts_df)
    
    coldata_df <- read.csv("coldata.csv", row.names = "sample", check.names = FALSE)
    
    # Align counts and coldata
    common_samples <- intersect(colnames(counts_mat), rownames(coldata_df))
    if (length(common_samples) == 0) {
        stop("Error: No matching samples found between counts.csv and coldata.csv")
    }
    counts_mat <- counts_mat[, common_samples, drop = FALSE]
    coldata_df <- coldata_df[common_samples, , drop = FALSE]
    
    # Ensure condition is a factor
    coldata_df\$condition <- as.factor(coldata_df\$condition)
    
    # --- Format conversions using DEFormats ---
    message("Performing format conversions...")
    
    # 3.1: Create DGEList and convert to DESeqDataSet
    dge_initial <- DGEList(counts = counts_mat, group = coldata_df\$condition)
    dds_converted <- as.DESeqDataSet(dge_initial)
    # Set the design formula for the converted DESeqDataSet
    design(dds_converted) <- ~ group
    
    # 3.2: Create SummarizedExperiment and convert to DGEList directly
    se <- SummarizedExperiment(
        assays = list(counts = counts_mat),
        colData = coldata_df
    )
    # Rename condition to group so DGEList automatically detects the grouping factor
    names(colData(se))[names(colData(se)) == "condition"] <- "group"
    dge_converted <- DGEList(se)
    
    # --- Parallel Differential Expression Analysis ---
    message("Running DESeq2 analysis on converted object...")
    # Run DESeq2 on the DESeqDataSet converted from DGEList
    dds_analyzed <- DESeq(dds_converted, quiet = TRUE)
    res_deseq <- results(dds_analyzed)
    res_deseq_df <- as.data.frame(res_deseq)
    res_deseq_df\$gene_id <- rownames(res_deseq_df)
    
    message("Running edgeR analysis on converted object...")
    # Run edgeR on the DGEList converted from SummarizedExperiment
    dge_converted <- estimateDisp(dge_converted)
    et_analyzed <- exactTest(dge_converted)
    res_edger <- topTags(et_analyzed, n = Inf)\$table
    res_edger\$gene_id <- rownames(res_edger)
    
    # --- Compare and Save Results ---
    message("Comparing results and writing outputs...")
    
    # Write individual results
    write.csv(res_deseq_df, "deseq2_results.csv", row.names = FALSE)
    write.csv(res_edger, "edger_results.csv", row.names = FALSE)
    
    # Merge results for comparison
    merged_res <- merge(
        res_deseq_df[, c("gene_id", "log2FoldChange", "pvalue", "padj")],
        res_edger[, c("gene_id", "logFC", "PValue", "FDR")],
        by = "gene_id",
        suffixes = c("_deseq2", "_edger")
    )
    write.csv(merged_res, "method_comparison.csv", row.names = FALSE)
    
    # Generate comparison plot
    pdf("method_comparison.pdf", width = 6, height = 6)
    plot(
        merged_res\$log2FoldChange, 
        merged_res\$logFC,
        xlab = "DESeq2 Log2 Fold Change",
        ylab = "edgeR Log2 Fold Change",
        main = "LFC Correlation between DESeq2 and edgeR",
        pch = 16, 
        col = rgb(0, 0, 1, 0.5)
    )
    abline(a = 0, b = 1, col = "red", lty = 2)
    grid()
    dev.off()
    
    message("Pipeline completed successfully!")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

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
      process = "BIOC_DEFORMATS_DEFORMATS_INTEROPERABILITY_PIPELINE",
      domain  = "bioconductor",
      declared_qc_steps = c("dispersion/size-factor estimation"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_DEFORMATS_DEFORMATS_INTEROPERABILITY_PIPELINE":',
        paste0('    DEFormats: ', as.character(packageVersion('DEFormats')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_deformats_interoperability_pipeline.csv versions.yml
    """
}

workflow BIOC_DEFORMATS_DEFORMATS_INTEROPERABILITY_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_DEFORMATS_DEFORMATS_INTEROPERABILITY_PIPELINE(ch_input)

    emit:
    tables   = BIOC_DEFORMATS_DEFORMATS_INTEROPERABILITY_PIPELINE.out.tables
    plots    = BIOC_DEFORMATS_DEFORMATS_INTEROPERABILITY_PIPELINE.out.plots
    objects  = BIOC_DEFORMATS_DEFORMATS_INTEROPERABILITY_PIPELINE.out.objects
    versions = BIOC_DEFORMATS_DEFORMATS_INTEROPERABILITY_PIPELINE.out.versions
}
