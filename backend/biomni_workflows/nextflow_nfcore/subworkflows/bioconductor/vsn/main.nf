#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: vsn — standard_microarray_normalization
// Calibrate and variance-stabilize microarray intensity data from ExpressionSet or matrix objects.
// Input: kidney, lymphoma
// Container: quay.io/biocontainers/bioconductor-vsn:3.78.1--r45h01b2380_0
// R packages: Biobase, affydata, ggplot2, limma, vsn
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, limma, vsn
// Visualizations: mean-SD plot
// QC: between-array normalization, variance-stabilizing normalization, normalization diagnostic plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run one-step normalization with justvsn
//  * 2. [Core Analysis] Alternatively, run two-step normalization by fitting
//  * 3. [Core Analysis] Assess variance stabilization using meanSdPlot
//  * 4. [Core Analysis] Perform spike-in normalization or normalization without

nextflow.enable.dsl = 2

process BIOC_VSN_STANDARD_MICROARRAY_NORMALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-variant_calling:3.20"

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
    .bm_deps <- c("Biobase", "affydata", "ggplot2", "limma", "vsn")
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
    
    # Load required Bioconductor and CRAN libraries
    library(vsn)
    library(Biobase)
    library(limma)
    
    # Read the declared USER INPUT files from the working directory.
    # We check for both extensionless filenames and '.rds' extensions.
    if (file.exists("kidney")) {
      kidney <- readRDS("kidney")
    } else if (file.exists("kidney.rds")) {
      kidney <- readRDS("kidney.rds")
    } else {
      stop("Error: 'kidney' input file not found in the working directory.")
    }
    
    if (file.exists("lymphoma")) {
      lymphoma <- readRDS("lymphoma")
    } else if (file.exists("lymphoma.rds")) {
      lymphoma <- readRDS("lymphoma.rds")
    } else {
      stop("Error: 'lymphoma' input file not found in the working directory.")
    }
    
    # --- Run one-step normalization with justvsn ---
    xnorm = justvsn(kidney)
    saveRDS(xnorm, "xnorm.rds")
    
    # Calculate generalized log-ratios
    M = exprs(xnorm)[,1] - exprs(xnorm)[,2]
    write.csv(data.frame(M = M), "M_log_ratios.csv", row.names = TRUE)
    
    # --- Alternatively, run two-step normalization by fitting ---
    fit = vsn2(kidney)
    saveRDS(fit, "fit.rds")
    
    ynorm = predict(fit, kidney)
    saveRDS(ynorm, "ynorm.rds")
    
    # --- Assess variance stabilization using meanSdPlot ---
    pdf("meanSdPlot_ranks_true.pdf")
    p1 = meanSdPlot(xnorm, ranks = TRUE)
    if (inherits(p1, "gg") || inherits(p1, "ggplot")) {
      print(p1)
    }
    dev.off()
    
    pdf("meanSdPlot_ranks_false.pdf")
    p2 = meanSdPlot(xnorm, ranks = FALSE)
    if (inherits(p2, "gg") || inherits(p2, "ggplot")) {
      print(p2)
    }
    dev.off()
    
    # --- Perform spike-in normalization or normalization without ---
    # Define spike-in indices (features 100 to 200 as documented in the vignette)
    # We ensure the indices do not exceed the number of rows in the kidney dataset
    max_spike <- min(200, nrow(kidney))
    spikeins = 100:max_spike
    
    spfit = vsn2(kidney[spikeins,], lts.quantile=1)
    saveRDS(spfit, "spfit.rds")
    
    nkid = predict(spfit, newdata=kidney)
    saveRDS(nkid, "nkid.rds")
    
    # Perform quantile normalization on lymphoma, then run VSN without calibration
    lym_q = normalizeQuantiles(exprs(lymphoma))
    lym_qvsn = vsn2(lym_q, calib="none")
    saveRDS(lym_qvsn, "lym_qvsn.rds")
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

    # VSN — DESeqTransform / vsd matrix; mean-SD slope ≤ 0.5 (vsn::meanSdPlot).
    .vsn_slope <- NA_real_
    for (.vsn_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
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

    # normalization diagnostic plot — file-exists check for any PDF emitted
    # with "norm" / "mean_sd" / "library" in the filename. Pairs with
    # bioc_count_normalization (numeric metric); this row is the visual gate.
    .ndp_pdfs <- list.files(".", pattern = "(?i)(norm|mean.?sd|library).*\\.pdf\$")
    .ndp_passes <- length(.ndp_pdfs) > 0
    .gates_by_label[["normalization diagnostic plot"]] <- list(
      gate_row = "bioc_normalization_diagnostic_plot",
      metric_name = "normalization_plot_exists",
      metric_value = if (.ndp_passes) 1 else 0,
      passes = .ndp_passes,
      status = if (.ndp_passes) paste0("computed (", length(.ndp_pdfs), " diagnostic PDF(s) emitted)")
               else "not_computed (no normalization diagnostic PDF found)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_VSN_STANDARD_MICROARRAY_NORMALIZATION",
      domain  = "bioconductor",
      declared_qc_steps = c("between-array normalization", "variance-stabilizing normalization", "normalization diagnostic plot"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_VSN_STANDARD_MICROARRAY_NORMALIZATION":',
        paste0('    vsn: ', as.character(packageVersion('vsn')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_microarray_normalization.csv versions.yml
    """
}

workflow BIOC_VSN_STANDARD_MICROARRAY_NORMALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ kidney, lymphoma ] ]

    main:
    BIOC_VSN_STANDARD_MICROARRAY_NORMALIZATION(ch_input)

    emit:
    tables   = BIOC_VSN_STANDARD_MICROARRAY_NORMALIZATION.out.tables
    plots    = BIOC_VSN_STANDARD_MICROARRAY_NORMALIZATION.out.plots
    objects  = BIOC_VSN_STANDARD_MICROARRAY_NORMALIZATION.out.objects
    versions = BIOC_VSN_STANDARD_MICROARRAY_NORMALIZATION.out.versions
}
