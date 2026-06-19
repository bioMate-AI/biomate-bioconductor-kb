#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DEXSeq — complex_experimental_design
// Perform differential exon usage analysis controlling for additional covariates or blocking factors (e.g., library type).
// Input: dxd
// Container: quay.io/biocontainers/bioconductor-dexseq:1.56.0--r45hdfd78af_0
// R packages: DEXSeq
// Bioconductor: 3.20 | R: 4.4
// Requires: DEXSeq
// Visualizations: MA plot, dispersion plot
// QC: dispersion/size-factor estimation, dispersion QC plot, diagnostic MA/PCA QC
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define full and reduced model formulas
//  * 2. [Core Analysis] Estimate dispersions using the full model formula in estimateDispersions
//  * 3. [Core Analysis] Test for differential exon usage using both formulas in testForDEU
//  * 4. [Core Analysis] Extract results using DEXSeqResults

nextflow.enable.dsl = 2

process BIOC_DEXSEQ_COMPLEX_EXPERIMENTAL_DESIGN {
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
    .bm_deps <- c("DEXSeq")
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
        library(DEXSeq)
        
        # Read the user input file 'dxd' from the working directory
        if (file.exists("dxd")) {
          dxd <- readRDS("dxd")
        } else if (file.exists("dxd.rds")) {
          dxd <- readRDS("dxd.rds")
        } else {
          stop("Error: Input file 'dxd' or 'dxd.rds' not found in the working directory.")
        }
        
        # Estimate size factors (required before estimating dispersions)
        dxd = estimateSizeFactors(dxd)
        
        # Identify the blocking factor (covariate) dynamically
        covariate = setdiff(colnames(sampleAnnotation(dxd)), c("sample", "condition", "sizeFactor"))[1]
        
        # 1. Define full and reduced model formulas dynamically
        formulaFullModel    = as.formula(paste0("~ sample + exon + ", covariate, ":exon + condition:exon"))
        formulaReducedModel = as.formula(paste0("~ sample + exon + ", covariate, ":exon"))
        
        # 2. Estimate dispersions using the full model formula
        dxd = estimateDispersions( dxd, formula = formulaFullModel )
        
        # 3. Test for differential exon usage
        dxd = testForDEU( dxd, 
        	reducedModel = formulaReducedModel, 
                fullModel = formulaFullModel )
        
        # 4. Extract results
        dxr2 = DEXSeqResults( dxd )
        
        # Write outputs
        # Save the updated DEXSeqDataSet and DEXSeqResults objects as RDS files first
        # to ensure primary outputs are not lost if subsequent steps fail
        saveRDS(dxd, file = "dxd_complex_analyzed.rds")
        saveRDS(dxr2, file = "dxr2_complex_results.rds")
        
        # Save the results table as a CSV file
        # Convert DEXSeqResults to a data frame and flatten list/matrix columns for CSV compatibility
        dxr_df <- as.data.frame(dxr2)
        for (col in colnames(dxr_df)) {
          if (is.list(dxr_df[[col]]) || inherits(dxr_df[[col]], "List")) {
            dxr_df[[col]] <- vapply(dxr_df[[col]], paste, collapse = ";", FUN.VALUE = character(1))
          } else if (is.matrix(dxr_df[[col]])) {
            dxr_df[[col]] <- apply(dxr_df[[col]], 1, paste, collapse = ";")
          } else if (inherits(dxr_df[[col]], "GRanges")) {
            dxr_df[[col]] <- as.character(dxr_df[[col]])
          }
        }
        write.csv(dxr_df, file = "dexseq_complex_results.csv", row.names = TRUE)
        
        # Generate diagnostic plots
        pdf("dexseq_complex_plots.pdf", width = 7, height = 7)
        tryCatch({
          plotDispEsts(dxd)
        }, error = function(e) {
          warning("Could not generate dispersion plot: ", e\$message)
        })
        
        tryCatch({
          plotMA(dxr2)
        }, error = function(e) {
          warning("Could not generate MA plot: ", e\$message)
        })
        dev.off()
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # dispersion/size-factor estimation — object-type-aware. Try DESeq2
    # DESeqDataSet (mcols\$dispOutlier), then edgeR DGEList (common.dispersion).
    .dsf_value <- NA_real_; .dsf_kind <- "none"
    for (.dsf_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .dsf_obj <- tryCatch(readRDS(.dsf_rds), error = function(e) NULL)
      if (!is.null(.dsf_obj)) {
        if (inherits(.dsf_obj, "DESeqDataSet")) {
          .dsf_o <- tryCatch(mcols(.dsf_obj)\$dispOutlier, error = function(e) NULL)
          if (!is.null(.dsf_o)) { .dsf_value <- round(mean(.dsf_o, na.rm = TRUE), 4); .dsf_kind <- "deseq2"; break }
        } else if (inherits(.dsf_obj, "DGEList")) {
          .dsf_v <- tryCatch(.dsf_obj\$common.dispersion, error = function(e) NULL)
          if (!is.null(.dsf_v) && is.finite(.dsf_v)) { .dsf_value <- round(sqrt(.dsf_v), 4); .dsf_kind <- "edger_bcv"; break }
        }
      }
    }
    .gates_by_label[["dispersion/size-factor estimation"]] <- list(
      gate_row = "bioc_dispersion_size_factor",
      metric_name = if (.dsf_kind == "edger_bcv") "common_bcv" else "disp_outlier_fraction",
      metric_value = .dsf_value,
      passes = isTRUE(
        (.dsf_kind == "deseq2" && is.finite(.dsf_value) && .dsf_value <= 0.01) ||
        (.dsf_kind == "edger_bcv" && is.finite(.dsf_value) && .dsf_value > 0 && .dsf_value < 1.0)
      ),
      status = if (is.finite(.dsf_value)) paste0("computed (", .dsf_kind, ")")
               else "not_computed (no DESeqDataSet/DGEList .rds artifact present)"
    )

    # dispersion QC plot — file-exists check for any PDF with "disp" or "bcv"
    # in the filename. Pairs with bioc_dispersion_size_factor.
    .dqp_pdfs <- list.files(".", pattern = "(?i)(disp|bcv).*\\.pdf\$")
    .dqp_passes <- length(.dqp_pdfs) > 0
    .gates_by_label[["dispersion QC plot"]] <- list(
      gate_row = "bioc_dispersion_qc_plot",
      metric_name = "dispersion_plot_exists",
      metric_value = if (.dqp_passes) 1 else 0,
      passes = .dqp_passes,
      status = if (.dqp_passes) paste0("computed (", length(.dqp_pdfs), " dispersion PDF(s) emitted)")
               else "not_computed (no dispersion PDF found)"
    )

    # diagnostic MA/PCA QC — PC1 variance explained on any large matrix.
    # Pass when PC1 > 10% (Risso 2014 RUV-seq diagnostic).
    .pca_pc1 <- NA_real_; .pca_files <- character(0)
    for (.pca_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .pca_obj <- tryCatch(readRDS(.pca_rds), error = function(e) NULL)
      .pca_mat <- if (is.matrix(.pca_obj) || is.data.frame(.pca_obj)) .pca_obj else NULL
      if (!is.null(.pca_mat) && ncol(.pca_mat) >= 3 && nrow(.pca_mat) >= 100) {
        .pca_m <- suppressWarnings(as.matrix(.pca_mat))
        .pca_kept <- apply(.pca_m, 1, function(r) all(is.finite(r)) && var(r) > 0)
        if (sum(.pca_kept) >= 50) {
          .pca_fit <- tryCatch(prcomp(t(.pca_m[.pca_kept, , drop = FALSE])), error = function(e) NULL)
          if (!is.null(.pca_fit)) {
            .pca_vars <- (.pca_fit\$sdev^2) / sum(.pca_fit\$sdev^2)
            .pca_pc1 <- round(.pca_vars[1] * 100, 2); .pca_files <- c(.pca_files, .pca_rds); break
          }
        }
      }
    }
    .gates_by_label[["diagnostic MA/PCA QC"]] <- list(
      gate_row = "bioc_diagnostic_ma_pca_qc",
      metric_name = "pc1_var_explained",
      metric_value = .pca_pc1,
      passes = isTRUE(is.finite(.pca_pc1) && .pca_pc1 > 10),
      status = if (is.finite(.pca_pc1)) paste0("computed (PC1=", .pca_pc1, "%)")
               else "not_computed (no large numeric matrix .rds artifact present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_DEXSEQ_COMPLEX_EXPERIMENTAL_DESIGN",
      domain  = "bioconductor",
      declared_qc_steps = c("dispersion/size-factor estimation", "dispersion QC plot", "diagnostic MA/PCA QC"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_DEXSEQ_COMPLEX_EXPERIMENTAL_DESIGN":',
        paste0('    DEXSeq: ', as.character(packageVersion('DEXSeq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_complex_experimental_design.csv versions.yml
    """
}

workflow BIOC_DEXSEQ_COMPLEX_EXPERIMENTAL_DESIGN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ dxd ] ]

    main:
    BIOC_DEXSEQ_COMPLEX_EXPERIMENTAL_DESIGN(ch_input)

    emit:
    tables   = BIOC_DEXSEQ_COMPLEX_EXPERIMENTAL_DESIGN.out.tables
    plots    = BIOC_DEXSEQ_COMPLEX_EXPERIMENTAL_DESIGN.out.plots
    objects  = BIOC_DEXSEQ_COMPLEX_EXPERIMENTAL_DESIGN.out.objects
    versions = BIOC_DEXSEQ_COMPLEX_EXPERIMENTAL_DESIGN.out.versions
}
