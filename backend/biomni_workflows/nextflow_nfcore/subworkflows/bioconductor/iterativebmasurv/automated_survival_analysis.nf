#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: iterativeBMAsurv — automated_survival_analysis
// Perform gene selection, model training, risk prediction, and risk group assessment in a single automated function call.
// Input: trainData, trainSurv, trainCens, testData, testSurv, testCens
// Container: quay.io/biocontainers/bioconductor-iterativebmasurv:1.68.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: iterativeBMAsurv, survival
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run iterateBMAsurv.train.predict.assess to perform the entire pipeline
//  * 2. [Core Analysis] Extract statistics and evaluation metrics from the returned object

nextflow.enable.dsl = 2

process BIOC_ITERATIVEBMASURV_AUTOMATED_SURVIVAL_ANALYSIS {
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
    .bm_deps <- c("BMA", "iterativeBMAsurv", "survival")
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
    library(BMA)
    library(iterativeBMAsurv)
    library(survival)
    
    # Helper function to read matrix inputs (RDS or CSV)
    read_input_matrix <- function(base_name) {
      if (file.exists(paste0(base_name, ".rds"))) {
        return(as.matrix(readRDS(paste0(base_name, ".rds"))))
      } else if (file.exists(base_name)) {
        tryCatch({
          return(as.matrix(readRDS(base_name)))
        }, error = function(e) {
          df <- read.csv(base_name, row.names = 1, check.names = FALSE)
          return(as.matrix(df))
        })
      } else if (file.exists(paste0(base_name, ".csv"))) {
        df <- read.csv(paste0(base_name, ".csv"), row.names = 1, check.names = FALSE)
        return(as.matrix(df))
      } else {
        stop(paste("Required input file not found:", base_name))
      }
    }
    
    # Helper function to read vector inputs (RDS or CSV)
    read_input_vector <- function(base_name) {
      if (file.exists(paste0(base_name, ".rds"))) {
        val <- readRDS(paste0(base_name, ".rds"))
        if (is.list(val) || is.data.frame(val)) {
          return(as.vector(unlist(val)))
        }
        return(as.vector(val))
      } else if (file.exists(base_name)) {
        tryCatch({
          val <- readRDS(base_name)
          if (is.list(val) || is.data.frame(val)) return(as.vector(unlist(val)))
          return(as.vector(val))
        }, error = function(e) {
          return(as.numeric(readLines(base_name)))
        })
      } else if (file.exists(paste0(base_name, ".csv"))) {
        df <- read.csv(paste0(base_name, ".csv"), header = FALSE)
        return(as.vector(df[[1]]))
      } else {
        stop(paste("Required input file not found:", base_name))
      }
    }
    
    # Read user inputs from the working directory
    trainData <- read_input_matrix("trainData")
    trainSurv <- read_input_vector("trainSurv")
    trainCens <- read_input_vector("trainCens")
    testData  <- read_input_matrix("testData")
    testSurv  <- read_input_vector("testSurv")
    testCens  <- read_input_vector("testCens")
    
    # Run the automated survival analysis pipeline exactly as documented
    ret.bma <- iterateBMAsurv.train.predict.assess (
      train.dat=trainData, 
      test.dat=testData, 
      surv.time.train=trainSurv, 
      surv.time.test=testSurv, 
      cens.vec.train=trainCens, 
      cens.vec.test=testCens, 
      p=10, 
      nbest=5
    )
    
    # Extract statistics and evaluation metrics
    number.genes <- ret.bma\$nvar
    number.models <- ret.bma\$nmodel
    evaluate.success <- ret.bma\$statistics
    
    # Print the evaluation success to standard output
    print(evaluate.success)
    
    # Write named output files for the results
    # 1. Save the complete returned BMA object
    saveRDS(ret.bma, file = "bma_results.rds")
    
    # 2. Save predicted risk scores
    if (!is.null(ret.bma\$ypred)) {
      write.csv(data.frame(Sample = names(ret.bma\$ypred), RiskScore = ret.bma\$ypred), 
                file = "predicted_risk_scores.csv", row.names = FALSE)
    }
    
    # 3. Save risk group table
    if (!is.null(ret.bma\$result.table)) {
      write.csv(as.data.frame(ret.bma\$result.table), file = "risk_group_table.csv")
    }
    
    # 4. Save survival statistics summary as a text file
    sink("survival_statistics.txt")
    cat("=== BMA Survival Analysis Statistics ===\n\n")
    cat("Number of selected genes:", number.genes, "\n")
    cat("Number of selected models:", number.models, "\n")
    cat("Success status:", ret.bma\$success, "\n\n")
    if (!is.null(evaluate.success)) {
      print(evaluate.success)
    }
    sink()
    
    # 5. Save a summary CSV of key metrics
    p_val <- NA
    if (!is.null(evaluate.success)) {
      df <- length(evaluate.success\$n) - 1
      if (df > 0) {
        p_val <- 1 - pchisq(evaluate.success\$chisq, df)
      }
    }
    summary_df <- data.frame(
      Metric = c("Number_of_Genes", "Number_of_Models", "Success", "LogRank_Chisq", "LogRank_Pvalue"),
      Value = c(number.genes, number.models, as.character(ret.bma\$success), 
                if(!is.null(evaluate.success)) evaluate.success\$chisq else NA, 
                p_val)
    )
    write.csv(summary_df, file = "bma_summary.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_ITERATIVEBMASURV_AUTOMATED_SURVIVAL_ANALYSIS":',
        paste0('    iterativeBMAsurv: ', as.character(packageVersion('iterativeBMAsurv')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_automated_survival_analysis.csv versions.yml
    """
}

workflow BIOC_ITERATIVEBMASURV_AUTOMATED_SURVIVAL_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ trainData, trainSurv, trainCens, testData, testSurv, testCens ] ]

    main:
    BIOC_ITERATIVEBMASURV_AUTOMATED_SURVIVAL_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_ITERATIVEBMASURV_AUTOMATED_SURVIVAL_ANALYSIS.out.tables
    plots    = BIOC_ITERATIVEBMASURV_AUTOMATED_SURVIVAL_ANALYSIS.out.plots
    objects  = BIOC_ITERATIVEBMASURV_AUTOMATED_SURVIVAL_ANALYSIS.out.objects
    versions = BIOC_ITERATIVEBMASURV_AUTOMATED_SURVIVAL_ANALYSIS.out.versions
}
