#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: iterativeBMA — microarray_binary_classification
// Perform gene selection and binary classification on microarray expression data using iterative Bayesian Model Averaging.
// Input: trainData, trainClass, testData, testClass
// Container: quay.io/biocontainers/bioconductor-iterativebma:1.68.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, iterativeBMA
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the training and test ExpressionSet data and class labels
//  * 2. [Core Analysis] Train the iterative BMA model to select relevant genes using iterateBMAglm.train
//  * 3. [Core Analysis] Extract selected genes and model posterior probabilities
//  * 4. [Core Analysis] Predict class probabilities for test samples using bma.predict
//  * 5. [Core Analysis] Evaluate prediction accuracy using brier.score
//  * 6. [Core Analysis] Alternatively, perform training and prediction in a single step using iterateBMAglm.train.predict or iterateBMAglm.train.predict.t
//  * 7. [Visualization & Output] Visualize selected genes and models using imageplot.iterate.bma

nextflow.enable.dsl = 2

process BIOC_ITERATIVEBMA_MICROARRAY_BINARY_CLASSIFICATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("Biobase", "BMA", "iterativeBMA")
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
    library("Biobase")
    library("BMA")
    library("iterativeBMA")
    
    # Define input file paths
    train_data_path <- "trainData.rds"
    train_class_path <- "trainClass.rds"
    test_data_path <- "testData.rds"
    test_class_path <- "testClass.rds"
    
    # Verify input files exist
    if (!file.exists(train_data_path)) {
      stop(paste("Required input file missing:", train_data_path))
    }
    if (!file.exists(train_class_path)) {
      stop(paste("Required input file missing:", train_class_path))
    }
    if (!file.exists(test_data_path)) {
      stop(paste("Required input file missing:", test_data_path))
    }
    if (!file.exists(test_class_path)) {
      stop(paste("Required input file missing:", test_class_path))
    }
    
    # Load user input datasets
    trainData <- readRDS(train_data_path)
    trainClass <- readRDS(train_class_path)
    testData <- readRDS(test_data_path)
    testClass <- readRDS(test_class_path)
    
    # Validate input classes and types
    if (!inherits(trainData, "ExpressionSet")) {
      stop("trainData must be an ExpressionSet object.")
    }
    if (!inherits(testData, "ExpressionSet")) {
      stop("testData must be an ExpressionSet object.")
    }
    if (!is.numeric(trainClass) || !all(trainClass %in% c(0, 1))) {
      stop("trainClass must be a numeric vector of 0s and 1s.")
    }
    if (!is.numeric(testClass) || !all(testClass %in% c(0, 1))) {
      stop("testClass must be a numeric vector of 0s and 1s.")
    }
    
    # -------------------------------------------------------------------------
    # Step 2: Train the iterative BMA model to select relevant genes
    # -------------------------------------------------------------------------
    message("Training iterative BMA model...")
    ret.bic.glm <- iterateBMAglm.train (train.expr.set=trainData, trainClass, p=100)
    
    # Save the trained model object
    saveRDS(ret.bic.glm, file = "ret_bic_glm.rds")
    
    # -------------------------------------------------------------------------
    # Step 3: Extract selected genes and model posterior probabilities
    # -------------------------------------------------------------------------
    message("Extracting selected genes...")
    ret.gene.names <- ret.bic.glm\$namesx[ret.bic.glm\$probne0 > 0]
    
    # Create a summary data frame of selected genes and their probabilities
    selected_genes_df <- data.frame(
      Gene = ret.bic.glm\$namesx,
      ProbNe0 = ret.bic.glm\$probne0,
      stringsAsFactors = FALSE
    )
    # Filter to only those with probne0 > 0
    selected_genes_df <- selected_genes_df[selected_genes_df\$ProbNe0 > 0, ]
    write.csv(selected_genes_df, file = "selected_genes.csv", row.names = FALSE)
    
    # -------------------------------------------------------------------------
    # Step 4: Predict class probabilities for test samples using bma.predict
    # -------------------------------------------------------------------------
    message("Predicting class probabilities for test samples...")
    curr.test.dat <- t(exprs(testData)[ret.gene.names, , drop = FALSE])
    
    y.pred.test <- apply (curr.test.dat, 1, bma.predict, postprobArr=ret.bic.glm\$postprob, mleArr=ret.bic.glm\$mle)
    
    # Save predictions to CSV
    predictions_df <- data.frame(
      Sample = names(y.pred.test),
      Predicted_Probability = y.pred.test,
      True_Class = testClass,
      stringsAsFactors = FALSE
    )
    write.csv(predictions_df, file = "predictions_bma_predict.csv", row.names = FALSE)
    
    # -------------------------------------------------------------------------
    # Step 5: Evaluate prediction accuracy using brier.score
    # -------------------------------------------------------------------------
    message("Evaluating prediction accuracy...")
    brier_score_1 <- brier.score (y.pred.test, testClass)
    
    # -------------------------------------------------------------------------
    # Step 6: Alternative training and prediction in a single step
    # -------------------------------------------------------------------------
    message("Running iterateBMAglm.train.predict...")
    ret.vec <- iterateBMAglm.train.predict (train.expr.set=trainData, test.expr.set=testData, trainClass, p=100)
    
    brier_score_2 <- brier.score (ret.vec, testClass)
    
    # Save alternative predictions
    alt_predictions_df <- data.frame(
      Sample = names(ret.vec),
      Predicted_Probability = ret.vec,
      True_Class = testClass,
      stringsAsFactors = FALSE
    )
    write.csv(alt_predictions_df, file = "predictions_train_predict.csv", row.names = FALSE)
    
    message("Running iterateBMAglm.train.predict.test...")
    test_results <- iterateBMAglm.train.predict.test (train.expr.set=trainData, test.expr.set=testData, trainClass, testClass, p=100)
    
    # Save the test results list
    saveRDS(test_results, file = "train_predict_test_results.rds")
    
    # Write Brier scores and summary metrics to a text file
    sink("evaluation_summary.txt")
    cat("=== Evaluation Summary ===\n\n")
    cat("Brier Score (manual prediction):", brier_score_1, "\n")
    cat("Brier Score (train.predict):    ", brier_score_2, "\n\n")
    cat("iterateBMAglm.train.predict.test Results:\n")
    cat("Number of selected genes:       ", test_results\$num.genes, "\n")
    cat("Number of selected models:      ", test_results\$num.model, "\n")
    cat("Number of classification errors:", test_results\$num.err, "\n")
    cat("Brier Score:                    ", test_results\$brierScore, "\n")
    sink()
    
    # -------------------------------------------------------------------------
    # Step 7: Visualize selected genes and models using imageplot.iterate.bma
    # -------------------------------------------------------------------------
    message("Generating image plot...")
    pdf("imageplot_iterate_bma.pdf", width = 8, height = 8)
    imageplot.iterate.bma (ret.bic.glm)
    dev.off()
    
    message("Pipeline completed successfully. Outputs written to working directory.")

    writeLines(c(
        '"BIOC_ITERATIVEBMA_MICROARRAY_BINARY_CLASSIFICATION":',
        paste0('    iterativeBMA: ', as.character(packageVersion('iterativeBMA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_microarray_binary_classification.csv versions.yml
    """
}

workflow BIOC_ITERATIVEBMA_MICROARRAY_BINARY_CLASSIFICATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ trainData, trainClass, testData, testClass ] ]

    main:
    BIOC_ITERATIVEBMA_MICROARRAY_BINARY_CLASSIFICATION(ch_input)

    emit:
    tables   = BIOC_ITERATIVEBMA_MICROARRAY_BINARY_CLASSIFICATION.out.tables
    plots    = BIOC_ITERATIVEBMA_MICROARRAY_BINARY_CLASSIFICATION.out.plots
    objects  = BIOC_ITERATIVEBMA_MICROARRAY_BINARY_CLASSIFICATION.out.objects
    versions = BIOC_ITERATIVEBMA_MICROARRAY_BINARY_CLASSIFICATION.out.versions
}
