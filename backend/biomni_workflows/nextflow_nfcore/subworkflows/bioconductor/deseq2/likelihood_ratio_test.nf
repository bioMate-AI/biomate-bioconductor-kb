#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DESeq2 — likelihood_ratio_test
// Perform a Likelihood Ratio Test (LRT) to identify genes with significant changes across multi-level factors or time-series.
// Input: dds
// Container: quay.io/biocontainers/bioconductor-deseq2:1.50.2--r45ha27e39d_0
// R packages: DESeq2
// Bioconductor: 3.20 | R: 4.4
// Requires: DESeq2
// Visualizations: MA plot
// QC: diagnostic MA/PCA QC
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run DESeq() with LRT test and specify a reduced design formula
//  * 2. [Core Analysis] Extract results

nextflow.enable.dsl = 2

process BIOC_DESEQ2_LIKELIHOOD_RATIO_TEST {
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
    .bm_deps <- c("DESeq2")
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
    library(DESeq2)
    
    # Read user input
    if (file.exists("dds")) {
      dds <- readRDS("dds")
    } else if (file.exists("dds.rds")) {
      dds <- readRDS("dds.rds")
    } else {
      stop("Input file 'dds' or 'dds.rds' not found in the working directory.")
    }
    
    # Execute documented workflow
    dds <- DESeq(dds, test="LRT", reduced=~1)
    res <- results(dds)
    
    # Write outputs
    # 1. CSV table of results
    write.csv(as.data.frame(res), file = "lrt_results.csv", row.names = TRUE)
    
    # 2. RDS of the processed dds and results
    saveRDS(dds, file = "dds_lrt_processed.rds")
    saveRDS(res, file = "res_lrt_processed.rds")
    
    # 3. Diagnostic plots
    pdf("lrt_plots.pdf", width = 7, height = 7)
    plotMA(res, main = "Likelihood Ratio Test (LRT) - MA Plot")
    if (!is.null(res\$pvalue)) {
      hist(res\$pvalue, breaks = 50, col = "skyblue", border = "white",
           xlab = "p-value", main = "P-value Distribution")
    }
    dev.off()
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # diagnostic MA/PCA QC — PC1 variance explained on any large matrix.
    # Pass when PC1 > 10% (Risso 2014 RUV-seq diagnostic).
    .pca_pc1 <- NA_real_; .pca_files <- character(0)
    for (.pca_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
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

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_DESEQ2_LIKELIHOOD_RATIO_TEST",
      domain  = "bioconductor",
      declared_qc_steps = c("diagnostic MA/PCA QC"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_DESEQ2_LIKELIHOOD_RATIO_TEST":',
        paste0('    DESeq2: ', as.character(packageVersion('DESeq2')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_likelihood_ratio_test.csv versions.yml
    """
}

workflow BIOC_DESEQ2_LIKELIHOOD_RATIO_TEST_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ dds ] ]

    main:
    BIOC_DESEQ2_LIKELIHOOD_RATIO_TEST(ch_input)

    emit:
    tables   = BIOC_DESEQ2_LIKELIHOOD_RATIO_TEST.out.tables
    plots    = BIOC_DESEQ2_LIKELIHOOD_RATIO_TEST.out.plots
    objects  = BIOC_DESEQ2_LIKELIHOOD_RATIO_TEST.out.objects
    versions = BIOC_DESEQ2_LIKELIHOOD_RATIO_TEST.out.versions
}
