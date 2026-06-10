#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Rmagpie — nsc_classification
// Train a Nearest Shrunken Centroid (NSC) classifier on a microarray dataset, evaluate it using cross-validation, and classify new samples.
// Input: ExpressionSet, vV_newSamples.txt
// Container: quay.io/biocontainers/bioconductor-rmagpie:1.66.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, Rmagpie
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define feature selection thresholds using new("thresholds", ...)
//  * 2. [Input & Preparation] Create an assessment experiment using new("assessment", ...) with NSC options
//  * 3. [Core Analysis] Run external one-layer cross-validation using runOneLayerExtCV
//  * 4. [Core Analysis] Run external two-layer cross-validation using runTwoLayerExtCV
//  * 5. [Core Analysis] Train the final classifier on the whole dataset using findFinalClassifier
//  * 6. [Core Analysis] Classify new samples using classifyNewSamples

nextflow.enable.dsl = 2

process BIOC_RMAGPIE_NSC_CLASSIFICATION {
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
        
        library(Rmagpie)
        library(Biobase)
        
        # 1. Read the user input files from the working directory
        if (file.exists("ExpressionSet.rds")) {
          vV70genes <- readRDS("ExpressionSet.rds")
        } else if (file.exists("ExpressionSet")) {
          vV70genes <- readRDS("ExpressionSet")
        } else {
          stop("Error: ExpressionSet file not found in the working directory.")
        }
        
        newSamplesFile <- "vV_newSamples.txt"
        if (!file.exists(newSamplesFile)) {
          stop("Error: vV_newSamples.txt not found in the working directory.")
        }
        
        # 2. Define feature selection thresholds
        thresholds <- new("thresholds", optionValues=c(0,0.1,0.2,0.3,0.4,0.5,1,2))
        
        # 3. Create an assessment experiment using NSC options
        myAssessment2 <- new ( "assessment",
                                 dataset = vV70genes,
                                 noFolds1stLayer = 9,
                                 noFolds2ndLayer = 10,
                                 classifierName = "nsc",
                                 featureSelectionMethod = 'nsc',
                                 featureSelectionOptions = thresholds,
                                 typeFoldCreation = "original",
                                 noOfRepeats = 2)
        
        # 4. Run external one-layer cross-validation
        myAssessment2 <- runOneLayerExtCV(myAssessment2)
        
        # 5. Run external two-layer cross-validation
        myAssessment2 <- runTwoLayerExtCV(myAssessment2)
        
        # 6. Train the final classifier on the whole dataset
        myAssessment2 <- findFinalClassifier(myAssessment2)
        
        # 7. Classify new samples
        res <- classifyNewSamples( myAssessment2,newSamplesFile)
        
        # 8. Write named output files for the results
        # Save classification predictions to a CSV file
        res_df <- data.frame(
          Sample = names(res),
          Prediction = as.character(res),
          stringsAsFactors = FALSE
        )
        write.csv(res_df, "classification_results.csv", row.names = FALSE)
        
        # Save the final assessment object to an RDS file
        saveRDS(myAssessment2, "assessment_nsc.rds")
        
        # Generate and save diagnostic plots
        tryCatch({
          png("plotErrorsSummaryOneLayerCV.png")
          plotErrorsSummaryOneLayerCV(myAssessment2)
          dev.off()
        }, error = function(e) {
          warning("Could not generate plotErrorsSummaryOneLayerCV: ", e\$message)
        })
        
        tryCatch({
          png("plotSummaryErrorRate.png")
          plotErrorsRepeatedOneLayerCV(myAssessment2)
          dev.off()
        }, error = function(e) {
          warning("Could not generate plotErrorsRepeatedOneLayerCV: ", e\$message)
        })
        
        tryCatch({
          png("twoLayerCrossValidation.png")
          plotErrorsFoldTwoLayerCV(myAssessment2)
          dev.off()
        }, error = function(e) {
          warning("Could not generate plotErrorsFoldTwoLayerCV: ", e\$message)
        })

    writeLines(c(
        '"BIOC_RMAGPIE_NSC_CLASSIFICATION":',
        paste0('    Rmagpie: ', as.character(packageVersion('Rmagpie')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_nsc_classification.csv versions.yml
    """
}

workflow BIOC_RMAGPIE_NSC_CLASSIFICATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ExpressionSet, vV_newSamples.txt ] ]

    main:
    BIOC_RMAGPIE_NSC_CLASSIFICATION(ch_input)

    emit:
    tables   = BIOC_RMAGPIE_NSC_CLASSIFICATION.out.tables
    plots    = BIOC_RMAGPIE_NSC_CLASSIFICATION.out.plots
    objects  = BIOC_RMAGPIE_NSC_CLASSIFICATION.out.objects
    versions = BIOC_RMAGPIE_NSC_CLASSIFICATION.out.versions
}
