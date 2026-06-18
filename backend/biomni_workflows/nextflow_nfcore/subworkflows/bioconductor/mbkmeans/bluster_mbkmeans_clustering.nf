#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mbkmeans — bluster_mbkmeans_clustering
// Cluster single-cell data using the bluster framework's clusterRows function with MbkmeansParam.
// Input: pca_matrix.rds, sce_object.rds
// Container: quay.io/biocontainers/bioconductor-mbkmeans:1.26.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, bluster, mbkmeans
// Visualizations: cluster plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run clusterRows on PCA coordinates with default MbkmeansParam
//  * 2. [Core Analysis] Run clusterRows on PCA coordinates with custom batch size
//  * 3. [Visualization & Output] Run clusterRows on PCA coordinates returning full mbkmeans output
//  * 4. [Core Analysis] Run clusterRows on transposed logcounts assay

nextflow.enable.dsl = 2

process BIOC_MBKMEANS_BLUSTER_MBKMEANS_CLUSTERING {
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
    .bm_deps <- c("mbkmeans", "bluster")
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
    library(mbkmeans)
    library(bluster)
    
    # -----------------------------------------------------------------------------
    # Stage 0: Read User Input Files
    # -----------------------------------------------------------------------------
    if (!file.exists("pca_matrix.rds") || !file.exists("sce_object.rds")) {
      stop("Required input files 'pca_matrix.rds' and/or 'sce_object.rds' are missing in the working directory.")
    }
    
    # Load PCA matrix (cells in rows, PCs in columns)
    mat <- readRDS("pca_matrix.rds")
    
    # Load SingleCellExperiment object containing logcounts assay
    sce1000 <- readRDS("sce_object.rds")
    
    # -----------------------------------------------------------------------------
    # Stage 1: Run clusterRows on PCA coordinates with default MbkmeansParam
    # -----------------------------------------------------------------------------
    res1 <- clusterRows(mat, MbkmeansParam(centers=5))
    
    # -----------------------------------------------------------------------------
    # Stage 2: Run clusterRows on PCA coordinates with custom batch size
    # -----------------------------------------------------------------------------
    res2 <- clusterRows(mat, MbkmeansParam(centers=5, batch_size=10))
    
    # -----------------------------------------------------------------------------
    # Stage 3: Run clusterRows on PCA coordinates returning full mbkmeans output
    # -----------------------------------------------------------------------------
    res3 <- clusterRows(mat, MbkmeansParam(centers=5, batch_size=10), full = TRUE)
    
    # -----------------------------------------------------------------------------
    # Stage 4: Run clusterRows on transposed logcounts assay
    # -----------------------------------------------------------------------------
    res4 <- clusterRows(t(logcounts(sce1000)), MbkmeansParam(centers=4))
    
    # -----------------------------------------------------------------------------
    # Stage 5: Write Named Output Files
    # -----------------------------------------------------------------------------
    
    # Save cluster assignments as CSV tables
    write.csv(
      data.frame(Cell = rownames(mat), Cluster = as.vector(res1)),
      file = "cluster_assignments_default.csv",
      row.names = FALSE
    )
    
    write.csv(
      data.frame(Cell = rownames(mat), Cluster = as.vector(res2)),
      file = "cluster_assignments_batch10.csv",
      row.names = FALSE
    )
    
    write.csv(
      data.frame(Cell = colnames(sce1000), Cluster = as.vector(res4)),
      file = "cluster_assignments_logcounts.csv",
      row.names = FALSE
    )
    
    # Save the full mbkmeans output object (from Stage 3)
    saveRDS(res3, file = "full_mbkmeans_output.rds")
    
    # Generate a PDF plot comparing the clustering results on the first two PCs
    pdf("clustering_comparison_plots.pdf", width = 12, height = 4)
    par(mfrow = c(1, 3))
    
    # Plot 1: Default Mbkmeans (k=5)
    plot(
      mat[, 1], mat[, 2],
      col = as.factor(res1),
      pch = 16,
      main = "Default Mbkmeans (k=5)",
      xlab = "PC1",
      ylab = "PC2"
    )
    
    # Plot 2: Batch Size 10 (k=5)
    plot(
      mat[, 1], mat[, 2],
      col = as.factor(res2),
      pch = 16,
      main = "Batch Size 10 (k=5)",
      xlab = "PC1",
      ylab = "PC2"
    )
    
    # Plot 3: Full Mbkmeans Output Clusters (k=5)
    plot(
      mat[, 1], mat[, 2],
      col = as.factor(res3\$clusters),
      pch = 16,
      main = "Full Output Clusters (k=5)",
      xlab = "PC1",
      ylab = "PC2"
    )
    
    dev.off()
    
    message("Pipeline completed successfully. Outputs written to working directory.")

    writeLines(c(
        '"BIOC_MBKMEANS_BLUSTER_MBKMEANS_CLUSTERING":',
        paste0('    mbkmeans: ', as.character(packageVersion('mbkmeans')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bluster_mbkmeans_clustering.csv versions.yml
    """
}

workflow BIOC_MBKMEANS_BLUSTER_MBKMEANS_CLUSTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pca_matrix.rds, sce_object.rds ] ]

    main:
    BIOC_MBKMEANS_BLUSTER_MBKMEANS_CLUSTERING(ch_input)

    emit:
    tables   = BIOC_MBKMEANS_BLUSTER_MBKMEANS_CLUSTERING.out.tables
    plots    = BIOC_MBKMEANS_BLUSTER_MBKMEANS_CLUSTERING.out.plots
    objects  = BIOC_MBKMEANS_BLUSTER_MBKMEANS_CLUSTERING.out.objects
    versions = BIOC_MBKMEANS_BLUSTER_MBKMEANS_CLUSTERING.out.versions
}
