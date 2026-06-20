#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: BEAT — single_cell_epimutation_analysis
// Quantify DNA methylation and call regional epimutations from single-cell bisulfite sequencing data compared to a reference sample.
// Input: reference.positions.csv, sample.positions.csv
// Container: quay.io/biocontainers/bioconductor-beat:1.48.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BEAT
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the package and define the local path and sample parameters using makeParams
//  * 2. [Core Analysis] Pool individual CpG counts into genomic regions using positions_to_regions
//  * 3. [Core Analysis] Model regional methylation rates and correct for experimental biases using generate_results
//  * 4. [Core Analysis] Call methylating and demethylating epimutations using epimutation_calls

nextflow.enable.dsl = 2

process BIOC_BEAT_SINGLE_CELL_EPIMUTATION_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20-slim"

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
    .bm_deps <- c("BEAT")
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
    
    # Load the required BEAT library
    library(BEAT)
    
    # Define the local path as the current working directory where the user input files are located
    localpath <- getwd()
    
    # Verify that the required user input files exist in the working directory
    required_files <- c("reference.positions.csv", "sample.positions.csv")
    missing_files <- required_files[!file.exists(file.path(localpath, required_files))]
    if (length(missing_files) > 0) {
      stop(paste("Missing required input file(s):", paste(missing_files, collapse = ", ")))
    }
    
    # Read and display the first few rows of the single-cell sample positions
    positions <- read.csv(file.path(localpath, "sample.positions.csv"))
    cat("--- First few rows of sample.positions.csv ---\n")
    print(head(positions))
    
    # Define sample names and reference status
    sampNames <- c('reference', 'sample')
    is.reference <- c(TRUE, FALSE)
    
    # Define conversion rates based on false positive rates (pplus)
    pplus <- c(0.2, 0.5)
    convrates <- 1 - pplus
    
    # Create the parameter object for the BEAT pipeline
    params <- makeParams(
      localpath = localpath,
      sampNames = sampNames,
      convrates = convrates,
      is.reference = is.reference,
      pminus = 0.2,
      regionSize = 10000,
      minCounts = 5
    )
    
    cat("\n--- Parameter Configuration ---\n")
    print(params)
    
    # Step 1: Pool individual CpG counts into genomic regions
    cat("\n--- Pooling CpG counts into regions ---\n")
    positions_to_regions(params)
    
    # Step 2: Model regional methylation rates and correct for experimental biases
    cat("\n--- Modeling regional methylation rates ---\n")
    generate_results(params)
    
    # Step 3: Call methylating and demethylating epimutations
    cat("\n--- Calling epimutations ---\n")
    epiCalls <- epimutation_calls(params)
    
    # Display the head of the epimutation calls if available
    cat("\n--- Methylating Epimutation Sites (First 3) ---\n")
    print(head(epiCalls\$methSites\$singlecell, 3))
    
    cat("\n--- Demethylating Epimutation Sites (First 3) ---\n")
    print(head(epiCalls\$demethSites\$singlecell, 3))
    
    # Save the final epimutation calls object to an RDS file for downstream analysis
    output_rds <- file.path(localpath, "epimutation_calls_results.rds")
    saveRDS(epiCalls, file = output_rds)
    cat(paste("\nPipeline completed successfully. Results saved to:", output_rds, "\n"))
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # array detection QC — ExpressionSet detection p-values or detection-column data.frame.
    .adq_rate <- NA_real_
    for (.adq_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .adq_obj <- tryCatch(readRDS(.adq_rds), error = function(e) NULL)
      .adq_pv <- NULL
      if (!is.null(.adq_obj)) {
        if (inherits(.adq_obj, "ExpressionSet")) {
          .adq_pv <- tryCatch(Biobase::assayDataElement(.adq_obj, "Detection"), error = function(e) NULL)
        } else if (is.matrix(.adq_obj) || is.data.frame(.adq_obj)) {
          .adq_cols <- grep("(?i)(detection|pvalue|pval)", colnames(.adq_obj), value = TRUE)
          if (length(.adq_cols) > 0) .adq_pv <- as.matrix(.adq_obj[, .adq_cols, drop = FALSE])
        }
      }
      if (!is.null(.adq_pv) && length(.adq_pv) > 0) {
        .adq_rate <- round(mean(as.numeric(.adq_pv) < 0.05, na.rm = TRUE), 4); break
      }
    }
    .gates_by_label[["array detection QC"]] <- list(
      gate_row = "bioc_array_detection_qc",
      metric_name = "detection_rate",
      metric_value = .adq_rate,
      passes = isTRUE(is.finite(.adq_rate) && .adq_rate >= 0.75),
      status = if (is.finite(.adq_rate)) "computed (probe-detection p<0.05 fraction)"
               else "not_computed (no ExpressionSet/detection-p .rds present)"
    )

    # alignment/mapping QC — workflow-emitted artifact check for common log
    # files (.log, .summary, alignment metrics tables). Binary pass.
    .amqc_logs <- c(list.files(".", pattern = "(?i)(align|map|samtools|flagstat).*\\.(log|txt|summary)\$"),
                    list.files(".", pattern = "(?i)flagstat\\."))
    .amqc_passes <- length(.amqc_logs) > 0
    .gates_by_label[["alignment/mapping QC"]] <- list(
      gate_row = "bioc_alignment_mapping_qc",
      metric_name = "alignment_qc_artifacts",
      metric_value = length(.amqc_logs),
      passes = .amqc_passes,
      status = if (.amqc_passes) paste0("computed (", length(.amqc_logs), " alignment log(s) emitted)")
               else "not_computed (no alignment log/summary artifact present)"
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
      process = "BIOC_BEAT_SINGLE_CELL_EPIMUTATION_ANALYSIS",
      domain  = "bioconductor",
      declared_qc_steps = c("array detection QC", "alignment/mapping QC", "low-count filtering"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_BEAT_SINGLE_CELL_EPIMUTATION_ANALYSIS":',
        paste0('    BEAT: ', as.character(packageVersion('BEAT')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_cell_epimutation_analysis.csv versions.yml
    """
}

workflow BIOC_BEAT_SINGLE_CELL_EPIMUTATION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ reference.positions.csv, sample.positions.csv ] ]

    main:
    BIOC_BEAT_SINGLE_CELL_EPIMUTATION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_BEAT_SINGLE_CELL_EPIMUTATION_ANALYSIS.out.tables
    plots    = BIOC_BEAT_SINGLE_CELL_EPIMUTATION_ANALYSIS.out.plots
    objects  = BIOC_BEAT_SINGLE_CELL_EPIMUTATION_ANALYSIS.out.objects
    versions = BIOC_BEAT_SINGLE_CELL_EPIMUTATION_ANALYSIS.out.versions
}
