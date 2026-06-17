#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MSPrep — summarized_experiment_pipeline
// Pre-process mass spectrometry metabolomics data stored in a SummarizedExperiment object through summarization, filtering, imputation, and normalization.
// Input: metabolomics_se.rds
// Container: quay.io/biocontainers/bioconductor-msprep:1.20.1--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MSPrep, SummarizedExperiment
// QC: missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Summarize technical replicates using msSummarize()
//  * 2. [Core Analysis] Filter compounds based on presence threshold using msFilter()
//  * 3. [Core Analysis] Impute missing values using msImpute()
//  * 4. [Core Analysis] Transform and normalize data using msNormalize()
//  * 5. [Core Analysis] Alternatively, run the entire pipeline in one step using msPrepare()

nextflow.enable.dsl = 2

process BIOC_MSPREP_SUMMARIZED_EXPERIMENT_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    .bm_deps <- c("MSPrep", "SummarizedExperiment")
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
        l        library(SummarizedExperiment)
ibrary(MSPrep)
        
        # -----------------------------------------------------------------------------
        # 1. Load User Input
        # -----------------------------------------------------------------------------
        # Read the SummarizedExperiment object from the working directory
        COPD_131 <- readRDS("metabolomics_se.rds")
        
        # -----------------------------------------------------------------------------
        # 2. Execute MSPrep Pipeline Steps
        # -----------------------------------------------------------------------------
        
        # Step 2.1: Summarize technical replicates
        summarizedSE131 <- msSummarize(COPD_131,
                                       cvMax = 0.5,
                                       minPropPresent = 1/3,
                                       replicate = "replicate",
                                       returnToSE = TRUE)
        
        # Step 2.2: Filter compounds based on presence threshold
        filteredSE131 <- msFilter(summarizedSE131,
                                  filterPercent = 0.8)
        
        # Step 2.3: Impute missing values using Bayesian PCA (bpca)
        imputedSE131 <- msImpute(filteredSE131,
                                 imputeMethod = "bpca",
                                 nPcs = 3,
                                 missingValue = 0)
        
        # Step 2.4: Transform and normalize data using median normalization
        normalizedSe131 <- msNormalize(imputedSE131,
                                       normalizeMethod = "median",
                                       transform = "none")
        
        # -----------------------------------------------------------------------------
        # 3. Save Outputs
        # -----------------------------------------------------------------------------
        
        # Save intermediate and final SummarizedExperiment objects
        saveRDS(summarizedSE131, "summarized_se.rds")
        saveRDS(filteredSE131, "filtered_se.rds")
        saveRDS(imputedSE131, "imputed_se.rds")
        saveRDS(normalizedSe131, "normalized_se.rds")
        
        # Export final normalized abundances and metadata as CSV tables for downstream analysis
        write.csv(assay(normalizedSe131), "normalized_abundance.csv", row.names = TRUE)
        write.csv(as.data.frame(colData(normalizedSe131)), "sample_metadata.csv", row.names = TRUE)
        write.csv(as.data.frame(rowData(normalizedSe131)), "metabolite_metadata.csv", row.names = TRUE)
        
        # Print completion message
        cat("MSPrep pipeline completed successfully. Outputs saved to working directory.\n")
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
      process = "BIOC_MSPREP_SUMMARIZED_EXPERIMENT_PIPELINE",
      domain  = "bioconductor",
      declared_qc_steps = c("missing-value handling"),
      gates_by_label = .gates_by_label,
      evidence_tier = "SILVER (Lazar 2013 NAR; <5% community convention)",
      harness_version = "0.1.0-bulk-mv"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_MSPREP_SUMMARIZED_EXPERIMENT_PIPELINE":',
        paste0('    MSPrep: ', as.character(packageVersion('MSPrep')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_summarized_experiment_pipeline.csv versions.yml
    """
}

workflow BIOC_MSPREP_SUMMARIZED_EXPERIMENT_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ metabolomics_se.rds ] ]

    main:
    BIOC_MSPREP_SUMMARIZED_EXPERIMENT_PIPELINE(ch_input)

    emit:
    tables   = BIOC_MSPREP_SUMMARIZED_EXPERIMENT_PIPELINE.out.tables
    plots    = BIOC_MSPREP_SUMMARIZED_EXPERIMENT_PIPELINE.out.plots
    objects  = BIOC_MSPREP_SUMMARIZED_EXPERIMENT_PIPELINE.out.objects
    versions = BIOC_MSPREP_SUMMARIZED_EXPERIMENT_PIPELINE.out.versions
}
