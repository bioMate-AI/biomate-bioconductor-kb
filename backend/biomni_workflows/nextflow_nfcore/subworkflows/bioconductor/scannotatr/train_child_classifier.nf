#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scAnnotatR — train_child_classifier
// Train a classifier for a cell subtype (child model) that depends on a parent classifier.
// Input: zilionis
// Container: quay.io/biocontainers/bioconductor-scannotatr:1.16.0--r45hdfd78af_0
// R packages: SingleCellExperiment, ggplot2, scAnnotatR
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, ggplot2, scAnnotatR
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the parent classifier from default models
//  * 2. [Input & Preparation] Prepare training and testing datasets, removing NA cells and defining subtype labels
//  * 3. [Input & Preparation] Define marker genes for the subtype
//  * 4. [Core Analysis] Train the child classifier using train_classifier with the parent classifier specified
//  * 5. [Core Analysis] Evaluate the child classifier on the test set using test_classifier
//  * 6. [Visualization & Output] Save both parent and child classifiers to a local database
//  * 7. [Core Analysis] Classify cells using the newly trained local database via classify_cells

nextflow.enable.dsl = 2

process BIOC_SCANNOTATR_TRAIN_CHILD_CLASSIFIER {
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
    .bm_deps <- c("SingleCellExperiment", "ggplot2", "scAnnotatR")
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
        
    library(scAnnotatR)
    library(ggplot2)
    
    # 1. Load the parent classifier from default models
    default_models <- load_models('default')
    classifier_B <- default_models[['B cells']]
    
    # 2. Prepare training and testing datasets from user input
    # Read the SingleCellExperiment object from the working directory
    zilionis <- readRDS("zilionis")
    
    # Apply the same preprocessing and splitting as the documented workflow
    colnames(zilionis) <- paste0("Cell", 1:ncol(zilionis))
    pivot <- ncol(zilionis) %/% 2
    train_set <- zilionis[, 1:pivot]
    test_set <- zilionis[, (1+pivot):ncol(zilionis)]
    
    # Remove NA cells and define subtype labels
    train_set <- train_set[, !is.na(train_set\$`Most likely LM22 cell type`)]
    test_set <- test_set[, !is.na(test_set\$`Most likely LM22 cell type`)]
    
    train_set\$plasma <- unlist(lapply(train_set\$`Most likely LM22 cell type`, function(x) if (x == 'Plasma cells') {1} else {0}))
    test_set\$plasma <- unlist(lapply(test_set\$`Most likely LM22 cell type`, function(x) if (x == 'Plasma cells') {1} else {0}))
    
    # 3. Define marker genes for the subtype
    selected_marker_genes_plasma <- c('BACH2', 'BLK', 'CD14', 'CD19', 'CD27', 'CD37', 'CD38', 'CD40LG', 'CD74', 'CD79A', 'CD79B', 'CD83', 'CD84', 'CD86', 'CR2', 'DERL3', 'FLI1', 'IGHG1', 'IGHG2', 'IGHM', 'IL2RA', 'IRF8', 'LRMP', 'LY86', 'MCL1', 'MEF2C', 'MME', 'MS4A1', 'MVK', 'MZB1', 'POU2AF1', 'PTEN', 'RASGRP2', 'SDC1', 'SP140', 'TCF3', 'VPREB3')
    
    # 4. Train the child classifier using train_classifier with the parent classifier specified
    set.seed(123)
    classifier_plasma <- train_classifier(
      train_obj = train_set, 
      marker_genes = selected_marker_genes_plasma, 
      cell_type = "Plasma cells", 
      assay = 'counts', 
      tag_slot = 'plasma', 
      parent_classifier = classifier_B
    )
    
    # Print classifier details
    print(classifier_plasma)
    print(caret_model(classifier_plasma))
    
    # 5. Evaluate the child classifier on the test set using test_classifier
    classifier_plasma_test <- test_classifier(
      test_obj = test_set, 
      classifier = classifier_plasma, 
      assay = 'counts', 
      tag_slot = 'plasma', 
      parent_classifier = classifier_B
    )
    
    # Save evaluation metrics
    writeLines(as.character(classifier_plasma_test\$auc), "auc_value.txt")
    
    # Plot and save ROC curve
    roc_curve <- plot_roc_curve(test_result = classifier_plasma_test)
    pdf("roc_curve.pdf")
    plot(roc_curve)
    dev.off()
    
    # 6. Save both parent and child classifiers to a local database
    save_new_model(new_model = classifier_B, path_to_models = tempdir(), include.default = FALSE)
    save_new_model(new_model = classifier_plasma, path_to_models = tempdir(), include.default = FALSE)
    
    # Save the trained child classifier object as RDS
    saveRDS(classifier_plasma, "classifier_plasma.rds")
    
    # 7. Classify cells using the newly trained local database via classify_cells
    classified <- classify_cells(
      classify_obj = test_set, 
      assay = 'counts', 
      cell_types = 'all', 
      path_to_models = tempdir()
    )
    
    # Save classification results tables
    tab1 <- table(classified\$predicted_cell_type, classified\$plasma)
    tab2 <- table(classified\$most_probable_cell_type, classified\$plasma)
    write.csv(as.data.frame(tab1), "predicted_vs_plasma.csv", row.names = TRUE)
    write.csv(as.data.frame(tab2), "most_probable_vs_plasma.csv", row.names = TRUE)
    
    # Classify cells ignoring ambiguous results
    classified_ignored <- classify_cells(
      classify_obj = test_set, 
      assay = 'counts', 
      cell_types = 'all', 
      path_to_models = tempdir(), 
      ignore_ambiguous_result = TRUE
    )
    
    tab3 <- table(classified_ignored\$predicted_cell_type, classified_ignored\$plasma)
    write.csv(as.data.frame(tab3), "predicted_ignored_vs_plasma.csv", row.names = TRUE)

    writeLines(c(
        '"BIOC_SCANNOTATR_TRAIN_CHILD_CLASSIFIER":',
        paste0('    scAnnotatR: ', as.character(packageVersion('scAnnotatR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_train_child_classifier.csv versions.yml
    """
}

workflow BIOC_SCANNOTATR_TRAIN_CHILD_CLASSIFIER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ zilionis ] ]

    main:
    BIOC_SCANNOTATR_TRAIN_CHILD_CLASSIFIER(ch_input)

    emit:
    tables   = BIOC_SCANNOTATR_TRAIN_CHILD_CLASSIFIER.out.tables
    plots    = BIOC_SCANNOTATR_TRAIN_CHILD_CLASSIFIER.out.plots
    objects  = BIOC_SCANNOTATR_TRAIN_CHILD_CLASSIFIER.out.objects
    versions = BIOC_SCANNOTATR_TRAIN_CHILD_CLASSIFIER.out.versions
}
