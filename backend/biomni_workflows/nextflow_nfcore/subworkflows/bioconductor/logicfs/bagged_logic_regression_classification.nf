#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: logicFS — bagged_logic_regression_classification
// Train a bagged logic regression classifier, estimate out-of-bag error, and predict classes of new observations.
// Input: data.logicfs, cl.logicfs
// Container: quay.io/biocontainers/bioconductor-logicfs:2.30.0--r45hdfd78af_0
// Requires: logicFS
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the package and data
//  * 2. [Core Analysis] Convert categorical SNP variables into binary dummy variables
//  * 3. [Input & Preparation] Set up simulated annealing control parameters
//  * 4. [Core Analysis] Train a bagged logic regression model
//  * 5. [Core Analysis] Inspect variable importance from the bagged model
//  * 6. [Core Analysis] Predict class labels for observations and calculate misclassification rate

nextflow.enable.dsl = 2

process BIOC_LOGICFS_BAGGED_LOGIC_REGRESSION_CLASSIFICATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-variant_calling:3.20"

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
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
    
    # Load the required package
    library(logicFS)
    
    # Helper function to robustly load data.logicfs
    load_data_logicfs <- function() {
      if (file.exists("data.logicfs")) {
        # Try reading as RDS
        res <- tryCatch(readRDS("data.logicfs"), error = function(e) NULL)
        if (!is.null(res)) return(res)
        
        # Try reading as table with header
        res <- tryCatch(as.matrix(read.table("data.logicfs", header = TRUE, check.names = FALSE)), error = function(e) NULL)
        if (!is.null(res)) return(res)
        
        # Try reading as table without header
        res <- tryCatch(as.matrix(read.table("data.logicfs", header = FALSE, check.names = FALSE)), error = function(e) NULL)
        if (!is.null(res)) return(res)
      }
      stop("Error: 'data.logicfs' file not found or could not be read.")
    }
    
    # Helper function to robustly load cl.logicfs
    load_cl_logicfs <- function() {
      if (file.exists("cl.logicfs")) {
        # Try reading as RDS
        res <- tryCatch(readRDS("cl.logicfs"), error = function(e) NULL)
        if (!is.null(res)) return(res)
        
        # Try reading as a simple vector/scan
        res <- tryCatch(scan("cl.logicfs", quiet = TRUE), error = function(e) NULL)
        if (!is.null(res)) return(res)
        
        # Try reading as a single-column table
        res <- tryCatch(read.table("cl.logicfs")[[1]], error = function(e) NULL)
        if (!is.null(res)) return(res)
      }
      stop("Error: 'cl.logicfs' file not found or could not be read.")
    }
    
    # 1. Load the user-provided data
    data.logicfs <- load_data_logicfs()
    cl.logicfs <- load_cl_logicfs()
    
    # 2. Convert categorical SNP variables into binary dummy variables
    bin.snps <- make.snp.dummy(data.logicfs)
    
    # 3. Set up simulated annealing control parameters
    my.anneal <- logreg.anneal.control(start = 2, end = -2, iter = 10000)
    
    # 4. Train a bagged logic regression model
    bag.out <- logic.bagging(bin.snps, cl.logicfs, B = 20, nleaves = 10, rand = 1234, anneal.control = my.anneal)
    bag.out
    
    # 5. Inspect variable importance from the bagged model
    bag.out\$vim
    
    # Save model and variable importance objects
    saveRDS(bag.out, "bag_out.rds")
    saveRDS(bag.out\$vim, "variable_importance.rds")
    
    # Write text summary of variable importance
    sink("variable_importance_summary.txt")
    print(bag.out\$vim)
    sink()
    
    # Plot variable importance and save as PDF
    pdf("variable_importance_plot.pdf")
    plot(bag.out)
    dev.off()
    
    # 6. Predict class labels for observations and calculate misclassification rate
    cl.preds <- predict(bag.out, bin.snps)
    misclass_rate <- mean(cl.preds != cl.logicfs)
    
    # Output predictions and misclassification rate
    write.csv(data.frame(Actual = cl.logicfs, Predicted = cl.preds), "predictions.csv", row.names = FALSE)
    writeLines(as.character(misclass_rate), "misclassification_rate.txt")
    
    cat("Pipeline completed successfully. Misclassification Rate:", misclass_rate, "\n")

    writeLines(c(
        '"BIOC_LOGICFS_BAGGED_LOGIC_REGRESSION_CLASSIFICATION":',
        paste0('    logicFS: ', as.character(packageVersion('logicFS')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bagged_logic_regression_classification.csv versions.yml
    """
}

workflow BIOC_LOGICFS_BAGGED_LOGIC_REGRESSION_CLASSIFICATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ data.logicfs, cl.logicfs ] ]

    main:
    BIOC_LOGICFS_BAGGED_LOGIC_REGRESSION_CLASSIFICATION(ch_input)

    emit:
    tables   = BIOC_LOGICFS_BAGGED_LOGIC_REGRESSION_CLASSIFICATION.out.tables
    plots    = BIOC_LOGICFS_BAGGED_LOGIC_REGRESSION_CLASSIFICATION.out.plots
    objects  = BIOC_LOGICFS_BAGGED_LOGIC_REGRESSION_CLASSIFICATION.out.objects
    versions = BIOC_LOGICFS_BAGGED_LOGIC_REGRESSION_CLASSIFICATION.out.versions
}
