#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scClassify — train_custom_model
// Train and save a custom scClassifyTrainModel on a reference dataset for future predictions.
// Input: reference_expression.csv, reference_labels.csv
// Container: quay.io/biocontainers/bioconductor-scclassify:1.22.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Matrix, scClassify
// Visualizations: phylogenetic tree
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load and format reference expression matrix as a sparse matrix (dgCMatrix)
//  * 2. [Core Analysis] Train the model using train_scClassify() with selected feature selection methods

nextflow.enable.dsl = 2

process BIOC_SCCLASSIFY_TRAIN_CUSTOM_MODEL {
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
    .bm_deps <- c("scClassify", "Matrix")
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
    library("scClassify")
    library("Matrix")
    
    # 1. Load and format reference expression matrix and labels
    # Read the log-normalized expression matrix (genes as rows, cells as columns)
    exprs_df <- read.csv("reference_expression.csv", row.names = 1, check.names = FALSE)
    exprsMat_xin_subset <- as.matrix(exprs_df)
    exprsMat_xin_subset <- as(exprsMat_xin_subset, "dgCMatrix")
    
    # Read the cell type annotations
    labels_df <- read.csv("reference_labels.csv", header = TRUE, stringsAsFactors = FALSE)
    
    # Align labels with the expression matrix columns if possible, or extract the label vector
    if (ncol(labels_df) > 1 && any(labels_df[[1]] %in% colnames(exprsMat_xin_subset))) {
      # If first column contains cell IDs matching the expression matrix
      rownames(labels_df) <- labels_df[[1]]
      labels_df <- labels_df[colnames(exprsMat_xin_subset), , drop = FALSE]
      
      type_col <- grep("type|label|class", colnames(labels_df), ignore.case = TRUE, value = TRUE)
      if (length(type_col) > 0) {
        xin_cellTypes <- as.character(labels_df[[type_col[1]]])
      } else {
        xin_cellTypes <- as.character(labels_df[[2]])
      }
    } else {
      # Otherwise, assume the labels are in the same order as the columns of the expression matrix
      type_col <- grep("type|label|class", colnames(labels_df), ignore.case = TRUE, value = TRUE)
      if (length(type_col) > 0) {
        xin_cellTypes <- as.character(labels_df[[type_col[1]]])
      } else {
        xin_cellTypes <- as.character(labels_df[[1]])
      }
    }
    
    # 2. Train the model using train_scClassify
    trainClass <- train_scClassify(exprsMat_train = exprsMat_xin_subset,
                                   cellTypes_train = xin_cellTypes,
                                   selectFeatures = c("limma", "BI"),
                                   returnList = FALSE
    )
    
    # Print model summary to console
    print(trainClass)
    
    # 3. Save meaningful results
    # Save the trained model object
    saveRDS(trainClass, file = "scClassify_model.rds")
    
    # Save cell type training summary
    summary_df <- data.frame(table(xin_cellTypes))
    colnames(summary_df) <- c("CellType", "Count")
    write.csv(summary_df, "model_cell_type_summary.csv", row.names = FALSE)
    
    # Plot and save the cell type hierarchy tree
    pdf("cell_type_tree.pdf", width = 8, height = 6)
    tryCatch({
      plotCellTypeTree(cellTypeTree(trainClass))
    }, error = function(e) {
      warning("Could not plot cell type tree: ", e\$message)
    })
    dev.off()

    writeLines(c(
        '"BIOC_SCCLASSIFY_TRAIN_CUSTOM_MODEL":',
        paste0('    scClassify: ', as.character(packageVersion('scClassify')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_train_custom_model.csv versions.yml
    """
}

workflow BIOC_SCCLASSIFY_TRAIN_CUSTOM_MODEL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ reference_expression.csv, reference_labels.csv ] ]

    main:
    BIOC_SCCLASSIFY_TRAIN_CUSTOM_MODEL(ch_input)

    emit:
    tables   = BIOC_SCCLASSIFY_TRAIN_CUSTOM_MODEL.out.tables
    plots    = BIOC_SCCLASSIFY_TRAIN_CUSTOM_MODEL.out.plots
    objects  = BIOC_SCCLASSIFY_TRAIN_CUSTOM_MODEL.out.objects
    versions = BIOC_SCCLASSIFY_TRAIN_CUSTOM_MODEL.out.versions
}
