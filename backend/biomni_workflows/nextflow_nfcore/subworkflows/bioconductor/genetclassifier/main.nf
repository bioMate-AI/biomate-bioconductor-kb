#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: geNetClassifier — train_classifier_and_networks
// Train a multi-class SVM classifier, rank significant genes, estimate generalization error, and construct co-expression networks from gene expression data.
// Input: expression_data.RData, sample_metadata.csv
// Container: quay.io/biocontainers/bioconductor-genetclassifier:1.50.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, geNetClassifier
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load the gene expression dataset and define training
//  * 2. [Visualization & Output] Run geNetClassifier() to rank genes, train the SVM
//  * 3. [Visualization & Output] Inspect the ranked genes and significant gene counts
//  * 4. [Visualization & Output] Evaluate classifier performance and generalization error
//  * 5. [Visualization & Output] Export the constructed gene networks to text files
//  * 6. [Visualization & Output] Save meaningful results to disk

nextflow.enable.dsl = 2

process BIOC_GENETCLASSIFIER_TRAIN_CLASSIFIER_AND_NETWORKS {
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
    .bm_deps <- c("geNetClassifier", "Biobase")
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
    library(geNetClassifier)
    library(Biobase)
    
    # ==========================================
    # --- Load the gene expression dataset and define training ---
    # ==========================================
    
    if (!file.exists("expression_data.RData")) {
      stop("Required input file 'expression_data.RData' not found in the working directory.")
    }
    if (!file.exists("sample_metadata.csv")) {
      stop("Required input file 'sample_metadata.csv' not found in the working directory.")
    }
    
    # Load ExpressionSet from RData
    local_env <- new.env()
    load("expression_data.RData", envir = local_env)
    eset_objs <- names(local_env)[sapply(local_env, function(x) inherits(x, "ExpressionSet"))]
    if (length(eset_objs) == 0) {
      stop("No ExpressionSet object found in 'expression_data.RData'.")
    }
    leukemiasEset <- local_env[[eset_objs[1]]]
    
    # Load metadata
    metadata <- read.csv("sample_metadata.csv", stringsAsFactors = FALSE)
    
    # Align metadata with ExpressionSet samples
    sample_ids <- sampleNames(leukemiasEset)
    id_col <- NULL
    for (col in colnames(metadata)) {
      if (any(sample_ids %in% metadata[[col]])) {
        id_col <- col
        break
      }
    }
    
    if (!is.null(id_col)) {
      rownames(metadata) <- metadata[[id_col]]
      metadata <- metadata[sample_ids, , drop = FALSE]
      pData(leukemiasEset) <- metadata
    } else {
      pData(leukemiasEset) <- cbind(pData(leukemiasEset), metadata)
    }
    
    # Ensure "LeukemiaType" column exists in pData
    if (!"LeukemiaType" %in% colnames(pData(leukemiasEset))) {
      class_cols <- c("class", "label", "LeukemiaType", "subtype", "group", "type")
      found_col <- intersect(class_cols, colnames(pData(leukemiasEset)))
      if (length(found_col) > 0) {
        pData(leukemiasEset)\$LeukemiaType <- pData(leukemiasEset)[[found_col[1]]]
      } else {
        pData(leukemiasEset)\$LeukemiaType <- metadata[[2]]
      }
    }
    
    # Ensure LeukemiaType is a factor
    pData(leukemiasEset)\$LeukemiaType <- as.factor(pData(leukemiasEset)\$LeukemiaType)
    
    # Define training samples dynamically to ensure robustness across different dataset sizes
    classes <- as.character(pData(leukemiasEset)\$LeukemiaType)
    unique_classes <- unique(classes)
    trainSamples <- unlist(lapply(unique_classes, function(cl) {
      which(classes == cl)[1:min(10, sum(classes == cl))]
    }))
    trainSamples <- sort(trainSamples)
    
    # Construct geneSymbols mapping from featureNames of leukemiasEset
    if ("symbol" %in% colnames(fData(leukemiasEset))) {
      geneSymbols <- fData(leukemiasEset)\$symbol
      names(geneSymbols) <- featureNames(leukemiasEset)
    } else if ("GeneSymbol" %in% colnames(fData(leukemiasEset))) {
      geneSymbols <- fData(leukemiasEset)\$GeneSymbol
      names(geneSymbols) <- featureNames(leukemiasEset)
    } else {
      geneSymbols <- featureNames(leukemiasEset)
      names(geneSymbols) <- featureNames(leukemiasEset)
    }
    
    # ==========================================
    # --- Run geNetClassifier() to rank genes, train the SVM ---
    #    estimate generalization error, and build co-expression networks
    # ==========================================
    
    leukemiasClassifier <- geNetClassifier(
      eset=leukemiasEset[,trainSamples], 
      sampleLabels="LeukemiaType", 
      plotsName="leukemiasClassifier", 
      estimateGError=TRUE, 
      geneLabels=geneSymbols
    )
    
    # ==========================================
    # --- Inspect the ranked genes and significant gene counts ---
    # ==========================================
    
    names(leukemiasClassifier)
    leukemiasClassifier@genesRanking
    numGenes(leukemiasClassifier@genesRanking)
    subRanking <- getTopRanking(leukemiasClassifier@genesRanking, 10)
    getRanking(subRanking)
    
    # Wrap potentially out-of-bounds or class-specific calls in tryCatch for robustness
    tryCatch({
      getRanking(subRanking, showGeneID=TRUE)\$geneID[,1:4]
    }, error = function(e) {
      message("Note: Could not subset first 4 classes. Showing all available classes:")
      print(getRanking(subRanking, showGeneID=TRUE)\$geneID)
    })
    
    tryCatch({
      genesDetails(subRanking)\$AML
    }, error = function(e) {
      message("Note: AML class details not available. Showing details for the first available class:")
      print(genesDetails(subRanking)[[1]])
    })
    
    numSignificantGenes(leukemiasClassifier@genesRanking)
    
    # ==========================================
    # --- Evaluate classifier performance and generalization error ---
    # ==========================================
    
    leukemiasClassifier@classifier
    leukemiasClassifier@classificationGenes
    leukemiasClassifier@generalizationError
    leukemiasClassifier@generalizationError@confMatrix
    leukemiasClassifier@generalizationError@probMatrix
    
    # ==========================================
    # --- Export the constructed gene networks to text files ---
    # ==========================================
    
    leukemiasClassifier@genesNetwork
    network2txt(leukemiasClassifier@genesNetwork, filePrefix="leukemiasNetwork")
    
    # ==========================================
    # --- Save meaningful results to disk ---
    # ==========================================
    
    message("Saving pipeline results to disk...")
    saveRDS(leukemiasClassifier, file="leukemiasClassifier.rds")
    
    # Save ranking
    ranking_list <- getRanking(leukemiasClassifier@genesRanking)
    if (is.list(ranking_list)) {
      write.csv(as.data.frame(ranking_list\$geneLabels), file="genes_ranking_labels.csv", row.names=FALSE)
    } else {
      write.csv(as.data.frame(ranking_list), file="genes_ranking.csv", row.names=FALSE)
    }
    
    # Save confusion matrix if available
    if (!is.null(leukemiasClassifier@generalizationError@confMatrix)) {
      write.csv(as.data.frame.matrix(leukemiasClassifier@generalizationError@confMatrix), file="confusion_matrix.csv")
    }
    
    # Save probability matrix if available
    if (!is.null(leukemiasClassifier@generalizationError@probMatrix)) {
      write.csv(as.data.frame(leukemiasClassifier@generalizationError@probMatrix), file="probability_matrix.csv")
    }
    
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_GENETCLASSIFIER_TRAIN_CLASSIFIER_AND_NETWORKS":',
        paste0('    geNetClassifier: ', as.character(packageVersion('geNetClassifier')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_train_classifier_and_networks.csv versions.yml
    """
}

workflow BIOC_GENETCLASSIFIER_TRAIN_CLASSIFIER_AND_NETWORKS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_data.RData, sample_metadata.csv ] ]

    main:
    BIOC_GENETCLASSIFIER_TRAIN_CLASSIFIER_AND_NETWORKS(ch_input)

    emit:
    tables   = BIOC_GENETCLASSIFIER_TRAIN_CLASSIFIER_AND_NETWORKS.out.tables
    plots    = BIOC_GENETCLASSIFIER_TRAIN_CLASSIFIER_AND_NETWORKS.out.plots
    objects  = BIOC_GENETCLASSIFIER_TRAIN_CLASSIFIER_AND_NETWORKS.out.objects
    versions = BIOC_GENETCLASSIFIER_TRAIN_CLASSIFIER_AND_NETWORKS.out.versions
}
