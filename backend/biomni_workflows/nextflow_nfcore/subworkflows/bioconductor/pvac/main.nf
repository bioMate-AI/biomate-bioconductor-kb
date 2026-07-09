#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: pvac — pvac_microarray_filtering
// Perform PCA-based gene filtering on Affymetrix microarray data to remove non-informative probesets before differential expression testing.
// Input: celfiles
// Container: quay.io/biocontainers/bioconductor-pvac:1.58.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: affy, pvac
// Visualizations: density plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read raw CEL files into an AffyBatch object
//  * 2. [Visualization & Output] Summarize probe-level data to probeset-level expression using RMA
//  * 3. [Core Analysis] Calculate PVAC scores and identify passing probesets
//  * 4. [Visualization & Output] Subset the summarized ExpressionSet to keep only the filtered probesets

nextflow.enable.dsl = 2

process BIOC_PVAC_PVAC_MICROARRAY_FILTERING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("affy", "pvac")
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
    
    # Check if input directory exists
    if (!dir.exists("celfiles")) {
      stop("Error: 'celfiles' directory not found in the working directory.")
    }
    
    # Check if there are CEL files in the directory
    cel_files <- list.files("celfiles", pattern = "\\\\.[cC][eE][lL](\\\\.gz)?\$", full.names = TRUE)
    if (length(cel_files) == 0) {
      stop("Error: No CEL files found in 'celfiles' directory.")
    }
    
    if (length(cel_files) < 6) {
      warning("PVAC filtering is most effective with at least 6 samples. Found: ", length(cel_files))
    }
    
    library(affy)
    library(pvac)
    
    # 1. Read raw CEL files into an AffyBatch object
    # We name the object MLL.A to match the documented code exactly
    MLL.A <- ReadAffy(celfile.path = "celfiles")
    
    # 2. Summarize probe-level data to probeset-level expression using RMA
    myeset <- rma(MLL.A)
    
    # 3. Calculate PVAC scores and identify passing probesets
    ft <- pvacFilter(MLL.A)
    
    # 4. Subset the summarized ExpressionSet to keep only the filtered probesets
    myeset.filtered <- myeset[ft\$aset,]
    
    # Generate and save the density plot
    pdf("pvac_density_plot.pdf", width = 7, height = 7)
    plot(density(ft\$pvac[ft\$nullset]), xlab = "PVAC score", main = "",
         col = "gray", cex.lab = 0.5, xlim = c(0, 1))
    lines(density(ft\$pvac), col = 1)
    abline(v = ft\$cutoff, lty = 2, col = "gray")
    dev.off()
    
    # Save outputs
    saveRDS(myeset.filtered, "myeset_filtered.rds")
    saveRDS(ft, "pvac_filter_results.rds")
    write.csv(exprs(myeset.filtered), "filtered_expression_matrix.csv", row.names = TRUE)
    
    # Write a summary text file
    summary_conn <- file("pvac_filter_summary.txt")
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
      process = "BIOC_PVAC_PVAC_MICROARRAY_FILTERING",
      domain  = "bioconductor",
      declared_qc_steps = c("between-array normalization", "array detection QC", "low-count filtering"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)


    writeLines(c(
      paste("Total probesets before filtering:", nrow(myeset)),
      paste("Probesets passing filter:", length(ft\$aset)),
      paste("Probesets filtered out:", nrow(myeset) - length(ft\$aset)),
      paste("PVAC cutoff score:", ft\$cutoff)
    ), summary_conn)
    close(summary_conn)

    writeLines(c(
        '"BIOC_PVAC_PVAC_MICROARRAY_FILTERING":',
        paste0('    pvac: ', as.character(packageVersion('pvac')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pvac_microarray_filtering.csv versions.yml
    """
}

workflow BIOC_PVAC_PVAC_MICROARRAY_FILTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ celfiles ] ]

    main:
    BIOC_PVAC_PVAC_MICROARRAY_FILTERING(ch_input)

    emit:
    tables   = BIOC_PVAC_PVAC_MICROARRAY_FILTERING.out.tables
    plots    = BIOC_PVAC_PVAC_MICROARRAY_FILTERING.out.plots
    objects  = BIOC_PVAC_PVAC_MICROARRAY_FILTERING.out.objects
    versions = BIOC_PVAC_PVAC_MICROARRAY_FILTERING.out.versions
}
