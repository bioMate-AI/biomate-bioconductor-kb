#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: switchBox — ktsp_classifier_training_and_prediction
// Train a KTSP classifier on a training dataset (with optional filtering or restricted pairs) and use it to classify new test samples.
// Input: matTraining, trainingGroup, matTesting
// Container: quay.io/biocontainers/bioconductor-switchbox:1.46.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: switchBox
// Visualizations: heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Train the KTSP classifier using SWAP.Train.KTSP
//  * 2. [Core Analysis] Compute and aggregate TSP votes/statistics using SWAP.KTSP.Statistics
//  * 3. [Core Analysis] Classify training samples to check resubstitution performance using SWAP.KTSP.Classify
//  * 4. [Core Analysis] Classify new test samples using SWAP.KTSP.Classify
//  * 5. [Core Analysis] Calculate signed TSP scores using SWAP.CalculateSignedScore

nextflow.enable.dsl = 2

process BIOC_SWITCHBOX_KTSP_CLASSIFIER_TRAINING_AND_PREDICTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("switchBox")
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
    library(switchBox)
    
    # Helper function to read input files from the working directory
    read_input <- function(base_name) {
      rds_path <- paste0(base_name, ".rds")
      csv_path <- paste0(base_name, ".csv")
      
      if (file.exists(rds_path)) {
        message("Reading ", rds_path)
        return(readRDS(rds_path))
      } else if (file.exists(csv_path)) {
        message("Reading ", csv_path)
        df <- read.csv(csv_path, row.names = 1, check.names = FALSE)
        if (base_name == "trainingGroup") {
          return(as.factor(df[[1]]))
        } else {
          return(as.matrix(df))
        }
      } else {
        stop(paste("Required input file not found in working directory:", base_name))
      }
    }
    
    # Load user inputs
    matTraining <- read_input("matTraining")
    trainingGroup <- read_input("trainingGroup")
    matTesting <- read_input("matTesting")
    
    # Define alternative filtering function based on t-test (from vignette)
    topRttest <- function(situation, data, quant = 0.75) {
      out <- apply(data, 1, function(x, ...) t.test(x ~ situation)\$statistic )
      names(out[ abs(out) > quantile(abs(out), quant) ])
    }
    
    # Generate RestrictedPairs robustly based on the input features
    set.seed(123)
    n_genes <- nrow(matTraining)
    if (n_genes >= 36) {
      somePairs <- matrix(sample(rownames(matTraining), 36, replace = FALSE), ncol = 2)
    } else {
      # Fallback: sample with replacement but ensure distinct genes in each pair
      pairs_list <- list()
      gene_names <- rownames(matTraining)
      if (length(gene_names) < 2) {
        stop("matTraining must have at least 2 features (rows) to form pairs.")
      }
      while (length(pairs_list) < 18) {
        p <- sample(gene_names, 2, replace = FALSE)
        pairs_list[[paste(p, collapse = "-")]] <- p
      }
      somePairs <- do.call(rbind, pairs_list)
    }
    
    # ==========================================
    # STAGE 1: Train the KTSP classifier using SWAP.Train.KTSP
    # ==========================================
    message("Training classifiers...")
    
    # 1.1 Default training with krange
    classifier1 <- SWAP.Train.KTSP(matTraining, trainingGroup, krange = c(3:15))
    saveRDS(classifier1, "classifier_krange.rds")
    
    # 1.2 Training with Wilcoxon filtering
    classifier2 <- SWAP.Train.KTSP(matTraining, trainingGroup, FilterFunc = SWAP.Filter.Wilcoxon, featureNo = 4)
    saveRDS(classifier2, "classifier_wilcoxon.rds")
    
    # 1.3 Training with no filtering
    classifier3 <- SWAP.Train.KTSP(matTraining, trainingGroup, FilterFunc = NULL)
    saveRDS(classifier3, "classifier_nofilter.rds")
    
    # 1.4 Training with t-test filtering and krange (with fallback if krange is too large for feature set)
    safe_krange_rttest <- c(15:min(30, max(15, floor(nrow(matTraining)/2))))
    classifier4 <- tryCatch({
      SWAP.Train.KTSP(matTraining, trainingGroup, FilterFunc = topRttest, quant = 0.9, krange = c(15:30))
    }, error = function(e) {
      warning("Could not train with krange=15:30, trying a smaller safe krange: ", e\$message)
      SWAP.Train.KTSP(matTraining, trainingGroup, FilterFunc = topRttest, quant = 0.9, krange = safe_krange_rttest)
    })
    saveRDS(classifier4, "classifier_rttest.rds")
    
    # 1.5 Training with RestrictedPairs
    classifier5 <- tryCatch({
      SWAP.Train.KTSP(matTraining, trainingGroup, RestrictedPairs = somePairs, krange = 3:16)
    }, error = function(e) {
      warning("Could not train with RestrictedPairs and krange=3:16, trying a smaller safe krange: ", e\$message)
      safe_krange_restricted <- 3:min(16, max(3, nrow(somePairs)))
      SWAP.Train.KTSP(matTraining, trainingGroup, RestrictedPairs = somePairs, krange = safe_krange_restricted)
    })
    saveRDS(classifier5, "classifier_restricted.rds")
    
    # Set up active classifier for subsequent steps (matching vignette flow)
    safe_krange_default <- 2:min(8, max(2, floor(nrow(matTraining)/2)))
    classifier <- tryCatch({
      SWAP.Train.KTSP(matTraining, trainingGroup, FilterFunc = NULL, krange = 2:8)
    }, error = function(e) {
      SWAP.Train.KTSP(matTraining, trainingGroup, FilterFunc = NULL, krange = safe_krange_default)
    })
    saveRDS(classifier, "classifier_active.rds")
    
    
    # ==========================================
    # STAGE 2: Compute and aggregate TSP votes/statistics using SWAP.KTSP.Statistics
    # ==========================================
    message("Computing TSP statistics...")
    
    ktspStatDefault <- SWAP.KTSP.Statistics(inputMat = matTraining, classifier = classifier)
    saveRDS(ktspStatDefault, "ktsp_statistics_default.rds")
    
    ktspStatSum <- SWAP.KTSP.Statistics(inputMat = matTraining, classifier = classifier, CombineFunc = sum)
    saveRDS(ktspStatSum, "ktsp_statistics_sum.rds")
    
    ktspStatThreshold <- SWAP.KTSP.Statistics(inputMat = matTraining, classifier = classifier, CombineFunc = function(x) sum(x) > 2)
    saveRDS(ktspStatThreshold, "ktsp_statistics_threshold.rds")
    
    # Generate Heatmap of individual TSP votes
    pdf("tsp_votes_heatmap.pdf", width = 8, height = 8)
    colorForRows <- as.character(1 + as.numeric(trainingGroup))
    heatmap(1 * ktspStatThreshold\$comparisons, scale = "none",
            margins = c(10, 5), cexCol = 0.85, cexRow = 1,
            labRow = trainingGroup, RowSideColors = colorForRows)
    dev.off()
    
    
    # ==========================================
    # STAGE 3: Classify training samples to check resubstitution performance using SWAP.KTSP.Classify
    # ==========================================
    message("Classifying training samples...")
    
    trainingPrediction1 <- SWAP.KTSP.Classify(matTraining, classifier)
    trainingPrediction2 <- SWAP.KTSP.Classify(matTraining, classifier, DecisionFunc = function(x) sum(x) > 5.5)
    
    # Save training predictions
    training_df <- data.frame(
      Sample = colnames(matTraining),
      Prediction_Default = as.character(trainingPrediction1),
      Prediction_Threshold = as.character(trainingPrediction2),
      True_Group = as.character(trainingGroup),
      stringsAsFactors = FALSE
    )
    write.csv(training_df, "training_predictions.csv", row.names = FALSE)
    
    
    # ==========================================
    # STAGE 4: Classify new test samples using SWAP.KTSP.Classify
    # ==========================================
    message("Classifying test samples...")
    
    # Classify single sample
    testPrediction1 <- SWAP.KTSP.Classify(matTesting[ , 1, drop = FALSE], classifier)
    saveRDS(testPrediction1, "test_prediction_single.rds")
    
    # Classify complete test set
    testPrediction2 <- SWAP.KTSP.Classify(matTesting, classifier)
    testPrediction3 <- SWAP.KTSP.Classify(matTesting, classifier, DecisionFunc = function(x) sum(x) > 5.5)
    
    # Save test predictions
    test_df <- data.frame(
      Sample = colnames(matTesting),
      Prediction_Default = as.character(testPrediction2),
      Prediction_Threshold = as.character(testPrediction3),
      stringsAsFactors = FALSE
    )
    write.csv(test_df, "test_predictions.csv", row.names = FALSE)
    
    
    # ==========================================
    # STAGE 5: Calculate signed TSP scores using SWAP.CalculateSignedScore
    # ==========================================
    message("Calculating signed TSP scores...")
    
    scores1 <- SWAP.CalculateSignedScore(matTraining, trainingGroup, FilterFunc = NULL)
    saveRDS(scores1, "signed_scores_nofilter.rds")
    
    safe_featureNo <- min(20, nrow(matTraining))
    scores2 <- tryCatch({
      SWAP.CalculateSignedScore(matTraining, trainingGroup, featureNo = 20)
    }, error = function(e) {
      SWAP.CalculateSignedScore(matTraining, trainingGroup, featureNo = safe_featureNo)
    })
    saveRDS(scores2, "signed_scores_wilcoxon.rds")
    
    scores3 <- SWAP.CalculateSignedScore(matTraining, trainingGroup, FilterFunc = NULL, RestrictedPairs = somePairs)
    saveRDS(scores3, "signed_scores_restricted.rds")
    
    # Generate Histogram of scores
    pdf("tsp_scores_histogram.pdf", width = 6, height = 6)
    hist(scores3\$score, col = "salmon", main = "TSP scores")
    dev.off()
    
    message("Pipeline completed successfully. All outputs saved to the working directory.")

    writeLines(c(
        '"BIOC_SWITCHBOX_KTSP_CLASSIFIER_TRAINING_AND_PREDICTION":',
        paste0('    switchBox: ', as.character(packageVersion('switchBox')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ktsp_classifier_training_and_prediction.csv versions.yml
    """
}

workflow BIOC_SWITCHBOX_KTSP_CLASSIFIER_TRAINING_AND_PREDICTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ matTraining, trainingGroup, matTesting ] ]

    main:
    BIOC_SWITCHBOX_KTSP_CLASSIFIER_TRAINING_AND_PREDICTION(ch_input)

    emit:
    tables   = BIOC_SWITCHBOX_KTSP_CLASSIFIER_TRAINING_AND_PREDICTION.out.tables
    plots    = BIOC_SWITCHBOX_KTSP_CLASSIFIER_TRAINING_AND_PREDICTION.out.plots
    objects  = BIOC_SWITCHBOX_KTSP_CLASSIFIER_TRAINING_AND_PREDICTION.out.objects
    versions = BIOC_SWITCHBOX_KTSP_CLASSIFIER_TRAINING_AND_PREDICTION.out.versions
}
