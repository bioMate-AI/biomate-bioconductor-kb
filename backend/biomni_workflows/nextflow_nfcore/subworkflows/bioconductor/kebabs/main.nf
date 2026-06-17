#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: kebabs — binary_sequence_classification
// Train a support vector machine classifier on biological sequences to predict binary labels and evaluate performance.
// Input: sequences.fasta, labels.txt
// Container: quay.io/biocontainers/bioconductor-kebabs:1.44.0--r45ha27e39d_0
// R packages: Biostrings, apcluster, BSgenome, kebabs
// Bioconductor: 3.20 | R: 4.4
// Requires: Biostrings, kebabs
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define the sequence kernel
//  * 2. [Core Analysis] Train the SVM model using kbsvm
//  * 3. [Core Analysis] Predict labels on test sequences
//  * 4. [Core Analysis] Evaluate prediction performance

nextflow.enable.dsl = 2

process BIOC_KEBABS_BINARY_SEQUENCE_CLASSIFICATION {
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
    .bm_deps <- c("Biostrings", "apcluster", "BSgenome", "kebabs")
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
    
    # -----------------------------------------------------------------------------
    # Stage 0: Read User Input Files
    # -----------------------------------------------------------------------------
    # Read DNA sequences from the FASTA file
    enhancerFB <- readDNAStringSet("sequences.fasta")
    
    # Read binary class labels from the text file
    yFB <- scan("labels.txt", quiet = TRUE)
    
    # Validate inputs
    if (length(enhancerFB) != length(yFB)) {
      stop("Error: The number of sequences in 'sequences.fasta' must match the number of labels in 'labels.txt'.")
    }
    
    # -----------------------------------------------------------------------------
    # Stage 1: Prepare Train/Test Split
    # -----------------------------------------------------------------------------
    numSamples <- length(enhancerFB)
    trainingFraction <- 0.7
    
    # Set seed for reproducibility of the split
    set.seed(42)
    train <- sample(1:numSamples, trainingFraction * numSamples)
    test <- c(1:numSamples)[-train]
    
    # -----------------------------------------------------------------------------
    # Stage 2: Execute Documented Workflow
    # -----------------------------------------------------------------------------
    # 1. Define the sequence kernel
    specK2 <- spectrumKernel(k=2)
    
    # 2. Train the SVM model using kbsvm
    model <- kbsvm(x=enhancerFB[train], y=yFB[train], kernel=specK2,
                   pkg="e1071", svm="C-svc", cost=15)
    
    # 3. Predict labels on test sequences
    pred <- predict(model, enhancerFB[test])
    
    # 4. Evaluate prediction performance
    eval_res <- evaluatePrediction(pred, yFB[test], allLabels=unique(yFB))
    
    # -----------------------------------------------------------------------------
    # Stage 3: Write Named Output Files
    # -----------------------------------------------------------------------------
    # Save the trained SVM model object
    saveRDS(model, "kebabs_model.rds")
    
    # Save predictions and true labels to a CSV file
    predictions_df <- data.frame(
      Sequence_Index = test,
      True_Label = yFB[test],
      Predicted_Label = as.vector(pred)
    )
    write.csv(predictions_df, "predictions.csv", row.names = FALSE)
    
    # Save the evaluation metrics object
    saveRDS(eval_res, "evaluation_metrics.rds")
    
    # Write a text summary of the evaluation performance
    sink("evaluation_summary.txt")
    print(eval_res)
    sink()
    
    # Generate and save ROC curve plot
    tryCatch({
      preddec <- predict(model, enhancerFB[test], predictionType = "decision")
      rocdata <- computeROCandAUC(preddec, yFB[test], unique(yFB))
      pdf("roc_curve.pdf", width = 6, height = 6)
      plot(rocdata, main = "Receiver Operating Characteristics", col = "red", lwd = 2)
      dev.off()
    }, error = function(e) {
      warning("Could not generate ROC plot: ", e\$message)
    })

    writeLines(c(
        '"BIOC_KEBABS_BINARY_SEQUENCE_CLASSIFICATION":',
        paste0('    kebabs: ', as.character(packageVersion('kebabs')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_binary_sequence_classification.csv versions.yml
    """
}

workflow BIOC_KEBABS_BINARY_SEQUENCE_CLASSIFICATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sequences.fasta, labels.txt ] ]

    main:
    BIOC_KEBABS_BINARY_SEQUENCE_CLASSIFICATION(ch_input)

    emit:
    tables   = BIOC_KEBABS_BINARY_SEQUENCE_CLASSIFICATION.out.tables
    plots    = BIOC_KEBABS_BINARY_SEQUENCE_CLASSIFICATION.out.plots
    objects  = BIOC_KEBABS_BINARY_SEQUENCE_CLASSIFICATION.out.objects
    versions = BIOC_KEBABS_BINARY_SEQUENCE_CLASSIFICATION.out.versions
}
