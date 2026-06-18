#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: vsn — affymetrix_genechip_normalization
// Preprocess Affymetrix genechip data using the RMA method with VSN background correction, normalization, and transformation.
// Input: Dilution
// Container: quay.io/biocontainers/bioconductor-vsn:3.78.1--r45h01b2380_0
// R packages: Biobase, affy, vsn
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, affy, vsn
// Visualizations: mean-SD plot
// QC: variance-stabilizing normalization, normalization diagnostic plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Save the normalized ExpressionSet object as an RDS file
//  * 2. [Visualization & Output] Save the normalized expression matrix as a CSV table
//  * 3. [Visualization & Output] Generate and save diagnostic plots (mean-sd plot) to a PDF

nextflow.enable.dsl = 2

process BIOC_VSN_AFFYMETRIX_GENECHIP_NORMALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-variant_calling:3.20-slim"

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
    .bm_deps <- c("Biobase", "affy", "vsn")
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
    library(vsn)
    library(affy)
    library(Biobase)
    
    # Define input file path
    input_file <- "Dilution.rds"
    
    # Verify the input file exists
    if (!file.exists(input_file)) {
      stop(paste("Error: Input file", input_file, "not found in the working directory."))
    }
    
    # Read the user input AffyBatch object
    Dilution <- readRDS(input_file)
    
    # Verify the object class
    if (!inherits(Dilution, "AffyBatch")) {
      stop("Error: The input object must be of class 'AffyBatch'.")
    }
    
    # Run the documented workflow: vsnrma to perform background correction,
    # between-array normalization, transformation, and summarization.
    d_vsn = vsnrma(Dilution)
    
    # Write named output files for the meaningful results
    
    # --- Save the normalized ExpressionSet object as an RDS file ---
    saveRDS(d_vsn, file = "d_vsn.rds")
    
    # --- Save the normalized expression matrix as a CSV table ---
    normalized_exprs <- exprs(d_vsn)
    write.csv(normalized_exprs, file = "normalized_intensities.csv", row.names = TRUE)
    
    # --- Generate and save diagnostic plots (mean-sd plot) to a PDF ---
    pdf("vsn_diagnostic_plots.pdf", width = 7, height = 7)
    tryCatch({
      meanSdPlot(d_vsn)
    }, error = function(e) {
      warning("Could not generate meanSdPlot: ", e\$message)
    })
    dev.off()
    
    cat("Pipeline completed successfully. Outputs written to 'd_vsn.rds', 'normalized_intensities.csv', and 'vsn_diagnostic_plots.pdf'.\n")
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
      process = "BIOC_VSN_AFFYMETRIX_GENECHIP_NORMALIZATION",
      domain  = "bioconductor",
      declared_qc_steps = c("variance-stabilizing normalization", "normalization diagnostic plot"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_VSN_AFFYMETRIX_GENECHIP_NORMALIZATION":',
        paste0('    vsn: ', as.character(packageVersion('vsn')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_affymetrix_genechip_normalization.csv versions.yml
    """
}

workflow BIOC_VSN_AFFYMETRIX_GENECHIP_NORMALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Dilution ] ]

    main:
    BIOC_VSN_AFFYMETRIX_GENECHIP_NORMALIZATION(ch_input)

    emit:
    tables   = BIOC_VSN_AFFYMETRIX_GENECHIP_NORMALIZATION.out.tables
    plots    = BIOC_VSN_AFFYMETRIX_GENECHIP_NORMALIZATION.out.plots
    objects  = BIOC_VSN_AFFYMETRIX_GENECHIP_NORMALIZATION.out.objects
    versions = BIOC_VSN_AFFYMETRIX_GENECHIP_NORMALIZATION.out.versions
}
