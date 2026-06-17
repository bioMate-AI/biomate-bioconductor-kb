#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scran — quick_clustering_and_normalization
// Perform quick clustering to assist in cluster-based normalization factor calculation and subsequent subclustering.
// Input: sce.ready
// Container: quay.io/biocontainers/bioconductor-scran:1.38.0--r45ha27e39d_0
// R packages: SingleCellExperiment, bluster, knitr, pheatmap, scater, scran, scRNAseq, scuttle
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, scran, scuttle
// QC: clustering QC
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Generate quick-and-dirty clusters using quickCluster()
//  * 2. [Core Analysis] Compute size factors within clusters using computeSumFactors()
//  * 3. [Core Analysis] Perform subclustering within identified clusters using quickSubCluster()

nextflow.enable.dsl = 2

process BIOC_SCRAN_QUICK_CLUSTERING_AND_NORMALIZATION {
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
    .bm_deps <- c("SingleCellExperiment", "bluster", "knitr", "pheatmap", "scater", "scran", "scRNAseq", "scuttle")
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
    library(scran)
    library(scuttle)
    
    # 1. Read the input SingleCellExperiment object
    if (!file.exists("sce.ready")) {
      stop("Error: Input file 'sce.ready' not found in the working directory.")
    }
    
    message("Reading input SingleCellExperiment object...")
    sce.ready <- readRDS("sce.ready")
    
    # 2. Perform quick clustering
    message("Performing quick clustering...")
    clusters <- quickCluster(sce.ready)
    
    # Save quick clustering results
    clusters_df <- data.frame(
      Cell = colnames(sce.ready),
      Cluster = clusters,
      stringsAsFactors = FALSE
    )
    write.csv(clusters_df, "quick_clusters.csv", row.names = FALSE)
    
    # 3. Compute size factors within clusters
    message("Computing sum factors...")
    sce.normed <- computeSumFactors(sce.ready, clusters=clusters)
    
    # Extract and save size factors summary
    sf_summary <- summary(sizeFactors(sce.normed))
    message("Size factors summary:")
    print(sf_summary)
    
    sink("size_factors_summary.txt")
    print(sf_summary)
    sink()
    
    # Save the normalized SingleCellExperiment object
    saveRDS(sce.normed, "sce_normed.rds")
    
    # 4. Perform subclustering within identified clusters
    message("Performing subclustering...")
    subout <- quickSubCluster(sce.ready, groups=clusters)
    
    # Extract and save subcluster table
    subcluster_table <- table(metadata(subout)\$subcluster)
    message("Subcluster table:")
    print(subcluster_table)
    
    subcluster_df <- as.data.frame(subcluster_table)
    colnames(subcluster_df) <- c("Subcluster", "CellCount")
    write.csv(subcluster_df, "subcluster_table.csv", row.names = FALSE)
    
    # Save the subclustering output object
    saveRDS(subout, "subout.rds")
    
    message("Workflow completed successfully. Outputs saved: 'quick_clusters.csv', 'sce_normed.rds', 'size_factors_summary.txt', 'subcluster_table.csv', 'subout.rds'.")

    writeLines(c(
        '"BIOC_SCRAN_QUICK_CLUSTERING_AND_NORMALIZATION":',
        paste0('    scran: ', as.character(packageVersion('scran')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_quick_clustering_and_normalization.csv versions.yml
    """
}

workflow BIOC_SCRAN_QUICK_CLUSTERING_AND_NORMALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sce.ready ] ]

    main:
    BIOC_SCRAN_QUICK_CLUSTERING_AND_NORMALIZATION(ch_input)

    emit:
    tables   = BIOC_SCRAN_QUICK_CLUSTERING_AND_NORMALIZATION.out.tables
    plots    = BIOC_SCRAN_QUICK_CLUSTERING_AND_NORMALIZATION.out.plots
    objects  = BIOC_SCRAN_QUICK_CLUSTERING_AND_NORMALIZATION.out.objects
    versions = BIOC_SCRAN_QUICK_CLUSTERING_AND_NORMALIZATION.out.versions
}
