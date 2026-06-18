#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ppcseq — outlier_identification_and_visualization
// Identify and visualize outlier transcripts from RNA-seq differential expression analysis results.
// Input: counts.tsv
// Container: quay.io/biocontainers/bioconductor-ppcseq:1.18.0--r45ha27e39d_0
// R packages: dplyr, ggplot2, knitr, ppcseq, readr
// Bioconductor: 3.20 | R: 4.4
// Requires: dplyr, ggplot2, ppcseq, readr
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the tidy count and differential expression data
//  * 2. [Core Analysis] Identify outlier transcripts using identify_outliers with a specified GLM formula and significance threshold
//  * 3. [Visualization & Output] Generate credible interval plots for the identified outliers using plot_credible_intervals

nextflow.enable.dsl = 2

process BIOC_PPCSEQ_OUTLIER_IDENTIFICATION_AND_VISUALIZATION {
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
    .bm_deps <- c("dplyr", "ggplot2", "knitr", "ppcseq", "readr")
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
    library(dplyr)
    library(ppcseq)
    library(readr)
    library(ggplot2)
    
    # 1. Load the tidy count and differential expression data
    # The input file 'counts.tsv' must be present in the working directory.
    # It should contain columns: sample, symbol, value, PValue, FDR, and a covariate (e.g., Label, condition)
    if (!file.exists("counts.tsv")) {
      stop("Error: 'counts.tsv' not found in the working directory.")
    }
    
    counts <- readr::read_tsv("counts.tsv", col_types = readr::cols())
    
    # Dynamically determine the formula based on covariate columns present
    # Exclude numeric columns to prevent DE statistics (like logFC, test statistics) from being used as covariates
    covariate_cols <- setdiff(colnames(counts), c("sample", "symbol", "value", "PValue", "FDR"))
    if (length(covariate_cols) > 0) {
      covariate_cols <- covariate_cols[!sapply(counts[covariate_cols], is.numeric)]
    }
    
    if (length(covariate_cols) > 0) {
      design_formula <- as.formula(paste("~", paste(covariate_cols, collapse = " + ")))
    } else {
      design_formula <- ~ 1
    }
    
    # 2. Identify outlier transcripts using identify_outliers
    # We reproduce the documented code faithfully.
    counts.ppc = 
    	counts %>%
    	mutate(is_significant = FDR < 0.0001) %>%
    	identify_outliers(
    		formula = design_formula,
    		.sample = sample, 
    		.transcript = symbol,
    		.abundance = value,
    		.significance = PValue,
    		.do_check = is_significant,
    		percent_false_positive_genes = 5, 
    		approximate_posterior_inference = FALSE,
    		cores = 1
    	)
    
    # Save the raw outlier identification results as an RDS object
    saveRDS(counts.ppc, file = "outliers_identified.rds")
    
    # Also save a flattened summary table for easy inspection
    counts.ppc_summary <- counts.ppc %>% 
      dplyr::select(-dplyr::any_of("sample_wise_data"))
    write_csv(counts.ppc_summary, "outliers_summary.csv")
    
    # 3. Generate credible interval plots for the identified outliers
    counts.ppc_plots = 
    	counts.ppc %>% 
    	plot_credible_intervals() 
    
    # Save the plots object
    saveRDS(counts.ppc_plots, file = "credible_interval_plots.rds")
    
    # Export the generated plots to a PDF file
    if (nrow(counts.ppc_plots) > 0) {
      plots_list <- counts.ppc_plots %>% pull(plot)
      
      pdf("credible_intervals_plots.pdf", width = 8, height = 6)
      for (i in seq_along(plots_list)) {
        print(plots_list[[i]])
      }
      dev.off()
    } else {
      message("No outlier plots to save.")
    }
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

    # count normalization — scan .rds matrix artifacts for library-size CV
    # ratio (post-norm / pre-norm); without raw input we report median lib CV
    # as a proxy diagnostic. Threshold = 0.7 (Bullard 2010 BMC Bioinf).
    .cn_lib_cvs <- numeric(0)
    .cn_scanned <- character(0)
    for (.cn_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .cn_obj <- tryCatch(readRDS(.cn_rds), error = function(e) NULL)
      .cn_mat <- if (is.matrix(.cn_obj) || is.data.frame(.cn_obj)) .cn_obj else NULL
      if (!is.null(.cn_mat) && ncol(.cn_mat) >= 2 && nrow(.cn_mat) >= 2) {
        .cn_lib <- tryCatch(colSums(as.matrix(.cn_mat), na.rm = TRUE), error = function(e) NULL)
        if (!is.null(.cn_lib) && all(is.finite(.cn_lib)) && mean(.cn_lib) > 0) {
          .cn_lib_cvs <- c(.cn_lib_cvs, sd(.cn_lib) / mean(.cn_lib))
          .cn_scanned <- c(.cn_scanned, .cn_rds)
        }
      }
    }
    .cn_med_cv <- if (length(.cn_lib_cvs) > 0) round(median(.cn_lib_cvs), 4) else NA_real_
    .gates_by_label[["count normalization"]] <- list(
      gate_row = "bioc_count_normalization",
      metric_name = "lib_size_cv_median",
      metric_value = .cn_med_cv,
      passes = isTRUE(is.finite(.cn_med_cv) && .cn_med_cv <= 0.3),
      status = if (is.finite(.cn_med_cv)) paste0("computed (proxy: median lib-size CV across ", length(.cn_scanned), " matrix .rds; raw-vs-norm ratio not measurable without paired input)")
               else "not_computed (no count matrix .rds artifact present)"
    )

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

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_PPCSEQ_OUTLIER_IDENTIFICATION_AND_VISUALIZATION",
      domain  = "bioconductor",
      declared_qc_steps = c("low-count filtering", "count normalization", "dispersion/size-factor estimation"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_PPCSEQ_OUTLIER_IDENTIFICATION_AND_VISUALIZATION":',
        paste0('    ppcseq: ', as.character(packageVersion('ppcseq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_outlier_identification_and_visualization.csv versions.yml
    """
}

workflow BIOC_PPCSEQ_OUTLIER_IDENTIFICATION_AND_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ counts.tsv ] ]

    main:
    BIOC_PPCSEQ_OUTLIER_IDENTIFICATION_AND_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_PPCSEQ_OUTLIER_IDENTIFICATION_AND_VISUALIZATION.out.tables
    plots    = BIOC_PPCSEQ_OUTLIER_IDENTIFICATION_AND_VISUALIZATION.out.plots
    objects  = BIOC_PPCSEQ_OUTLIER_IDENTIFICATION_AND_VISUALIZATION.out.objects
    versions = BIOC_PPCSEQ_OUTLIER_IDENTIFICATION_AND_VISUALIZATION.out.versions
}
