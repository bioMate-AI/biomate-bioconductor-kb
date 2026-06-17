#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: geneClassifiers — gene_classification
// Apply published gene expression classifiers to pre-normalized ExpressionSet data to obtain patient risk scores and classifications, with optional handling of mi
// Input: expression_set.RData
// Container: quay.io/biocontainers/bioconductor-geneclassifiers:1.34.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, geneClassifiers
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the package and inspect available classifiers using showClassifierList and getClassifier
//  * 2. [Input & Preparation] Import and register the normalization method of the ExpressionSet using setNormalizationMethod
//  * 3. [Core Analysis] Run the classifier on the normalized data using runClassifier (with optional allow.reweighted = TRUE if probe-sets are missing)
//  * 4. [Core Analysis] Extract patient scores and risk classifications using getScores and getClassifications

nextflow.enable.dsl = 2

process BIOC_GENECLASSIFIERS_GENE_CLASSIFICATION {
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
    .bm_deps <- c("geneClassifiers", "Biobase")
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
    
    library(geneClassifiers)
    library(Biobase)
    
    # 1. Inspect available classifiers
    showClassifierList()
    
    EMC92Classifier <- getClassifier("EMC92")
    EMC92Classifier
    
    HM19Classifier <- getClassifier("HM19")
    HM19Classifier
    
    getWeights(EMC92Classifier)[1:10]
    
    getDecisionBoundaries(HM19Classifier)
    
    getEventChain(EMC92Classifier)
    
    # 2. Load the user-provided ExpressionSet from the working directory
    if (!file.exists("expression_set.RData")) {
        stop("Error: 'expression_set.RData' not found in the working directory.")
    }
    
    env <- new.env()
    load("expression_set.RData", envir = env)
    obj_names <- ls(env)
    
    exampleMAS5 <- NULL
    for (name in obj_names) {
        if (inherits(env[[name]], "ExpressionSet")) {
            exampleMAS5 <- env[[name]]
            break
        }
    }
    
    if (is.null(exampleMAS5)) {
        stop("Error: No ExpressionSet object found in 'expression_set.RData'.")
    }
    
    class(exampleMAS5)
    dim(exampleMAS5)
    preproc(experimentData(exampleMAS5))
    
    # 3. Import and register the normalization method of the ExpressionSet
    fixedData <- setNormalizationMethod( exampleMAS5, method="MAS5.0", targetValue = 500 )
    fixedData
    
    # 4. Run the classifiers on the normalized data
    resultsEMC92  <- runClassifier( "EMC92" , fixedData )
    resultsUAMS70 <- runClassifier( "UAMS70", fixedData )
    
    resultsEMC92
    resultsUAMS70
    
    # 5. Extract patient scores and risk classifications
    results_df <- data.frame(
        "score_EMC92"  = getScores( resultsEMC92 ),
        "class_EMC92"  = getClassifications( resultsEMC92 ),
        "score_UAMS70" = getScores( resultsUAMS70 ),
        "class_UAMS70" = getClassifications( resultsUAMS70 )
    )
    
    write.csv(results_df, "classifier_results.csv", row.names = TRUE)
    
    # 6. Run classifier with missing probe-sets (reweighted)
    # We subset the data to simulate missing probe-sets
    num_features <- min(70, nrow(fixedData))
    resultsEMC92.reWeighted <- runClassifier( 
        "EMC92" , 
        fixedData[1:num_features,] ,
        allow.reweighted=TRUE
    )
    
    resultsEMC92.reWeighted
    
    # 7. Generate comparison plot and save to PDF
    pdf("emc92_reweighted_comparison.pdf", width = 7, height = 7)
    plot(
        x = getScores(resultsEMC92),
        y = getScores(resultsEMC92.reWeighted), 
        xlab = "complete", 
        ylab = "reweighted", 
        main = "EMC92 scores",
        pch = 21,
        bg  ='black'
    )
    lines(c(-10,10),c(-10,10),col=2,lty=2)
    abline(
        v = getDecisionBoundaries( getClassifier( resultsEMC92           )),
        h = getDecisionBoundaries( getClassifier( resultsEMC92.reWeighted)),
        col='red'
    )
    dev.off()
    
    # 8. Save results as RDS objects for downstream analysis
    saveRDS(resultsEMC92, "resultsEMC92.rds")
    saveRDS(resultsUAMS70, "resultsUAMS70.rds")
    saveRDS(resultsEMC92.reWeighted, "resultsEMC92_reWeighted.rds")

    writeLines(c(
        '"BIOC_GENECLASSIFIERS_GENE_CLASSIFICATION":',
        paste0('    geneClassifiers: ', as.character(packageVersion('geneClassifiers')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gene_classification.csv versions.yml
    """
}

workflow BIOC_GENECLASSIFIERS_GENE_CLASSIFICATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_set.RData ] ]

    main:
    BIOC_GENECLASSIFIERS_GENE_CLASSIFICATION(ch_input)

    emit:
    tables   = BIOC_GENECLASSIFIERS_GENE_CLASSIFICATION.out.tables
    plots    = BIOC_GENECLASSIFIERS_GENE_CLASSIFICATION.out.plots
    objects  = BIOC_GENECLASSIFIERS_GENE_CLASSIFICATION.out.objects
    versions = BIOC_GENECLASSIFIERS_GENE_CLASSIFICATION.out.versions
}
