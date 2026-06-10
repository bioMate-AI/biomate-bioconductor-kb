#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: kebabs — sequence_regression_and_feature_weights
// Train a regression model on biological sequences to predict continuous values and extract feature weights.
// Input: sequences.fasta, values.txt
// Container: quay.io/biocontainers/bioconductor-kebabs:1.44.0--r45ha27e39d_0
// R packages: Biostrings, kebabs
// Bioconductor: 3.20 | R: 4.4
// Requires: Biostrings, kebabs
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define the sequence kernel
//  * 2. [Core Analysis] Train a support vector regression model
//  * 3. [Core Analysis] Predict continuous values
//  * 4. [Core Analysis] Extract feature weights

nextflow.enable.dsl = 2

process BIOC_KEBABS_SEQUENCE_REGRESSION_AND_FEATURE_WEIGHTS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("Biostrings", "kebabs")
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
    library(kebabs)
    library(Biostrings)
    
    # 1. Read user input files
    # Read biological sequences from sequences.fasta
    enhancerFB <- readDNAStringSet("sequences.fasta")
    
    # Read continuous numeric response variables from values.txt
    yReg <- scan("values.txt", what = numeric(), quiet = TRUE)
    
    # Ensure the number of sequences matches the number of response values
    if (length(enhancerFB) != length(yReg)) {
        stop("Error: The number of sequences in 'sequences.fasta' must match the number of values in 'values.txt'.")
    }
    
    # Define train and test splits (70% training, 30% testing)
    set.seed(123) # Set seed for reproducible split
    numSamples <- length(enhancerFB)
    trainingFraction <- 0.7
    train <- sample(1:numSamples, floor(trainingFraction * numSamples))
    test <- seq_len(numSamples)[-train]
    
    # 2. Define the sequence kernel
    gappyK1M2 <- gappyPairKernel(k=1, m=2)
    
    # 3. Train a support vector regression model
    model <- kbsvm(x=enhancerFB[train], y=yReg[train],
                   kernel=gappyK1M2, pkg="e1071", svm="nu-svr",
                   nu=0.7)
    
    # 4. Predict continuous values
    pred <- predict(model, enhancerFB[test])
    
    # 5. Extract feature weights
    featWeights <- featureWeights(model)
    
    # 6. Write meaningful results to output files
    # Save the trained model object
    saveRDS(model, file = "regression_model.rds")
    
    # Save predictions alongside true values
    predictions_df <- data.frame(
        Sequence_Index = test,
        True_Value = yReg[test],
        Predicted_Value = as.numeric(pred)
    )
    write.csv(predictions_df, file = "predictions.csv", row.names = FALSE)
    
    # Save feature weights as a CSV table
    # Feature weights are returned as a dense matrix or vector depending on the model
    feat_weights_df <- as.data.frame(as.matrix(featWeights))
    write.csv(feat_weights_df, file = "feature_weights.csv", row.names = TRUE)
    
    # Generate a PDF plot of Predicted vs. True values
    pdf("predictions_vs_true.pdf", width = 6, height = 6)
    plot(yReg[test], pred, 
         xlab = "True Values", 
         ylab = "Predicted Values", 
         main = "SVR Predictions vs True Values",
         pch = 19, col = "blue")
    abline(0, 1, col = "red", lty = 2, lwd = 2)
    dev.off()

    writeLines(c(
        '"BIOC_KEBABS_SEQUENCE_REGRESSION_AND_FEATURE_WEIGHTS":',
        paste0('    kebabs: ', as.character(packageVersion('kebabs')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sequence_regression_and_feature_weights.csv versions.yml
    """
}

workflow BIOC_KEBABS_SEQUENCE_REGRESSION_AND_FEATURE_WEIGHTS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sequences.fasta, values.txt ] ]

    main:
    BIOC_KEBABS_SEQUENCE_REGRESSION_AND_FEATURE_WEIGHTS(ch_input)

    emit:
    tables   = BIOC_KEBABS_SEQUENCE_REGRESSION_AND_FEATURE_WEIGHTS.out.tables
    plots    = BIOC_KEBABS_SEQUENCE_REGRESSION_AND_FEATURE_WEIGHTS.out.plots
    objects  = BIOC_KEBABS_SEQUENCE_REGRESSION_AND_FEATURE_WEIGHTS.out.objects
    versions = BIOC_KEBABS_SEQUENCE_REGRESSION_AND_FEATURE_WEIGHTS.out.versions
}
