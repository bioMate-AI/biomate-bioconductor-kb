#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: globaltest — goodness_of_fit_testing
// Test for non-linearity or missed interactions in a regression model using penalized splines.
// Input: kyphosis
// Container: quay.io/biocontainers/bioconductor-globaltest:5.64.0--r45hdfd78af_0
// R packages: globaltest, rpart
// Bioconductor: 3.20 | R: 4.4
// Requires: globaltest, rpart
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Fit a null generalized linear model
//  * 2. [Core Analysis] Test for non-linear effects of covariates using gtPS()
//  * 3. [Core Analysis] Extract the tested smooth terms using sterms()

nextflow.enable.dsl = 2

process BIOC_GLOBALTEST_GOODNESS_OF_FIT_TESTING {
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
    .bm_deps <- c("globaltest", "rpart")
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
    library(globaltest)
    library(rpart)
    
    # 1. Read the user input file
    # The pipeline expects 'kyphosis.csv' or 'kyphosis' in the working directory.
    if (file.exists("kyphosis.csv")) {
      kyphosis <- read.csv("kyphosis.csv")
    } else if (file.exists("kyphosis")) {
      kyphosis <- read.csv("kyphosis")
    } else {
      stop("Input file 'kyphosis.csv' or 'kyphosis' not found in the working directory.")
    }
    
    # Ensure Kyphosis is a factor if it was read as character
    if ("Kyphosis" %in% colnames(kyphosis) && is.character(kyphosis\$Kyphosis)) {
      kyphosis\$Kyphosis <- as.factor(kyphosis\$Kyphosis)
    }
    
    # 2. Fit a null generalized linear model
    fit0<-glm(Kyphosis~., data = kyphosis, family="binomial")
    
    # 3. Test for non-linear effects of covariates using gtPS()
    res<-gtPS(fit0)
    
    # 4. Extract the results and tested smooth terms
    res_result <- res@result
    smooth_terms <- sterms(res)
    
    # 5. Write meaningful outputs to files
    write.csv(res_result, "gtPS_results.csv", row.names = TRUE)
    write.table(smooth_terms, "smooth_terms.txt", row.names = FALSE, col.names = FALSE, quote = FALSE)
    saveRDS(res, "gtPS_object.rds")
    
    # Print summary to standard output
    cat("--- Goodness-of-Fit Test Results ---\n")
    print(res_result)
    cat("\n--- Tested Smooth Terms ---\n")
    print(smooth_terms)

    writeLines(c(
        '"BIOC_GLOBALTEST_GOODNESS_OF_FIT_TESTING":',
        paste0('    globaltest: ', as.character(packageVersion('globaltest')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_goodness_of_fit_testing.csv versions.yml
    """
}

workflow BIOC_GLOBALTEST_GOODNESS_OF_FIT_TESTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ kyphosis ] ]

    main:
    BIOC_GLOBALTEST_GOODNESS_OF_FIT_TESTING(ch_input)

    emit:
    tables   = BIOC_GLOBALTEST_GOODNESS_OF_FIT_TESTING.out.tables
    plots    = BIOC_GLOBALTEST_GOODNESS_OF_FIT_TESTING.out.plots
    objects  = BIOC_GLOBALTEST_GOODNESS_OF_FIT_TESTING.out.objects
    versions = BIOC_GLOBALTEST_GOODNESS_OF_FIT_TESTING.out.versions
}
