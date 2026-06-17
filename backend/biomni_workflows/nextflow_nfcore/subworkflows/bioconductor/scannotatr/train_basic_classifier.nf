#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scAnnotatR — train_basic_classifier
// Train a new SVM classifier for an independent cell type and evaluate its performance.
// Input: zilionis
// Container: quay.io/biocontainers/bioconductor-scannotatr:1.16.0--r45hdfd78af_0
// R packages: SingleCellExperiment, scAnnotatR
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, scAnnotatR
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the dataset and split it into training and testing sets
//  * 2. [Input & Preparation] Define ground-truth cell labels, marking unknown or NA cells as 'ambiguous'
//  * 3. [Input & Preparation] Define a set of marker genes for the target cell type
//  * 4. [Core Analysis] Train the classifier using train_classifier
//  * 5. [Core Analysis] Evaluate the classifier on the test set using test_classifier
//  * 6. [Visualization & Output] Plot the ROC curve of the test results
//  * 7. [Visualization & Output] Save the trained model to a local directory and optionally delete it

nextflow.enable.dsl = 2

process BIOC_SCANNOTATR_TRAIN_BASIC_CLASSIFIER {
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
    .bm_deps <- c("SingleCellExperiment", "scAnnotatR")
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
    library(scAnnotatR)
    
    # 1. Load the dataset and split it into training and testing sets
    # Read the user input file 'zilionis' from the working directory
    zilionis <- readRDS("zilionis")
    
    # Subset to 5000 cells if the input dataset is larger, matching the vignette's scale
    if (ncol(zilionis) > 5000) {
      zilionis <- zilionis[, 1:5000]
    }
    
    colnames(zilionis) <- paste0("Cell", 1:ncol(zilionis))
    pivot = ncol(zilionis) %/% 2
    train_set <- zilionis[, 1:pivot]
    test_set <- zilionis[, (1+pivot):ncol(zilionis)]
    
    # 2. Define ground-truth cell labels, marking unknown or NA cells as 'ambiguous'
    train_set\$B_cell <- unlist(lapply(train_set\$`Most likely LM22 cell type`, function(x) if (is.na(x)) { 'ambiguous' } else if (x %in% c('Plasma cells', 'B cells memory', 'B cells naive')) { 'B cells' } else { 'others' }))
    test_set\$B_cell <- unlist(lapply(test_set\$`Most likely LM22 cell type`, function(x) if (is.na(x)) { 'ambiguous' } else if (x %in% c('Plasma cells', 'B cells memory', 'B cells naive')) { 'B cells' } else { 'others' }))
    
    # 3. Define a set of marker genes for the target cell type
    selected_marker_genes_B <- c("CD19", "MS4A1", "CD79A", "CD79B", 'CD27', 'IGHG1', 'IGHG2', 'IGHM', "CR2", "MEF2C", 'VPREB3', 'CD86', 'LY86', "BLK", "DERL3")
    
    # 4. Train the classifier using train_classifier
    set.seed(123)
    classifier_B <- train_classifier(train_obj = train_set, cell_type = "B cells", marker_genes = selected_marker_genes_B, assay = 'counts', tag_slot = 'B_cell')
    
    # Save the trained classifier object
    saveRDS(classifier_B, "classifier_B.rds")
    
    # 5. Evaluate the classifier on the test set using test_classifier
    classifier_B_test <- test_classifier(classifier = classifier_B, test_obj = test_set, assay = 'counts', tag_slot = 'B_cell')
    
    # Save evaluation metrics
    write.csv(as.data.frame(classifier_B_test\$overall_roc), "overall_roc.csv", row.names = FALSE)
    
    # 6. Plot the ROC curve of the test results
    roc_curve <- plot_roc_curve(test_result = classifier_B_test)
    pdf("roc_curve.pdf")
    plot(roc_curve)
    dev.off()
    
    # 7. Save the trained model to a local directory and optionally delete it
    save_new_model(new_model = classifier_B, path_to_models = tempdir(), include.default = FALSE)
    delete_model("B cells", path_to_models = tempdir())

    writeLines(c(
        '"BIOC_SCANNOTATR_TRAIN_BASIC_CLASSIFIER":',
        paste0('    scAnnotatR: ', as.character(packageVersion('scAnnotatR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_train_basic_classifier.csv versions.yml
    """
}

workflow BIOC_SCANNOTATR_TRAIN_BASIC_CLASSIFIER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ zilionis ] ]

    main:
    BIOC_SCANNOTATR_TRAIN_BASIC_CLASSIFIER(ch_input)

    emit:
    tables   = BIOC_SCANNOTATR_TRAIN_BASIC_CLASSIFIER.out.tables
    plots    = BIOC_SCANNOTATR_TRAIN_BASIC_CLASSIFIER.out.plots
    objects  = BIOC_SCANNOTATR_TRAIN_BASIC_CLASSIFIER.out.objects
    versions = BIOC_SCANNOTATR_TRAIN_BASIC_CLASSIFIER.out.versions
}
