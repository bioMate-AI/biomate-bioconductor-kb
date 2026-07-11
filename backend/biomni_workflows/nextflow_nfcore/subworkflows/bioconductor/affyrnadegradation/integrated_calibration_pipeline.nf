#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: AffyRNADegradation — integrated_calibration_pipeline
// Perform probe-level normalization using VSN, correct for probe positional bias, and compute summarized expression measures.
// Input: AmpData
// Container: quay.io/biocontainers/bioconductor-affyrnadegradation:1.56.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: AffyRNADegradation, Biobase, affy, vsn
// Visualizations: box plot
// QC: variance-stabilizing normalization
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Normalize raw AffyBatch data using VSN
//  * 2. [Core Analysis] Correct for probe positional bias on the normalized data
//  * 3. [Visualization & Output] Summarize probe intensities into expression sets using median polish

nextflow.enable.dsl = 2

process BIOC_AFFYRNADEGRADATION_INTEGRATED_CALIBRATION_PIPELINE {
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
    .bm_deps <- c("AffyRNADegradation", "affy", "vsn", "Biobase")
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
    library(AffyRNADegradation)
    library(affy)
    library(vsn)
    library(Biobase)
    
    # 1. Read the input AmpData object from the working directory
    if (file.exists("AmpData.rds")) {
      AmpData <- readRDS("AmpData.rds")
    } else if (file.exists("AmpData.RData")) {
      env <- new.env()
      load("AmpData.RData", envir = env)
      if ("AmpData" %in% names(env)) {
        AmpData <- env\$AmpData
      } else {
        load("AmpData.RData")
      }
    } else {
      stop("Error: Required input file 'AmpData.rds' or 'AmpData.RData' not found in the working directory.")
    }
    
    # Verify that the loaded object is of class AffyBatch
    if (!inherits(AmpData, "AffyBatch")) {
      stop("Error: Loaded object 'AmpData' is not of class 'AffyBatch'.")
    }
    
    # 2. Normalize raw AffyBatch data using VSN
    # (Reproducing the exact documented call)
    affydata.vsn <- do.call(affy:::normalize, c(alist(AmpData, "vsn"), NULL))
    
    # 3. Correct for probe positional bias on the normalized data
    # (Reproducing the exact documented call)
    affydata.vsn <- afbatch(RNADegradation(affydata.vsn))
    
    # 4. Summarize probe intensities into expression sets using median polish
    # (Reproducing the exact documented call)
    expr <- computeExprSet(affydata.vsn, summary.method="medianpolish", pmcorrect.method="pmonly")
    
    # 5. Write outputs to the working directory
    # Save the complete ExpressionSet object
    saveRDS(expr, file = "normalized_expression_set.rds")
    
    # Export the expression matrix as a CSV file
    expr_matrix <- exprs(expr)
    write.csv(expr_matrix, file = "expression_matrix.csv", row.names = TRUE)
    
    # Generate a diagnostic boxplot of the normalized and corrected expression values
    pdf("expression_summary.pdf", width = 8, height = 6)
    boxplot(expr_matrix, 
            main = "VSN Normalized & Positional Bias Corrected Expression",
            las = 2, 
            col = "skyblue", 
            ylab = "Log2 Intensity")
    dev.off()
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # VSN — DESeqTransform / vsd matrix; mean-SD slope ≤ 0.5 (vsn::meanSdPlot).
    .vsn_slope <- NA_real_
    for (.vsn_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
      .vsn_obj <- tryCatch(readRDS(.vsn_rds), error = function(e) NULL)
      .vsn_mat <- NULL
      if (!is.null(.vsn_obj)) {
        if (inherits(.vsn_obj, "DESeqTransform") || inherits(.vsn_obj, "SummarizedExperiment")) {
          .vsn_mat <- tryCatch(assay(.vsn_obj), error = function(e) NULL)
        } else if (is.matrix(.vsn_obj)) { .vsn_mat <- .vsn_obj }
      }
      if (!is.null(.vsn_mat) && nrow(.vsn_mat) > 100) {
        .vsn_rmean <- suppressWarnings(rowMeans(.vsn_mat, na.rm = TRUE))
        .vsn_rsd <- suppressWarnings(apply(.vsn_mat, 1, sd, na.rm = TRUE))
        .vsn_ok <- is.finite(.vsn_rmean) & is.finite(.vsn_rsd)
        if (sum(.vsn_ok) > 50) {
          .vsn_fit <- tryCatch(lm(.vsn_rsd[.vsn_ok] ~ .vsn_rmean[.vsn_ok]), error = function(e) NULL)
          if (!is.null(.vsn_fit)) { .vsn_slope <- round(abs(coef(.vsn_fit)[2]), 4); break }
        }
      }
    }
    .gates_by_label[["variance-stabilizing normalization"]] <- list(
      gate_row = "bioc_vsn_normalization",
      metric_name = "mean_sd_slope_after_vsn",
      metric_value = .vsn_slope,
      passes = isTRUE(is.finite(.vsn_slope) && .vsn_slope <= 0.5),
      status = if (is.finite(.vsn_slope)) "computed (lm slope row-SD ~ row-mean)"
               else "not_computed (no DESeqTransform/vsd .rds present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_AFFYRNADEGRADATION_INTEGRATED_CALIBRATION_PIPELINE",
      domain  = "bioconductor",
      declared_qc_steps = c("variance-stabilizing normalization"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_AFFYRNADEGRADATION_INTEGRATED_CALIBRATION_PIPELINE":',
        paste0('    AffyRNADegradation: ', as.character(packageVersion('AffyRNADegradation')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_integrated_calibration_pipeline.csv versions.yml
    """
}

workflow BIOC_AFFYRNADEGRADATION_INTEGRATED_CALIBRATION_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ AmpData ] ]

    main:
    BIOC_AFFYRNADEGRADATION_INTEGRATED_CALIBRATION_PIPELINE(ch_input)

    emit:
    tables   = BIOC_AFFYRNADEGRADATION_INTEGRATED_CALIBRATION_PIPELINE.out.tables
    plots    = BIOC_AFFYRNADEGRADATION_INTEGRATED_CALIBRATION_PIPELINE.out.plots
    objects  = BIOC_AFFYRNADEGRADATION_INTEGRATED_CALIBRATION_PIPELINE.out.objects
    versions = BIOC_AFFYRNADEGRADATION_INTEGRATED_CALIBRATION_PIPELINE.out.versions
}
