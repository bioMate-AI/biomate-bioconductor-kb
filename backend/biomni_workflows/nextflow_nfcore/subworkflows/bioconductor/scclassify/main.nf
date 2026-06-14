#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scClassify — joint_scclassify
// Perform joint training and cell type prediction on a query dataset using a reference dataset in a single step.
// Input: reference_expression.csv, reference_labels.csv, query_expression.csv
// Container: quay.io/biocontainers/bioconductor-scclassify:1.22.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Matrix, scClassify
// Visualizations: phylogenetic tree
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load and format reference and query expression matrices as sparse matrices (dgCMatrix)
//  * 2. [Core Analysis] Run joint classification using scClassify()
//  * 3. [Core Analysis] Inspect the trained cell type tree and prediction results

nextflow.enable.dsl = 2

process BIOC_SCCLASSIFY_JOINT_SCCLASSIFY {
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
    .bm_deps <- c("scClassify", "Matrix")
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
    library("scClassify")
    library("Matrix")
    
    # 1. Load and format reference and query expression matrices as sparse matrices (dgCMatrix)
    # Read reference expression matrix (log-normalized, genes as rows, cells as columns)
    ref_expr <- read.csv("reference_expression.csv", row.names = 1, check.names = FALSE)
    exprsMat_xin_subset <- as.matrix(ref_expr)
    exprsMat_xin_subset <- as(exprsMat_xin_subset, "dgCMatrix")
    
    # Read reference cell type annotations
    ref_labels <- read.csv("reference_labels.csv", header = TRUE)
    xin_cellTypes <- as.character(ref_labels[, 1])
    
    # Read query expression matrix (log-normalized, genes as rows, cells as columns)
    query_expr <- read.csv("query_expression.csv", row.names = 1, check.names = FALSE)
    exprsMat_wang_subset <- as.matrix(query_expr)
    exprsMat_wang_subset <- as(exprsMat_wang_subset, "dgCMatrix")
    
    # Since query labels are not provided in the user input, we set wang_cellTypes to NULL
    wang_cellTypes <- NULL
    
    # 2. Run joint classification using scClassify()
    scClassify_res <- scClassify(exprsMat_train = exprsMat_xin_subset,
                                 cellTypes_train = xin_cellTypes,
                                 exprsMat_test = list(wang = exprsMat_wang_subset),
                                 cellTypes_test = list(wang = wang_cellTypes),
                                 tree = "HOPACH",
                                 algorithm = "WKNN",
                                 selectFeatures = c("limma"),
                                 similarity = c("pearson"),
                                 returnList = FALSE,
                                 verbose = FALSE)
    
    # 3. Inspect the trained cell type tree and prediction results
    # Print training model summary
    print(scClassify_res\$trainRes)
    
    # Plot and save the cell type tree
    pdf("cell_type_tree.pdf", width = 8, height = 6)
    plotCellTypeTree(cellTypeTree(scClassify_res\$trainRes))
    dev.off()
    
    # Save the prediction results to a CSV file
    pred_res <- scClassify_res\$testRes\$wang\$pearson_WKNN_limma\$predRes
    predictions_df <- data.frame(
      Cell = colnames(exprsMat_wang_subset),
      Predicted_CellType = pred_res
    )
    write.csv(predictions_df, "query_predictions.csv", row.names = FALSE)
    
    # Save the full scClassify results object
    saveRDS(scClassify_res, "scClassify_results.rds")
    
    # Faithfully attempt to run the documented table function
    tryCatch({
      tbl <- table(scClassify_res\$testRes\$wang\$pearson_WKNN_limma\$predRes, wang_cellTypes)
      print(tbl)
    }, error = function(e) {
      cat("\nDistribution of predicted cell types:\n")
      print(table(scClassify_res\$testRes\$wang\$pearson_WKNN_limma\$predRes))
    })

    writeLines(c(
        '"BIOC_SCCLASSIFY_JOINT_SCCLASSIFY":',
        paste0('    scClassify: ', as.character(packageVersion('scClassify')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_joint_scclassify.csv versions.yml
    """
}

workflow BIOC_SCCLASSIFY_JOINT_SCCLASSIFY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ reference_expression.csv, reference_labels.csv, query_expression.csv ] ]

    main:
    BIOC_SCCLASSIFY_JOINT_SCCLASSIFY(ch_input)

    emit:
    tables   = BIOC_SCCLASSIFY_JOINT_SCCLASSIFY.out.tables
    plots    = BIOC_SCCLASSIFY_JOINT_SCCLASSIFY.out.plots
    objects  = BIOC_SCCLASSIFY_JOINT_SCCLASSIFY.out.objects
    versions = BIOC_SCCLASSIFY_JOINT_SCCLASSIFY.out.versions
}
