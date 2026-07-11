#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: PECA — peca_microarray_affy
// Identify differential gene expression from Affymetrix microarray probe-level data.
// Input: SpikeIn133
// Container: quay.io/biocontainers/bioconductor-peca:1.42.0--r44hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: PECA, affy
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Subset or prepare the AffyBatch object
//  * 2. [Core Analysis] Run PECA on the AffyBatch object using PECA_AffyBatch

nextflow.enable.dsl = 2

process BIOC_PECA_PECA_MICROARRAY_AFFY {
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
    .bm_deps <- c("PECA", "affy")
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
    library(PECA)
    library(affy)
    
    # Read the user input file 'SpikeIn133' from the working directory.
    # We handle cases where it might be saved as an RDS or RData file, with or without extension.
    input_path <- "SpikeIn133"
    if (file.exists(input_path)) {
      SpikeIn133 <- tryCatch({
        readRDS(input_path)
      }, error = function(e) {
        env <- new.env()
        load(input_path, envir = env)
        if (exists("SpikeIn133", envir = env)) {
          get("SpikeIn133", envir = env)
        } else {
          get(ls(env)[1], envir = env)
        }
      })
    } else if (file.exists("SpikeIn133.rds")) {
      SpikeIn133 <- readRDS("SpikeIn133.rds")
    } else if (file.exists("SpikeIn133.RData")) {
      env <- new.env()
      load("SpikeIn133.RData", envir = env)
      if (exists("SpikeIn133", envir = env)) {
        SpikeIn133 <- env\$SpikeIn133
      } else {
        SpikeIn133 <- env[[ls(env)[1]]]
      }
    } else {
      stop("Required input file 'SpikeIn133' not found in the working directory.")
    }
    
    # 1. Subset or prepare the AffyBatch object
    data <- SpikeIn133[,c(1,15,29,2,16,30)]
    
    # 2. Run PECA on the AffyBatch object using PECA_AffyBatch
    results <- PECA_AffyBatch(normalize="true", affy=data)
    
    # Write meaningful results to output files
    write.csv(results, file = "peca_results.csv", row.names = TRUE)
    saveRDS(results, file = "peca_results.rds")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # between-array norm — file-exists check for post-norm QC PDFs.
    .ban_pdfs <- list.files(".", pattern = "(?i)(boxplot|density|qnorm|norm.*array).*\\.pdf\$")
    .ban_passes <- length(.ban_pdfs) > 0
    .gates_by_label[["between-array normalization"]] <- list(
      gate_row = "bioc_count_normalization",
      metric_name = "between_array_norm_plot_exists",
      metric_value = if (.ban_passes) 1 else 0,
      passes = .ban_passes,
      status = if (.ban_passes) paste0("computed (", length(.ban_pdfs), " PDF(s) emitted)")
               else "not_computed (no between-array QC PDF present)"
    )

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
      process = "BIOC_PECA_PECA_MICROARRAY_AFFY",
      domain  = "bioconductor",
      declared_qc_steps = c("between-array normalization", "array detection QC", "low-count filtering"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_PECA_PECA_MICROARRAY_AFFY":',
        paste0('    PECA: ', as.character(packageVersion('PECA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_peca_microarray_affy.csv versions.yml
    """
}

workflow BIOC_PECA_PECA_MICROARRAY_AFFY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ SpikeIn133 ] ]

    main:
    BIOC_PECA_PECA_MICROARRAY_AFFY(ch_input)

    emit:
    tables   = BIOC_PECA_PECA_MICROARRAY_AFFY.out.tables
    plots    = BIOC_PECA_PECA_MICROARRAY_AFFY.out.plots
    objects  = BIOC_PECA_PECA_MICROARRAY_AFFY.out.objects
    versions = BIOC_PECA_PECA_MICROARRAY_AFFY.out.versions
}
