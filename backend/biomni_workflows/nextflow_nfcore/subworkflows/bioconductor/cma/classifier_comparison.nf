#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CMA — classifier_comparison
// Compare multiple classification algorithms (specifically discriminant analysis variants) on the same dataset using cross-validation.
// Input: khanX, khanY
// Container: quay.io/biocontainers/bioconductor-cma:1.68.0--r45hdfd78af_0
// R packages: CMA
// Bioconductor: 3.20 | R: 4.4
// Requires: CMA
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Generate learning sets using GenerateLearningsets
//  * 2. [Core Analysis] Run classification for classifiers that do not require gene selection (e.g., DLDA, PLS-LDA) using classification
//  * 3. [Core Analysis] Perform gene selection using GeneSelection for classifiers that require it (e.g., LDA, FDA, QDA)
//  * 4. [Core Analysis] Run classification for those classifiers using classification with the selected genes
//  * 5. [Core Analysis] Run classification with hyperparameter tuning (e.g., scDA) using classification and tuninglist
//  * 6. [Core Analysis] Compare all classifiers using compare

nextflow.enable.dsl = 2

process BIOC_CMA_CLASSIFIER_COMPARISON {
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
    
    # Helper function to robustly read the user input files from the working directory
    read_input <- function(filename) {
      # 1. Try reading as RDS directly if file exists
      if (file.exists(filename)) {
        obj <- tryCatch(readRDS(filename), error = function(e) NULL)
        if (!is.null(obj)) return(obj)
        
        obj <- tryCatch(read.csv(filename, header = TRUE, row.names = 1), error = function(e) NULL)
        if (!is.null(obj)) return(obj)
      }
      
      # 2. Try with common extensions
      for (ext in c(".rds", ".RDS")) {
        if (file.exists(paste0(filename, ext))) {
          return(readRDS(paste0(filename, ext)))
        }
      }
      for (ext in c(".csv", ".CSV")) {
        if (file.exists(paste0(filename, ext))) {
          df <- read.csv(paste0(filename, ext))
          # If first column looks like row names (non-numeric/unique IDs), read with row.names = 1
          if (ncol(df) > 1 && is.character(df[[1]]) && length(unique(df[[1]])) == nrow(df)) {
            return(read.csv(paste0(filename, ext), row.names = 1))
          }
          return(df)
        }
      }
      for (ext in c(".txt", ".tsv", ".TXT", ".TSV")) {
        if (file.exists(paste0(filename, ext))) {
          return(read.table(paste0(filename, ext), header = TRUE))
        }
      }
      stop(paste("Required input file", filename, "not found in the working directory."))
    }
    
    # Read user inputs
    khanX_raw <- read_input("khanX")
    khanY_raw <- read_input("khanY")
    
    # Format khanX as a matrix (samples as rows, genes as columns)
    khanX <- as.matrix(khanX_raw)
    
    # Format khanY as a vector/factor of class labels
    if (is.data.frame(khanY_raw) || is.matrix(khanY_raw)) {
      if (ncol(khanY_raw) > 1) {
        khanY <- as.vector(khanY_raw[[1]])
      } else {
        khanY <- as.vector(unlist(khanY_raw))
      }
    } else {
      khanY <- as.vector(khanY_raw)
    }
    khanY <- as.factor(khanY)
    
    # --- Documented Workflow ---
    
    # 1. Generate learning sets
    set.seed(27611)
    fiveCV5iter <- GenerateLearningsets(y=khanY, method = "CV", fold = 5, niter = 5, strat = TRUE)
    
    # 2. Run classification for classifiers that do not require gene selection
    class_dlda <- classification(X = khanX, y=khanY, learningsets = fiveCV5iter,
                                 classifier = dldaCMA)
    
    # 3. Perform gene selection
    genesel_da <- GeneSelection(X=khanX, y=khanY, learningsets = fiveCV5iter,
                                method = "t.test", scheme = "one-vs-all")
    
    # 4. Run classification for classifiers requiring gene selection
    class_lda <- classification(X = khanX, y=khanY, learningsets = fiveCV5iter,
                                 classifier = ldaCMA, genesel= genesel_da,
                                 nbgene = 10)
                                 
    class_fda <- classification(X = khanX, y=khanY, learningsets = fiveCV5iter,
                                 classifier = fdaCMA, genesel = genesel_da,
                                 nbgene = 10, comp = 2)
                                 
    class_qda <- classification(X = khanX, y=khanY, learningsets = fiveCV5iter,
                                 classifier = qdaCMA, genesel = genesel_da,
                                 nbgene = 1)
    
    # 5. Run classification with hyperparameter tuning
    set.seed(876)
    class_scda <- classification(X = khanX, y=khanY, learningsets = fiveCV5iter,
                                 classifier = scdaCMA, tuninglist = list(grids = list()))
    
    class_plsda <- classification(X = khanX, y=khanY, learningsets = fiveCV5iter,
                                 classifier = pls_ldaCMA)
    
    # 6. Compare all classifiers
    dalike <- list(class_dlda, class_lda, class_fda, class_qda, class_scda, class_plsda)
    
    # Save comparison plot to PDF
    pdf("classifier_comparison_plots.pdf", width = 8, height = 11)
    par(mfrow = c(3,1))
    comparison <- compare(dalike, plot = TRUE, measure = c("misclassification", "brier score", "average probability"))
    dev.off()
    
    # Print comparison results to console
    print(comparison)
    
    # --- Save Outputs ---
    # Save comparison table as CSV
    write.csv(as.data.frame(comparison), "classifier_comparison_results.csv", row.names = TRUE)
    
    # Save R objects for downstream analysis
    saveRDS(comparison, "comparison_object.rds")
    saveRDS(dalike, "classification_results_list.rds")
    saveRDS(fiveCV5iter, "learningsets.rds")
    saveRDS(genesel_da, "genesel_da.rds")

    writeLines(c(
        '"BIOC_CMA_CLASSIFIER_COMPARISON":',
        paste0('    CMA: ', as.character(packageVersion('CMA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_classifier_comparison.csv versions.yml
    """
}

workflow BIOC_CMA_CLASSIFIER_COMPARISON_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ khanX, khanY ] ]

    main:
    BIOC_CMA_CLASSIFIER_COMPARISON(ch_input)

    emit:
    tables   = BIOC_CMA_CLASSIFIER_COMPARISON.out.tables
    plots    = BIOC_CMA_CLASSIFIER_COMPARISON.out.plots
    objects  = BIOC_CMA_CLASSIFIER_COMPARISON.out.objects
    versions = BIOC_CMA_CLASSIFIER_COMPARISON.out.versions
}
