#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: BEclear — step_by_step_batch_correction
// Detect, score, and correct batch effects in DNA methylation data using a step-by-step manual workflow.
// Input: beta_values.csv, sample_metadata.csv
// Container: quay.io/biocontainers/bioconductor-beclear:2.26.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BEclear, ids
// Visualizations: plot (ggplot/base)
// QC: missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Calculate batch effects (median differences and p-values) using calcBatchEffects
//  * 2. [Visualization & Output] Summarize batch-affected gene-sample combinations using calcSummary
//  * 3. [Core Analysis] Calculate batch severity scores using calcScore
//  * 4. [Core Analysis] Set batch-affected values to NA using clearBEgenes
//  * 5. [Core Analysis] Impute the missing values using block-based stochastic gradient descent with imputeMissingData
//  * 6. [Core Analysis] Correct out-of-bounds predicted values using replaceOutsideValues
//  * 7. [Visualization & Output] Visualize the distributions before and after correction using makeBoxplot

nextflow.enable.dsl = 2

process BIOC_BECLEAR_STEP_BY_STEP_BATCH_CORRECTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20"

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
    .bm_deps <- c("BEclear", "ids")
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
    library(BEclear)
    library(ids)
    
    # ---------------------------------------------------------
    # 1. Read User Input Files
    # ---------------------------------------------------------
    # Read the beta values matrix (genes/probes as rows, samples as columns)
    ex.data <- as.matrix(read.csv("beta_values.csv", row.names = 1, check.names = FALSE))
    
    # Read the sample metadata (must contain sample_id and batch_id)
    ex.samples <- read.csv("sample_metadata.csv", stringsAsFactors = FALSE)
    
    # Ensure the columns of ex.samples are correctly formatted and ordered
    # The first column must be "sample_id" and the second "batch_id"
    ex.samples <- ex.samples[, c("sample_id", "batch_id")]
    
    # ---------------------------------------------------------
    # 2. Step-by-Step Batch Correction Workflow
    # ---------------------------------------------------------
    
    # Step 2.1: Calculate batch effects (median differences and p-values)
    batchEffect <- calcBatchEffects(
      data = ex.data, samples = ex.samples,
      adjusted = TRUE, method = "fdr"
    )
    mdifs <- batchEffect\$med
    pvals <- batchEffect\$pval
    
    # Step 2.2: Summarize batch-affected gene-sample combinations
    summary <- calcSummary(medians = mdifs, pvalues = pvals)
    
    # Step 2.3: Calculate batch severity scores
    score <- calcScore(ex.data, ex.samples, summary, dir = getwd())
    
    # Step 2.4: Set batch-affected values to NA
    cleared.data <- clearBEgenes(ex.data, ex.samples, summary)
    
    # Step 2.5: Impute the missing values using block-based stochastic gradient descent
    corrected.data <- imputeMissingData(cleared.data,
      rowBlockSize = 60,
      colBlockSize = 60, epochs = 50,
      outputFormat = "", dir = getwd()
    )
    
    # Step 2.6: Correct out-of-bounds predicted values (outside [0, 1])
    corrected.data.valid <- replaceOutsideValues(corrected.data)
    
    # ---------------------------------------------------------
    # 3. Save Outputs
    # ---------------------------------------------------------
    
    # Save tabular results
    write.csv(summary, "batch_effects_summary.csv", row.names = FALSE)
    write.csv(score, "batch_scores.csv", row.names = FALSE)
    write.csv(corrected.data.valid, "corrected_beta_values.csv", row.names = TRUE)
    saveRDS(corrected.data.valid, "corrected_beta_values.rds")
    
    # Step 2.7: Visualize the distributions before and after correction
    pdf("batch_correction_plots.pdf", width = 10, height = 7)
    
    # Plot before correction
    makeBoxplot(ex.data, ex.samples, score,
      bySamples = TRUE,
      col = "standard", main = "Example data", xlab = "Batch",
      ylab = "Beta value", scoreCol = TRUE)
    
    # Plot after correction
    makeBoxplot(corrected.data, ex.samples, score,
      bySamples = TRUE,
      col = "standard", main = "Corrected example data",
      xlab = "Batch", ylab = "Beta value", scoreCol = FALSE)
    
    dev.off()
    # ── BIOC_QC_HARNESS — Phase 3c bulk adoption (missing-value handling) ───
    # Defensive scan: list every *.rds the workflow produced, load each one,
    # compute NA fraction across numeric cells where the artifact is a
    # matrix or data.frame. Report max NA fraction across artifacts.
    # Threshold from bioc_missing_value_handling: < 5% pass.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()
    .na_fracs <- numeric(0)
    .scanned_files <- character(0)
    for (.rds_file in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .obj <- tryCatch(readRDS(.rds_file), error = function(e) NULL)
      .mat <- if (is.matrix(.obj) || is.data.frame(.obj)) .obj else NULL
      if (!is.null(.mat)) {
        .vals <- suppressWarnings(as.numeric(as.matrix(.mat)))
        if (length(.vals) > 0) {
          .na_fracs <- c(.na_fracs, mean(is.na(.vals)))
          .scanned_files <- c(.scanned_files, .rds_file)
        }
      }
    }
    .na_max <- if (length(.na_fracs) > 0) round(max(.na_fracs), 4) else NA_real_
    .gates_by_label[["missing-value handling"]] <- list(
      gate_row = "bioc_missing_value_handling",
      metric_name = "na_fraction_remaining",
      metric_value = .na_max,
      passes = isTRUE(is.finite(.na_max) && .na_max < 0.05),
      status = if (is.finite(.na_max)) paste0("computed (scanned ", length(.scanned_files), " rds files)")
               else "not_computed (no matrix/data.frame .rds artifact present)"
    )
    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_BECLEAR_STEP_BY_STEP_BATCH_CORRECTION",
      domain  = "bioconductor",
      declared_qc_steps = c("missing-value handling"),
      gates_by_label = .gates_by_label,
      evidence_tier = "SILVER (Lazar 2013 NAR; <5% community convention)",
      harness_version = "0.1.0-bulk-mv"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_BECLEAR_STEP_BY_STEP_BATCH_CORRECTION":',
        paste0('    BEclear: ', as.character(packageVersion('BEclear')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_step_by_step_batch_correction.csv versions.yml
    """
}

workflow BIOC_BECLEAR_STEP_BY_STEP_BATCH_CORRECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ beta_values.csv, sample_metadata.csv ] ]

    main:
    BIOC_BECLEAR_STEP_BY_STEP_BATCH_CORRECTION(ch_input)

    emit:
    tables   = BIOC_BECLEAR_STEP_BY_STEP_BATCH_CORRECTION.out.tables
    plots    = BIOC_BECLEAR_STEP_BY_STEP_BATCH_CORRECTION.out.plots
    objects  = BIOC_BECLEAR_STEP_BY_STEP_BATCH_CORRECTION.out.objects
    versions = BIOC_BECLEAR_STEP_BY_STEP_BATCH_CORRECTION.out.versions
}
