#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: saser — aberrant_expression_analysis
// Detect aberrant gene expression from BAM files and GTF annotation.
// Input: BAMFiles, gtfFileName
// Container: quay.io/biocontainers/bioconductor-saser:1.6.0--r45hdfd78af_0
// R packages: GenomicFeatures, PRROC, ASpli, BiocParallel, data.table, DESeq2, DEXSeq, dplyr, edgeR, GenomicAlignments, igraph, limma, saseR, txdbmaker
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)
// QC: filter low-expression genes, low-count filtering

nextflow.enable.dsl = 2

process BIOC_SASER_ABERRANT_EXPRESSION_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-saser:1.6.0--r45hdfd78af_0"

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
    .bm_deps <- c("GenomicFeatures", "PRROC", "ASpli", "BiocParallel", "data.table", "DESeq2", "DEXSeq", "dplyr", "edgeR", "GenomicAlignments", "igraph", "limma", "saseR", "txdbmaker", "SummarizedExperiment")
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
    library(saseR)
    library(SummarizedExperiment)
    suppressWarnings(library(ASpli))
    library(edgeR)
    library(DESeq2)
    library(limma)
    library(GenomicFeatures)
    library(dplyr)
    library(PRROC)
    library(BiocParallel)
    library(data.table)
    library(igraph)
    library(txdbmaker)
    
    # -----------------------------------------------------------------------------
    # --- USER INPUTS ---
    # Read GTF and BAM files from the working directory
    # -----------------------------------------------------------------------------
    gtfFileName <- list.files(pattern = "\\\\.gtf\$", full.names = TRUE)[1]
    BAMFiles <- list.files(pattern = "\\\\.bam\$", full.names = TRUE)
    
    if (is.na(gtfFileName)) {
      stop("Error: No GTF file (.gtf) found in the working directory.")
    }
    if (length(BAMFiles) == 0) {
      stop("Error: No BAM files (.bam) found in the working directory.")
    }
    
    # Construct targets data frame dynamically based on the input BAM files
    targets <- data.frame( 
      row.names = paste0('Sample', seq_along(BAMFiles)),
      bam = BAMFiles,
      f1 = rep("A", length(BAMFiles)),
      stringsAsFactors = FALSE
    )
    
    # -----------------------------------------------------------------------------
    # --- GENOME ANNOTATION & FEATURE EXTRACTION ---
    # -----------------------------------------------------------------------------
    genomeTxDb <- txdbmaker::makeTxDbFromGFF(gtfFileName)
    features <- binGenome(genomeTxDb, logTo = NULL)
    
    # -----------------------------------------------------------------------------
    # --- READ COUNTING ---
    # -----------------------------------------------------------------------------
    ASpliSE <- BamtoAspliCounts(
      features = features,
      targets = targets,
      minReadLength = 100,
      libType = "SE",
      BPPARAM = MulticoreParam(1L)
    )
    
    # -----------------------------------------------------------------------------
    # --- ABERRANT EXPRESSION ANALYSIS PIPELINE ---
    # -----------------------------------------------------------------------------
    # Extract gene counts
    SEgenes <- convertASpli(ASpliSE, type = "gene")
    
    # Define design formula in metadata
    metadata(SEgenes)\$design <- ~1
    
    # Filter low-count genes
    filtergenes <- filterByExpr(SEgenes)
    SEgenes <- SEgenes[filtergenes,]
    
    # Calculate normalization offsets
    SEgenes <- calculateOffsets(SEgenes, method = "TMM")
    
    # Estimate latent confounders
    SEgenes <- saseRfindEncodingDim(SEgenes, method = "GD")
    
    # Fit the regression model and calculate p-values
    SEgenes <- saseRfit(
      SEgenes,
      analysis = "AE",
      padjust = "BH",
      fit = "fast"
    )
    
    # -----------------------------------------------------------------------------
    # --- WRITE OUTPUTS ---
    # -----------------------------------------------------------------------------
    # Save the complete SummarizedExperiment object
    saveRDS(SEgenes, file = "aberrant_expression_results.rds")
    
    # Extract and save p-values and adjusted p-values
    pvals <- assays(SEgenes)\$pValue
    pvals_adj <- assays(SEgenes)\$pValueAdjust
    
    write.csv(as.data.frame(pvals), file = "p_values.csv", row.names = TRUE)
    write.csv(as.data.frame(pvals_adj), file = "adjusted_p_values.csv", row.names = TRUE)
    
    # Generate and save diagnostic plot
    pdf("p_value_distribution.pdf", width = 8, height = 6)
    hist(
      pvals, 
      col = "skyblue", 
      border = "white", 
      main = "Distribution of Aberrant Expression p-values", 
      xlab = "p-value", 
      ylab = "Frequency"
    )
    dev.off()
    
    message("Pipeline completed successfully. Outputs written to working directory.")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # filter low-expression genes — alias of low-count filtering metric
    # (Chen 2016 F1000 edgeR filterByExpr semantics).
    .fleg_kept <- NA_real_; .fleg_files <- character(0)
    for (.fleg_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .fleg_obj <- tryCatch(readRDS(.fleg_rds), error = function(e) NULL)
      .fleg_mat <- if (is.matrix(.fleg_obj) || is.data.frame(.fleg_obj)) .fleg_obj else NULL
      if (!is.null(.fleg_mat) && nrow(.fleg_mat) > 100) {
        .fleg_m <- suppressWarnings(as.matrix(.fleg_mat))
        .fleg_rowmed <- suppressWarnings(apply(.fleg_m, 1, function(r) median(as.numeric(r), na.rm = TRUE)))
        .fleg_kept <- sum(is.finite(.fleg_rowmed) & .fleg_rowmed >= 1) / nrow(.fleg_m)
        .fleg_files <- c(.fleg_files, .fleg_rds); break
      }
    }
    .gates_by_label[["filter low-expression genes"]] <- list(
      gate_row = "bioc_low_count_filtering",
      metric_name = "genes_kept_fraction",
      metric_value = if (is.finite(.fleg_kept)) round(.fleg_kept, 4) else NA_real_,
      passes = isTRUE(is.finite(.fleg_kept) && .fleg_kept >= 0.3 && .fleg_kept <= 0.6),
      status = if (is.finite(.fleg_kept)) paste0("computed (median count >= 1 rows / total)")
               else "not_computed (no expression matrix .rds artifact present)"
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

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_SASER_ABERRANT_EXPRESSION_ANALYSIS",
      domain  = "bioconductor",
      declared_qc_steps = c("filter low-expression genes", "low-count filtering"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_SASER_ABERRANT_EXPRESSION_ANALYSIS":',
        paste0('        saser: ', as.character(packageVersion("saser")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_aberrant_expression_analysis.csv versions.yml
    """
}

workflow BIOC_SASER_ABERRANT_EXPRESSION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ BAMFiles, gtfFileName ] ]

    main:
    BIOC_SASER_ABERRANT_EXPRESSION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SASER_ABERRANT_EXPRESSION_ANALYSIS.out.tables
    plots    = BIOC_SASER_ABERRANT_EXPRESSION_ANALYSIS.out.plots
    objects  = BIOC_SASER_ABERRANT_EXPRESSION_ANALYSIS.out.objects
    versions = BIOC_SASER_ABERRANT_EXPRESSION_ANALYSIS.out.versions
}
