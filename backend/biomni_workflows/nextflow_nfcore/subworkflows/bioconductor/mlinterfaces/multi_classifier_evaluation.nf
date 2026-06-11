#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MLInterfaces — multi_classifier_evaluation
// Train, cross-validate, and compare multiple machine learning classifiers (Random Forest, LDA, SVM) on a dataset.
// Input: crES
// Container: quay.io/biocontainers/bioconductor-mlinterfaces:1.90.0--r45ha27e39d_0
// R packages: Biobase, MASS, MLInterfaces, e1071, randomForest
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, MLInterfaces, e1071, randomForest
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Train and test a Random Forest classifier using a split-sample approach
//  * 2. [Core Analysis] Train and test a Linear Discriminant Analysis (LDA) classifier using split-sample and balanced 5-fold cross-validation
//  * 3. [Core Analysis] Train and test a Support Vector Machine (SVM) classifier

nextflow.enable.dsl = 2

process BIOC_MLINTERFACES_MULTI_CLASSIFIER_EVALUATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    .bm_deps <- c("Biobase", "MASS", "MLInterfaces", "e1071", "randomForest")
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
        library(MLInterfaces)
        library(randomForest)
        library(MASS)
        library(e1071)
        library(Biobase)
        
        # ----------------------------------------------------------------------
        # 1. Read User Input
        # ----------------------------------------------------------------------
        # Read the crES object from the working directory (expecting RDS format)
        if (file.exists("crES.rds")) {
          crES <- readRDS("crES.rds")
        } else if (file.exists("crES")) {
          crES <- readRDS("crES")
        } else {
          stop("Required input file 'crES' or 'crES.rds' not found in the working directory.")
        }
        
        # Ensure the response variable is explicitly cast as a factor
        # to prevent randomForest from attempting regression.
        # Dynamically determine the response variable and number of samples.
        if (is(crES, "ExpressionSet")) {
          resp_var <- varLabels(crES)[1]
          n_samples <- ncol(crES)
        } else if (is.data.frame(crES)) {
          resp_var <- colnames(crES)[ncol(crES)]
          n_samples <- nrow(crES)
        } else {
          stop("Input must be an ExpressionSet or a data.frame.")
        }
        
        crES[[resp_var]] <- factor(crES[[resp_var]])
        form <- as.formula(paste(resp_var, "~ ."))
        
        # Dynamically set training indices to 70% of the dataset to prevent out-of-bounds errors
        trainInd <- 1:floor(n_samples * 0.7)
        
        # ----------------------------------------------------------------------
        # 2. Execute Documented Workflow
        # ----------------------------------------------------------------------
        
        # Stage 1: Train and test a Random Forest classifier using a split-sample approach
        rf1 = MLearn(form, crES, randomForestI, trainInd )
        rf1_conf <- confuMat(rf1)
        print("Random Forest Confusion Matrix:")
        print(rf1_conf)
        
        # Stage 2: Train and test a Linear Discriminant Analysis (LDA) classifier
        # using split-sample and balanced 5-fold cross-validation
        ld1 = MLearn(form, crES, ldaI, trainInd )
        ld1_conf <- confuMat(ld1)
        print("LDA Split-Sample Confusion Matrix:")
        print(ld1_conf)
        
        xvld = MLearn( form, crES, ldaI, xvalSpec("LOG", 5,balKfold.xvspec(5)))
        xvld_conf <- confuMat(xvld)
        print("LDA Cross-Validation Confusion Matrix:")
        print(xvld_conf)
        
        # Stage 3: Train and test a Support Vector Machine (SVM) classifier
        sv1 = MLearn(form, crES, svmI, trainInd)
        sv1_conf <- confuMat(sv1)
        print("SVM Confusion Matrix:")
        print(sv1_conf)
        
        # ----------------------------------------------------------------------
        # 3. Write Outputs
        # ----------------------------------------------------------------------
        # Save confusion matrices as CSV files using as.data.frame.matrix to preserve 2D structure
        write.csv(as.data.frame.matrix(rf1_conf), "rf1_confusion_matrix.csv", row.names = TRUE)
        write.csv(as.data.frame.matrix(ld1_conf), "ld1_confusion_matrix.csv", row.names = TRUE)
        write.csv(as.data.frame.matrix(xvld_conf), "xvld_confusion_matrix.csv", row.names = TRUE)
        write.csv(as.data.frame.matrix(sv1_conf), "sv1_confusion_matrix.csv", row.names = TRUE)
        
        # Save the classifier output objects as RDS files
        saveRDS(rf1, "rf1_classifier.rds")
        saveRDS(ld1, "ld1_classifier.rds")
        saveRDS(xvld, "xvld_classifier.rds")
        saveRDS(sv1, "sv1_classifier.rds")

    writeLines(c(
        '"BIOC_MLINTERFACES_MULTI_CLASSIFIER_EVALUATION":',
        paste0('    MLInterfaces: ', as.character(packageVersion('MLInterfaces')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multi_classifier_evaluation.csv versions.yml
    """
}

workflow BIOC_MLINTERFACES_MULTI_CLASSIFIER_EVALUATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ crES ] ]

    main:
    BIOC_MLINTERFACES_MULTI_CLASSIFIER_EVALUATION(ch_input)

    emit:
    tables   = BIOC_MLINTERFACES_MULTI_CLASSIFIER_EVALUATION.out.tables
    plots    = BIOC_MLINTERFACES_MULTI_CLASSIFIER_EVALUATION.out.plots
    objects  = BIOC_MLINTERFACES_MULTI_CLASSIFIER_EVALUATION.out.objects
    versions = BIOC_MLINTERFACES_MULTI_CLASSIFIER_EVALUATION.out.versions
}
