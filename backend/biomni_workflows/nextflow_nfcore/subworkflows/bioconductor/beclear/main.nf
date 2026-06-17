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

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20-slim"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
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
