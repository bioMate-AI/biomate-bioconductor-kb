#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CMA — single_classifier_pipeline
// Run a complete classification pipeline for a single classifier including learning set generation, gene selection, hyperparameter tuning, classification, and det
// Input: golubX, golubY
// Container: quay.io/biocontainers/bioconductor-cma:1.68.0--r45hdfd78af_0
// R packages: CMA
// Bioconductor: 3.20 | R: 4.4
// Requires: CMA
// Visualizations: box plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Generate learning sets using GenerateLearningsets
//  * 2. [Core Analysis] Perform gene selection using GeneSelection
//  * 3. [Core Analysis] Tune hyperparameters using CMA:::tune
//  * 4. [Core Analysis] Run classification using classification
//  * 5. [Core Analysis] Join results and evaluate performance using join, evaluation, ftable, roc, and obsinfo

nextflow.enable.dsl = 2

process BIOC_CMA_SINGLE_CLASSIFIER_PIPELINE {
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
    .bm_deps <- c("CMA")
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
    
    # Load required library
    library(CMA)
    
    # ==========================================
    # 1. READ USER INPUT FILES
    # ==========================================
    # The pipeline reads golubX and golubY from the working directory.
    # It supports RDS, CSV, TSV, or plain text formats.
    find_and_read <- function(base_name) {
      extensions <- c("", ".rds", ".csv", ".tsv", ".txt")
      for (ext in extensions) {
        file_path <- paste0(base_name, ext)
        if (file.exists(file_path)) {
          message("Reading ", file_path)
          if (grepl("\\\\.rds\$", file_path, ignore.case = TRUE)) {
            return(readRDS(file_path))
          } else if (grepl("\\\\.csv\$", file_path, ignore.case = TRUE)) {
            df <- tryCatch({
              read.csv(file_path, row.names = 1, check.names = FALSE)
            }, error = function(e) {
              read.csv(file_path, check.names = FALSE)
            })
            return(df)
          } else if (grepl("\\\\.tsv\$|\\\\.txt\$", file_path, ignore.case = TRUE) || ext == "") {
            df <- tryCatch({
              read.table(file_path, header = TRUE, row.names = 1, sep = "\t", check.names = FALSE)
            }, error = function(e) {
              tryCatch({
                read.table(file_path, header = TRUE, sep = "\t", check.names = FALSE)
              }, error = function(e2) {
                read.table(file_path, check.names = FALSE)
              })
            })
            return(df)
          }
        }
      }
      stop(paste("Required file", base_name, "not found in the working directory."))
    }
    
    golubX_raw <- find_and_read("golubX")
    golubY_raw <- find_and_read("golubY")
    
    # Format inputs appropriately
    golubX <- as.matrix(golubX_raw)
    
    if (is.data.frame(golubY_raw) || is.matrix(golubY_raw)) {
      golubY <- golubY_raw[[1]]
    } else {
      golubY <- golubY_raw
    }
    
    golubY <- as.vector(golubY)
    if (is.character(golubY)) {
      golubY <- as.factor(golubY)
    }
    
    # ==========================================
    # 2. GENERATE LEARNING SETS
    # ==========================================
    loodat <- GenerateLearningsets(y=golubY, method ="LOOCV")
    class(loodat)
    getSlots(class(loodat))
    show(loodat)
    
    set.seed(321)
    fiveCVdat <- GenerateLearningsets(y=golubY, method = "CV", fold = 5, strat = TRUE)
    
    set.seed(456)
    MCCVdat <- GenerateLearningsets(y=golubY, method = "MCCV", niter = 3,
                                    ntrain = floor(2/3*length(golubY)), strat = TRUE)
    
    set.seed(651)
    bootdat <- GenerateLearningsets(y=golubY, method = "bootstrap", niter = 3, strat = TRUE)
    
    # ==========================================
    # 3. PERFORM GENE SELECTION
    # ==========================================
    varsel_fiveCV <- GeneSelection(X = golubX, y=golubY, learningsets = fiveCVdat, method = "wilcox.test")
    varsel_MCCV <- GeneSelection(X = golubX, y=golubY, learningsets = MCCVdat, method = "wilcox.test")
    varsel_boot <- GeneSelection(X = golubX, y=golubY, learningsets = bootdat, method = "wilcox.test")
    
    show(varsel_fiveCV)
    toplist(varsel_fiveCV, iter=1)
    seliter <- numeric()
    for(i in 1:5) {
      seliter <- c(seliter, toplist(varsel_fiveCV, iter = i, top = 10, show = FALSE)\$index)
    }
    sorted_seliter <- sort(table(seliter), dec = TRUE)
    print(sorted_seliter)
    
    # Save gene selection results
    write.csv(as.data.frame(sorted_seliter), "top_genes_fiveCV.csv", row.names = TRUE)
    
    # ==========================================
    # 4. HYPERPARAMETER TUNING
    # ==========================================
    set.seed(351) 
    tuningstep <- CMA:::tune(X = golubX, y=golubY, learningsets = fiveCVdat,
                          genesel = varsel_fiveCV, nbgene = 100, classifier = svmCMA,
                          grids = list(cost = c(0.1, 1, 10, 100, 200)),probability=T)
    
    show(tuningstep)
    best_params <- unlist(best(tuningstep))
    print(best_params)
    
    # Save tuning parameters
    writeLines(capture.output(print(best_params)), "best_tuning_params.txt")
    
    # Plot and save tuning results
    pdf("tuning_plots.pdf", width = 8, height = 8)
    par(mfrow = c(2,2))
    for(i in 1:4) {
      plot(tuningstep, iter = i, main = paste("iteration", i))
    }
    dev.off()
    
    # ==========================================
    # 5. CLASSIFICATION
    # ==========================================
    class_fiveCV <- classification(X = golubX, y=golubY, learningsets = fiveCVdat,
                          genesel = varsel_fiveCV, nbgene = 100, classifier = svmCMA,
                          cost = 0.1,probability=T)
                          
    class_MCCV <- classification(X = golubX, y=golubY, learningsets = MCCVdat,
                          genesel = varsel_MCCV, nbgene = 100, classifier = svmCMA,
                          cost = 0.1,probability=T)
                          
    class_boot <- classification(X = golubX, y=golubY, learningsets = bootdat,
                          genesel = varsel_boot, nbgene = 0.1, classifier = svmCMA,
                          cost = 100,probability=T)
    
    # ==========================================
    # 6. JOIN RESULTS AND EVALUATION
    # ==========================================
    resultlist <- list(class_fiveCV, class_MCCV, class_boot)
    result <- lapply(resultlist, join)
    
    schemes <- c("five-fold CV", "MCCV", "bootstrap")
    
    # Plot and save voting/probability plots
    pdf("voting_plots.pdf", width = 8, height = 10)
    par(mfrow = c(3,1))
    for(i in seq(along = result)) {
      plot(result[[i]], main = schemes[i])
    }
    dev.off()
    
    # Print and save confusion matrices
    invisible(lapply(result, ftable))
    
    # Plot and save ROC curves
    pdf("roc_curves.pdf", width = 8, height = 8)
    par(mfrow = c(2,2))
    for(i in seq(along = result)) {
      roc(result[[i]])
    }
    dev.off()
    
    totalresult <- join(result)
    total_ftable <- ftable(totalresult)
    print(total_ftable)
    
    # Save confusion matrices to text file
    sink("confusion_matrices.txt")
    cat("=== Individual Confusion Matrices ===\n")
    for (i in seq_along(result)) {
      cat("\nScheme:", schemes[i], "\n")
      print(ftable(result[[i]]))
    }
    cat("\n=== Total Confusion Matrix ===\n")
    print(total_ftable)
    sink()
    
    # Detailed evaluation for MCCV
    av_MCCV <- evaluation(class_MCCV, measure = "average probability")
    show(av_MCCV)
    
    pdf("evaluation_boxplot.pdf", width = 6, height = 6)
    boxplot(av_MCCV)
    dev.off()
    
    mccv_summary <- summary(av_MCCV)
    print(mccv_summary)
    
    av_obs_MCCV <- evaluation(class_MCCV, measure = "average probability", scheme = "obs")
    show(av_obs_MCCV)
    
    mccv_obs_info <- obsinfo(av_obs_MCCV, threshold = 0.6)
    print(mccv_obs_info)
    
    # Save evaluation summaries and observation info
    sink("evaluation_summary.txt")
    cat("=== Average Probability Evaluation (MCCV) ===\n")
    print(mccv_summary)
    cat("\n=== Observation-wise Average Probability (MCCV) ===\n")
    print(av_obs_MCCV)
    cat("\n=== Observations with average probability < 0.6 ===\n")
    print(mccv_obs_info)
    sink()
    
    write.csv(as.data.frame(mccv_obs_info), "obs_info_MCCV.csv", row.names = TRUE)
    
    # Save final classification results as RDS
    saveRDS(result, "classification_results.rds")
    
    message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_CMA_SINGLE_CLASSIFIER_PIPELINE":',
        paste0('    CMA: ', as.character(packageVersion('CMA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_classifier_pipeline.csv versions.yml
    """
}

workflow BIOC_CMA_SINGLE_CLASSIFIER_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ golubX, golubY ] ]

    main:
    BIOC_CMA_SINGLE_CLASSIFIER_PIPELINE(ch_input)

    emit:
    tables   = BIOC_CMA_SINGLE_CLASSIFIER_PIPELINE.out.tables
    plots    = BIOC_CMA_SINGLE_CLASSIFIER_PIPELINE.out.plots
    objects  = BIOC_CMA_SINGLE_CLASSIFIER_PIPELINE.out.objects
    versions = BIOC_CMA_SINGLE_CLASSIFIER_PIPELINE.out.versions
}
