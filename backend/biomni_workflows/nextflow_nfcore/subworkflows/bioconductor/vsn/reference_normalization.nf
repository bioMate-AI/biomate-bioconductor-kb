#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: vsn — reference_normalization
// Normalize new test arrays against an existing reference dataset without changing the reference parameters.
// Input: lymphoma
// Container: quay.io/biocontainers/bioconductor-vsn:3.78.1--r45h01b2380_0
// R packages: Biobase, vsn
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, vsn
// Visualizations: plot (ggplot/base)
// QC: variance-stabilizing normalization
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Read User Input
//  * 2. [Core Analysis] Run Documented Workflow: Reference Normalization
//  * 3. [Core Analysis] Save Outputs

nextflow.enable.dsl = 2

process BIOC_VSN_REFERENCE_NORMALIZATION {
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
    .bm_deps <- c("Biobase", "vsn")
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
    library("vsn")
    library("Biobase")
    
    # ------------------------------------------------------------------------------
    # --- Read User Input ---
    # ------------------------------------------------------------------------------
    # The pipeline expects the 'lymphoma' ExpressionSet to be saved as an RDS file
    # in the working directory, named either 'lymphoma.rds' or 'lymphoma'.
    if (file.exists("lymphoma.rds")) {
      lymphoma <- readRDS("lymphoma.rds")
    } else if (file.exists("lymphoma")) {
      lymphoma <- readRDS("lymphoma")
    } else {
      stop("Required input file 'lymphoma.rds' or 'lymphoma' not found in the working directory.")
    }
    
    # Determine the number of samples in the user-provided ExpressionSet
    N <- ncol(lymphoma)
    
    # ------------------------------------------------------------------------------
    # --- Run Documented Workflow: Reference Normalization ---
    # ------------------------------------------------------------------------------
    # Fit the VSN model on the reference arrays (first N-1 samples)
    ref = vsn2(lymphoma[, 1:(N-1)])
    
    # Fit the VSN model on the last array using the reference parameters
    f8 = vsn2(lymphoma[, N], reference = ref)
    
    # Fit the VSN model on all arrays jointly for comparison
    fall = vsn2(lymphoma)
    
    # ------------------------------------------------------------------------------
    # --- Save Outputs ---
    # ------------------------------------------------------------------------------
    # Save the fitted VSN objects as RDS
    saveRDS(ref, "vsn_ref_fit.rds")
    saveRDS(f8, "vsn_f8_fit.rds")
    saveRDS(fall, "vsn_fall_fit.rds")
    
    # Extract and save the normalized expression values as CSV
    write.csv(exprs(f8), "normalized_intensities_f8.csv", row.names = TRUE)
    write.csv(exprs(fall), "normalized_intensities_fall.csv", row.names = TRUE)
    
    # Generate diagnostic plot comparing reference-normalized vs joint-normalized values
    pdf("reference_vs_joint_normalization_plot.pdf", width = 6, height = 6)
    plot(exprs(f8), exprs(fall)[, N], 
         pch = ".", 
         asp = 1,
         xlab = "Reference Normalization (f8)",
         ylab = paste0("Joint Normalization (fall[,", N, "])"),
         main = "Comparison of Normalization Methods")
    abline(a = 0, b = 1, col = "red")
    dev.off()
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

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

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_VSN_REFERENCE_NORMALIZATION",
      domain  = "bioconductor",
      declared_qc_steps = c("variance-stabilizing normalization"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_VSN_REFERENCE_NORMALIZATION":',
        paste0('    vsn: ', as.character(packageVersion('vsn')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_reference_normalization.csv versions.yml
    """
}

workflow BIOC_VSN_REFERENCE_NORMALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ lymphoma ] ]

    main:
    BIOC_VSN_REFERENCE_NORMALIZATION(ch_input)

    emit:
    tables   = BIOC_VSN_REFERENCE_NORMALIZATION.out.tables
    plots    = BIOC_VSN_REFERENCE_NORMALIZATION.out.plots
    objects  = BIOC_VSN_REFERENCE_NORMALIZATION.out.objects
    versions = BIOC_VSN_REFERENCE_NORMALIZATION.out.versions
}
