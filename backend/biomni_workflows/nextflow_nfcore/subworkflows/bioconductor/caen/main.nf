#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CAEN — caen_feature_selection_and_classification
// Select differentially expressed feature genes from count data and perform classification using ZIPLDA.
// Input: realData, y
// Container: quay.io/biocontainers/bioconductor-caen:1.18.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: CAEN, SummarizedExperiment
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Estimate prior probabilities using estimatep
//  * 2. [Core Analysis] Select top feature genes using CAEN
//  * 3. [Core Analysis] Subset and transpose the expression data for classification
//  * 4. [Core Analysis] Perform cross-validation to find the best tuning parameter using ZIPLDA.cv
//  * 5. [Core Analysis] Classify samples using ZIPLDA

nextflow.enable.dsl = 2

process BIOC_CAEN_CAEN_FEATURE_SELECTION_AND_CLASSIFICATION {
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
    .bm_deps <- c("CAEN")
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
    library(CAEN)
    
    # -----------------------------------------------------------------------------
    # 1. Read User Input Files
    # -----------------------------------------------------------------------------
    # The pipeline expects 'realData.rds' (a SummarizedExperiment object)
    # and 'y.rds' (a numeric vector of class labels) in the working directory.
    if (!file.exists("realData.rds") || !file.exists("y.rds")) {
      stop("Required input files 'realData.rds' and/or 'y.rds' are missing from the working directory.")
    }
    
    realData <- readRDS("realData.rds")
    y <- readRDS("y.rds")
    
    # Ensure y is a numeric vector
    y <- as.numeric(y)
    
    # Set up x and xte as in the documented workflow
    x <- realData
    xte <- realData
    
    # Determine the number of classes K dynamically from the input labels
    K_classes <- length(unique(y))
    
    # -----------------------------------------------------------------------------
    # 2. Estimate Prior Probabilities
    # -----------------------------------------------------------------------------
    message("Estimating prior probabilities...")
    prob <- estimatep(x = x, y = y, xte = x, beta = 1, type = "mle", prior = NULL)     
    prob0 <- estimatep(x = x, y = y, xte = xte, beta = 1, type = "mle", 
                       prior = NULL)   
    
    # -----------------------------------------------------------------------------
    # 3. Select Top Feature Genes using CAEN
    # -----------------------------------------------------------------------------
    message("Selecting feature genes using CAEN...")
    # We use K = K_classes to match the input data structure dynamically
    myscore <- CAEN(dataTable = x, y = y, K = K_classes, gene_no_list = 100)
    
    # -----------------------------------------------------------------------------
    # 4. Subset and Transpose Data for Classification
    # -----------------------------------------------------------------------------
    message("Subsetting and transposing data...")
    ddd <- myscore\$np
    datx <- t(assay(x)[ddd,])
    datxte <- t(assay(xte)[ddd,])
    probb <- prob[ddd,]
    probb0 <- prob0[ddd,]
    
    # -----------------------------------------------------------------------------
    # 5. Perform Cross-Validation and Classification using ZIPLDA
    # -----------------------------------------------------------------------------
    message("Running ZIPLDA cross-validation...")
    zipldacv.out <- ZIPLDA.cv(x = datx, y = y, prob0 = t(probb))
    
    message("Running ZIPLDA classification...")
    ZIPLDA.out <- ZIPLDA(x = datx, y = y, xte = datxte, transform = FALSE, 
                         prob0 = t(probb0), rho = zipldacv.out\$bestrho)
    classResult <- ZIPLDA.out\$ytehat
    
    # -----------------------------------------------------------------------------
    # 6. Save Outputs
    # -----------------------------------------------------------------------------
    message("Saving results...")
    
    # Save selected features and their scores
    selected_features_df <- data.frame(
      Gene_Index = ddd,
      Gene_Name = rownames(assay(x))[ddd],
      Correlation_Coefficient = myscore\$r[ddd]
    )
    write.csv(selected_features_df, "selected_features.csv", row.names = FALSE)
    
    # Save classification results
    classification_df <- data.frame(
      Sample = colnames(xte),
      True_Label = y,
      Predicted_Label = classResult
    )
    write.csv(classification_df, "classification_results.csv", row.names = FALSE)
    
    # Save full ZIPLDA and CV outputs as RDS for downstream analysis
    saveRDS(zipldacv.out, "ziplda_cv_output.rds")
    saveRDS(ZIPLDA.out, "ziplda_output.rds")
    
    message("Pipeline completed successfully. Outputs written to 'selected_features.csv', 'classification_results.csv', 'ziplda_cv_output.rds', and 'ziplda_output.rds'.")

    writeLines(c(
        '"BIOC_CAEN_CAEN_FEATURE_SELECTION_AND_CLASSIFICATION":',
        paste0('    CAEN: ', as.character(packageVersion('CAEN')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_caen_feature_selection_and_classification.csv versions.yml
    """
}

workflow BIOC_CAEN_CAEN_FEATURE_SELECTION_AND_CLASSIFICATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ realData, y ] ]

    main:
    BIOC_CAEN_CAEN_FEATURE_SELECTION_AND_CLASSIFICATION(ch_input)

    emit:
    tables   = BIOC_CAEN_CAEN_FEATURE_SELECTION_AND_CLASSIFICATION.out.tables
    plots    = BIOC_CAEN_CAEN_FEATURE_SELECTION_AND_CLASSIFICATION.out.plots
    objects  = BIOC_CAEN_CAEN_FEATURE_SELECTION_AND_CLASSIFICATION.out.objects
    versions = BIOC_CAEN_CAEN_FEATURE_SELECTION_AND_CLASSIFICATION.out.versions
}
