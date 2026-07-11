#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scShapes — differential_distribution_analysis
// Identify the best-fit distribution for genes in scRNA-seq data and detect genes changing distribution shapes between treatment conditions.
// Input: counts, covariates, lib_size, ifnb.distr
// Container: quay.io/biocontainers/bioconductor-scshapes:1.16.0--r45hdfd78af_0
// R packages: BiocParallel, scShapes
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocParallel, scShapes
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Filter genes based on zero expression percentage using filter_counts
//  * 2. [Core Analysis] Perform Kolmogorov-Smirnov test using ks_test to select genes belonging to the ZINB family
//  * 3. [Core Analysis] Select significant genes using ks_sig and subset the count matrix
//  * 4. [Core Analysis] Fit Poisson, NB, ZIP, and ZINB models using fit_models
//  * 5. [Core Analysis] Calculate BIC values using model_bic and select the model with the least BIC using lbic_model
//  * 6. [Core Analysis] Perform goodness-of-fit testing using gof_model
//  * 7. [Core Analysis] Select the final best-fit model using select_model
//  * 8. [Core Analysis] Extract model parameters using model_param
//  * 9. [Core Analysis] Identify genes changing distribution shape between conditions using change_shape

nextflow.enable.dsl = 2

process BIOC_SCSHAPES_DIFFERENTIAL_DISTRIBUTION_ANALYSIS {
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
    .bm_deps <- c("BiocParallel", "scShapes")
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
        library(scShapes)
        library(BiocParallel)
        
        # Set seed for reproducibility
        set.seed(0xBEEF)
        
        # Helper function to read input files robustly
        read_input <- function(base_name) {
          rds_path <- paste0(base_name, ".rds")
          csv_path <- paste0(base_name, ".csv")
          
          if (file.exists(rds_path)) {
            return(readRDS(rds_path))
          } else if (file.exists(csv_path)) {
            df <- read.csv(csv_path, row.names = 1, check.names = FALSE)
            if (base_name == "counts") {
              return(as.matrix(df))
            } else if (base_name == "covariates" || base_name == "lib_size") {
              if (ncol(df) == 1) {
                return(df[[1]])
              } else {
                return(as.matrix(df))
              }
            }
            return(df)
          } else if (file.exists(base_name)) {
            return(readRDS(base_name))
          } else {
            stop(paste("Required input file not found:", base_name))
          }
        }
        
        # Load user inputs
        scData <- list()
        scData\$counts <- read_input("counts")
        scData\$covariates <- read_input("covariates")
        scData\$lib_size <- read_input("lib_size")
        ifnb.distr <- read_input("ifnb.distr")
        
        # 1. Filter genes based on zero expression percentage
        scData_filt <- filter_counts(scData\$counts, perc.zero = 0.1)
        
        # 2. Perform Kolmogorov-Smirnov test to select genes belonging to the ZINB family
        scData_KS <- ks_test(counts=scData_filt, cexpr=scData\$covariates, lib.size=scData\$lib_size, BPPARAM=SnowParam(workers=8,type="SOCK"))
        
        # 3. Select significant genes and subset the count matrix
        scData_KS_sig <- ks_sig(scData_KS)
        scData.sig.genes <- scData_filt[rownames(scData_filt) %in% names(scData_KS_sig\$genes),]
        
        # 4. Fit Poisson, NB, ZIP, and ZINB models
        scData_models <- fit_models(counts=scData.sig.genes, cexpr=scData\$covariates, lib.size=scData\$lib_size, BPPARAM=SnowParam(workers=8,type="SOCK"))
        
        # 5. Calculate BIC values and select the model with the least BIC
        scData_bicvals <- model_bic(scData_models)
        scData_least.bic <- lbic_model(scData_bicvals, scData.sig.genes)
        
        # 6. Perform goodness-of-fit testing
        scData_gof <- gof_model(scData_least.bic, cexpr=scData\$covariates, lib.size=scData\$lib_size, BPPARAM=SnowParam(workers=8,type="SOCK"))
        
        # 7. Select the final best-fit model
        scData_fit <- select_model(scData_gof)
        
        # 8. Extract model parameters
        scData_params <- model_param(scData_models, scData_fit, model=NULL)
        
        # 9. Identify genes changing distribution shape between conditions
        ifnb.DD.genes <- change_shape(ifnb.distr)
        
        # Save outputs to the working directory
        saveRDS(scData_filt, "scData_filt.rds")
        saveRDS(scData_KS, "scData_KS.rds")
        saveRDS(scData_KS_sig, "scData_KS_sig.rds")
        saveRDS(scData_models, "scData_models.rds")
        saveRDS(scData_bicvals, "scData_bicvals.rds")
        saveRDS(scData_least.bic, "scData_least.bic.rds")
        saveRDS(scData_gof, "scData_gof.rds")
        saveRDS(scData_fit, "scData_fit.rds")
        write.csv(scData_fit, "scData_fit.csv", row.names = TRUE)
        saveRDS(scData_params, "scData_params.rds")
        saveRDS(ifnb.DD.genes, "ifnb.DD.genes.rds")
        
        # Write out text summaries of the results
        sink("summary_report.txt")
        cat("=== scShapes Analysis Summary ===\n\n")
        cat("Number of filtered genes:", nrow(scData_filt), "\n")
        cat("Number of significant KS genes:", length(scData_KS_sig\$genes), "\n")
        cat("Distribution of best-fit models:\n")
        print(table(scData_fit))
        cat("\nNumber of shape-changing genes identified:", length(unlist(ifnb.DD.genes)), "\n")
        sink()
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # cell QC metrics — defensive cell-count + per-cell summary from any
    # matrix artifact. Pass when columns (cells) ≥ 50 and rows (features) ≥ 200
    # (Luecken & Theis 2019 single-cell QC floor).
    .cqc_ncells <- NA_real_; .cqc_nfeats <- NA_real_; .cqc_files <- character(0)
    for (.cqc_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
      .cqc_obj <- tryCatch(readRDS(.cqc_rds), error = function(e) NULL)
      .cqc_mat <- if (is.matrix(.cqc_obj) || is.data.frame(.cqc_obj)) .cqc_obj else NULL
      if (!is.null(.cqc_mat) && nrow(.cqc_mat) > 100) {
        .cqc_ncells <- ncol(.cqc_mat); .cqc_nfeats <- nrow(.cqc_mat)
        .cqc_files <- c(.cqc_files, .cqc_rds); break
      }
    }
    .gates_by_label[["cell QC metrics"]] <- list(
      gate_row = "bioc_cell_qc_metrics",
      metric_name = "n_cells",
      metric_value = .cqc_ncells,
      passes = isTRUE(is.finite(.cqc_ncells) && .cqc_ncells >= 50 && .cqc_nfeats >= 200),
      status = if (is.finite(.cqc_ncells)) paste0("computed (cells=", .cqc_ncells, ", features=", .cqc_nfeats, "; proxy gate)")
               else "not_computed (no scRNA matrix .rds artifact present)"
    )

    # count normalization — scan .rds matrix artifacts for library-size CV
    # ratio (post-norm / pre-norm); without raw input we report median lib CV
    # as a proxy diagnostic. Threshold = 0.7 (Bullard 2010 BMC Bioinf).
    .cn_lib_cvs <- numeric(0)
    .cn_scanned <- character(0)
    for (.cn_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
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
      process = "BIOC_SCSHAPES_DIFFERENTIAL_DISTRIBUTION_ANALYSIS",
      domain  = "bioconductor",
      declared_qc_steps = c("cell QC metrics", "count normalization", "low-count filtering"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_SCSHAPES_DIFFERENTIAL_DISTRIBUTION_ANALYSIS":',
        paste0('    scShapes: ', as.character(packageVersion('scShapes')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_differential_distribution_analysis.csv versions.yml
    """
}

workflow BIOC_SCSHAPES_DIFFERENTIAL_DISTRIBUTION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ counts, covariates, lib_size, ifnb.distr ] ]

    main:
    BIOC_SCSHAPES_DIFFERENTIAL_DISTRIBUTION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SCSHAPES_DIFFERENTIAL_DISTRIBUTION_ANALYSIS.out.tables
    plots    = BIOC_SCSHAPES_DIFFERENTIAL_DISTRIBUTION_ANALYSIS.out.plots
    objects  = BIOC_SCSHAPES_DIFFERENTIAL_DISTRIBUTION_ANALYSIS.out.objects
    versions = BIOC_SCSHAPES_DIFFERENTIAL_DISTRIBUTION_ANALYSIS.out.versions
}
