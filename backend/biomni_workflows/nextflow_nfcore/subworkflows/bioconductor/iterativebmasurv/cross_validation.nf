#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: iterativeBMAsurv — cross_validation
// Perform k-run n-fold cross-validation on the training set to evaluate model performance and optimize parameters.
// Input: trainData, trainSurv, trainCens
// Container: quay.io/biocontainers/bioconductor-iterativebmasurv:1.68.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: iterativeBMAsurv
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Run crossVal with specified folds, runs, and parameters to evaluate the model and write results to files

nextflow.enable.dsl = 2

process BIOC_ITERATIVEBMASURV_CROSS_VALIDATION {
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
    .bm_deps <- c("BMA", "iterativeBMAsurv")
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
    library(BMA)
    library(iterativeBMAsurv)
    
    # Read user input files from the working directory
    # Supporting both RDS and CSV formats for robustness
    if (file.exists("trainData.rds")) {
      trainData <- readRDS("trainData.rds")
    } else if (file.exists("trainData.csv")) {
      trainData <- as.matrix(read.csv("trainData.csv", row.names = 1))
    } else {
      stop("Error: trainData (trainData.rds or trainData.csv) not found in the working directory.")
    }
    
    if (file.exists("trainSurv.rds")) {
      trainSurv <- readRDS("trainSurv.rds")
    } else if (file.exists("trainSurv.csv")) {
      trainSurv <- as.vector(read.csv("trainSurv.csv", header = FALSE)[[1]])
    } else {
      stop("Error: trainSurv (trainSurv.rds or trainSurv.csv) not found in the working directory.")
    }
    
    if (file.exists("trainCens.rds")) {
      trainCens <- readRDS("trainCens.rds")
    } else if (file.exists("trainCens.csv")) {
      trainCens <- as.vector(read.csv("trainCens.csv", header = FALSE)[[1]])
    } else {
      stop("Error: trainCens (trainCens.rds or trainCens.csv) not found in the working directory.")
    }
    
    # Run cross-validation using the exact documented function call and arguments
    cv <- crossVal (exset=trainData, survTime=trainSurv, censor=trainCens, diseaseType="DLBCL", noRuns=1, noFolds=2, p=10, nbest=5)
    
    # Save the returned cross-validation object
    saveRDS(cv, "cv_results.rds")

    writeLines(c(
        '"BIOC_ITERATIVEBMASURV_CROSS_VALIDATION":',
        paste0('    iterativeBMAsurv: ', as.character(packageVersion('iterativeBMAsurv')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cross_validation.csv versions.yml
    """
}

workflow BIOC_ITERATIVEBMASURV_CROSS_VALIDATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ trainData, trainSurv, trainCens ] ]

    main:
    BIOC_ITERATIVEBMASURV_CROSS_VALIDATION(ch_input)

    emit:
    tables   = BIOC_ITERATIVEBMASURV_CROSS_VALIDATION.out.tables
    plots    = BIOC_ITERATIVEBMASURV_CROSS_VALIDATION.out.plots
    objects  = BIOC_ITERATIVEBMASURV_CROSS_VALIDATION.out.objects
    versions = BIOC_ITERATIVEBMASURV_CROSS_VALIDATION.out.versions
}
