#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: pcaMethods — robust_pca_outliers
// Perform PCA on data containing extreme outliers using robust SVD or by setting outliers to NA and running PPCA.
// Input: metaboliteDataComplete
// Container: quay.io/biocontainers/bioconductor-pcamethods:2.2.0--r45ha27e39d_0
// R packages: pcaMethods
// Bioconductor: 3.20 | R: 4.4
// Requires: pcaMethods
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Pre-center the data
//  * 2. [Core Analysis] Run standard SVD PCA, robust PCA, and PPCA (with outliers set to NA) for comparison
//  * 3. [Core Analysis] Extract loadings to evaluate robustness

nextflow.enable.dsl = 2

process BIOC_PCAMETHODS_ROBUST_PCA_OUTLIERS {
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
    .bm_deps <- c("pcaMethods")
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
    
    # 1. Read the user input file
    # The pipeline expects 'metaboliteDataComplete' in the working directory.
    # We support both CSV and tab-delimited formats.
    if (file.exists("metaboliteDataComplete.csv")) {
      metaboliteDataComplete <- as.matrix(read.csv("metaboliteDataComplete.csv", row.names = 1, check.names = FALSE))
    } else if (file.exists("metaboliteDataComplete.tsv")) {
      metaboliteDataComplete <- as.matrix(read.delim("metaboliteDataComplete.tsv", row.names = 1, check.names = FALSE))
    } else if (file.exists("metaboliteDataComplete")) {
      metaboliteDataComplete <- as.matrix(read.table("metaboliteDataComplete", header = TRUE, row.names = 1, check.names = FALSE))
    } else {
      stop("Error: Input file 'metaboliteDataComplete' (CSV, TSV, or table format) not found in the working directory.")
    }
    
    # 2. Pre-center the data and introduce artificial outliers
    mdc          <- scale(metaboliteDataComplete, center=TRUE, scale=FALSE)
    cond         <- runif(length(mdc)) < 0.05
    mdcOut       <- mdc
    mdcOut[cond] <- 10
    
    # 3. Run standard SVD PCA, robust PCA, and PPCA (with outliers set to NA) for comparison
    resSvd       <- pca(mdc, method="svd", nPcs=5, center=FALSE)
    resSvdOut    <- pca(mdcOut, method="svd", nPcs=5, center=FALSE)
    resRobSvd    <- pca(mdcOut, method="robustPca", nPcs=5, center=FALSE)
    
    mdcNa        <- mdc
    mdcNa[cond]  <- NA
    resPPCA      <- pca(mdcNa, method="ppca", nPcs=5, center=FALSE)
    
    # 4. Save the PCA results as RDS objects
    saveRDS(resSvd, "resSvd.rds")
    saveRDS(resSvdOut, "resSvdOut.rds")
    saveRDS(resRobSvd, "resRobSvd.rds")
    saveRDS(resPPCA, "resPPCA.rds")
    
    # 5. Extract and save loadings to evaluate robustness
    write.csv(loadings(resSvd), "loadings_Svd.csv", row.names = TRUE)
    write.csv(loadings(resSvdOut), "loadings_SvdOut.csv", row.names = TRUE)
    write.csv(loadings(resRobSvd), "loadings_RobSvd.csv", row.names = TRUE)
    write.csv(loadings(resPPCA), "loadings_PPCA.csv", row.names = TRUE)
    
    # 6. Generate comparison plots and save as PDF
    pdf("outlier_comparison_plots.pdf", width = 10, height = 10)
    par(mfrow=c(2,2))
    plot(loadings(resSvd)[,1], loadings(resSvdOut)[,1], 
         xlab="Loading 1 SVD", ylab="Loading 1 SVD with outliers")
    plot(loadings(resSvd)[,1], loadings(resRobSvd)[,1],
         xlab="Loading 1 SVD", ylab="Loading 1 robustSVD with outliers")
    plot(loadings(resSvd)[,1], loadings(resPPCA)[,1],
         xlab="Loading 1 SVD", ylab="Loading 1 PPCA with outliers=NA")
    plot(loadings(resRobSvd)[,1], loadings(resPPCA)[,1],
         xlab="Loading 1 robust SVD with outliers", ylab="Loading 1 svdImpute with outliers=NA")
    dev.off()

    writeLines(c(
        '"BIOC_PCAMETHODS_ROBUST_PCA_OUTLIERS":',
        paste0('    pcaMethods: ', as.character(packageVersion('pcaMethods')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_robust_pca_outliers.csv versions.yml
    """
}

workflow BIOC_PCAMETHODS_ROBUST_PCA_OUTLIERS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ metaboliteDataComplete ] ]

    main:
    BIOC_PCAMETHODS_ROBUST_PCA_OUTLIERS(ch_input)

    emit:
    tables   = BIOC_PCAMETHODS_ROBUST_PCA_OUTLIERS.out.tables
    plots    = BIOC_PCAMETHODS_ROBUST_PCA_OUTLIERS.out.plots
    objects  = BIOC_PCAMETHODS_ROBUST_PCA_OUTLIERS.out.objects
    versions = BIOC_PCAMETHODS_ROBUST_PCA_OUTLIERS.out.versions
}
