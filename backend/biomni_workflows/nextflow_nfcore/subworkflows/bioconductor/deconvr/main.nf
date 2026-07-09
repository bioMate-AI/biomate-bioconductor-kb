#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: deconvR — wgbs_deconvolution
// Map WGBS methylation data to Illumina probe IDs and predict cell-type proportions using a reference atlas.
// Input: WGBS_GRanges.rda, IlluminaMethEpicB5ProbeIDs, HumanCellTypeMethAtlas
// Container: quay.io/biocontainers/bioconductor-deconvr:1.16.0--r45hdfd78af_0
// R packages: GenomicRanges, deconvR
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, deconvR
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the WGBS data and probe ID locations
//  * 2. [Core Analysis] Map WGBS genomic coordinates to probe IDs using BSmeth2Probe
//  * 3. [Core Analysis] Perform deconvolution on the mapped bulk data using deconvolute

nextflow.enable.dsl = 2

process BIOC_DECONVR_WGBS_DECONVOLUTION {
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
    .bm_deps <- c("GenomicRanges", "deconvR")
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
    library(deconvR)
    library(GenomicRanges)
    
    # Helper function to robustly load user input files from the working directory
    # supporting various formats (.rda, .RData, .rds, or no extension)
    load_input <- function(filename, object_name) {
      possible_files <- c(
        filename,
        paste0(filename, ".rda"),
        paste0(filename, ".RData"),
        paste0(filename, ".rds")
      )
      
      loaded <- FALSE
      for (f in possible_files) {
        if (file.exists(f)) {
          if (grepl("\\\\.rds\$", f, ignore.case = TRUE)) {
            assign(object_name, readRDS(f), envir = .GlobalEnv)
            loaded <- TRUE
            message(paste("Successfully loaded", object_name, "from RDS file:", f))
            break
          } else {
            # load() loads into the global environment
            tmp_env <- new.env()
            load(f, envir = tmp_env)
            if (object_name %in% names(tmp_env)) {
              assign(object_name, tmp_env[[object_name]], envir = .GlobalEnv)
              loaded <- TRUE
              message(paste("Successfully loaded", object_name, "from RDA file:", f))
              break
            } else {
              # If the object name doesn't match but there is only one object in the RDA
              objs <- names(tmp_env)
              if (length(objs) == 1) {
                assign(object_name, tmp_env[[objs[1]]], envir = .GlobalEnv)
                loaded <- TRUE
                message(paste("Successfully loaded", object_name, "(originally named", objs[1], ") from RDA file:", f))
                break
              }
            }
          }
        }
      }
      
      if (!loaded) {
        stop(paste("Error: Could not find or load", filename, "as .rda, .RData, or .rds in the working directory."))
      }
    }
    
    # ==========================================
    # STAGE 1: Load WGBS data, probe ID locations, and reference atlas
    # ==========================================
    message("Stage 1: Loading input datasets...")
    
    # Load WGBS_GRanges
    load_input("WGBS_GRanges.rda", "WGBS_GRanges")
    
    # Load IlluminaMethEpicB5ProbeIDs
    load_input("IlluminaMethEpicB5ProbeIDs", "IlluminaMethEpicB5ProbeIDs")
    
    # Load HumanCellTypeMethAtlas
    load_input("HumanCellTypeMethAtlas", "HumanCellTypeMethAtlas")
    
    
    # ==========================================
    # STAGE 2: Map WGBS genomic coordinates to probe IDs using BSmeth2Probe
    # ==========================================
    message("Stage 2: Mapping WGBS genomic coordinates to probe IDs...")
    
    mapped_WGBS_data <- BSmeth2Probe(probe_id_locations = IlluminaMethEpicB5ProbeIDs, 
                                     WGBS_data = WGBS_GRanges,
                                     multipleMapping = TRUE,
                                     cutoff = 10)
    
    # Save mapped WGBS data
    write.csv(mapped_WGBS_data, file = "mapped_WGBS_data.csv", row.names = FALSE)
    saveRDS(mapped_WGBS_data, file = "mapped_WGBS_data.rds")
    message("Mapped WGBS data saved to 'mapped_WGBS_data.csv' and 'mapped_WGBS_data.rds'.")
    
    
    # ==========================================
    # STAGE 3: Perform deconvolution on the mapped bulk data using deconvolute
    # ==========================================
    message("Stage 3: Performing cell-type deconvolution...")
    
    deconvolution <- deconvolute(reference = HumanCellTypeMethAtlas, 
                                 bulk = mapped_WGBS_data)
    
    # Extract and save predicted proportions
    proportions <- deconvolution\$proportions
    write.csv(proportions, file = "predicted_proportions.csv", row.names = TRUE)
    message("Predicted cell-type proportions saved to 'predicted_proportions.csv'.")
    
    # Save full deconvolution results object (which includes partial R-squared values)
    saveRDS(deconvolution, file = "deconvolution_results.rds")
    message("Full deconvolution results object saved to 'deconvolution_results.rds'.")
    
    message("Pipeline completed successfully.")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # array detection QC — ExpressionSet detection p-values or detection-column data.frame.
    .adq_rate <- NA_real_
    for (.adq_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
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
    for (.lcf_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
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
      process = "BIOC_DECONVR_WGBS_DECONVOLUTION",
      domain  = "bioconductor",
      declared_qc_steps = c("array detection QC", "alignment/mapping QC", "low-count filtering"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_DECONVR_WGBS_DECONVOLUTION":',
        paste0('    deconvR: ', as.character(packageVersion('deconvR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_wgbs_deconvolution.csv versions.yml
    """
}

workflow BIOC_DECONVR_WGBS_DECONVOLUTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ WGBS_GRanges.rda, IlluminaMethEpicB5ProbeIDs, HumanCellTypeMethAtlas ] ]

    main:
    BIOC_DECONVR_WGBS_DECONVOLUTION(ch_input)

    emit:
    tables   = BIOC_DECONVR_WGBS_DECONVOLUTION.out.tables
    plots    = BIOC_DECONVR_WGBS_DECONVOLUTION.out.plots
    objects  = BIOC_DECONVR_WGBS_DECONVOLUTION.out.objects
    versions = BIOC_DECONVR_WGBS_DECONVOLUTION.out.versions
}
