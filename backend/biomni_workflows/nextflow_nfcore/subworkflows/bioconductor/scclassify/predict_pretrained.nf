#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scClassify — predict_pretrained
// Predict cell types in a query dataset using an existing pretrained scClassify model.
// Input: pretrained_model.RData, query_expression.csv
// Container: quay.io/biocontainers/bioconductor-scclassify:1.22.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Matrix, scClassify
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the pretrained model and query expression matrix
//  * 2. [Core Analysis] Format the query matrix as a sparse matrix (dgCMatrix)
//  * 3. [Core Analysis] Run prediction using predict_scClassify()
//  * 4. [Core Analysis] Inspect prediction results

nextflow.enable.dsl = 2

process BIOC_SCCLASSIFY_PREDICT_PRETRAINED {
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
        library(scClassify)
        library(Matrix)
        
        # 1. Load the pretrained model and query expression matrix
        # Load pretrained model from pretrained_model.RData
        env <- new.env()
        load("pretrained_model.RData", envir = env)
        
        # Find the scClassifyTrainModel object in the loaded environment
        obj_names <- ls(env)
        model_name <- NULL
        for (name in obj_names) {
          if (inherits(env[[name]], "scClassifyTrainModel")) {
            model_name <- name
            break
          }
        }
        
        if (is.null(model_name)) {
          if (length(obj_names) > 0) {
            pretrained_model <- env[[obj_names[1]]]
          } else {
            stop("No objects found in pretrained_model.RData")
          }
        } else {
          pretrained_model <- env[[model_name]]
        }
        
        # Load query expression matrix
        query_df <- read.csv("query_expression.csv", row.names = 1, check.names = FALSE)
        exprsMat_query <- as.matrix(query_df)
        
        # Check if query cell types are provided for validation
        query_cellTypes <- NULL
        if (file.exists("query_celltypes.csv")) {
          ct_df <- read.csv("query_celltypes.csv", stringsAsFactors = FALSE)
          query_cellTypes <- ct_df[[1]]
        }
        
        # 2. Format the query matrix as a sparse matrix (dgCMatrix)
        exprsMat_query <- as(exprsMat_query, "dgCMatrix")
        
        # Inspect model features
        model_feature <- features(pretrained_model)[1]
        print(features(pretrained_model))
        
        # Plot cell type tree and save to PDF
        pdf("cell_type_tree.pdf")
        tryCatch({
          plotCellTypeTree(cellTypeTree(pretrained_model))
        }, error = function(e) {
          warning("Could not plot cell type tree: ", e\$message)
        })
        dev.off()
        
        # 3. Run prediction using predict_scClassify()
        pred_res <- predict_scClassify(exprsMat_test = exprsMat_query,
                                       trainRes = pretrained_model,
                                       cellTypes_test = query_cellTypes,
                                       algorithm = "WKNN",
                                       features = model_feature,
                                       similarity = c("pearson", "spearman"),
                                       prob_threshold = 0.7,
                                       verbose = TRUE)
        
        # 4. Inspect and save prediction results
        # Save full prediction results object
        saveRDS(pred_res, "prediction_results.rds")
        
        pearson_res_name <- paste0("pearson_WKNN_", model_feature)
        spearman_res_name <- paste0("spearman_WKNN_", model_feature)
        
        # Save predicted cell types as CSV
        pred_df <- data.frame(
          Cell = colnames(exprsMat_query),
          Pearson = pred_res[[pearson_res_name]]\$predRes,
          Spearman = pred_res[[spearman_res_name]]\$predRes,
          stringsAsFactors = FALSE
        )
        colnames(pred_df)[2] <- paste0("Pearson_WKNN_", model_feature)
        colnames(pred_df)[3] <- paste0("Spearman_WKNN_", model_feature)
        write.csv(pred_df, "predicted_cell_types.csv", row.names = FALSE)
        
        # Generate and save confusion tables if ground truth is available
        if (!is.null(query_cellTypes)) {
          tab_pearson <- table(pred_res[[pearson_res_name]]\$predRes, query_cellTypes)
          write.csv(as.data.frame(tab_pearson), "pearson_confusion_matrix.csv")
          
          tab_spearman <- table(pred_res[[spearman_res_name]]\$predRes, query_cellTypes)
          write.csv(as.data.frame(tab_spearman), "spearman_confusion_matrix.csv")
          
          print(paste("Pearson WKNN", model_feature, "Confusion Matrix:"))
          print(tab_pearson)
          print(paste("Spearman WKNN", model_feature, "Confusion Matrix:"))
          print(tab_spearman)
        } else {
          tab_pearson <- table(pred_res[[pearson_res_name]]\$predRes)
          write.csv(as.data.frame(tab_pearson), "pearson_prediction_distribution.csv")
          
          tab_spearman <- table(pred_res[[spearman_res_name]]\$predRes)
          write.csv(as.data.frame(tab_spearman), "spearman_prediction_distribution.csv")
          
          print(paste("Pearson WKNN", model_feature, "Prediction Distribution:"))
          print(tab_pearson)
          print(paste("Spearman WKNN", model_feature, "Prediction Distribution:"))
          print(tab_spearman)
        }

    writeLines(c(
        '"BIOC_SCCLASSIFY_PREDICT_PRETRAINED":',
        paste0('    scClassify: ', as.character(packageVersion('scClassify')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_predict_pretrained.csv versions.yml
    """
}

workflow BIOC_SCCLASSIFY_PREDICT_PRETRAINED_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pretrained_model.RData, query_expression.csv ] ]

    main:
    BIOC_SCCLASSIFY_PREDICT_PRETRAINED(ch_input)

    emit:
    tables   = BIOC_SCCLASSIFY_PREDICT_PRETRAINED.out.tables
    plots    = BIOC_SCCLASSIFY_PREDICT_PRETRAINED.out.plots
    objects  = BIOC_SCCLASSIFY_PREDICT_PRETRAINED.out.objects
    versions = BIOC_SCCLASSIFY_PREDICT_PRETRAINED.out.versions
}
