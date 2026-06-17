#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MantelCorr — mantel_cluster_correlation_analysis
// Perform k-means over-partitioning, compute Mantel correlation coefficients, and run permutation testing to identify statistically significant gene clusters from
// Input: expression_matrix.csv
// Container: quay.io/biocontainers/bioconductor-mantelcorr:1.80.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MantelCorr
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Over-partition the gene space into non-overlapping clusters using GetClusters
//  * 2. [Core Analysis] Compute full and cluster-specific dissimilarity matrices using DistMatrices
//  * 3. [Core Analysis] Calculate Mantel correlation coefficients for each cluster using MantelCorrs
//  * 4. [Core Analysis] Perform a permutation test to determine cluster significance using PermutationTest
//  * 5. [Core Analysis] Generate lists of significant and non-significant clusters using ClusterList
//  * 6. [Core Analysis] Extract the specific genes belonging to the significant clusters using ClusterGeneList

nextflow.enable.dsl = 2

process BIOC_MANTELCORR_MANTEL_CLUSTER_CORRELATION_ANALYSIS {
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
    .bm_deps <- c("MantelCorr")
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
            library(MantelCorr)
            
            # 1. Read the user input file
            # The input must be a numeric p x n matrix of gene expression values,
            # where rows represent genes and columns represent samples, with dimnames assigned.
            input_file <- "expression_matrix.csv"
            if (!file.exists(input_file)) {
              stop(paste("Error: Input file", input_file, "not found in the working directory."))
            }
            
            # Read the CSV and convert to a numeric matrix
            data_df <- read.csv(input_file, row.names = 1, check.names = FALSE)
            data <- as.matrix(data_df)
            mode(data) <- "numeric"
            
            # 2. Determine parameters dynamically based on input dimensions
            p <- nrow(data)
            n <- ncol(data)
            
            # k-means over-partitioning parameter k must be between 5 and p/2
            k <- min(500, floor(p / 2))
            if (k < 5) {
              k <- 5
            }
            
            # 3. Execute the MantelCorr workflow stages
            # Stage 1: Over-partition the gene space into non-overlapping clusters
            kmeans.result <- GetClusters(data, k, 100)
            
            # Stage 2: Compute full and cluster-specific dissimilarity matrices
            DistMatrices.result <- DistMatrices(data, kmeans.result\$clusters)
            
            # Stage 3: Calculate Mantel correlation coefficients for each cluster
            MantelCorrs.result <- MantelCorrs(DistMatrices.result\$Dfull, DistMatrices.result\$Dsubsets)
            
            # Stage 4: Perform a permutation test to determine cluster significance
            # Using 100 permutations as in the documented code, with dynamic sample size n
            permuted.pval <- PermutationTest(DistMatrices.result\$Dfull, DistMatrices.result\$Dsubsets, 100, n, 0.05)
            
            # Stage 5: Generate lists of significant and non-significant clusters
            ClusterLists <- ClusterList(permuted.pval, kmeans.result\$cluster.sizes, MantelCorrs.result)
            
            # Stage 6: Extract the specific genes belonging to the significant clusters
            ClusterGenes <- ClusterGeneList(kmeans.result\$clusters, ClusterLists\$SignificantClusters, data)
            
            # 4. Save meaningful results to output files
            # Save the complete R objects for downstream analysis
            saveRDS(ClusterLists, "ClusterLists.rds")
            saveRDS(ClusterGenes, "ClusterGenes.rds")
            
            # Save a comprehensive CSV summary of all clusters
            cluster_summary <- data.frame(
              Cluster = 1:length(kmeans.result\$cluster.sizes),
              Size = kmeans.result\$cluster.sizes,
              MantelCorr = MantelCorrs.result,
              Permutation_Threshold = permuted.pval,
              Significant = MantelCorrs.result >= permuted.pval
            )
            write.csv(cluster_summary, "cluster_summary.csv", row.names = FALSE)
            
            # Save a text summary of the genes in the clusters
            sink("cluster_genes_summary.txt")
            cat("====================================================\n")
            cat("MantelCorr Cluster Gene List Summary\n")
            cat("====================================================\n\n")
            print(ClusterGenes)
            sink()

    writeLines(c(
        '"BIOC_MANTELCORR_MANTEL_CLUSTER_CORRELATION_ANALYSIS":',
        paste0('    MantelCorr: ', as.character(packageVersion('MantelCorr')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mantel_cluster_correlation_analysis.csv versions.yml
    """
}

workflow BIOC_MANTELCORR_MANTEL_CLUSTER_CORRELATION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.csv ] ]

    main:
    BIOC_MANTELCORR_MANTEL_CLUSTER_CORRELATION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_MANTELCORR_MANTEL_CLUSTER_CORRELATION_ANALYSIS.out.tables
    plots    = BIOC_MANTELCORR_MANTEL_CLUSTER_CORRELATION_ANALYSIS.out.plots
    objects  = BIOC_MANTELCORR_MANTEL_CLUSTER_CORRELATION_ANALYSIS.out.objects
    versions = BIOC_MANTELCORR_MANTEL_CLUSTER_CORRELATION_ANALYSIS.out.versions
}
