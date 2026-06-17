#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: nipalsMCIA — out_of_sample_prediction
// Predict MCIA global scores for new test samples using a model trained on a training set.
// Input: data_blocks_train, data_blocks_test, metadata_train, metadata_test
// Container: quay.io/biocontainers/bioconductor-nipalsmcia:1.8.1--r45hdfd78af_0
// R packages: MultiAssayExperiment, ggplot2, nipalsMCIA
// Bioconductor: 3.20 | R: 4.4
// Requires: MultiAssayExperiment, ggplot2, nipalsMCIA
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Convert training and test sets to MAE objects using simple_mae()
//  * 2. [Core Analysis] Train MCIA model on training MAE using nipals_multiblock()
//  * 3. [Core Analysis] Predict global scores for test MAE using predict_gs()
//  * 4. [Visualization & Output] Extract global scores and metadata for visualization

nextflow.enable.dsl = 2

process BIOC_NIPALSMCIA_OUT_OF_SAMPLE_PREDICTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-single_cell:3.20-slim"

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
    .bm_deps <- c("MultiAssayExperiment", "ggplot2", "nipalsMCIA", "SummarizedExperiment")
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
    library(ggplot2)
    library(SummarizedExperiment)
    library(MultiAssayExperiment)
    library(nipalsMCIA)
    
    # Read user input files from the working directory
    data_blocks_train <- readRDS("data_blocks_train.rds")
    data_blocks_test <- readRDS("data_blocks_test.rds")
    metadata_train <- readRDS("metadata_train.rds")
    metadata_test <- readRDS("metadata_test.rds")
    
    # 1. Convert training and test sets to MAE objects using simple_mae()
    data_blocks_train_mae <- simple_mae(data_blocks_train, row_format = "sample", colData = metadata_train)
    data_blocks_test_mae <- simple_mae(data_blocks_test, row_format = "sample", colData = metadata_test)
    
    # 2. Train MCIA model on training MAE using nipals_multiblock()
    MCIA_train <- nipals_multiblock(data_blocks = data_blocks_train_mae, col_preproc_method = "colprofile", num_PCs = 10, plots = "none", tol = 1e-9)
    
    # 3. Extract global scores and metadata for visualization
    meta_colors <- get_metadata_colors(mcia_results = MCIA_train, color_col = 1, color_pal_params = list(option = "E"))
    global_scores <- nmb_get_gs(MCIA_train)
    MCIA_out <- data.frame(global_scores[, 1:2])
    
    meta_train <- nmb_get_metadata(MCIA_train)
    meta_col <- colnames(meta_train)[1]
    
    MCIA_out[[meta_col]] <- meta_train[[meta_col]]
    colnames(MCIA_out) <- c("Factor.1", "Factor.2", meta_col)
    
    # 4. Predict global scores for test MAE using predict_gs()
    MCIA_test_scores <- predict_gs(mcia_results = MCIA_train, test_data = data_blocks_test_mae)
    
    # Prepare test scores for visualization and output
    MCIA_out_test <- data.frame(MCIA_test_scores[, 1:2])
    MCIA_out_test[[meta_col]] <- MultiAssayExperiment::colData(data_blocks_test_mae)[[meta_col]]
    colnames(MCIA_out_test) <- c("Factor.1", "Factor.2", meta_col)
    MCIA_out_test\$set <- "test"
    MCIA_out\$set <- "train"
    MCIA_out_full <- rbind(MCIA_out, MCIA_out_test)
    rownames(MCIA_out_full) <- NULL
    
    # Save visualization plot to PDF
    pdf("mcia_prediction_plot.pdf", width = 8, height = 6)
    p <- ggplot(data = MCIA_out_full, aes(x = Factor.1, y = Factor.2, color = .data[[meta_col]], shape = set)) +
      geom_point(size = 3) +
      labs(title = "MCIA training and test data", color = meta_col) +
      scale_color_manual(values = meta_colors) +
      theme_bw()
    print(p)
    dev.off()
    
    # Save outputs to files
    saveRDS(MCIA_train, "MCIA_train_model.rds")
    write.csv(MCIA_out_full, "MCIA_combined_scores.csv", row.names = FALSE)
    write.csv(MCIA_out_test, "MCIA_test_scores.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_NIPALSMCIA_OUT_OF_SAMPLE_PREDICTION":',
        paste0('    nipalsMCIA: ', as.character(packageVersion('nipalsMCIA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_out_of_sample_prediction.csv versions.yml
    """
}

workflow BIOC_NIPALSMCIA_OUT_OF_SAMPLE_PREDICTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ data_blocks_train, data_blocks_test, metadata_train, metadata_test ] ]

    main:
    BIOC_NIPALSMCIA_OUT_OF_SAMPLE_PREDICTION(ch_input)

    emit:
    tables   = BIOC_NIPALSMCIA_OUT_OF_SAMPLE_PREDICTION.out.tables
    plots    = BIOC_NIPALSMCIA_OUT_OF_SAMPLE_PREDICTION.out.plots
    objects  = BIOC_NIPALSMCIA_OUT_OF_SAMPLE_PREDICTION.out.objects
    versions = BIOC_NIPALSMCIA_OUT_OF_SAMPLE_PREDICTION.out.versions
}
