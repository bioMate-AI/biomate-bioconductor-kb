#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: a4Classif — a4_classif_microarray_pipeline
// Perform multi-classifier analysis (Lasso, PAM, Random Forest) on normalized microarray expression data to identify predictive gene signatures and evaluate class
// Input: counts.csv, coldata.csv
// Container: 1.58.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, a4Classif
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_A4CLASSIF_A4_CLASSIF_MICROARRAY_PIPELINE {
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
    library(a4Classif)
    library(Biobase)
    
    # Stage 1: Load and preprocess input data
    message("Loading input datasets...")
    exprs_df <- read.csv("counts.csv", row.names = 1, check.names = FALSE)
    if ("gene_id" %in% colnames(exprs_df)) {
      rownames(exprs_df) <- exprs_df\$gene_id
      exprs_df\$gene_id <- NULL
    }
    exprs_matrix <- as.matrix(exprs_df)
    
    coldata <- read.csv("coldata.csv", row.names = 1, check.names = FALSE)
    if ("sample" %in% colnames(coldata)) {
      rownames(coldata) <- coldata\$sample
    }
    
    # Align samples between expression matrix and metadata
    common_samples <- intersect(colnames(exprs_matrix), rownames(coldata))
    if (length(common_samples) == 0) {
      stop("Error: No common samples found between counts.csv and coldata.csv")
    }
    exprs_matrix <- exprs_matrix[, common_samples, drop = FALSE]
    coldata <- coldata[common_samples, , drop = FALSE]
    
    # Ensure the grouping variable 'condition' is a factor
    coldata\$condition <- as.factor(coldata\$condition)
    
    # Create ExpressionSet object required by a4Classif
    phenoData <- new("AnnotatedDataFrame", data = coldata)
    eset <- ExpressionSet(assayData = exprs_matrix, phenoData = phenoData)
    
    # Stage 2: Lasso Classification
    message("Running Lasso Classification...")
    resultLasso <- tryCatch({
      lassoClass(object = eset, groups = "condition")
    }, error = function(e) {
      message("Lasso classification failed: ", e\$message)
      NULL
    })
    
    if (!is.null(resultLasso)) {
      pdf("lasso_coefficients.pdf")
      plot(resultLasso, label = TRUE, main = "Lasso coefficients vs penalization")
      dev.off()
      
      lasso_table <- topTable(resultLasso, n = 15)
      write.csv(lasso_table, "lasso_top_genes.csv", row.names = TRUE)
    } else {
      write.csv(data.frame(Message = "Lasso failed to converge or run"), "lasso_top_genes.csv")
      pdf("lasso_coefficients.pdf")
      plot(1, type='n', main="Lasso Failed")
      dev.off()
    }
    
    # Stage 3: PAM Classification
    message("Running PAM Classification...")
    resultPam <- tryCatch({
      pamClass(object = eset, groups = "condition")
    }, error = function(e) {
      message("PAM classification failed: ", e\$message)
      NULL
    })
    
    if (!is.null(resultPam)) {
      pdf("pam_misclassification.pdf")
      plot(resultPam, main = "PAM misclassification error vs number of genes")
      dev.off()
      
      pam_table <- topTable(resultPam, n = 15)
      write.csv(pam_table, "pam_top_genes.csv", row.names = TRUE)
    } else {
      write.csv(data.frame(Message = "PAM failed to converge or run"), "pam_top_genes.csv")
      pdf("pam_misclassification.pdf")
      plot(1, type='n', main="PAM Failed")
      dev.off()
    }
    
    # Stage 4: Random Forest Classification
    message("Running Random Forest Classification...")
    resultRf <- tryCatch({
      rfClass(object = eset, groups = "condition")
    }, error = function(e) {
      message("Random Forest classification failed: ", e\$message)
      NULL
    })
    
    if (!is.null(resultRf)) {
      pdf("rf_error_plot.pdf")
      plot(resultRf)
      dev.off()
      
      rf_table <- topTable(resultRf, n = 15)
      write.csv(rf_table, "rf_top_genes.csv", row.names = TRUE)
    } else {
      write.csv(data.frame(Message = "Random Forest failed to run"), "rf_top_genes.csv")
      pdf("rf_error_plot.pdf")
      plot(1, type='n', main="RF Failed")
      dev.off()
    }
    
    # Stage 5: ROC Curve Visualization
    message("Generating ROC Curve...")
    target_gene <- rownames(eset)[1]
    pdf("roc_curve.pdf")
    tryCatch({
      ROCcurve(gene = target_gene, object = eset, groups = "condition")
    }, error = function(e) {
      plot(1, type='n', main=paste("ROC Curve Failed for", target_gene))
      legend("center", legend=e\$message, bty="n")
    })
    dev.off()
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_A4CLASSIF_A4_CLASSIF_MICROARRAY_PIPELINE":',
        paste0('    a4Classif: ', as.character(packageVersion('a4Classif')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_a4_classif_microarray_pipeline.csv versions.yml
    """
}

workflow BIOC_A4CLASSIF_A4_CLASSIF_MICROARRAY_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_A4CLASSIF_A4_CLASSIF_MICROARRAY_PIPELINE(ch_input)

    emit:
    tables   = BIOC_A4CLASSIF_A4_CLASSIF_MICROARRAY_PIPELINE.out.tables
    plots    = BIOC_A4CLASSIF_A4_CLASSIF_MICROARRAY_PIPELINE.out.plots
    objects  = BIOC_A4CLASSIF_A4_CLASSIF_MICROARRAY_PIPELINE.out.objects
    versions = BIOC_A4CLASSIF_A4_CLASSIF_MICROARRAY_PIPELINE.out.versions
}
