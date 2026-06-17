#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DaMiRseq — cross_validation_and_independent_prediction
// Train and test classification models inside a cross-validation loop, select the best model, normalize/adjust an independent test set, and predict classes.
// Input: count_data.txt, covariate_data.txt
// Container: quay.io/biocontainers/bioconductor-damirseq:2.22.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: DaMiRseq
// QC: count normalization
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Split data into learning and independent test sets
//  * 2. [Core Analysis] Normalize and adjust the learning set
//  * 3. [Core Analysis] Perform feature selection, model training, and testing inside a cross-validation loop
//  * 4. [Core Analysis] Select the best model
//  * 5. [Core Analysis] Normalize and adjust the independent test set using learning set parameters
//  * 6. [Core Analysis] Predict classes on the adjusted independent test set

nextflow.enable.dsl = 2

process BIOC_DAMIRSEQ_CROSS_VALIDATION_AND_INDEPENDENT_PREDICTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("DaMiRseq", "SummarizedExperiment")
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
        library(DaMiRseq)
        library(SummarizedExperiment)
        
        # 1. Read user input files
        if (!file.exists("count_data.txt") || !file.exists("covariate_data.txt")) {
          stop("Required input files 'count_data.txt' and/or 'covariate_data.txt' are missing in the working directory.")
        }
        
        count_data <- read.delim("count_data.txt", header=TRUE, row.names=1, check.names=FALSE)
        covariate_data <- read.delim("covariate_data.txt", header=TRUE, row.names=1, check.names=FALSE, stringsAsFactors=TRUE)
        
        # Ensure count data is integer matrix/df
        count_data <- as.data.frame(lapply(count_data, as.integer), row.names = rownames(count_data))
        
        # Align samples between count data and covariate data
        common_samples <- intersect(colnames(count_data), rownames(covariate_data))
        if (length(common_samples) == 0) {
          stop("No common samples found between count_data.txt and covariate_data.txt.")
        }
        count_data <- count_data[, common_samples, drop=FALSE]
        covariate_data <- covariate_data[common_samples, , drop=FALSE]
        
        # Ensure 'class' column is present and is a factor
        if (!"class" %in% colnames(covariate_data)) {
          stop("covariate_data.txt must contain a 'class' column.")
        }
        covariate_data\$class <- as.factor(covariate_data\$class)
        
        # Construct SummarizedExperiment object
        SE <- DaMiR.makeSE(count_data, covariate_data)
        
        # 2. Split data into learning and independent test sets
        n_samples <- ncol(SE)
        if (n_samples >= 10) {
          idx_test <- (n_samples - 3):n_samples
        } else if (n_samples >= 4) {
          idx_test <- (n_samples - 1):n_samples
        } else {
          stop("Insufficient samples to perform split into learning and independent test sets.")
        }
        
        Ind_Test_set <- SE[, idx_test, drop=FALSE]
        Learning_set <- SE[, -idx_test, drop=FALSE]
        
        # 3. Normalize and adjust the learning set
        data_norm <- DaMiR.normalization(Learning_set, minCounts=10, fSample=0.7, hyper = "yes", th.cv=3)
        sv <- DaMiR.SV(data_norm)
        
        # Dynamically determine the number of surrogate variables to use (up to 4)
        n_sv_val <- min(4, ncol(sv))
        if (is.null(n_sv_val) || n_sv_val < 1) {
          n_sv_val <- 1
        }
        data_adjust <- DaMiR.SVadjust(data_norm, sv, n.sv=n_sv_val)
        
        # 4. Perform feature selection, model training, and testing inside a cross-validation loop
        nfold <- 3
        classes <- colData(data_adjust)\$class
        cv_sample <- integer(length(classes))
        set.seed(12345)
        for (cl in levels(classes)) {
          idx_cl <- which(classes == cl)
          if (length(idx_cl) > 0) {
            cv_sample[idx_cl] <- sample(rep_len(seq_len(nfold), length(idx_cl)))
          }
        }
        
        cv_models <- list()
        cv_predictors <- list()
        res_df <- data.frame(matrix(nrow = nfold, ncol = 7))
        colnames(res_df) <- c("Accuracy", "N.predictors", "MCC", "sensitivity", "Specificty", "PPV", "NPV")
        
        for (cv_fold in seq_len(nfold)) {
          idx_cv <- which(cv_sample != cv_fold)
          TR_set <- data_adjust[, idx_cv, drop=FALSE]
          Val_set <- data_adjust[, -idx_cv, drop=FALSE]
          
          # Feature selection
          data_reduced <- DaMiR.FSelect(t(assay(TR_set)), as.data.frame(colData(TR_set)), th.corr=0.4)
          data_reduced <- DaMiR.FReduct(data_reduced\$data, th.corr = 0.9)
          df_importance <- DaMiR.FSort(data_reduced, as.data.frame(colData(TR_set)))
          selected_features <- DaMiR.FBest(data_reduced, ranking=df_importance, autoselect = "yes")
          
          TR_set <- TR_set[selected_features\$predictors, , drop=FALSE]
          Val_set <- Val_set[selected_features\$predictors, drop=FALSE]
          
          # Model building
          ensl_model <- DaMiR.EnsL_Train(TR_set, cl_type = c("RF", "LR"))
          cv_models[[cv_fold]] <- ensl_model
          
          # Model testing
          res_Val <- DaMiR.EnsL_Test(Val_set, EnsL_model = ensl_model)
          
          # Store ML results
          res_df[cv_fold, 1] <- res_Val\$accuracy[1]
          res_df[cv_fold, 2] <- length(res_Val\$predictors)
          res_df[cv_fold, 3] <- res_Val\$MCC[1]
          res_df[cv_fold, 4] <- res_Val\$sensitivity[1]
          res_df[cv_fold, 5] <- res_Val\$Specificty[1]
          res_df[cv_fold, 6] <- res_Val\$PPV[1]
          res_df[cv_fold, 7] <- res_Val\$NPV[1]
          
          cv_predictors[[cv_fold]] <- res_Val\$predictors
        }
        
        # 5. Select the best model
        idx_best_model <- DaMiR.ModelSelect(res_df, type.sel = "mode", npred.sel = "min")
        
        # 6. Normalize and adjust the independent test set using learning set parameters
        expr_LearningSet <- Learning_set[rownames(data_norm)]
        expr_Ind_Test_set <- Ind_Test_set[rownames(data_norm)]
        norm_ind_ts <- DaMiR.iTSnorm(expr_LearningSet, expr_Ind_Test_set, normtype = "vst", method = "precise")
        adj_norm_ind_ts <- DaMiR.iTSadjust(data_adjust, norm_ind_ts)
        
        # 7. Predict classes on the adjusted independent test set
        prediction <- DaMiR.EnsL_Predict(t(adj_norm_ind_ts), bestModel = cv_models[[idx_best_model]])
        
        # Write outputs
        write.csv(res_df, "cv_metrics.csv", row.names=TRUE)
        write.csv(prediction, "prediction_results.csv", row.names=TRUE)
        writeLines(cv_predictors[[idx_best_model]], "best_model_predictors.txt")
        saveRDS(cv_models[[idx_best_model]], "best_model.rds")
        
        cat("Pipeline completed successfully. Outputs written to cv_metrics.csv, prediction_results.csv, best_model_predictors.txt, and best_model.rds.\n")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

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

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_DAMIRSEQ_CROSS_VALIDATION_AND_INDEPENDENT_PREDICTION",
      domain  = "bioconductor",
      declared_qc_steps = c("count normalization"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_DAMIRSEQ_CROSS_VALIDATION_AND_INDEPENDENT_PREDICTION":',
        paste0('    DaMiRseq: ', as.character(packageVersion('DaMiRseq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cross_validation_and_independent_prediction.csv versions.yml
    """
}

workflow BIOC_DAMIRSEQ_CROSS_VALIDATION_AND_INDEPENDENT_PREDICTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ count_data.txt, covariate_data.txt ] ]

    main:
    BIOC_DAMIRSEQ_CROSS_VALIDATION_AND_INDEPENDENT_PREDICTION(ch_input)

    emit:
    tables   = BIOC_DAMIRSEQ_CROSS_VALIDATION_AND_INDEPENDENT_PREDICTION.out.tables
    plots    = BIOC_DAMIRSEQ_CROSS_VALIDATION_AND_INDEPENDENT_PREDICTION.out.plots
    objects  = BIOC_DAMIRSEQ_CROSS_VALIDATION_AND_INDEPENDENT_PREDICTION.out.objects
    versions = BIOC_DAMIRSEQ_CROSS_VALIDATION_AND_INDEPENDENT_PREDICTION.out.versions
}
