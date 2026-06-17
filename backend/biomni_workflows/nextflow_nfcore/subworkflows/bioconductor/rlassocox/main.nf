#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RLassoCox — rlasso_cox_survival_prediction
// Train a topologically weighted Lasso-Cox model with or without cross-validation to predict survival risk and identify prognostic gene biomarkers.
// Input: gene_expression.csv, survival_data.csv, gene_network.rds
// Container: quay.io/biocontainers/bioconductor-rlassocox:1.18.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: RLassoCox, igraph
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load gene expression, survival data, and the gene interaction network
//  * 2. [Core Analysis] Split data into training and testing sets
//  * 3. [Core Analysis] Train the RLasso-Cox model using network topology weights
//  * 4. [Core Analysis] Predict survival risk on test data using the trained model
//  * 5. [Core Analysis] Perform cross-validation to find the optimal lambda parameter
//  * 6. [Core Analysis] Extract active prognostic features and their coefficients at the optimal lambda
//  * 7. [Core Analysis] Predict survival risk on test data using the cross-validated model

nextflow.enable.dsl = 2

process BIOC_RLASSOCOX_RLASSO_COX_SURVIVAL_PREDICTION {
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
    .bm_deps <- c("RLassoCox", "igraph")
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
    library("RLassoCox")
    library("igraph")
    
    # 1. Load gene expression, survival data, and the gene interaction network
    mRNA_df <- read.csv("gene_expression.csv", row.names = 1, check.names = FALSE)
    mRNA_matrix <- as.matrix(mRNA_df)
    
    survData <- read.csv("survival_data.csv", row.names = 1)
    # Ensure survival data columns are named exactly "time" and "status" and status is numeric (0/1)
    survData\$status <- as.numeric(survData\$status)
    survData\$time <- as.numeric(survData\$time)
    
    dGMMirGraph <- readRDS("gene_network.rds")
    
    # 2. Split data into training and testing sets
    set.seed(20150122)
    train.Idx <- sample(1:dim(mRNA_matrix)[1], floor(2/3*dim(mRNA_matrix)[1]))
    test.Idx <- setdiff(1:dim(mRNA_matrix)[1], train.Idx)
    x.train <- mRNA_matrix[train.Idx ,]
    x.test <- mRNA_matrix[test.Idx ,]
    y.train <- survData[train.Idx,]
    y.test <- survData[test.Idx,]
    
    # 3. Train the RLasso-Cox model using network topology weights
    mod <- RLassoCox(x=x.train, y=y.train, globalGraph=dGMMirGraph)
    
    # Display topological weights
    head(mod\$PT)
    
    # Save plots to a PDF file
    pdf("rlassocox_analysis_plots.pdf", width = 8, height = 6)
    
    # Plot coefficient paths
    plot(mod\$glmnetRes)
    
    # Print model summary
    print(mod\$glmnetRes)
    
    # Extract coefficients at lambda = 0.2
    head(coef(mod\$glmnetRes, s = 0.2))
    
    # 4. Predict survival risk on test data using the trained model
    lp <- predict(object = mod, newx = x.test, s = c(0.1, 0.2))
    write.csv(as.data.frame(lp), "predicted_risk_test_trained.csv", row.names = TRUE)
    
    # 5. Perform cross-validation to find the optimal lambda parameter
    cv.mod <- cvRLassoCox(x=x.train, y=y.train, globalGraph=dGMMirGraph, nfolds = 5)
    
    # Plot cross-validation error curve
    plot(cv.mod\$glmnetRes, xlab = "log(lambda)")
    dev.off()
    
    # Extract optimal lambda values
    cv.mod\$glmnetRes\$lambda.min
    cv.mod\$glmnetRes\$lambda.1se
    
    # 6. Extract active prognostic features and their coefficients at the optimal lambda
    coef.min <- coef(cv.mod\$glmnetRes, s = "lambda.min")
    nonZeroIdx <- which(coef.min[,1] != 0)
    features <- rownames(coef.min)[nonZeroIdx]
    features.coef <- coef.min[nonZeroIdx]
    names(features.coef) <- features
    
    # Save prognostic features to CSV
    features_df <- data.frame(Gene = features, Coefficient = features.coef, row.names = NULL)
    write.csv(features_df, "prognostic_features.csv", row.names = FALSE)
    
    # 7. Predict survival risk on test data using the cross-validated model
    lp <- predict.cvRLassoCox(object = cv.mod, newx = x.test, s = "lambda.min")
    write.csv(as.data.frame(lp), "predicted_survival_risk_cv.csv", row.names = TRUE)
    
    # Save trained models for future use
    saveRDS(mod, "rlassocox_model.rds")
    saveRDS(cv.mod, "cv_rlassocox_model.rds")

    writeLines(c(
        '"BIOC_RLASSOCOX_RLASSO_COX_SURVIVAL_PREDICTION":',
        paste0('    RLassoCox: ', as.character(packageVersion('RLassoCox')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rlasso_cox_survival_prediction.csv versions.yml
    """
}

workflow BIOC_RLASSOCOX_RLASSO_COX_SURVIVAL_PREDICTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gene_expression.csv, survival_data.csv, gene_network.rds ] ]

    main:
    BIOC_RLASSOCOX_RLASSO_COX_SURVIVAL_PREDICTION(ch_input)

    emit:
    tables   = BIOC_RLASSOCOX_RLASSO_COX_SURVIVAL_PREDICTION.out.tables
    plots    = BIOC_RLASSOCOX_RLASSO_COX_SURVIVAL_PREDICTION.out.plots
    objects  = BIOC_RLASSOCOX_RLASSO_COX_SURVIVAL_PREDICTION.out.objects
    versions = BIOC_RLASSOCOX_RLASSO_COX_SURVIVAL_PREDICTION.out.versions
}
