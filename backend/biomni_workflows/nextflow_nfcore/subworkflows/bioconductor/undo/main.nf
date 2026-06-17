#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: UNDO — unsupervised_tumor_stroma_deconvolution
// Deconvolute mixed tumor-stroma gene expression data to estimate the mixing matrix and pure expression profiles without prior knowledge.
// Input: mixed_expression.csv, true_mixing_matrix.csv, pure_expressions.csv
// Container: quay.io/biocontainers/bioconductor-undo:1.52.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: UNDO
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the mixed expression data and optional validation data
//  * 2. [Core Analysis] Run deconvolution using two_source_deconv() to estimate the mixing matrix and calculate validation metrics
//  * 3. [Core Analysis] Run two_source_deconv() with return=1 to extract the estimated pure expression profiles
//  * 4. [Visualization & Output] Plot the estimated expressions against measured pure expressions to validate the deconvolution

nextflow.enable.dsl = 2

process BIOC_UNDO_UNSUPERVISED_TUMOR_STROMA_DECONVOLUTION {
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
    .bm_deps <- c("UNDO")
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
    library(UNDO)
    
    # 1. Load the mixed expression data and optional validation data
    if (!file.exists("mixed_expression.csv")) {
      stop("Error: Required input file 'mixed_expression.csv' is missing.")
    }
    
    X_df <- read.csv("mixed_expression.csv", row.names = 1, check.names = FALSE)
    X <- as.matrix(X_df)
    
    # Load optional true mixing matrix
    if (file.exists("true_mixing_matrix.csv")) {
      A_df <- read.csv("true_mixing_matrix.csv", row.names = 1, check.names = FALSE)
      A <- as.matrix(A_df)
    }
    
    # Load optional pure expressions
    if (file.exists("pure_expressions.csv")) {
      S_df <- read.csv("pure_expressions.csv", row.names = 1, check.names = FALSE)
      S <- as.matrix(S_df)
    }
    
    # 2 & 3. Run deconvolution using two_source_deconv() with return=1 to estimate the mixing matrix, 
    # calculate validation metrics (if validation data exists), and extract the estimated pure expression profiles
    if (exists("A") && exists("S")) {
      result <- two_source_deconv(X, lowper=0.4, highper=0.1, epsilon1=0.01, epsilon2=0.01, A, S[,1], S[,2], return=1)
    } else if (exists("A") && !exists("S")) {
      result <- two_source_deconv(X, lowper=0.4, highper=0.1, epsilon1=0.01, epsilon2=0.01, A, return=1)
    } else if (!exists("A") && exists("S")) {
      result <- two_source_deconv(X, lowper=0.4, highper=0.1, epsilon1=0.01, epsilon2=0.01, NULL, S[,1], S[,2], return=1)
    } else {
      result <- two_source_deconv(X, lowper=0.4, highper=0.1, epsilon1=0.01, epsilon2=0.01, return=1)
    }
    
    # The estimated pure expressions are appended as the last element of the result list when return=1
    Sest <- result[[length(result)]]
    
    # Save results to files
    write.csv(result[[1]], "estimated_mixing_matrix.csv", row.names = TRUE)
    write.csv(Sest, "estimated_pure_expressions.csv", row.names = TRUE)
    saveRDS(result, "deconvolution_results.rds")
    
    # 4. Plot the estimated expressions against measured pure expressions to validate the deconvolution (if pure expressions are provided)
    if (exists("S")) {
      pdf("deconvolution_plots.pdf", width = 10, height = 5)
      par(mfrow = c(1, 2))
      
      # Determine dynamic titles based on column names, or fallback to generic names
      title1 <- if (!is.null(colnames(S)[1])) colnames(S)[1] else "Source 1"
      title2 <- if (!is.null(colnames(S)[2])) colnames(S)[2] else "Source 2"
      
      # Determine dynamic axis limits based on the data range
      lims1 <- range(c(S[,1], Sest[,1]), na.rm = TRUE)
      lims2 <- range(c(S[,2], Sest[,2]), na.rm = TRUE)
      
      plot(S[,1], Sest[,1], main=title1, xlab="Estimated expression", 
      ylab="Measured expression", xlim=lims1, ylim=lims1,
      pch=1, col="turquoise", cex=0.5)
      
      plot(S[,2], Sest[,2], main=title2, xlab="Estimated expression", 
      ylab="Measured expression", xlim=lims2, ylim=lims2,
      pch=1, col="turquoise", cex=0.5)
      
      dev.off()
    }

    writeLines(c(
        '"BIOC_UNDO_UNSUPERVISED_TUMOR_STROMA_DECONVOLUTION":',
        paste0('    UNDO: ', as.character(packageVersion('UNDO')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_unsupervised_tumor_stroma_deconvolution.csv versions.yml
    """
}

workflow BIOC_UNDO_UNSUPERVISED_TUMOR_STROMA_DECONVOLUTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ mixed_expression.csv, true_mixing_matrix.csv, pure_expressions.csv ] ]

    main:
    BIOC_UNDO_UNSUPERVISED_TUMOR_STROMA_DECONVOLUTION(ch_input)

    emit:
    tables   = BIOC_UNDO_UNSUPERVISED_TUMOR_STROMA_DECONVOLUTION.out.tables
    plots    = BIOC_UNDO_UNSUPERVISED_TUMOR_STROMA_DECONVOLUTION.out.plots
    objects  = BIOC_UNDO_UNSUPERVISED_TUMOR_STROMA_DECONVOLUTION.out.objects
    versions = BIOC_UNDO_UNSUPERVISED_TUMOR_STROMA_DECONVOLUTION.out.versions
}
