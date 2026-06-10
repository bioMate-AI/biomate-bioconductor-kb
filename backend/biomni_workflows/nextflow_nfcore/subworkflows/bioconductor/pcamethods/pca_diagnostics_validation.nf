#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: pcaMethods — pca_diagnostics_validation
// Evaluate PCA model quality using Q2 cross-validation and estimate the optimal number of PCs.
// Input: metaboliteData, metaboliteDataComplete
// Container: quay.io/biocontainers/bioconductor-pcamethods:2.2.0--r45ha27e39d_0
// R packages: lattice, pcaMethods
// Bioconductor: 3.20 | R: 4.4
// Requires: lattice, pcaMethods
// Visualizations: bar plot, PCA plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Preprocess and center the data
//  * 2. [Core Analysis] Run PCA using PPCA and SVD-Impute
//  * 3. [Core Analysis] Calculate Q2 cross-validation scores
//  * 4. [Core Analysis] Estimate the optimal number of PCs using kEstimate

nextflow.enable.dsl = 2

process BIOC_PCAMETHODS_PCA_DIAGNOSTICS_VALIDATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    .bm_deps <- c("lattice", "pcaMethods")
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
    library(pcaMethods)
    library(lattice)
    
    # Function to robustly read input files from the working directory
    read_input_matrix <- function(base_name) {
      possible_files <- c(
        paste0(base_name, ".csv"),
        base_name,
        paste0(base_name, ".txt"),
        paste0(base_name, ".tsv")
      )
      for (f in possible_files) {
        if (file.exists(f)) {
          df <- read.csv(f, header = TRUE, row.names = 1, check.names = FALSE)
          return(as.matrix(df))
        }
      }
      stop(paste("Error: Could not find input file for", base_name))
    }
    
    # 1. Read user input files
    metaboliteData <- read_input_matrix("metaboliteData")
    metaboliteDataComplete <- read_input_matrix("metaboliteDataComplete")
    
    # 2. Preprocess and center the data
    md  <- prep(metaboliteData, scale="none", center=TRUE)
    mdC  <- prep(metaboliteDataComplete, scale="none", center=TRUE)
    
    # 3. Run PCA using PPCA and SVD-Impute
    resPPCA  <- pca(md, method="ppca", center=FALSE, nPcs=5)
    resSVDI  <- pca(md, method="svdImpute", center=FALSE, nPcs=5)
    
    # 4. Calculate Q2 cross-validation scores
    q2SVDI <- Q2(resSVDI, mdC, fold=10)
    q2PPCA <- Q2(resPPCA, mdC, fold=10)
    
    # Workaround for PPCA instability as documented in the vignette
    while( sum((abs(q2PPCA)) > 1) >= 1 ) {
        q2PPCA <- Q2(resPPCA, mdC, fold=10)
    }
    
    # 5. Estimate the optimal number of PCs using kEstimate
    errEsti <- kEstimate(md, method = "ppca", evalPcs=1:5, nruncv=1, em="nrmsep")
    
    # 6. Save meaningful results to files
    # Save Q2 scores to CSV
    q2_df <- data.frame(
      PC = 1:5,
      Q2_PPCA = drop(q2PPCA),
      Q2_SVDI = drop(q2SVDI)
    )
    write.csv(q2_df, "q2_validation_scores.csv", row.names = FALSE)
    
    # Save kEstimate summary to CSV
    kest_summary <- data.frame(
      PC = errEsti\$evalPcs,
      eError = drop(errEsti\$eError)
    )
    write.csv(kest_summary, "kestimate_error_summary.csv", row.names = FALSE)
    
    # Save full RDS objects for downstream analysis
    saveRDS(resPPCA, "pca_resPPCA.rds")
    saveRDS(resSVDI, "pca_resSVDI.rds")
    saveRDS(errEsti, "kestimate_full_results.rds")
    
    # Generate diagnostic plots
    pdf("pca_diagnostics_plots.pdf", width = 10, height = 5)
    
    # Plot 1: Q2 comparison
    q2_plot_data <- data.frame(
      Q2 = c(drop(q2PPCA), drop(q2SVDI)), 
      method = c("PPCA", "SVD-Impute")[gl(2, 5)], 
      PC = rep(1:5, 2)
    )
    print(xyplot(Q2 ~ PC | method, q2_plot_data, ylab = expression(Q^2), type = "h", lwd = 4, main = "Q2 Cross-Validation Scores"))
    
    # Plot 2: kEstimate Errors
    par(mfrow = c(1, 2))
    barplot(drop(errEsti\$eError), names.arg = errEsti\$evalPcs, xlab = "Number of PCs", ylab = "NRMSEP (Single iteration)", main = "Overall Error Estimation")
    barplot(drop(errEsti\$variableWiseError[, which(errEsti\$evalPcs == errEsti\$bestNPcs)]), xlab = "Incomplete variable Index", ylab = "NRMSEP", main = paste("Variable-wise Error (Best PC =", errEsti\$bestNPcs, ")"))
    
    dev.off()

    writeLines(c(
        '"BIOC_PCAMETHODS_PCA_DIAGNOSTICS_VALIDATION":',
        paste0('    pcaMethods: ', as.character(packageVersion('pcaMethods')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pca_diagnostics_validation.csv versions.yml
    """
}

workflow BIOC_PCAMETHODS_PCA_DIAGNOSTICS_VALIDATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ metaboliteData, metaboliteDataComplete ] ]

    main:
    BIOC_PCAMETHODS_PCA_DIAGNOSTICS_VALIDATION(ch_input)

    emit:
    tables   = BIOC_PCAMETHODS_PCA_DIAGNOSTICS_VALIDATION.out.tables
    plots    = BIOC_PCAMETHODS_PCA_DIAGNOSTICS_VALIDATION.out.plots
    objects  = BIOC_PCAMETHODS_PCA_DIAGNOSTICS_VALIDATION.out.objects
    versions = BIOC_PCAMETHODS_PCA_DIAGNOSTICS_VALIDATION.out.versions
}
