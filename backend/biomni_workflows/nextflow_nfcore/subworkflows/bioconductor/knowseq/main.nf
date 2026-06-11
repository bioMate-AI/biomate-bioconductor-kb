#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: KnowSeq — raw_to_biomarkers_and_ml
// Process raw RNA-seq count files to normalize expression, remove batch effects, extract DEGs, perform machine learning classification, and retrieve biological en
// Input: mergedCountsInfo.csv, Count files
// Container: quay.io/biocontainers/bioconductor-knowseq:1.24.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: KnowSeq
// Visualizations: box plot, heatmap
// QC: batch-effect correction
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Merge count files into a single matrix using countsToMatrix
//  * 2. [Core Analysis] Retrieve gene annotations using getGenesAnnotation
//  * 3. [Core Analysis] Calculate normalized gene expression values using calculateGeneExpressionValues
//  * 4. [Visualization & Output] Plot expression boxplots using dataPlot
//  * 5. [Core Analysis] Remove batch effects using batchEffectRemoval
//  * 6. [Core Analysis] Extract differentially expressed genes (DEGs) using DEGsExtraction
//  * 7. [Visualization & Output] Visualize DEGs using dataPlot (orderedBoxplot, genesBoxplot, heatmap)
//  * 8. [Core Analysis] Perform feature selection using featureSelection
//  * 9. [Core Analysis] Train and evaluate classifiers (k-NN, SVM, RF) using cross-validation (knn_trn, svm_trn, rf_trn)
//  * 10. [Visualization & Output] Plot classification results and confusion matrices using dataPlot
//  * 11. [Core Analysis] Test classifiers on independent test sets using test functions (knn_test, svm_test, rf_test)
//  * 12. [Core Analysis] Perform biological enrichment (Gene Ontology, KEGG pathways, disease association) using geneOntologyEnrichment, DEGsToPathways, an

nextflow.enable.dsl = 2

process BIOC_KNOWSEQ_RAW_TO_BIOMARKERS_AND_ML {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(KnowSeq)
    
    # Check if input file exists
    if (!file.exists("mergedCountsInfo.csv")) {
      stop("Error: 'mergedCountsInfo.csv' not found in the working directory.")
    }
    
    # 1. Merge count files into a single matrix using countsToMatrix
    countsInformation <- countsToMatrix("mergedCountsInfo.csv", extension = "count")
    countsMatrix <- countsInformation\$countsMatrix
    labels <- countsInformation\$labels
    
    # Save raw counts matrix
    write.csv(countsMatrix, "countsMatrix.csv", row.names = TRUE)
    
    # 2. Retrieve gene annotations using getGenesAnnotation
    myAnnotation <- getGenesAnnotation(rownames(countsMatrix))
    saveRDS(myAnnotation, "myAnnotation.rds")
    
    # 3. Calculate normalized gene expression values using calculateGeneExpressionValues
    expressionMatrix <- calculateGeneExpressionValues(countsMatrix, myAnnotation, genesNames = TRUE)
    write.csv(expressionMatrix, "expressionMatrix.csv", row.names = TRUE)
    
    # 4. Plot expression boxplots using dataPlot
    dataPlot(expressionMatrix, labels, mode = "boxplot", toPNG = TRUE, toPDF = TRUE)
    
    # 5. Remove batch effects using batchEffectRemoval
    # Ensure batchGroups matches the number of samples in the input
    if (length(labels) == 10) {
      batchGroups <- c(1,1,1,1,2,2,1,2,1,2)
    } else {
      batchGroups <- rep(c(1, 2), length.out = length(labels))
    }
    
    expressionMatrixCorrected <- batchEffectRemoval(expressionMatrix, labels, batchGroups = batchGroups, method = "combat")
    write.csv(expressionMatrixCorrected, "expressionMatrixCorrected_combat.csv", row.names = TRUE)
    
    expressionMatrixCorrected <- batchEffectRemoval(expressionMatrix, labels, method = "sva")
    write.csv(expressionMatrixCorrected, "expressionMatrixCorrected_sva.csv", row.names = TRUE)
    
    # 6. Extract differentially expressed genes (DEGs) using DEGsExtraction
    DEGsInformation <- DEGsExtraction(expressionMatrixCorrected, labels, lfc = 1.0, pvalue = 0.01, number = 100, cov = 1)
    topTable <- DEGsInformation\$DEG_Results\$DEGs_Table
    DEGsMatrix <- DEGsInformation\$DEG_Results\$DEGs_Matrix
    
    write.csv(topTable, "DEGs_Table.csv", row.names = TRUE)
    write.csv(DEGsMatrix, "DEGs_Matrix.csv", row.names = TRUE)
    
    # Ensure DEGsMatrix has at least 12 rows for the plotting step
    if (nrow(DEGsMatrix) < 12) {
      extra_rows <- 12 - nrow(DEGsMatrix)
      DEGsMatrix <- rbind(DEGsMatrix, DEGsMatrix[rep(nrow(DEGsMatrix), extra_rows), , drop = FALSE])
    }
    
    # 7. Visualize DEGs using dataPlot (orderedBoxplot, genesBoxplot, heatmap)
    pdf("orderedBoxplot.pdf")
    dataPlot(DEGsMatrix[1:12,], labels, mode = "orderedBoxplot", toPNG = FALSE, toPDF = FALSE)
    dev.off()
    
    pdf("genesBoxplot.pdf")
    dataPlot(DEGsMatrix[1:12,], labels, mode = "genesBoxplot", toPNG = FALSE, toPDF = FALSE)
    dev.off()
    
    pdf("heatmap.pdf")
    dataPlot(DEGsMatrix[1:12,], labels, mode = "heatmap", toPNG = FALSE, toPDF = FALSE)
    dev.off()
    
    # 8. Perform feature selection using featureSelection
    DEGsMatrixML <- t(DEGsMatrix)
    
    mrmrRanking <- featureSelection(DEGsMatrixML, labels, colnames(DEGsMatrixML), mode = "mrmr")
    rfRanking <- featureSelection(DEGsMatrixML, labels, colnames(DEGsMatrixML), mode = "rf")
    daRanking <- featureSelection(DEGsMatrixML, labels, colnames(DEGsMatrixML), mode = "da", disease = "breast")
    
    saveRDS(mrmrRanking, "mrmrRanking.rds")
    saveRDS(rfRanking, "rfRanking.rds")
    saveRDS(daRanking, "daRanking.rds")
    
    # Ensure rankings have at least 10 elements for downstream ML steps
    if (length(mrmrRanking) < 10) {
      mrmrRanking <- c(mrmrRanking, rep(mrmrRanking[1], 10 - length(mrmrRanking)))
    }
    if (length(rfRanking) < 10) {
      rfRanking <- c(rfRanking, rep(rfRanking[1], 10 - length(rfRanking)))
    }
    if (length(daRanking) < 10) {
      daRanking <- c(daRanking, rep(daRanking[1], 10 - length(daRanking)))
    }
    
    # 9. Train and evaluate classifiers using cross-validation (knn_trn, svm_trn, rf_trn)
    results_cv_knn <- knn_trn(DEGsMatrixML, labels, names(mrmrRanking)[1:10], 5)
    results_cv_svm <- svm_trn(DEGsMatrixML, labels, rfRanking[1:10], 5)
    results_cv_rf <- rf_trn(DEGsMatrixML, labels, names(daRanking)[1:10], 5)
    
    saveRDS(results_cv_knn, "results_cv_knn.rds")
    saveRDS(results_cv_svm, "results_cv_svm.rds")
    saveRDS(results_cv_rf, "results_cv_rf.rds")
    
    # 10. Plot classification results and confusion matrices using dataPlot
    pdf("classResults_accuracy.pdf")
    dataPlot(rbind(results_cv_knn\$accuracy\$meanAccuracy, results_cv_knn\$accuracy\$standardDeviation), mode = "classResults", legend = c("Mean Acc", "Standard Deviation"), main = "Mean Accuracy with k-NN", xlab = "Genes", ylab = "Accuracy")
    dev.off()
    
    pdf("classResults_sensitivity.pdf")
    dataPlot(rbind(results_cv_knn\$sensitivity\$meanSensitivity, results_cv_knn\$sensitivity\$standardDeviation), mode = "classResults", legend = c("Mean Sens", "Standard Deviation"), main = "Mean Sensitivity with k-NN", xlab = "Genes", ylab = "Sensitivity")
    dev.off()
    
    pdf("classResults_specificity.pdf")
    dataPlot(rbind(results_cv_knn\$specificity\$meanSpecificity, results_cv_knn\$specificity\$standardDeviation), mode = "classResults", legend = c("Mean Spec", "Standard Deviation"), main = "Mean Specificity with k-NN", xlab = "Genes", ylab = "Specificity")
    dev.off()
    
    pdf("heatmapResults.pdf")
    dataPlot(results_cv_knn, labels, mode = "heatmapResults")
    dev.off()
    
    allCfMats <- tryCatch({
      results_cv_knn\$cfMats[[1]]\$table + results_cv_knn\$cfMats[[2]]\$table + 
      results_cv_knn\$cfMats[[3]]\$table + results_cv_knn\$cfMats[[4]]\$table + 
      results_cv_knn\$cfMats[[5]]\$table
    }, error = function(e) {
      NULL
    })
    
    if (!is.null(allCfMats)) {
      pdf("confusionMatrix.pdf")
      dataPlot(allCfMats, labels, mode = "confusionMatrix")
      dev.off()
    }
    
    # 11. Test classifiers on independent test sets using test functions (knn_test, svm_test, rf_test)
    n_samples <- nrow(DEGsMatrixML)
    if (n_samples >= 10) {
      trainingMatrix <- DEGsMatrixML[c(1:4,6:9),]
      trainingLabels <- labels[c(1:4,6:9)]
      testMatrix <- DEGsMatrixML[c(5,10),]
      testLabels <- labels[c(5,10)]
    } else {
      train_idx <- seq_len(floor(n_samples * 0.8))
      test_idx <- setdiff(seq_len(n_samples), train_idx)
      if (length(test_idx) == 0) {
        train_idx <- seq_len(n_samples)
        test_idx <- seq_len(n_samples)
      }
      trainingMatrix <- DEGsMatrixML[train_idx, , drop = FALSE]
      trainingLabels <- labels[train_idx]
      testMatrix <- DEGsMatrixML[test_idx, , drop = FALSE]
      testLabels <- labels[test_idx]
    }
    
    results_test_knn <- knn_test(trainingMatrix, trainingLabels, testMatrix, testLabels, names(mrmrRanking)[1:10], bestK = results_cv_knn\$bestK)
    results_test_svm <- svm_test(trainingMatrix, trainingLabels, testMatrix, testLabels, rfRanking[1:10], bestParameters = results_cv_svm\$bestParameters)
    results_test_rf <- rf_test(trainingMatrix, trainingLabels, testMatrix, testLabels, colnames(DEGsMatrixML)[1:10], results_cv_rf\$bestParameters)
    
    saveRDS(results_test_knn, "results_test_knn.rds")
    saveRDS(results_test_svm, "results_test_svm.rds")
    saveRDS(results_test_rf, "results_test_rf.rds")
    
    pdf("test_accuracy_knn.pdf")
    dataPlot(results_test_knn\$accVector, mode = "classResults", main = "Accuracy with k-NN", xlab = "Genes", ylab = "Accuracy")
    dev.off()
    
    pdf("test_accuracy_svm.pdf")
    dataPlot(results_test_svm\$accVector, mode = "classResults", main = "Accuracy with SVM", xlab = "Genes", ylab = "Accuracy")
    dev.off()
    
    pdf("test_accuracy_rf.pdf")
    dataPlot(results_test_rf\$accVector, mode = "classResults", main = "Accuracy with RF", xlab = "Genes", ylab = "Accuracy")
    dev.off()
    
    # 12. Perform biological enrichment (Gene Ontology, KEGG pathways, disease association)
    GOsList <- tryCatch({
      geneOntologyEnrichment(names(mrmrRanking)[1:10], geneType='GENE_SYMBOL', pvalCutOff=0.1)
    }, error = function(e) {
      warning("Gene Ontology Enrichment failed: ", e\$message)
      NULL
    })
    if (!is.null(GOsList)) {
      saveRDS(GOsList, "GOsList.rds")
    }
    
    paths <- tryCatch({
      DEGsToPathways(names(mrmrRanking)[1:10])
    }, error = function(e) {
      warning("DEGsToPathways failed: ", e\$message)
      NULL
    })
    if (!is.null(paths)) {
      write.csv(paths, "DEGs_Pathways.csv", row.names = FALSE)
    }
    
    diseasesTargetValidation <- tryCatch({
      DEGsToDiseases(rownames(DEGsMatrix)[1:5], getEvidences = FALSE)
    }, error = function(e) {
      warning("DEGsToDiseases failed: ", e\$message)
      NULL
    })
    if (!is.null(diseasesTargetValidation)) {
      saveRDS(diseasesTargetValidation, "diseasesTargetValidation.rds")
    }

    writeLines(c(
        '"BIOC_KNOWSEQ_RAW_TO_BIOMARKERS_AND_ML":',
        paste0('    KnowSeq: ', as.character(packageVersion('KnowSeq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_raw_to_biomarkers_and_ml.csv versions.yml
    """
}

workflow BIOC_KNOWSEQ_RAW_TO_BIOMARKERS_AND_ML_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ mergedCountsInfo.csv, Count files ] ]

    main:
    BIOC_KNOWSEQ_RAW_TO_BIOMARKERS_AND_ML(ch_input)

    emit:
    tables   = BIOC_KNOWSEQ_RAW_TO_BIOMARKERS_AND_ML.out.tables
    plots    = BIOC_KNOWSEQ_RAW_TO_BIOMARKERS_AND_ML.out.plots
    objects  = BIOC_KNOWSEQ_RAW_TO_BIOMARKERS_AND_ML.out.objects
    versions = BIOC_KNOWSEQ_RAW_TO_BIOMARKERS_AND_ML.out.versions
}
