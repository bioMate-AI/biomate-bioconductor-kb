#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: a4Core — a4_core_classification_pipeline
// Perform feature selection and classification evaluation on transcriptomics data using a4Core utility functions.
// Input: counts.csv, coldata.csv
// Container: 1.58.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, a4Core, glmnet
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_A4CORE_A4_CORE_CLASSIFICATION_PIPELINE {
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
    .bm_deps <- c("a4Core", "Biobase", "glmnet")
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
    
    # --- Load required libraries ---
    library(a4Core)
    library(Biobase)
    library(glmnet)
    
    # --- Read and preprocess input files ---
    # counts.csv: gene-by-sample normalized expression matrix (column 'gene_id' is row names)
    # coldata.csv: sample metadata with columns 'sample' and 'condition'
    counts_df <- read.csv("counts.csv", check.names = FALSE)
    if ("gene_id" %in% colnames(counts_df)) {
      rownames(counts_df) <- counts_df\$gene_id
      counts_df\$gene_id <- NULL
    }
    counts_mat <- as.matrix(counts_df)
    
    coldata <- read.csv("coldata.csv", check.names = FALSE)
    rownames(coldata) <- coldata\$sample
    
    # Align samples between expression matrix and metadata
    common_samples <- intersect(colnames(counts_mat), rownames(coldata))
    if (length(common_samples) == 0) {
      stop("No common samples found between counts.csv and coldata.csv")
    }
    counts_mat <- counts_mat[, common_samples, drop = FALSE]
    coldata <- coldata[common_samples, drop = FALSE]
    
    # --- Create ExpressionSet container ---
    pheno_data <- new("AnnotatedDataFrame", data = coldata)
    eSet <- ExpressionSet(assayData = counts_mat, phenoData = pheno_data)
    
    # --- Model Fitting using glmnet (Lasso/Elastic Net) ---
    # Prepare predictors (x) and response (y)
    x <- t(exprs(eSet))
    y <- factor(pData(eSet)\$condition)
    
    # Fit a logistic regression model with lasso penalty
    fit <- glmnet::glmnet(x, y, family = "binomial")
    
    # --- Feature Selection using a4Core::topTable ---
    # topTable extracts the most important features from the classification model
    top_feats <- tryCatch({
      a4Core::topTable(fit, n = 20)
    }, error = function(e) {
      message("Standard topTable call failed, using fallback coefficient extraction: ", e\$message)
      # Fallback: extract non-zero coefficients manually if topTable expects a specific subclass
      coefs <- as.matrix(coef(fit, s = min(fit\$lambda)))
      coefs_filtered <- coefs[coefs[, 1] != 0, , drop = FALSE]
      df <- data.frame(
        Feature = rownames(coefs_filtered),
        Coefficient = coefs_filtered[, 1]
      )
      df <- df[order(abs(df\$Coefficient), decreasing = TRUE), ]
      df
    })
    
    # Save top features
    write.csv(top_feats, "top_features.csv", row.names = FALSE)
    
    # --- Model Evaluation using a4Core::confusionMatrix ---
    # Predict classes using a representative lambda
    lambda_val <- fit\$lambda[median(seq_along(fit\$lambda))]
    preds <- predict(fit, newx = x, s = lambda_val, type = "class")
    preds_factor <- factor(preds, levels = levels(y))
    
    conf_mat <- tryCatch({
      a4Core::confusionMatrix(preds_factor, y)
    }, error = function(e) {
      message("confusionMatrix call failed, using base table fallback: ", e\$message)
      table(Predicted = preds_factor, Actual = y)
    })
    
    # Save confusion matrix
    write.csv(as.matrix(conf_mat), "confusion_matrix.csv", row.names = TRUE)
    
    # --- Visualization and Diagnostics ---
    pdf("diagnostic_plots.pdf", width = 8, height = 6)
    plot(fit, xvar = "lambda", label = TRUE)
    title("Lasso Coefficient Paths", line = 2.5)
    dev.off()
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_A4CORE_A4_CORE_CLASSIFICATION_PIPELINE":',
        paste0('    a4Core: ', as.character(packageVersion('a4Core')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_a4_core_classification_pipeline.csv versions.yml
    """
}

workflow BIOC_A4CORE_A4_CORE_CLASSIFICATION_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_A4CORE_A4_CORE_CLASSIFICATION_PIPELINE(ch_input)

    emit:
    tables   = BIOC_A4CORE_A4_CORE_CLASSIFICATION_PIPELINE.out.tables
    plots    = BIOC_A4CORE_A4_CORE_CLASSIFICATION_PIPELINE.out.plots
    objects  = BIOC_A4CORE_A4_CORE_CLASSIFICATION_PIPELINE.out.objects
    versions = BIOC_A4CORE_A4_CORE_CLASSIFICATION_PIPELINE.out.versions
}
