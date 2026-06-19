#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: infinityFlow — custom_regression_pipeline
// Run the Infinity Flow pipeline using custom regression models (e.g., SVM, LASSO, Linear Model) and custom hyperparameters.
// Input: input_dir, backbone_selection_file.csv, steady_state_lung_annotation
// Container: quay.io/biocontainers/bioconductor-infinityflow:1.20.2--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: e1071, flowCore, glmnetUtils, infinityFlow
// QC: missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load package and prepare data paths and annotations
//  * 2. [Input & Preparation] Define custom regression functions list
//  * 3. [Input & Preparation] Define corresponding hyperparameter list
//  * 4. [Core Analysis] Run the pipeline using infinity_flow() with custom regression arguments

nextflow.enable.dsl = 2

process BIOC_INFINITYFLOW_CUSTOM_REGRESSION_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20-slim"

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
    .bm_deps <- c("infinityFlow", "flowCore", "glmnetUtils", "e1071")
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
    
    library(infinityFlow)
    library(flowCore)
    
    # Load optional dependencies required for custom regression models
    if (requireNamespace("glmnetUtils", quietly = TRUE)) {
        library(glmnetUtils)
    }
    if (requireNamespace("e1071", quietly = TRUE)) {
        library(e1071)
    }
    
    # Verify and read user inputs from the working directory
    if (!dir.exists("input_dir")) {
        stop("Required input directory 'input_dir' not found in the working directory.")
    }
    
    if (!file.exists("backbone_selection_file.csv")) {
        stop("Required input 'backbone_selection_file.csv' not found in the working directory.")
    }
    
    steady_state_lung_annotation <- NULL
    if (file.exists("steady_state_lung_annotation.csv")) {
        steady_state_lung_annotation <- read.csv("steady_state_lung_annotation.csv", row.names = 1, stringsAsFactors = FALSE)
    } else if (file.exists("steady_state_lung_annotation.rds")) {
        steady_state_lung_annotation <- readRDS("steady_state_lung_annotation.rds")
    } else if (file.exists("steady_state_lung_annotation")) {
        steady_state_lung_annotation <- tryCatch({
            read.csv("steady_state_lung_annotation", row.names = 1, stringsAsFactors = FALSE)
        }, error = function(e) {
            readRDS("steady_state_lung_annotation")
        })
    } else {
        stop("Required input 'steady_state_lung_annotation' (CSV or RDS) not found in the working directory.")
    }
    
    # Define paths
    path_to_fcs <- "input_dir"
    path_to_output <- "output"
    path_to_intermediary_results <- "tmp"
    backbone_selection_file <- "backbone_selection_file.csv"
    
    # Extract targets and isotypes annotations
    targets <- steady_state_lung_annotation\$Infinity_target
    names(targets) <- rownames(steady_state_lung_annotation)
    isotypes <- steady_state_lung_annotation\$Infinity_isotype
    names(isotypes) <- rownames(steady_state_lung_annotation)
    
    # Define parameters
    input_events_downsampling <- 1000
    prediction_events_downsampling <- 500
    cores <- 1L
    
    # Define custom regression functions
    regression_functions <- list(
        XGBoost = fitter_xgboost, # XGBoost
        SVM = fitter_svm, # SVM
        LASSO2 = fitter_glmnet, # L1-penalized 2nd degree polynomial model
        LM = fitter_linear # Linear model
    )
    
    # Define corresponding hyperparameters
    backbone_size <- table(read.csv(backbone_selection_file)[,"type"])["backbone"]
    extra_args_regression_params <- list(
        ## Passed to the first element of `regression_functions`, e.g. XGBoost.
        list(nrounds = 500, eta = 0.05),
        # Passed to the second element, SVMs.
        list(type = "nu-regression", cost = 8, nu=0.5, kernel="radial"),
        # Passed to the third element, fitter_glmnet.
        list(alpha = 1, nfolds=10, degree = 2),
        # Passed to the fourth element, fitter_linear.
        list(degree = 1)
    )
    
    if(length(regression_functions) != length(extra_args_regression_params)){
        stop("Number of models and number of lists of hyperparameters mismatch")
    }
    
    # Run the pipeline
    imputed_data <- infinity_flow(
    	regression_functions = regression_functions,
    	extra_args_regression_params = extra_args_regression_params,
    	path_to_fcs = path_to_fcs,
    	path_to_output = path_to_output,
    	path_to_intermediary_results = path_to_intermediary_results,
    	backbone_selection_file = backbone_selection_file,
    	annotation = targets,
    	isotype = isotypes,
    	input_events_downsampling = input_events_downsampling,
    	prediction_events_downsampling = prediction_events_downsampling,
    	verbose = TRUE,
    	cores = cores
    )
    
    # Save meaningful outputs
    if (!dir.exists(path_to_output)) {
        dir.create(path_to_output, recursive = TRUE)
    }
    
    saveRDS(imputed_data, file = file.path(path_to_output, "imputed_data.rds"))
    
    if (!is.null(imputed_data\$bgc)) {
        write.csv(as.data.frame(imputed_data\$bgc), file = file.path(path_to_output, "imputed_data_bgc.csv"), row.names = TRUE)
    }
    if (!is.null(imputed_data\$raw)) {
        write.csv(as.data.frame(imputed_data\$raw), file = file.path(path_to_output, "imputed_data_raw.csv"), row.names = TRUE)
    }
    
    message("Pipeline completed successfully. Outputs saved to 'output' directory.")
    # ── BIOC_QC_HARNESS — Phase 3c bulk adoption (missing-value handling) ───
    # Defensive scan: list every *.rds the workflow produced, load each one,
    # compute NA fraction across numeric cells where the artifact is a
    # matrix or data.frame. Report max NA fraction across artifacts.
    # Threshold from bioc_missing_value_handling: < 5% pass.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()
    .na_fracs <- numeric(0)
    .scanned_files <- character(0)
    for (.rds_file in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .obj <- tryCatch(readRDS(.rds_file), error = function(e) NULL)
      .mat <- if (is.matrix(.obj) || is.data.frame(.obj)) .obj else NULL
      if (!is.null(.mat)) {
        .vals <- suppressWarnings(as.numeric(as.matrix(.mat)))
        if (length(.vals) > 0) {
          .na_fracs <- c(.na_fracs, mean(is.na(.vals)))
          .scanned_files <- c(.scanned_files, .rds_file)
        }
      }
    }
    .na_max <- if (length(.na_fracs) > 0) round(max(.na_fracs), 4) else NA_real_
    .gates_by_label[["missing-value handling"]] <- list(
      gate_row = "bioc_missing_value_handling",
      metric_name = "na_fraction_remaining",
      metric_value = .na_max,
      passes = isTRUE(is.finite(.na_max) && .na_max < 0.05),
      status = if (is.finite(.na_max)) paste0("computed (scanned ", length(.scanned_files), " rds files)")
               else "not_computed (no matrix/data.frame .rds artifact present)"
    )
    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_INFINITYFLOW_CUSTOM_REGRESSION_PIPELINE",
      domain  = "bioconductor",
      declared_qc_steps = c("missing-value handling"),
      gates_by_label = .gates_by_label,
      evidence_tier = "SILVER (Lazar 2013 NAR; <5% community convention)",
      harness_version = "0.1.0-bulk-mv"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_INFINITYFLOW_CUSTOM_REGRESSION_PIPELINE":',
        paste0('    infinityFlow: ', as.character(packageVersion('infinityFlow')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_custom_regression_pipeline.csv versions.yml
    """
}

workflow BIOC_INFINITYFLOW_CUSTOM_REGRESSION_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input_dir, backbone_selection_file.csv, steady_state_lung_annotation ] ]

    main:
    BIOC_INFINITYFLOW_CUSTOM_REGRESSION_PIPELINE(ch_input)

    emit:
    tables   = BIOC_INFINITYFLOW_CUSTOM_REGRESSION_PIPELINE.out.tables
    plots    = BIOC_INFINITYFLOW_CUSTOM_REGRESSION_PIPELINE.out.plots
    objects  = BIOC_INFINITYFLOW_CUSTOM_REGRESSION_PIPELINE.out.objects
    versions = BIOC_INFINITYFLOW_CUSTOM_REGRESSION_PIPELINE.out.versions
}
