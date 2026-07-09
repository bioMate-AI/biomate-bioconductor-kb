#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: tpSVG — covariate_adjusted_model
// Detect spatially variable genes while adjusting for known biological covariates (such as tissue anatomy or cell type composition).
// Input: spe
// Container: quay.io/biocontainers/bioconductor-tpsvg:1.6.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SpatialExperiment, tpSVG
// Visualizations: plot (ggplot/base)
// QC: missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Identify and remove cells/spots with missing covariate data using complete.cases
//  * 2. [Core Analysis] Extract the covariate vector or design matrix
//  * 3. [Core Analysis] Run tpSVG with the covariate matrix X, Poisson family, and log-transformed library size offset

nextflow.enable.dsl = 2

process BIOC_TPSVG_COVARIATE_ADJUSTED_MODEL {
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
    .bm_deps <- c("tpSVG", "SpatialExperiment", "SummarizedExperiment")
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
    library(tpSVG)
    library(SummarizedExperiment)
    library(SpatialExperiment)
    
    # Parse command-line arguments for covariate name
    args <- commandArgs(trailingOnly = TRUE)
    covariate_name <- if (length(args) > 0) args[1] else "covariate"
    
    # 1. Read the user input SpatialExperiment object
    input_file <- "spe.rds"
    if (!file.exists(input_file)) {
      stop(paste("Error: Input file", input_file, "not found in the working directory."))
    }
    
    spe <- readRDS(input_file)
    
    # Ensure the 'total' colData exists (library size), calculate if missing
    if (is.null(spe\$total)) {
      message("'total' column not found in colData. Calculating library size from counts assay...")
      spe\$total <- colSums(assay(spe, "counts"))
    }
    
    # Ensure the specified covariate exists in colData
    if (is.null(spe[[covariate_name]])) {
      stop(paste0("Error: '", covariate_name, "' covariate not found in colData(spe). This covariate is required for the covariate-adjusted model."))
    }
    
    # 2. Identify and remove cells/spots with missing covariate data
    idx_complete_case <- complete.cases(spe[[covariate_name]])
    spe <- spe[, idx_complete_case]
    
    # 3. Extract the covariate vector or design matrix
    x <- spe[[covariate_name]]
    
    # 4. Run tpSVG with the covariate matrix X, Poisson family, and log-transformed library size offset
    message("Running tpSVG covariate-adjusted model...")
    spe_poisson_cov <- tpSVG(
      spe,
      X = x, 
      family = poisson,
      assay_name = "counts",
      offset = log(spe\$total)   # Natural log library size
    )
    
    # 5. Save meaningful results
    # Save the updated SpatialExperiment object
    saveRDS(spe_poisson_cov, "spe_poisson_cov.rds")
    
    # Extract and save the rowData containing test statistics, p-values, and runtimes
    results_df <- as.data.frame(rowData(spe_poisson_cov))
    write.csv(results_df, "tp_svg_covariate_adjusted_results.csv", row.names = TRUE)
    
    # Generate a diagnostic plot of the p-value distribution
    pdf("tp_svg_pvalue_distribution.pdf", width = 6, height = 5)
    if ("raw_p" %in% colnames(results_df)) {
      hist(
        results_df\$raw_p, 
        breaks = 20, 
        col = "skyblue", 
        border = "white",
        main = "P-value Distribution (Covariate-Adjusted tpSVG)",
        xlab = "Raw p-value"
      )
    } else {
      plot.new()
      text(0.5, 0.5, "No raw_p column found in results", cex = 1.2)
    }
    dev.off()
    
    message("Pipeline completed successfully. Outputs saved: 'spe_poisson_cov.rds', 'tp_svg_covariate_adjusted_results.csv', 'tp_svg_pvalue_distribution.pdf'.")
    # ── BIOC_QC_HARNESS — Phase 3c bulk adoption (missing-value handling) ───
    # Defensive scan: list every *.rds the workflow produced, load each one,
    # compute NA fraction across numeric cells where the artifact is a
    # matrix or data.frame. Report max NA fraction across artifacts.
    # Threshold from bioc_missing_value_handling: < 5% pass.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()
    .na_fracs <- numeric(0)
    .scanned_files <- character(0)
    for (.rds_file in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
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
      process = "BIOC_TPSVG_COVARIATE_ADJUSTED_MODEL",
      domain  = "bioconductor",
      declared_qc_steps = c("missing-value handling"),
      gates_by_label = .gates_by_label,
      evidence_tier = "SILVER (Lazar 2013 NAR; <5% community convention)",
      harness_version = "0.1.0-bulk-mv"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_TPSVG_COVARIATE_ADJUSTED_MODEL":',
        paste0('    tpSVG: ', as.character(packageVersion('tpSVG')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_covariate_adjusted_model.csv versions.yml
    """
}

workflow BIOC_TPSVG_COVARIATE_ADJUSTED_MODEL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ spe ] ]

    main:
    BIOC_TPSVG_COVARIATE_ADJUSTED_MODEL(ch_input)

    emit:
    tables   = BIOC_TPSVG_COVARIATE_ADJUSTED_MODEL.out.tables
    plots    = BIOC_TPSVG_COVARIATE_ADJUSTED_MODEL.out.plots
    objects  = BIOC_TPSVG_COVARIATE_ADJUSTED_MODEL.out.objects
    versions = BIOC_TPSVG_COVARIATE_ADJUSTED_MODEL.out.versions
}
