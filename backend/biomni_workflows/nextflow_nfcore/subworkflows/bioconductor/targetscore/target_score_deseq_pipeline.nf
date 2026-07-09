#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: TargetScore — target_score_deseq_pipeline
// Perform differential expression analysis on RNA-seq count data using DESeq, then compute target scores using targetScore.
// Input: CountDataSet, seqScores matrix
// Container: quay.io/biocontainers/bioconductor-targetscore:1.48.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: DESeq, TargetScore
// Visualizations: plot (ggplot/base)
// QC: dispersion/size-factor estimation
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Estimate size factors and dispersions using DESeq
//  * 2. [Core Analysis] Perform negative binomial test to get log2 fold changes
//  * 3. [Core Analysis] Extract logFC and combine with sequence scores
//  * 4. [Core Analysis] Run targetScore

nextflow.enable.dsl = 2

process BIOC_TARGETSCORE_TARGET_SCORE_DESEQ_PIPELINE {
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
    .bm_deps <- c("DESeq", "TargetScore")
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
    library(DESeq)
    library(TargetScore)
    
    # Helper function to find files with or without extensions
    find_file <- function(base_name) {
      candidates <- c(base_name, paste0(base_name, ".csv"), paste0(base_name, ".tsv"), paste0(base_name, ".txt"))
      for (f in candidates) {
        if (file.exists(f)) return(f)
      }
      stop(paste("Required input file not found:", base_name))
    }
    
    # 1. Read CountDataSet
    count_file <- find_file("CountDataSet")
    message("Reading count data from: ", count_file)
    counts <- tryCatch({
      read.csv(count_file, row.names = 1, check.names = FALSE)
    }, error = function(e) {
      read.table(count_file, header = TRUE, row.names = 1, sep = "\t", check.names = FALSE)
    })
    
    count_matrix <- as.matrix(counts)
    storage.mode(count_matrix) <- "integer"
    
    # Define conditions (assuming first half is A, second half is B)
    n_cols <- ncol(count_matrix)
    if (n_cols < 2) {
      stop("CountDataSet must have at least 2 columns (samples) to perform differential analysis.")
    }
    conditions <- factor(c(rep("A", floor(n_cols/2)), rep("B", ceiling(n_cols/2))))
    
    # Create CountDataSet object
    cds <- newCountDataSet(count_matrix, conditions)
    
    # 2. Run DESeq pipeline
    cds <- estimateSizeFactors( cds )
    cds <- estimateDispersions( cds )
    deseq_stats <- nbinomTest( cds, "A", "B" )
    
    # 3. Read seqScores
    seq_file <- find_file("seqScores")
    message("Reading sequence scores from: ", seq_file)
    seqScores_df <- tryCatch({
      read.csv(seq_file, row.names = 1, check.names = FALSE)
    }, error = function(e) {
      read.table(seq_file, header = TRUE, row.names = 1, sep = "\t", check.names = FALSE)
    })
    seqScores_matrix <- as.matrix(seqScores_df)
    
    # Align genes between DESeq stats and seqScores
    common_genes <- intersect(deseq_stats\$id, rownames(seqScores_matrix))
    if (length(common_genes) == 0) {
      stop("No common genes found between CountDataSet and seqScores!")
    }
    
    deseq_stats_sub <- deseq_stats[match(common_genes, deseq_stats\$id), ]
    seqScores_sub <- seqScores_matrix[match(common_genes, rownames(seqScores_matrix)), , drop = FALSE]
    
    # Extract logFC and filter NAs
    logFC_all <- deseq_stats_sub\$log2FoldChange
    valid_idx <- !is.na(logFC_all) & apply(!is.na(seqScores_sub), 1, all)
    
    logFC <- logFC_all[valid_idx]
    seqScores <- seqScores_sub[valid_idx, , drop = FALSE]
    final_genes <- common_genes[valid_idx]
    
    if (length(logFC) == 0) {
      stop("No valid genes remaining after filtering NA values.")
    }
    
    # 4. Run targetScore
    p.targetScore <- targetScore(logFC, seqScores, tol=1e-3)
    
    # 5. Save results
    results_df <- data.frame(
      Gene = final_genes,
      log2FoldChange = logFC,
      TargetScore = p.targetScore,
      stringsAsFactors = FALSE
    )
    # Add seqScores columns to the results
    results_df <- cbind(results_df, as.data.frame(seqScores))
    
    write.csv(results_df, "target_scores_results.csv", row.names = FALSE)
    saveRDS(p.targetScore, "target_scores.rds")
    
    # Plot and save PDF
    pdf("target_scores_plot.pdf", width = 8, height = 8)
    pairs(cbind(TargetScore = p.targetScore, logFC = logFC, seqScores))
    dev.off()
    
    message("Pipeline completed successfully. Outputs written to 'target_scores_results.csv', 'target_scores.rds', and 'target_scores_plot.pdf'.")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

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
      process = "BIOC_TARGETSCORE_TARGET_SCORE_DESEQ_PIPELINE",
      domain  = "bioconductor",
      declared_qc_steps = c("dispersion/size-factor estimation"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_TARGETSCORE_TARGET_SCORE_DESEQ_PIPELINE":',
        paste0('    TargetScore: ', as.character(packageVersion('TargetScore')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_target_score_deseq_pipeline.csv versions.yml
    """
}

workflow BIOC_TARGETSCORE_TARGET_SCORE_DESEQ_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ CountDataSet, seqScores matrix ] ]

    main:
    BIOC_TARGETSCORE_TARGET_SCORE_DESEQ_PIPELINE(ch_input)

    emit:
    tables   = BIOC_TARGETSCORE_TARGET_SCORE_DESEQ_PIPELINE.out.tables
    plots    = BIOC_TARGETSCORE_TARGET_SCORE_DESEQ_PIPELINE.out.plots
    objects  = BIOC_TARGETSCORE_TARGET_SCORE_DESEQ_PIPELINE.out.objects
    versions = BIOC_TARGETSCORE_TARGET_SCORE_DESEQ_PIPELINE.out.versions
}
