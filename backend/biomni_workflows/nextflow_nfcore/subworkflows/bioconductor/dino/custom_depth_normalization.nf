#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Dino — custom_depth_normalization
// Normalize a UMI count matrix using Dino with custom sequencing depths calculated via Scran size factors.
// Input: pbmcSmall
// Container: quay.io/biocontainers/bioconductor-dino:1.16.0--r45hdfd78af_0
// R packages: Dino, Matrix, scran
// Bioconductor: 3.20 | R: 4.4
// Requires: Dino, Matrix, scran
// QC: low-count filtering
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Compute size factors using Scran's calculateSumFactors
//  * 2. [Core Analysis] Run Dino normalization with the depth parameter set to the log of the computed size factors

nextflow.enable.dsl = 2

process BIOC_DINO_CUSTOM_DEPTH_NORMALIZATION {
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
    .bm_deps <- c("Dino", "Matrix", "scran")
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
    library(Dino)
    library(scran)
    library(Matrix)
    
    # -----------------------------------------------------------------------------
    # Stage 0: Read User Input
    # -----------------------------------------------------------------------------
    # The pipeline expects 'pbmcSmall' as a raw UMI count matrix in the working directory.
    # We support RDS, CSV, or TSV formats.
    if (file.exists("pbmcSmall.rds")) {
      pbmcSmall <- readRDS("pbmcSmall.rds")
    } else if (file.exists("pbmcSmall.csv")) {
      pbmcSmall <- read.csv("pbmcSmall.csv", row.names = 1, check.names = FALSE)
      pbmcSmall <- as.matrix(pbmcSmall)
    } else if (file.exists("pbmcSmall.tsv")) {
      pbmcSmall <- read.delim("pbmcSmall.tsv", row.names = 1, check.names = FALSE)
      pbmcSmall <- as.matrix(pbmcSmall)
    } else if (file.exists("pbmcSmall")) {
      # Attempt to read as RDS if no extension is provided
      pbmcSmall <- readRDS("pbmcSmall")
    } else {
      stop("Error: Input file 'pbmcSmall' (RDS, CSV, or TSV format) not found in the working directory.")
    }
    
    # Ensure the input is in a matrix-like format
    if (is.data.frame(pbmcSmall)) {
      pbmcSmall <- as.matrix(pbmcSmall)
    }
    
    # Optional but highly recommended pre-filtering step from the vignette:
    # Filter genes lacking a minimum of non-zero expression (at least 20 non-zero samples)
    pbmcSmall <- pbmcSmall[rowSums(pbmcSmall != 0) >= 20, ]
    
    # -----------------------------------------------------------------------------
    # Stage 1: Compute size factors using Scran's calculateSumFactors
    # -----------------------------------------------------------------------------
    scranSizes <- calculateSumFactors(pbmcSmall)
    
    # -----------------------------------------------------------------------------
    # Stage 2: Run Dino normalization with custom sequencing depths
    # -----------------------------------------------------------------------------
    pbmcSmall_SNorm <- Dino(pbmcSmall, nCores = 1, depth = log(scranSizes))
    
    # -----------------------------------------------------------------------------
    # Stage 3: Write Outputs
    # -----------------------------------------------------------------------------
    # Save the normalized matrix as an RDS object
    saveRDS(pbmcSmall_SNorm, "pbmcSmall_SNorm.rds")
    
    # Save the normalized matrix as a CSV file
    # Since Dino outputs a sparse matrix by default, we convert it to a dense matrix for CSV export
    write.csv(as.matrix(pbmcSmall_SNorm), "pbmcSmall_SNorm.csv", row.names = TRUE)
    
    # Save the computed scran size factors
    size_factors_df <- data.frame(
      Cell = colnames(pbmcSmall),
      ScranSizeFactor = scranSizes,
      LogScranSizeFactor = log(scranSizes)
    )
    write.csv(size_factors_df, "scran_size_factors.csv", row.names = FALSE)
    
    cat("Pipeline completed successfully. Outputs written to 'pbmcSmall_SNorm.rds', 'pbmcSmall_SNorm.csv', and 'scran_size_factors.csv'.\n")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

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
      process = "BIOC_DINO_CUSTOM_DEPTH_NORMALIZATION",
      domain  = "bioconductor",
      declared_qc_steps = c("low-count filtering"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_DINO_CUSTOM_DEPTH_NORMALIZATION":',
        paste0('    Dino: ', as.character(packageVersion('Dino')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_custom_depth_normalization.csv versions.yml
    """
}

workflow BIOC_DINO_CUSTOM_DEPTH_NORMALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pbmcSmall ] ]

    main:
    BIOC_DINO_CUSTOM_DEPTH_NORMALIZATION(ch_input)

    emit:
    tables   = BIOC_DINO_CUSTOM_DEPTH_NORMALIZATION.out.tables
    plots    = BIOC_DINO_CUSTOM_DEPTH_NORMALIZATION.out.plots
    objects  = BIOC_DINO_CUSTOM_DEPTH_NORMALIZATION.out.objects
    versions = BIOC_DINO_CUSTOM_DEPTH_NORMALIZATION.out.versions
}
