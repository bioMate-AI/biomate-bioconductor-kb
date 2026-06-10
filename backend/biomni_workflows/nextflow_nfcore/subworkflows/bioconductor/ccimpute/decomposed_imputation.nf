#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ccImpute — decomposed_imputation
// Perform dropout imputation step-by-step using decomposed functions for finer control over distance calculation, SVD, clustering, and imputation.
// Input: sce
// Container: quay.io/biocontainers/bioconductor-ccimpute:1.12.0--r45ha27e39d_0
// R packages: BiocParallel, SingleCellExperiment, ccImpute
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocParallel, SingleCellExperiment, ccImpute
// Visualizations: plot (ggplot/base)
// QC: missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Calculate gene variances using rowVars_fast
//  * 2. [Core Analysis] Compute the cell correlation matrix using getCorM
//  * 3. [Core Analysis] Perform Singular Value Decomposition (SVD) using doSVD
//  * 4. [Core Analysis] Run consensus k-means clustering using runKM
//  * 5. [Core Analysis] Identify dropout events using findDropouts
//  * 6. [Core Analysis] Impute dropouts using computeDropouts and store the result in the "imputed" assay

nextflow.enable.dsl = 2

process BIOC_CCIMPUTE_DECOMPOSED_IMPUTATION {
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
    .bm_deps <- c("BiocParallel", "SingleCellExperiment", "ccImpute")
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
    library(ccImpute)
    library(BiocParallel)
    
    # 1. Read the input SingleCellExperiment object from the working directory
    if (file.exists("sce")) {
      sce <- readRDS("sce")
    } else if (file.exists("sce.rds")) {
      sce <- readRDS("sce.rds")
    } else {
      stop("Error: Input file 'sce' or 'sce.rds' not found in the working directory.")
    }
    
    # Ensure logcounts assay is present
    if (!"logcounts" %in% assayNames(sce)) {
      stop("Error: The input SingleCellExperiment object must contain a 'logcounts' assay.")
    }
    
    # Extract log-normalized expression matrix
    logX <- logcounts(sce)
    
    # Determine number of clusters (k) and kmNStart
    if ("cell_id" %in% colnames(colData(sce))) {
      k <- length(unique(colData(sce)\$cell_id))
    } else if ("celltype" %in% colnames(colData(sce))) {
      k <- length(unique(colData(sce)\$celltype))
    } else {
      # Fallback default if no cell labels are present
      k <- 4
    }
    
    # Set kmNStart based on cell count as recommended
    kmNStart <- if (ncol(sce) <= 2000) 1000 else 50
    
    # 2. Execute the decomposed imputation workflow exactly as documented
    cores <- 2
    BPPARAM = MulticoreParam(cores)
    register(BPPARAM) # Ensure bpparam() inside runKM uses this configuration
    
    w <- rowVars_fast(logcounts(sce), cores)
    corMat <- getCorM("spearman", logcounts(sce), w, cores)
    
    v <- doSVD(corMat, svdMaxRatio=.08, nCeil=2000, nCores=cores)
    
    consMtx <- runKM(logX, v, maxSets = 8, k, consMin=0.75, kmNStart, kmMax=1000,
                        BPPARAM=bpparam())
    
    dropIds <- findDropouts(logX, consMtx)
    
    iLogX <- computeDropouts(consMtx, logX, dropIds,
                                fastSolver=TRUE, nCores=cores)
    assay(sce, "imputed") <- iLogX
    
    # 3. Save the results
    # Save the updated SingleCellExperiment object
    saveRDS(sce, "sce_imputed.rds")
    
    # Save the imputed logcounts matrix as a CSV
    write.csv(as.matrix(iLogX), "imputed_logcounts.csv", row.names = TRUE)
    
    # Generate a diagnostic plot comparing pre- and post-imputation gene expression means
    pdf("imputation_summary.pdf", width = 8, height = 6)
    mean_original <- rowMeans(logX)
    mean_imputed <- rowMeans(iLogX)
    plot(mean_original, mean_imputed, 
         pch = 16, col = rgb(0, 0, 1, 0.2),
         xlab = "Mean Log-expression (Original)", 
         ylab = "Mean Log-expression (Imputed)",
         main = "Gene Expression Means: Original vs Imputed")
    abline(0, 1, col = "red", lty = 2)
    dev.off()

    writeLines(c(
        '"BIOC_CCIMPUTE_DECOMPOSED_IMPUTATION":',
        paste0('    ccImpute: ', as.character(packageVersion('ccImpute')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_decomposed_imputation.csv versions.yml
    """
}

workflow BIOC_CCIMPUTE_DECOMPOSED_IMPUTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sce ] ]

    main:
    BIOC_CCIMPUTE_DECOMPOSED_IMPUTATION(ch_input)

    emit:
    tables   = BIOC_CCIMPUTE_DECOMPOSED_IMPUTATION.out.tables
    plots    = BIOC_CCIMPUTE_DECOMPOSED_IMPUTATION.out.plots
    objects  = BIOC_CCIMPUTE_DECOMPOSED_IMPUTATION.out.objects
    versions = BIOC_CCIMPUTE_DECOMPOSED_IMPUTATION.out.versions
}
