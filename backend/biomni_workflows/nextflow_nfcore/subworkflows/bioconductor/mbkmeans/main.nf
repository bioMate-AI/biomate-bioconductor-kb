#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mbkmeans — mbkmeans_direct_clustering
// Cluster single-cell data represented as a SingleCellExperiment or matrix-like object using the mini-batch k-means algorithm, including batch size estimation and
// Input: sce_object.rds
// Container: quay.io/biocontainers/bioconductor-mbkmeans:1.26.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, mbkmeans, scater
// Visualizations: elbow plot
// QC: cell QC metrics, count normalization
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run mbkmeans on a specific assay of the SingleCellExperiment
//  * 2. [Core Analysis] Estimate optimal batch size using blocksize()
//  * 3. [Core Analysis] Run mbkmeans with random initialization
//  * 4. [Core Analysis] Perform PCA and run mbkmeans across multiple k values to find the optimal number of clusters using WCSS

nextflow.enable.dsl = 2

process BIOC_MBKMEANS_MBKMEANS_DIRECT_CLUSTERING {
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
    .bm_deps <- c("mbkmeans", "scater")
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
    library(mbkmeans)
    library(scater)
    
    # -----------------------------------------------------------------------------
    # Stage 0: Load User Input and Prepare Data
    # -----------------------------------------------------------------------------
    # Read the user-provided SingleCellExperiment object
    if (!file.exists("sce_object.rds")) {
      stop("Error: 'sce_object.rds' not found in the working directory.")
    }
    
    sce1000 <- readRDS("sce_object.rds")
    
    # Ensure the object is a SingleCellExperiment
    if (!inherits(sce1000, "SingleCellExperiment")) {
      stop("Error: The loaded object is not a SingleCellExperiment.")
    }
    
    # Ensure logcounts assay exists; if not, compute it
    if (!"logcounts" %in% assayNames(sce1000)) {
      message("'logcounts' assay not found. Computing log-normalized counts...")
      sce1000 <- scater::logNormCounts(sce1000)
    }
    
    # -----------------------------------------------------------------------------
    # Stage 1: Run mbkmeans on a specific assay of the SingleCellExperiment
    # -----------------------------------------------------------------------------
    res <- mbkmeans(sce1000, clusters = 5,
                    reduceMethod = NA,
                    whichAssay = "logcounts")
    
    # Save Stage 1 results
    saveRDS(res, "mbkmeans_res_k5.rds")
    write.csv(as.data.frame(res\$Clusters), "cluster_assignments_k5.csv", row.names = TRUE)
    
    # -----------------------------------------------------------------------------
    # Stage 2: Estimate optimal batch size using blocksize()
    # -----------------------------------------------------------------------------
    batchsize <- blocksize(sce1000)
    
    # Save batch size estimation
    writeLines(as.character(batchsize), "estimated_batch_size.txt")
    
    # -----------------------------------------------------------------------------
    # Stage 3: Run mbkmeans with random initialization
    # -----------------------------------------------------------------------------
    res_random <- mbkmeans(sce1000, clusters = 5, 
                    reduceMethod = NA,
                    whichAssay = "logcounts",
                    initializer = "random")
    
    # Save Stage 3 results
    saveRDS(res_random, "mbkmeans_res_random_k5.rds")
    
    # Compare initializations and save comparison table
    init_comparison <- table(res\$Clusters, res_random\$Clusters)
    write.csv(as.data.frame.matrix(init_comparison), "initialization_comparison.csv", row.names = TRUE)
    
    # -----------------------------------------------------------------------------
    # Stage 4: Perform PCA and run mbkmeans across multiple k values (optimal k selection)
    # -----------------------------------------------------------------------------
    sce1000 <- runPCA(sce1000, ncomponents=20)
    
    ks <- seq(5, 15)
    res <- lapply(ks, function(k) {
        mbkmeans(sce1000, clusters = k,
                 reduceMethod = "PCA",
                 calc_wcss = TRUE, num_init=10)
    })
    
    wcss <- sapply(res, function(x) sum(x\$WCSS_per_cluster))
    
    # Save WCSS results
    wcss_df <- data.frame(k = ks, WCSS = wcss)
    write.csv(wcss_df, "wcss_results.csv", row.names = FALSE)
    saveRDS(res, "mbkmeans_res_multi_k.rds")
    
    # Plot the elbow curve and save as PDF
    pdf("wcss_elbow_plot.pdf", width = 7, height = 5)
    plot(ks, wcss, type = "b", xlab = "Number of Clusters (k)", ylab = "Within-Cluster Sum of Squares (WCSS)",
         main = "Elbow Method for Optimal k Selection")
    dev.off()
    
    # Save the final updated SingleCellExperiment object
    saveRDS(sce1000, "sce_processed.rds")
    
    message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_MBKMEANS_MBKMEANS_DIRECT_CLUSTERING":',
        paste0('    mbkmeans: ', as.character(packageVersion('mbkmeans')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mbkmeans_direct_clustering.csv versions.yml
    """
}

workflow BIOC_MBKMEANS_MBKMEANS_DIRECT_CLUSTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sce_object.rds ] ]

    main:
    BIOC_MBKMEANS_MBKMEANS_DIRECT_CLUSTERING(ch_input)

    emit:
    tables   = BIOC_MBKMEANS_MBKMEANS_DIRECT_CLUSTERING.out.tables
    plots    = BIOC_MBKMEANS_MBKMEANS_DIRECT_CLUSTERING.out.plots
    objects  = BIOC_MBKMEANS_MBKMEANS_DIRECT_CLUSTERING.out.objects
    versions = BIOC_MBKMEANS_MBKMEANS_DIRECT_CLUSTERING.out.versions
}
