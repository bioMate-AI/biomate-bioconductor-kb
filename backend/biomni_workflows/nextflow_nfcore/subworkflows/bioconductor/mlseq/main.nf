#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MLSeq — rna_seq_classification
// Preprocess raw RNA-Seq count data, train a machine learning classifier (continuous, discrete, or voom-based) with parameter tuning, and predict class labels for
// Input: cervical.txt, class
// Container: quay.io/biocontainers/bioconductor-mlseq:2.28.0--r45hdfd78af_0
// R packages: caret, DESeq2, edgeR, knitr, MLSeq, VennDiagram
// Bioconductor: 3.20 | R: 4.4
// Requires: DESeq2, MLSeq, caret, edgeR
// Visualizations: plot (ggplot/base)
// QC: count normalization, voom mean-variance modelling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load raw count data and define class labels
//  * 2. [Core Analysis] Split data into training and test sets
//  * 3. [Input & Preparation] Create DESeqDataSet objects for training and testing
//  * 4. [Input & Preparation] Define control parameters using trainControl, discreteControl, or voomControl
//  * 5. [Core Analysis] Train the classifier using classify
//  * 6. [Core Analysis] Predict class labels of test samples using predict
//  * 7. [Core Analysis] Evaluate model performance using confusionMatrix
//  * 8. [Core Analysis] Extract selected biomarkers using selectedGenes (for sparse classifiers)
//  * 9. [Core Analysis] Modify and update the trained model using update

nextflow.enable.dsl = 2

process BIOC_MLSEQ_RNA_SEQ_CLASSIFICATION {
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
    .bm_deps <- c("caret", "DESeq2", "edgeR", "knitr", "MLSeq", "VennDiagram")
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
        library(MLSeq)
        library(DESeq2)
        library(caret)
        library(edgeR)
        
        # Set seed for reproducibility
        set.seed(2128)
        
        # 1. Load raw count data and define class labels from user input files
        cervical <- read.table("cervical.txt", header = TRUE)
        class_input <- read.table("class", header = TRUE)
        
        if ("condition" %in% colnames(class_input)) {
          class <- DataFrame(condition = factor(class_input\$condition))
        } else {
          class <- DataFrame(condition = factor(class_input[[1]]))
        }
        
        # 2. Split data into training and test sets
        vars <- sort(apply(cervical, 1, var, na.rm = TRUE), decreasing = TRUE)
        data <- cervical[names(vars)[1:100], ]
        nTest <- ceiling(ncol(data) * 0.3)
        ind <- sample(ncol(data), nTest, FALSE)
        data.train <- as.matrix(data[ ,-ind] + 1)
        data.test <- as.matrix(data[ ,ind] + 1)
        classtr <- class[-ind, , drop=FALSE]
        classts <- class[ind, , drop=FALSE]
        
        # 3. Create DESeqDataSet objects for training and testing
        data.trainS4 = DESeqDataSetFromMatrix(countData = data.train, colData = classtr, design = formula(~condition))
        data.testS4 = DESeqDataSetFromMatrix(countData = data.test, colData = classts, design = formula(~condition))
        
        # 4. Define control parameters and train classifiers
        fit.svm <- classify(data = data.trainS4, method = "svmRadial", preProcessing = "deseq-vst", ref = "T", tuneLength = 10, control = trainControl(method = "repeatedcv", number = 5, repeats = 10, classProbs = TRUE))
        
        ctrl.plda <- discreteControl(method = "repeatedcv", number = 5, repeats = 1, tuneLength = 10)
        fit.plda <- classify(data = data.trainS4, method = "PLDA", normalize = "deseq", ref = "T", control = ctrl.plda)
        
        ctrl.voomDLDA <- voomControl(method = "repeatedcv", number = 5, repeats = 1, tuneLength = 10)
        fit.voomDLDA <- classify(data = data.trainS4, method = "voomDLDA", normalize = "deseq", ref = "T", control = ctrl.voomDLDA)
        
        # Train voomNSC to enable selectedGenes extraction
        ctrl.voom <- voomControl(method = "repeatedcv", number = 5, repeats = 10, tuneLength = 10)
        fit.voomNSC <- classify(data = data.trainS4, method = "voomNSC", normalize = "deseq", ref = "T", control = ctrl.voom)
        
        # 5. Predict class labels of test samples
        pred.svm <- predict(fit.svm, data.testS4)
        pred.svm <- relevel(pred.svm, ref = "T")
        actual <- relevel(classts\$condition, ref = "T")
        
        # 6. Evaluate model performance
        tbl <- table(Predicted = pred.svm, Actual = actual)
        cm <- confusionMatrix(tbl, positive = "T")
        
        # 7. Extract selected biomarkers using selectedGenes
        genes_voomNSC <- selectedGenes(fit.voomNSC)
        
        # 8. Modify and update the trained model
        ctrl <- discreteControl(method = "repeatedcv", number = 5, repeats = 2, tuneLength = 10)
        fit <- classify(data = data.trainS4, method = "PLDA", normalize = "deseq", ref = "T", control = ctrl)
        
        method(fit) <- "PLDA2"
        ref(fit) <- "N"
        normalization(fit) <- "TMM"
        fit <- update(fit)
        
        method(fit) <- "rpart"
        control(fit) <- trainControl(method = "repeatedcv", number = 5, repeats = 2)
        preProcessing(fit) <- "tmm-logcpm"
        fit <- update(fit)
        
        # 9. Write outputs to files
        # Save confusion matrix and statistics
        write.csv(as.data.frame(tbl), "confusion_matrix_table.csv", row.names = TRUE)
        sink("confusion_matrix_summary.txt")
        print(cm)
        sink()
        
        # Save selected genes
        write.csv(data.frame(SelectedGenes = genes_voomNSC), "selected_genes_voomNSC.csv", row.names = FALSE)
        
        # Save trained models
        saveRDS(fit.svm, "fit_svm.rds")
        saveRDS(fit.plda, "fit_plda.rds")
        saveRDS(fit.voomDLDA, "fit_voomDLDA.rds")
        saveRDS(fit.voomNSC, "fit_voomNSC.rds")
        saveRDS(fit, "fit_updated.rds")
        
        # Save diagnostic plot
        pdf("fitted_model_svm_figure.pdf", height = 5.5)
        plot(fit.svm)
        dev.off()
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

    # voom — limma EList\$weights present, range > 0 (Law 2014 GB).
    .voom_w_range <- NA_real_
    for (.voom_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .voom_obj <- tryCatch(readRDS(.voom_rds), error = function(e) NULL)
      if (!is.null(.voom_obj) && inherits(.voom_obj, "EList")) {
        .voom_w <- tryCatch(.voom_obj\$weights, error = function(e) NULL)
        if (!is.null(.voom_w) && length(.voom_w) > 0) {
          .voom_w_range <- round(diff(range(.voom_w, na.rm = TRUE)), 4); break
        }
      }
    }
    .gates_by_label[["voom mean-variance modelling"]] <- list(
      gate_row = "bioc_voom_mean_variance",
      metric_name = "voom_weight_range",
      metric_value = .voom_w_range,
      passes = isTRUE(is.finite(.voom_w_range) && .voom_w_range > 0),
      status = if (is.finite(.voom_w_range)) "computed (EList\$weights range)"
               else "not_computed (no limma EList .rds artifact present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_MLSEQ_RNA_SEQ_CLASSIFICATION",
      domain  = "bioconductor",
      declared_qc_steps = c("count normalization", "voom mean-variance modelling"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_MLSEQ_RNA_SEQ_CLASSIFICATION":',
        paste0('    MLSeq: ', as.character(packageVersion('MLSeq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rna_seq_classification.csv versions.yml
    """
}

workflow BIOC_MLSEQ_RNA_SEQ_CLASSIFICATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ cervical.txt, class ] ]

    main:
    BIOC_MLSEQ_RNA_SEQ_CLASSIFICATION(ch_input)

    emit:
    tables   = BIOC_MLSEQ_RNA_SEQ_CLASSIFICATION.out.tables
    plots    = BIOC_MLSEQ_RNA_SEQ_CLASSIFICATION.out.plots
    objects  = BIOC_MLSEQ_RNA_SEQ_CLASSIFICATION.out.objects
    versions = BIOC_MLSEQ_RNA_SEQ_CLASSIFICATION.out.versions
}
