#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mbkmeans — bluster_mbkmeans_clustering
// Cluster single-cell data using the bluster framework's clusterRows function with MbkmeansParam.
// Input: pca_matrix.rds, sce_object.rds
// Container: quay.io/biocontainers/bioconductor-mbkmeans:1.26.0--r45ha27e39d_0
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
    
    # Load required libraries
    library(SingleCellExperiment)
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
