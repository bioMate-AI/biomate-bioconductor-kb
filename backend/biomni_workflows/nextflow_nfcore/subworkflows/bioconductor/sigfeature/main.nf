#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: sigFeature — significant_feature_selection_and_classification
// Rank features using the sigFeature algorithm, train an SVM classifier, and compare its performance and feature p-values against standard SVM-RFE.
// Input: expression_matrix.csv, sample_metadata.csv
// Container: quay.io/biocontainers/bioconductor-sigfeature:1.28.0--r45hdfd78af_0
// R packages: e1071, pheatmap, RColorBrewer, sigFeature, SummarizedExperiment
// Bioconductor: 3.20 | R: 4.4
// Requires: RColorBrewer, SummarizedExperiment, e1071, pheatmap, sigFeature
// Visualizations: heatmap, box plot, image plot, strip chart
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Transpose the expression matrix so samples are rows and features are columns
//  * 2. [Core Analysis] Recode sample labels to -1 and 1
//  * 3. [Core Analysis] Calculate baseline p-values using sigFeaturePvalue
//  * 4. [Core Analysis] Run feature selection using sigFeature or svmrfeFeatureRanking
//  * 5. [Core Analysis] Train an SVM model using the top ranked features
//  * 6. [Core Analysis] Predict class labels and evaluate accuracy
//  * 7. [Core Analysis] Compare p-values of selected features between methods

nextflow.enable.dsl = 2

process BIOC_SIGFEATURE_SIGNIFICANT_FEATURE_SELECTION_AND_CLASSIFICATION {
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
    .bm_deps <- c("e1071", "pheatmap", "RColorBrewer", "sigFeature", "SummarizedExperiment")
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
    library(sigFeature)
    library(e1071)
    library(pheatmap)
    library(RColorBrewer)
    
    # ==========================================
    # 1. Read User Input Files
    # ==========================================
    
    # Read expression matrix (features as rows, samples as columns)
    if (!file.exists("expression_matrix.csv")) {
      stop("Error: 'expression_matrix.csv' not found in the working directory.")
    }
    expr_df <- read.csv("expression_matrix.csv", row.names = 1, check.names = FALSE)
    
    # Read sample metadata containing binary class labels
    if (!file.exists("sample_metadata.csv")) {
      stop("Error: 'sample_metadata.csv' not found in the working directory.")
    }
    meta_df <- read.csv("sample_metadata.csv", row.names = 1, check.names = FALSE)
    
    # Align samples between expression matrix and metadata
    common_samples <- intersect(colnames(expr_df), rownames(meta_df))
    if (length(common_samples) == 0) {
      # Try matching by the first column of metadata if row names do not match
      common_samples <- intersect(colnames(expr_df), meta_df[[1]])
      if (length(common_samples) == 0) {
        stop("Error: No matching sample IDs found between expression matrix columns and metadata.")
      }
      rownames(meta_df) <- meta_df[[1]]
    }
    
    expr_df <- expr_df[, common_samples, drop = FALSE]
    meta_df <- meta_df[common_samples, , drop = FALSE]
    
    # ==========================================
    # 2. Prepare Data for sigFeature
    # ==========================================
    
    # Transpose expression matrix so samples are rows and features are columns
    x <- t(as.matrix(expr_df))
    
    # Identify binary class column and recode to -1 and 1
    class_col <- NULL
    for (col in colnames(meta_df)) {
      if (length(unique(meta_df[[col]])) == 2) {
        class_col <- col
        break
      }
    }
    if (is.null(class_col)) {
      class_col <- colnames(meta_df)[1]
    }
    
    raw_labels <- meta_df[[class_col]]
    unique_labels <- unique(raw_labels)
    y <- ifelse(raw_labels == unique_labels[1], -1, 1)
    
    # Ensure y is a numeric vector of -1 and 1
    y <- as.numeric(y)
    
    # ==========================================
    # 3. Calculate Baseline P-values
    # ==========================================
    
    pvals <- sigFeaturePvalue(x, y)
    
    # Save baseline p-values plot
    pdf("baseline_pvalues_histogram.pdf", width = 6, height = 5)
    hist(unlist(pvals), col = "skyblue", xlab = "p value", ylab = "Frequency", 
         main = "Baseline Feature P-values")
    dev.off()
    
    # ==========================================
    # 4. Feature Selection using sigFeature
    # ==========================================
    
    # Run the sigFeature algorithm to rank features
    sigfeatureRankedList <- sigFeature(x, y)
    
    # Save ranked features to CSV
    feature_names <- colnames(x)
    sigFeature_ranked_names <- feature_names[sigfeatureRankedList]
    write.csv(data.frame(Rank = seq_along(sigFeature_ranked_names), Feature = sigFeature_ranked_names), 
              "sigFeature_ranked_features.csv", row.names = FALSE)
    
    # ==========================================
    # 5. Train SVM Classifier (sigFeature)
    # ==========================================
    
    # Determine safe number of top features to use (up to 1000)
    num_feats <- min(1000, ncol(x))
    
    sigFeature.model <- svm(x[, sigfeatureRankedList[1:num_feats]], y, 
                            type = "C-classification", kernel = "linear")
    
    # Print model summary to console
    cat("\n=== sigFeature SVM Model Summary ===\n")
    print(summary(sigFeature.model))
    
    # Predict and evaluate accuracy
    pred <- predict(sigFeature.model, x[, sigfeatureRankedList[1:num_feats]])
    tab_sigFeature <- table(pred, y)
    cat("\n=== sigFeature Confusion Matrix ===\n")
    print(tab_sigFeature)
    write.csv(as.data.frame(tab_sigFeature), "sigFeature_confusion_matrix.csv")
    
    # ==========================================
    # 6. Feature Selection using Standard SVM-RFE
    # ==========================================
    
    # Run standard SVM-RFE algorithm
    featureRankedList <- svmrfeFeatureRanking(x, y)
    
    # Save SVM-RFE ranked features to CSV
    RFE_ranked_names <- feature_names[featureRankedList]
    write.csv(data.frame(Rank = seq_along(RFE_ranked_names), Feature = RFE_ranked_names), 
              "RFE_ranked_features.csv", row.names = FALSE)
    
    # Train SVM Classifier (SVM-RFE)
    RFE.model <- svm(x[, featureRankedList[1:num_feats]], y, 
                     type = "C-classification", kernel = "linear")
    
    # Print model summary to console
    cat("\n=== SVM-RFE Model Summary ===\n")
    print(summary(RFE.model))
    
    # Predict and evaluate accuracy
    pred_rfe <- predict(RFE.model, x[, featureRankedList[1:num_feats]])
    tab_RFE <- table(pred_rfe, y)
    cat("\n=== SVM-RFE Confusion Matrix ===\n")
    print(tab_RFE)
    write.csv(as.data.frame(tab_RFE), "RFE_confusion_matrix.csv")
    
    # ==========================================
    # 7. Compare P-values of Selected Features
    # ==========================================
    
    # Determine safe number of top features to compare (up to 100)
    num_compare <- min(100, ncol(x))
    
    pvalsigFe <- sigFeaturePvalue(x, y, num_compare, sigfeatureRankedList)
    pvalRFE   <- sigFeaturePvalue(x, y, num_compare, featureRankedList)
    
    # Save comparison histograms
    pdf("pvalue_comparison_histograms.pdf", width = 10, height = 5)
    par(mfrow = c(1, 2))
    hist(unlist(pvalsigFe), breaks = 50, col = "skyblue", main = "sigFeature", 
         xlab = "p value")
    hist(unlist(pvalRFE), breaks = 50, col = "skyblue", main = "SVM-RFE", 
         xlab = "p value")
    dev.off()
    
    # Save comparison boxplot
    pdf("pvalue_comparison_boxplot.pdf", width = 6, height = 6)
    mytitle <- 'Box Plot'
    boxplot(unlist(pvalsigFe), unlist(pvalRFE), main = mytitle, 
            names = c("sigFeature", "SVM-RFE"),
            ylab = "p value", ylim = c(min(unlist(pvalsigFe), na.rm = TRUE), max(unlist(pvalRFE), na.rm = TRUE)))
    stripchart(unlist(pvalsigFe), vertical = TRUE, method = "jitter", add = TRUE, pch = 16, 
               col = c('green'))
    stripchart(unlist(pvalRFE), vertical = TRUE, at = 2, method = "jitter", add = TRUE, 
               pch = 16, col = c('blue'))
    grid(nx = NULL, ny = NULL, col = "black", lty = "dotted")
    dev.off()
    
    # ==========================================
    # 8. Generate Heatmaps of Top Features
    # ==========================================
    
    num_heatmap <- min(20, ncol(x))
    
    pdf("heatmap_sigFeature.pdf", width = 8, height = 8)
    pheatmap(x[, sigfeatureRankedList[1:num_heatmap]], scale = "row", 
             clustering_distance_rows = "correlation")
    dev.off()
    
    pdf("heatmap_RFE.pdf", width = 8, height = 8)
    pheatmap(x[, featureRankedList[1:num_heatmap]], scale = "row", 
             clustering_distance_rows = "correlation")
    dev.off()
    
    # Save workspace image for reproducibility
    save.image("sigFeature_pipeline_results.RData")
    
    cat("\nPipeline completed successfully. Outputs saved to working directory.\n")

    writeLines(c(
        '"BIOC_SIGFEATURE_SIGNIFICANT_FEATURE_SELECTION_AND_CLASSIFICATION":',
        paste0('    sigFeature: ', as.character(packageVersion('sigFeature')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_significant_feature_selection_and_classification.csv versions.yml
    """
}

workflow BIOC_SIGFEATURE_SIGNIFICANT_FEATURE_SELECTION_AND_CLASSIFICATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.csv, sample_metadata.csv ] ]

    main:
    BIOC_SIGFEATURE_SIGNIFICANT_FEATURE_SELECTION_AND_CLASSIFICATION(ch_input)

    emit:
    tables   = BIOC_SIGFEATURE_SIGNIFICANT_FEATURE_SELECTION_AND_CLASSIFICATION.out.tables
    plots    = BIOC_SIGFEATURE_SIGNIFICANT_FEATURE_SELECTION_AND_CLASSIFICATION.out.plots
    objects  = BIOC_SIGFEATURE_SIGNIFICANT_FEATURE_SELECTION_AND_CLASSIFICATION.out.objects
    versions = BIOC_SIGFEATURE_SIGNIFICANT_FEATURE_SELECTION_AND_CLASSIFICATION.out.versions
}
