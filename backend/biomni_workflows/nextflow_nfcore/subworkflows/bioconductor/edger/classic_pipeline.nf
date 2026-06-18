#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: edgeR — classic_pipeline
// Perform pairwise differential expression analysis using exact tests (qCML method) for single-factor designs.
// Input: x
// Container: quay.io/biocontainers/bioconductor-edger:4.8.2--r45h01b2380_0
// R packages: edgeR
// Bioconductor: 3.20 | R: 4.4
// Requires: edgeR
// Visualizations: MDS plot, BCV plot
// QC: filter low-expression genes, dispersion QC plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create DGEList object with grouping
//  * 2. [Core Analysis] Estimate common and tagwise dispersions
//  * 3. [Core Analysis] Perform exact test
//  * 4. [Core Analysis] Extract top tags

nextflow.enable.dsl = 2

process BIOC_EDGER_CLASSIC_PIPELINE {
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
    .bm_deps <- c("edgeR")
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
    
    # Load required library
    library(edgeR)
    
    # -----------------------------------------------------------------------------
    # 1. Read User Input
    # -----------------------------------------------------------------------------
    # The pipeline expects a file named 'x.csv', 'x.tsv', or 'x.txt' in the working directory
    # representing the matrix of raw counts.
    if (file.exists("x.csv")) {
      x <- read.csv("x.csv", row.names = 1, check.names = FALSE)
    } else if (file.exists("x.tsv")) {
      x <- read.delim("x.tsv", row.names = 1, check.names = FALSE)
    } else if (file.exists("x.txt")) {
      x <- read.delim("x.txt", row.names = 1, check.names = FALSE)
    } else {
      stop("Error: Input file 'x.csv', 'x.tsv', or 'x.txt' containing raw counts not found in the working directory.")
    }
    
    # Convert to matrix
    x <- as.matrix(x)
    
    # Determine the number of samples (columns)
    n_samples <- ncol(x)
    if (n_samples < 2) {
      stop("Error: At least 2 samples (columns) are required for pairwise differential expression analysis.")
    }
    
    # Define a grouping factor for the single-factor design.
    # Since the user input only provides the count matrix, we assign samples to two groups
    # (alternating or split) to allow pairwise comparison.
    group <- factor(rep(1:2, length.out = n_samples))
    
    # -----------------------------------------------------------------------------
    # 2. Execute Documented edgeR Classic Pipeline
    # -----------------------------------------------------------------------------
    # Create DGEList object with grouping
    y <- DGEList(counts=x, group=group)
    
    # Filter lowly expressed genes
    keep <- filterByExpr(y)
    y <- y[keep, , keep.lib.sizes=FALSE]
    
    # Normalize library sizes (TMM)
    y <- normLibSizes(y)
    
    # Estimate common and tagwise dispersions (qCML method)
    y <- estimateCommonDisp(y)
    y <- estimateTagwiseDisp(y)
    
    # Perform exact test
    et <- exactTest(y)
    
    # Extract and print top tags (reproducing the documented call)
    topTags(et)
    
    # -----------------------------------------------------------------------------
    # 3. Write Outputs
    # -----------------------------------------------------------------------------
    # Save the complete differential expression results table
    de_results <- as.data.frame(topTags(et, n = Inf))
    write.csv(de_results, "differential_expression_results.csv", row.names = TRUE)
    
    # Save RDS objects for downstream analysis
    saveRDS(y, "edgeR_dgelist.rds")
    saveRDS(et, "edgeR_exact_test.rds")
    
    # Generate diagnostic plots
    pdf("edgeR_classic_plots.pdf", width = 7, height = 7)
    tryCatch({
      plotMDS(y, main = "MDS Plot")
    }, error = function(e) {
      warning("Could not generate MDS plot: ", e\$message)
    })
    
    tryCatch({
      plotBCV(y, main = "BCV Plot")
    }, error = function(e) {
      warning("Could not generate BCV plot: ", e\$message)
    })
    dev.off()
    
    cat("Pipeline completed successfully. Outputs written to 'differential_expression_results.csv', 'edgeR_dgelist.rds', 'edgeR_exact_test.rds', and 'edgeR_classic_plots.pdf'.\n")
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

    # dispersion QC plot — file-exists check for any PDF with "disp" or "bcv"
    # in the filename. Pairs with bioc_dispersion_size_factor.
    .dqp_pdfs <- list.files(".", pattern = "(?i)(disp|bcv).*\\.pdf\$")
    .dqp_passes <- length(.dqp_pdfs) > 0
    .gates_by_label[["dispersion QC plot"]] <- list(
      gate_row = "bioc_dispersion_qc_plot",
      metric_name = "dispersion_plot_exists",
      metric_value = if (.dqp_passes) 1 else 0,
      passes = .dqp_passes,
      status = if (.dqp_passes) paste0("computed (", length(.dqp_pdfs), " dispersion PDF(s) emitted)")
               else "not_computed (no dispersion PDF found)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_EDGER_CLASSIC_PIPELINE",
      domain  = "bioconductor",
      declared_qc_steps = c("filter low-expression genes", "dispersion QC plot"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_EDGER_CLASSIC_PIPELINE":',
        paste0('    edgeR: ', as.character(packageVersion('edgeR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_classic_pipeline.csv versions.yml
    """
}

workflow BIOC_EDGER_CLASSIC_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ x ] ]

    main:
    BIOC_EDGER_CLASSIC_PIPELINE(ch_input)

    emit:
    tables   = BIOC_EDGER_CLASSIC_PIPELINE.out.tables
    plots    = BIOC_EDGER_CLASSIC_PIPELINE.out.plots
    objects  = BIOC_EDGER_CLASSIC_PIPELINE.out.objects
    versions = BIOC_EDGER_CLASSIC_PIPELINE.out.versions
}
