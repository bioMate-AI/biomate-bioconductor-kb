#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DESeq2 — multi_factor_analysis
// Perform differential expression analysis controlling for additional batch or technical covariates.
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
//  * 1. [Core Analysis] Update design formula to include covariates
//  * 2. [Core Analysis] Run DESeq() pipeline
//  * 3. [Core Analysis] Extract results for the primary condition
//  * 4. [Core Analysis] Extract results for the covariate using contrasts

nextflow.enable.dsl = 2

process BIOC_DESEQ2_MULTI_FACTOR_ANALYSIS {
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
    .bm_deps <- c("DESeq2", "SummarizedExperiment")
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
     library(SummarizedExperiment)
   library(DESeq2)
    
    # Locate and read the user input file
    input_file <- "dds"
    if (!file.exists(input_file) && file.exists("dds.rds")) {
      input_file <- "dds.rds"
    }
    
    if (!file.exists(input_file)) {
      stop("Error: Input file 'dds' or 'dds.rds' not found in the working directory.")
    }
    
    # Load the DESeqDataSet object
    ddsMF <- readRDS(input_file)
    
    # 1. Extract design variables from the existing design formula
    design_vars <- all.vars(design(ddsMF))
    if (length(design_vars) < 2) {
      stop("Error: The design formula must contain at least two variables for multi-factor analysis.")
    }
    covariate <- design_vars[length(design_vars) - 1]
    primary_condition <- design_vars[length(design_vars)]
    
    # 2. Run DESeq() pipeline
    ddsMF <- DESeq(ddsMF)
    
    # 3. Extract results for the primary condition
    resMF <- results(ddsMF)
    
    # 4. Extract results for the covariate using contrasts
    covariate_levels <- levels(as.factor(colData(ddsMF)[[covariate]]))
    resMFType <- results(ddsMF,
                         contrast=c(covariate, covariate_levels[2], covariate_levels[1]))
    
    # Write meaningful output files
    # Save results tables as CSV
    write.csv(as.data.frame(resMF), file = paste0("results_multi_factor_", primary_condition, ".csv"), row.names = TRUE)
    write.csv(as.data.frame(resMFType), file = paste0("results_multi_factor_", covariate, ".csv"), row.names = TRUE)
    
    # Save the updated DESeqDataSet object
    saveRDS(ddsMF, file = "ddsMF_analyzed.rds")
    
    # Generate diagnostic MA-plots
    pdf("multi_factor_plots.pdf", width = 10, height = 5)
    par(mfrow = c(1, 2))
    plotMA(resMF, main = "MA-plot: Primary Condition")
    plotMA(resMFType, main = paste0("MA-plot: Covariate (", covariate, ")"))
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
      process = "BIOC_DESEQ2_MULTI_FACTOR_ANALYSIS",
      domain  = "bioconductor",
      declared_qc_steps = c("diagnostic MA/PCA QC"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_DESEQ2_MULTI_FACTOR_ANALYSIS":',
        paste0('    DESeq2: ', as.character(packageVersion('DESeq2')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multi_factor_analysis.csv versions.yml
    """
}

workflow BIOC_DESEQ2_MULTI_FACTOR_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ dds ] ]

    main:
    BIOC_DESEQ2_MULTI_FACTOR_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_DESEQ2_MULTI_FACTOR_ANALYSIS.out.tables
    plots    = BIOC_DESEQ2_MULTI_FACTOR_ANALYSIS.out.plots
    objects  = BIOC_DESEQ2_MULTI_FACTOR_ANALYSIS.out.objects
    versions = BIOC_DESEQ2_MULTI_FACTOR_ANALYSIS.out.versions
}
