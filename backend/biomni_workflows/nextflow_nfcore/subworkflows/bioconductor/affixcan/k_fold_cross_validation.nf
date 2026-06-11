#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: AffiXcan — k_fold_cross_validation
// Evaluate the predictive performance of GReX models using k-fold cross-validation.
// Input: exprMatrix, training.tba.toydata.rds, regionAssoc, trainingCovariates
// Container: quay.io/biocontainers/bioconductor-affixcan:1.28.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: AffiXcan, MultiAssayExperiment, SummarizedExperiment
// Visualizations: box plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Run affiXcanTrain() with the kfold parameter set to the desired number of folds to perform cross-validation and generate a perform

nextflow.enable.dsl = 2

process BIOC_AFFIXCAN_K_FOLD_CROSS_VALIDATION {
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
    library(AffiXcan)
    library(MultiAssayExperiment)
    
    # Helper function to read inputs robustly (handles RDS and RData formats)
    read_input <- function(name) {
      if (file.exists(name)) {
        res <- tryCatch(readRDS(name), error = function(e) NULL)
        if (!is.null(res)) return(res)
        res <- tryCatch({
          env <- new.env()
          load(name, envir = env)
          env[[ls(env)[1]]]
        }, error = function(e) NULL)
        if (!is.null(res)) return(res)
      }
      for (ext in c(".rds", ".RDS", ".RData", ".rdata")) {
        path <- paste0(name, ext)
        if (file.exists(path)) {
          if (tolower(ext) == ".rds") {
            res <- tryCatch(readRDS(path), error = function(e) NULL)
            if (!is.null(res)) return(res)
          } else {
            res <- tryCatch({
              env <- new.env()
              load(path, envir = env)
              env[[ls(env)[1]]]
            }, error = function(e) NULL)
            if (!is.null(res)) return(res)
          }
        }
      }
      stop(paste("Required input file not found or could not be read:", name))
    }
    
    # Define paths and load inputs from the working directory
    trainingTbaPaths <- "training.tba.toydata.rds"
    if (!file.exists(trainingTbaPaths)) {
      stop("Required input file 'training.tba.toydata.rds' not found in the working directory.")
    }
    
    exprMatrix <- read_input("exprMatrix")
    regionAssoc <- read_input("regionAssoc")
    trainingCovariates <- read_input("trainingCovariates")
    
    assay <- "values"
    
    # Run cross-validation using the exact documented function call
    training <- affiXcanTrain(exprMatrix=exprMatrix, assay=assay,
    tbaPaths=trainingTbaPaths, regionAssoc=regionAssoc, cov=trainingCovariates,
    varExplained=80, scale=TRUE, kfold=5)
    
    # Save the cross-validation performance report
    saveRDS(training, "cv_performance_report.rds")
    
    # Export performance report to CSV if possible, otherwise write a text summary
    tryCatch({
      if (is.data.frame(training) || is.matrix(training)) {
        write.csv(training, "cv_performance_report.csv", row.names = TRUE)
      } else {
        write.csv(as.data.frame(training), "cv_performance_report.csv", row.names = TRUE)
      }
    }, error = function(e) {
      tryCatch({
        sink("cv_performance_report_summary.txt")
        print(summary(training))
        cat("\n\nDetailed Structure:\n")
        print(str(training))
        sink()
      }, error = function(e2) NULL)
    })
    
    # Generate diagnostic performance plots
    tryCatch({
      pdf("cv_performance_plots.pdf")
      if (is.data.frame(training) || is.matrix(training)) {
        boxplot(training, main="Cross-Validation Performance", ylab="Metric Value")
      } else if (is.list(training)) {
        numeric_elements <- sapply(training, is.numeric)
        if (any(numeric_elements)) {
          boxplot(training[numeric_elements], main="Cross-Validation Performance")
        } else {
          plot(training[[1]], main="Cross-Validation Performance (First Element)")
        }
      }
      dev.off()
    }, error = function(e) {
      if (dev.cur() > 1) dev.off()
    })

    writeLines(c(
        '"BIOC_AFFIXCAN_K_FOLD_CROSS_VALIDATION":',
        paste0('    AffiXcan: ', as.character(packageVersion('AffiXcan')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_k_fold_cross_validation.csv versions.yml
    """
}

workflow BIOC_AFFIXCAN_K_FOLD_CROSS_VALIDATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ exprMatrix, training.tba.toydata.rds, regionAssoc, trainingCovariates ] ]

    main:
    BIOC_AFFIXCAN_K_FOLD_CROSS_VALIDATION(ch_input)

    emit:
    tables   = BIOC_AFFIXCAN_K_FOLD_CROSS_VALIDATION.out.tables
    plots    = BIOC_AFFIXCAN_K_FOLD_CROSS_VALIDATION.out.plots
    objects  = BIOC_AFFIXCAN_K_FOLD_CROSS_VALIDATION.out.objects
    versions = BIOC_AFFIXCAN_K_FOLD_CROSS_VALIDATION.out.versions
}
