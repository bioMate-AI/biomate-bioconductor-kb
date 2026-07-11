#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DESeq2 — standard_de_from_matrix
// Perform standard differential expression analysis starting from a raw count matrix and sample metadata.
// Input: cts, coldata
// Container: quay.io/biocontainers/bioconductor-deseq2:1.50.2--r45ha27e39d_0
// R packages: airway, BiocParallel, DESeq2, ggplot2, IHW, RColorBrewer
// Bioconductor: 3.20 | R: 4.4
// Requires: DESeq2
// Visualizations: MA plot, gene count plot
// QC: diagnostic MA/PCA QC, low-count filtering
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Construct DESeqDataSet from matrix
//  * 2. [Core Analysis] Pre-filter low count genes
//  * 3. [Core Analysis] Set factor levels and reference group
//  * 4. [Core Analysis] Run DESeq() pipeline
//  * 5. [Core Analysis] Extract results and apply LFC shrinkage
//  * 6. [Visualization & Output] Visualize results (MA-plot, plotCounts)
//  * 7. [Visualization & Output] Export results to CSV

nextflow.enable.dsl = 2

process BIOC_DESEQ2_STANDARD_DE_FROM_MATRIX {
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
    .bm_deps <- c("airway", "apeglm", "BiocParallel", "DESeq2", "ggplot2", "IHW", "RColorBrewer")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
    }
        
        # Load required libraries
        library("DESeq2")
        
        # Helper function to read input files robustly
        read_input_file <- function(base_name) {
          extensions <- c("", ".csv", ".tsv", ".txt")
          for (ext in extensions) {
            full_path <- paste0(base_name, ext)
            if (file.exists(full_path)) {
              # Try reading as CSV first, then fallback to whitespace-separated
              return(
                tryCatch({
                  read.csv(full_path, row.names = 1, check.names = FALSE)
                }, error = function(e) {
                  read.table(full_path, header = TRUE, row.names = 1, check.names = FALSE, sep = "")
                })
              )
            }
          }
          stop(paste("Required input file for", base_name, "not found in the working directory."))
        }
        
        # 1. Read user input files
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
        cts_df <- read_input_file("cts")
        cts <- as.matrix(cts_df)
        storage.mode(cts) <- "integer"
        
        coldata <- read_input_file("coldata")
        
        # Ensure sample names match and are in the same order
        common_samples <- intersect(colnames(cts), rownames(coldata))
        if (length(common_samples) == 0) {
          stop("No matching sample names found between cts columns and coldata rows.")
        }
        cts <- cts[, common_samples, drop = FALSE]
        coldata <- coldata[common_samples, , drop = FALSE]
        
        # Ensure the condition column exists
        if (!"condition" %in% colnames(coldata)) {
          stop("The coldata metadata must contain a 'condition' column.")
        }
        
        # 2. Construct DESeqDataSet from matrix
        dds <- DESeqDataSetFromMatrix(countData = cts,
                                      colData = coldata,
                                      design = ~ condition)
        
        # 3. Pre-filter low count genes
        smallestGroupSize <- min(table(dds\$condition))
        keep <- rowSums(counts(dds) >= 10) >= smallestGroupSize
        dds <- dds[keep,]
        
        # 4. Set factor levels and reference group
        dds\$condition <- factor(dds\$condition)
        dds\$condition <- relevel(dds\$condition, ref = levels(dds\$condition)[1])
        
        # 5. Run DESeq() pipeline
        dds <- DESeq(dds)
        
        # 6. Extract results and apply LFC shrinkage
        res <- results(dds)
        resultsNames(dds)
        res_coef <- resultsNames(dds)[length(resultsNames(dds))]
        resLFC <- lfcShrink(dds, coef=res_coef, type="apeglm")
        resOrdered <- res[order(res\$pvalue),]
        
        # Print summary to console
        summary(res)
        
        # 7. Visualize results and save to PDF
        pdf("deseq2_plots.pdf", width = 7, height = 7)
        plotMA(res, ylim=c(-2,2))
        plotMA(resLFC, ylim=c(-2,2))
        # Handle potential NA values in padj when finding the minimum
        valid_padj_idx <- which(!is.na(res\$padj))
        if (length(valid_padj_idx) > 0) {
          best_gene <- valid_padj_idx[which.min(res\$padj[valid_padj_idx])]
          plotCounts(dds, gene=best_gene, intgroup="condition")
        }
        dev.off()
        
        # 8. Export results to CSV and RDS
        write.csv(as.data.frame(resOrdered),
                  file="condition_treated_results.csv")
        
        saveRDS(dds, "dds.rds")
        saveRDS(res, "res.rds")
        saveRDS(resLFC, "resLFC.rds")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # diagnostic MA/PCA QC — PC1 variance explained on any large matrix.
    # Pass when PC1 > 10% (Risso 2014 RUV-seq diagnostic).
    .pca_pc1 <- NA_real_; .pca_files <- character(0)
    for (.pca_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
      .pca_obj <- tryCatch(readRDS(.pca_rds), error = function(e) NULL)
      .pca_mat <- if (is.matrix(.pca_obj) || is.data.frame(.pca_obj)) .pca_obj else NULL
      if (!is.null(.pca_mat) && ncol(.pca_mat) >= 3 && nrow(.pca_mat) >= 100) {
        .pca_m <- suppressWarnings(as.matrix(.pca_mat))
        .pca_kept <- apply(.pca_m, 1, function(r) all(is.finite(r)) && var(r) > 0)
        if (sum(.pca_kept) >= 50) {
          .pca_fit <- tryCatch(prcomp(t(.pca_m[.pca_kept, , drop = FALSE])), error = function(e) NULL)
          if (!is.null(.pca_fit)) {
            .pca_vars <- (.pca_fit\$sdev^2) / sum(.pca_fit\$sdev^2)
            .pca_pc1 <- round(.pca_vars[1] * 100, 2); .pca_files <- c(.pca_files, .pca_rds); break
          }
        }
      }
    }
    .gates_by_label[["diagnostic MA/PCA QC"]] <- list(
      gate_row = "bioc_diagnostic_ma_pca_qc",
      metric_name = "pc1_var_explained",
      metric_value = .pca_pc1,
      passes = isTRUE(is.finite(.pca_pc1) && .pca_pc1 > 10),
      status = if (is.finite(.pca_pc1)) paste0("computed (PC1=", .pca_pc1, "%)")
               else "not_computed (no large numeric matrix .rds artifact present)"
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
      process = "BIOC_DESEQ2_STANDARD_DE_FROM_MATRIX",
      domain  = "bioconductor",
      declared_qc_steps = c("diagnostic MA/PCA QC", "low-count filtering"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_DESEQ2_STANDARD_DE_FROM_MATRIX":',
        paste0('    DESeq2: ', as.character(packageVersion('DESeq2')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_de_from_matrix.csv versions.yml
    """
}

workflow BIOC_DESEQ2_STANDARD_DE_FROM_MATRIX_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ cts, coldata ] ]

    main:
    BIOC_DESEQ2_STANDARD_DE_FROM_MATRIX(ch_input)

    emit:
    tables   = BIOC_DESEQ2_STANDARD_DE_FROM_MATRIX.out.tables
    plots    = BIOC_DESEQ2_STANDARD_DE_FROM_MATRIX.out.plots
    objects  = BIOC_DESEQ2_STANDARD_DE_FROM_MATRIX.out.objects
    versions = BIOC_DESEQ2_STANDARD_DE_FROM_MATRIX.out.versions
}
