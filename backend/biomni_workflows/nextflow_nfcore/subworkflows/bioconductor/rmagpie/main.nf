#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Rmagpie — rfe_svm_classification
// Train an SVM classifier with Recursive Feature Elimination (RFE) feature selection on a microarray dataset, evaluate it using 1-layer and 2-layer cross-validati
// Input: ExpressionSet, vV_newSamples.txt
// Container: quay.io/biocontainers/bioconductor-rmagpie:1.66.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, Rmagpie
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define feature selection options using new("geneSubsets", ...)
//  * 2. [Input & Preparation] Create an assessment experiment using new("assessment", ...) with SVM and RFE options
//  * 3. [Core Analysis] Run external one-layer cross-validation using runOneLayerExtCV
//  * 4. [Core Analysis] Run external two-layer cross-validation using runTwoLayerExtCV
//  * 5. [Core Analysis] Train the final classifier on the whole dataset using findFinalClassifier
//  * 6. [Core Analysis] Classify new samples using classifyNewSamples
//  * 7. [Visualization & Output] Retrieve results using getResults and plot error rates using plotErrorsSummaryOneLayerCV, plotErrorsRepeatedOneLayerCV, or plotErr

nextflow.enable.dsl = 2

process BIOC_RMAGPIE_RFE_SVM_CLASSIFICATION {
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
    library(Rmagpie)
    library(Biobase)
    
    # Read user input files from the working directory
    if (!file.exists("ExpressionSet.rds")) {
      stop("Error: ExpressionSet.rds not found in the working directory.")
    }
    expression_set <- readRDS("ExpressionSet.rds")
    
    if (!file.exists("vV_newSamples.txt")) {
      stop("Error: vV_newSamples.txt not found in the working directory.")
    }
    newSamplesFile <- "vV_newSamples.txt"
    
    # Define feature selection options
    geneSubsets <- new("geneSubsets", speed="high", maxSubsetSize=20)
    
    # Create assessment experiment using the loaded ExpressionSet
    myAssessment <- new ( "assessment",
                            dataset = expression_set,
                            noFolds1stLayer = 9,
                            noFolds2ndLayer = 10,
                            classifierName = "svm",
                            featureSelectionMethod = 'rfe',
                            featureSelectionOptions = geneSubsets,
                            typeFoldCreation = "original",
                            svmKernel = "linear",
                            noOfRepeats = 3)
    
    # Run cross-validation and train final classifier
    set.seed(234)
    myAssessment <- runOneLayerExtCV(myAssessment)
    myAssessment <- runTwoLayerExtCV(myAssessment)
    myAssessment <- findFinalClassifier(myAssessment)
    
    # Classify new samples (Default)
    res <- classifyNewSamples( myAssessment,newSamplesFile)
    
    # Save prognosis classification lists dynamically based on dataset classes
    predicted_classes <- if(is.factor(res)) levels(res) else unique(as.character(res))
    for (cls in predicted_classes) {
      cls_samples <- names(res)[res == cls]
      writeLines(cls_samples, paste0(cls, "_samples.txt"))
    }
    
    # Classify new samples (Option Value = 1)
    res_opt1 <- classifyNewSamples( myAssessment,newSamplesFile,optionValue=1)
    write.csv(as.data.frame(res_opt1), "classification_results_option1.csv")
    
    # Retrieve and save text results
    sink("assessment_results_summary.txt")
    cat("=== Error Rate (Layer 1) ===\n")
    print(getResults(myAssessment, 1, topic='errorRate'))
    
    cat("\n=== CV Error Rate (Layer 1) ===\n")
    print(getResults(myAssessment, 1, topic='errorRate', errorType='cv'))
    
    cat("\n=== CV Error Rate (Layer 2) ===\n")
    print(getResults(myAssessment, 2, topic='errorRate', errorType='cv'))
    
    cat("\n=== Best Option Value (Layer 1) ===\n")
    print(getResults(myAssessment, 1, topic='bestOptionValue'))
    
    cat("\n=== Execution Time (Layer 1) ===\n")
    print(getResults(myAssessment, 1, topic='executionTime'))
    sink()
    
    # Retrieve and save selected genes
    res_genes <- getResults(myAssessment, c(1,1), topic='genesSelected', genesType='frequ')
    write.csv(as.data.frame(res_genes), "genes_selected_frequency.csv")
    
    # Retrieve specific fold genes (wrapped in tryCatch to handle potential index out of bounds)
    tryCatch({
      fold_genes <- getResults(myAssessment, c(1,2), topic='genesSelected', genesType='fold')[[3]][[2]]
      write.csv(as.data.frame(fold_genes), "genes_selected_fold1_2.csv")
    }, error = function(e) {
      message("Could not retrieve specific fold genes: ", e\$message)
    })
    
    # Generate and save plots
    png("plotErrorsSummaryOneLayerCV.png")
    plotErrorsSummaryOneLayerCV(myAssessment)
    dev.off()
    
    png("plotErrorsRepeatedOneLayerCV.png")
    plotErrorsRepeatedOneLayerCV(myAssessment)
    dev.off()
    
    png("plotErrorsFoldTwoLayerCV.png")
    plotErrorsFoldTwoLayerCV(myAssessment)
    dev.off()
    
    # Save the final assessment object
    saveRDS(myAssessment, "myAssessment_final.rds")

    writeLines(c(
        '"BIOC_RMAGPIE_RFE_SVM_CLASSIFICATION":',
        paste0('    Rmagpie: ', as.character(packageVersion('Rmagpie')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rfe_svm_classification.csv versions.yml
    """
}

workflow BIOC_RMAGPIE_RFE_SVM_CLASSIFICATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ExpressionSet, vV_newSamples.txt ] ]

    main:
    BIOC_RMAGPIE_RFE_SVM_CLASSIFICATION(ch_input)

    emit:
    tables   = BIOC_RMAGPIE_RFE_SVM_CLASSIFICATION.out.tables
    plots    = BIOC_RMAGPIE_RFE_SVM_CLASSIFICATION.out.plots
    objects  = BIOC_RMAGPIE_RFE_SVM_CLASSIFICATION.out.objects
    versions = BIOC_RMAGPIE_RFE_SVM_CLASSIFICATION.out.versions
}
