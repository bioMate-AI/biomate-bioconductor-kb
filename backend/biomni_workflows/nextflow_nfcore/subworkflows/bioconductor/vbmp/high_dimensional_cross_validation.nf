#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: vbmp — high_dimensional_cross_validation
// Perform cross-validation on high-dimensional gene expression data using a linear inner product kernel without covariance parameter estimation.
// Input: brca.x, brca.y
// Container: quay.io/biocontainers/bioconductor-vbmp:1.78.0--r45hdfd78af_0
// R packages: vbmp
// Bioconductor: 3.20 | R: 4.4
// Requires: vbmp
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define a cross-validation prediction function wrapping vbmp with linear inner product kernel and fixed theta
//  * 2. [Core Analysis] Partition data into cross-validation folds
//  * 3. [Core Analysis] Iterate through folds to predict class labels using predClass
//  * 4. [Core Analysis] Calculate the cross-validated error rate

nextflow.enable.dsl = 2

process BIOC_VBMP_HIGH_DIMENSIONAL_CROSS_VALIDATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("vbmp")
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
    library(vbmp)
    
    # Helper function to robustly load user input files
    load_data <- function(name) {
      possible_files <- c(
        name,
        paste0(name, ".rds"),
        paste0(name, ".csv"),
        paste0(name, ".tsv"),
        paste0(name, ".txt")
      )
      for (f in possible_files) {
        if (file.exists(f)) {
          # Try RDS
          if (grepl("\\\\.rds\$", f, ignore.case = TRUE) || f == name) {
            res <- tryCatch(readRDS(f), error = function(e) NULL)
            if (!is.null(res)) return(res)
          }
          # Try CSV
          if (grepl("\\\\.csv\$", f, ignore.case = TRUE) || f == name) {
            res <- tryCatch(read.csv(f, header = TRUE, row.names = 1), error = function(e) NULL)
            if (!is.null(res)) return(as.matrix(res))
            res <- tryCatch(read.csv(f, header = TRUE), error = function(e) NULL)
            if (!is.null(res)) return(as.matrix(res))
          }
          # Try TSV/TXT
          if (grepl("\\\\.(tsv|txt)\$", f, ignore.case = TRUE) || f == name) {
            res <- tryCatch(read.delim(f, header = TRUE, row.names = 1), error = function(e) NULL)
            if (!is.null(res)) return(as.matrix(res))
            res <- tryCatch(read.delim(f, header = TRUE), error = function(e) NULL)
            if (!is.null(res)) return(as.matrix(res))
          }
        }
      }
      stop(paste("Error: Could not find or read", name))
    }
    
    # 1. Read the declared USER INPUT files
    brca.x <- load_data("brca.x")
    brca.y <- load_data("brca.y")
    
    # Ensure correct data types
    brca.x <- as.matrix(brca.x)
    if (is.data.frame(brca.y) || is.matrix(brca.y)) {
      brca.y <- as.vector(as.matrix(brca.y))
    }
    
    # 2. Define the cross-validation prediction function wrapping vbmp
    predictVBMP <- function(x) {
        sKernelType <- "iprod";  
        Thresh      <- 1e-8; 
        theta       <- rep(1.0, ncol(brca.x));
        max.train.iter <- 24;
        resX <- vbmp( brca.x[!x,], brca.y[!x], 
                      brca.x[ x,], brca.y[ x], 
                      theta,  control=list(bThetaEstimate=F, 
                      bPlotFitting=F, maxIts=max.train.iter, 
                      sKernelType=sKernelType, Thresh=Thresh));      
        predClass(resX);
    }
    
    # 3. Partition data into cross-validation folds
    n     <- nrow(brca.x);
    Kfold <- n; # number of folds , if equal to n then LOO
    set.seed(123) # Set seed for reproducible fold sampling
    samps <- sample(rep(1:Kfold, length=n), n, replace=FALSE); 
    res   <- rep(NA, n);
    
    # 4. Iterate through folds to predict class labels
    print(paste("Crossvalidation started...... (",n,"steps )"));
    for (x in 1:Kfold) {
        cat(paste(x,", ",ifelse(x%%10==0,"\n",""),sep="")); 
        flush.console();
        res[samps==x] <- predictVBMP(samps==x); 
    }
    cat("\n")
    
    # 5. Calculate the cross-validated error rate
    CVerrorRate <- round(sum(res!=brca.y)/n,2);
    
    # 6. Write named output files for the meaningful results
    results_df <- data.frame(
      Sample_Index = 1:n,
      True_Class = brca.y,
      Predicted_Class = res,
      Correct = (res == brca.y)
    )
    write.csv(results_df, "cv_predictions.csv", row.names = FALSE)
    
    summary_df <- data.frame(
      Metric = c("Total_Samples", "Errors", "CV_Error_Rate"),
      Value = c(n, sum(res != brca.y), CVerrorRate)
    )
    write.csv(summary_df, "cv_summary.csv", row.names = FALSE)
    
    print(paste("Cross-validation complete. CV Error Rate:", CVerrorRate))

    writeLines(c(
        '"BIOC_VBMP_HIGH_DIMENSIONAL_CROSS_VALIDATION":',
        paste0('    vbmp: ', as.character(packageVersion('vbmp')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_high_dimensional_cross_validation.csv versions.yml
    """
}

workflow BIOC_VBMP_HIGH_DIMENSIONAL_CROSS_VALIDATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ brca.x, brca.y ] ]

    main:
    BIOC_VBMP_HIGH_DIMENSIONAL_CROSS_VALIDATION(ch_input)

    emit:
    tables   = BIOC_VBMP_HIGH_DIMENSIONAL_CROSS_VALIDATION.out.tables
    plots    = BIOC_VBMP_HIGH_DIMENSIONAL_CROSS_VALIDATION.out.plots
    objects  = BIOC_VBMP_HIGH_DIMENSIONAL_CROSS_VALIDATION.out.objects
    versions = BIOC_VBMP_HIGH_DIMENSIONAL_CROSS_VALIDATION.out.versions
}
