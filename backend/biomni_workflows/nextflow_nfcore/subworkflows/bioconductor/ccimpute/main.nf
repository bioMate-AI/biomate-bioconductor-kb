#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ccImpute — standard_imputation
// Perform dropout imputation on a log-normalized SingleCellExperiment object using the high-level ccImpute wrapper.
// Input: sce
// Container: quay.io/biocontainers/bioconductor-ccimpute:1.12.0--r45ha27e39d_0
// R packages: SingleCellExperiment, BiocParallel, ccImpute, mclust, rhpcblasctl, scRNAseq, scater, sessioninfo
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocParallel, SingleCellExperiment, ccImpute, mclust, scRNAseq, scater
// Visualizations: PCA plot
// QC: low-count filtering, missing-value handling, cell QC metrics, count normalization
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load required libraries
//  * 2. [Core Analysis] Filter bad cells and remove unexpressed genes
//  * 3. [Core Analysis] Recreate SingleCellExperiment and log-normalize counts
//  * 4. [Core Analysis] Run ccImpute with parallel processing parameters to generate the imputed assay

nextflow.enable.dsl = 2

process BIOC_CCIMPUTE_STANDARD_IMPUTATION {
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
    .bm_deps <- c("SingleCellExperiment", "BiocParallel", "ccImpute", "mclust", "rhpcblasctl", "scRNAseq", "scater", "sessioninfo", "SummarizedExperiment")
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
    
    # 1. Load required libraries
    library(scRNAseq)
    library(SummarizedExperiment)
    library(scater)
    library(ccImpute)
    library(stats)
    library(mclust)
    library(BiocParallel)
    
    # Load user input
    sce <- readRDS("sce.rds")
    
    # 2. Remove unexpressed genes
    # Extract labels robustly
    labels <- colData(sce)\$"Level 1"
    if (is.null(labels)) {
      if ("cell_id" %in% colnames(colData(sce))) {
        labels <- colData(sce)\$cell_id
      } else if (ncol(colData(sce)) > 0) {
        labels <- colData(sce)[, 1]
      } else {
        labels <- rep("CellType", ncol(sce))
      }
    }
    labels <- as.character(labels)
    
    # Extract X (CPM or counts) robustly
    X <- tryCatch({
      cpm(sce)
    }, error = function(e) {
      if ("counts" %in% assayNames(sce)) {
        scater::calculateCPM(sce)
      } else if ("logcounts" %in% assayNames(sce)) {
        exp(as.matrix(logcounts(sce))) - 1
      } else {
        as.matrix(counts(sce))
      }
    })
    
    # Remove genes that are not expressed in any cells:
    keep_genes <- rowSums(X) > 0
    X <- X[keep_genes, , drop = FALSE]
    sce <- sce[keep_genes, ]
    
    # 3. Update the SingleCellExperiment and add log-transformed data:
    colData(sce)\$cell_id <- labels
    assay(sce, "normcounts") <- as.matrix(X)
    logcounts(sce) <- log(assay(sce, "normcounts") + 1)
    
    # Compute PCA and ARI before imputation (as documented)
    set.seed(0)
    reducedDims(sce) <- list(PCA = prcomp(t(logcounts(sce)))\$x)
    k <- length(unique(colData(sce)\$cell_id))
    set.seed(0)
    assgmts <- kmeans(reducedDim(sce, "PCA"), centers = k, iter.max = 1e+09,
                      nstart = 1000)\$cluster
    ari_before <- adjustedRandIndex(assgmts, colData(sce)\$cell_id)
    
    # 4. Run ccImpute with parallel processing parameters to generate the imputed assay
    BPPARAM = MulticoreParam(2)
    sce <- ccImpute(sce, BPPARAM = BPPARAM)
    
    # Compute PCA and ARI after imputation (as documented)
    reducedDim(sce, "PCA_imputed") <- prcomp(t(assay(sce, "imputed")))\$x
    assgmts_imputed <- kmeans(reducedDim(sce, "PCA_imputed"), centers = k, 
                              iter.max = 1e+09, nstart = 1000)\$cluster
    ari_after <- adjustedRandIndex(assgmts_imputed, colData(sce)\$cell_id)
    
    # Save outputs
    # 1. Imputed SingleCellExperiment object
    saveRDS(sce, "sce_imputed.rds")
    
    # 2. Imputed expression matrix
    write.csv(as.matrix(assay(sce, "imputed")), "imputed_counts.csv", row.names = TRUE)
    
    # 3. ARI results
    ari_df <- data.frame(
      Stage = c("Before Imputation", "After Imputation"),
      ARI = c(ari_before, ari_after)
    )
    write.csv(ari_df, "ari_results.csv", row.names = FALSE)
    
    # 4. PCA plots
    pdf("pca_plots.pdf", width = 10, height = 5)
    par(mfrow = c(1, 2))
    pca_before <- reducedDim(sce, "PCA")
    plot(pca_before[, 1], pca_before[, 2], col = as.factor(colData(sce)\$cell_id),
         pch = 20, main = paste("Before Imputation (ARI =", round(ari_before, 3), ")"),
         xlab = "PC1", ylab = "PC2")
    pca_after <- reducedDim(sce, "PCA_imputed")
    plot(pca_after[, 1], pca_after[, 2], col = as.factor(colData(sce)\$cell_id),
         pch = 20, main = paste("After Imputation (ARI =", round(ari_after, 3), ")"),
         xlab = "PC1", ylab = "PC2")
    dev.off()

    writeLines(c(
        '"BIOC_CCIMPUTE_STANDARD_IMPUTATION":',
        paste0('    ccImpute: ', as.character(packageVersion('ccImpute')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_imputation.csv versions.yml
    """
}

workflow BIOC_CCIMPUTE_STANDARD_IMPUTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sce ] ]

    main:
    BIOC_CCIMPUTE_STANDARD_IMPUTATION(ch_input)

    emit:
    tables   = BIOC_CCIMPUTE_STANDARD_IMPUTATION.out.tables
    plots    = BIOC_CCIMPUTE_STANDARD_IMPUTATION.out.plots
    objects  = BIOC_CCIMPUTE_STANDARD_IMPUTATION.out.objects
    versions = BIOC_CCIMPUTE_STANDARD_IMPUTATION.out.versions
}
