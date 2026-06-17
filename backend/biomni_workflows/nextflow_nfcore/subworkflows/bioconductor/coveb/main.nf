#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: covEB — cov_estimation_unknown_blocks
// Estimate a shrunk covariance matrix from gene expression data when gene groupings/blocks are unknown, using thresholding to determine block structure.
// Input: Edata
// Container: quay.io/biocontainers/bioconductor-coveb:1.36.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: covEB, igraph
// Visualizations: network plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Filter genes based on variance across samples
//  * 2. [Core Analysis] Compute the sample covariance matrix
//  * 3. [Core Analysis] Estimate the shrunk covariance matrix using EBsingle with a starting threshold parameter
//  * 4. [Core Analysis] Threshold the estimated covariance matrix to identify significant correlations and extract network subgraphs

nextflow.enable.dsl = 2

process BIOC_COVEB_COV_ESTIMATION_UNKNOWN_BLOCKS {
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
    .bm_deps <- c("covEB", "igraph")
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
    library(covEB)
    library(igraph)
    
    # ----------------------------------------------------------------------
    # Stage 0: Read User Input
    # ----------------------------------------------------------------------
    # The pipeline expects Edata (matrix of gene expression values, genes as rows, samples as columns)
    # in the working directory as Edata.csv, Edata.tsv, or Edata.rds.
    
    Edata <- NULL
    
    if (file.exists("Edata.csv")) {
      Edata <- as.matrix(read.csv("Edata.csv", row.names = 1, check.names = FALSE))
    } else if (file.exists("Edata.rds")) {
      Edata <- readRDS("Edata.rds")
      if (!is.matrix(Edata)) {
        Edata <- as.matrix(Edata)
      }
    } else if (file.exists("Edata.tsv")) {
      Edata <- as.matrix(read.delim("Edata.tsv", row.names = 1, check.names = FALSE))
    } else {
      stop("Error: Input file 'Edata' (Edata.csv, Edata.tsv, or Edata.rds) not found in the working directory.")
    }
    
    # Ensure data is numeric
    class(Edata) <- "numeric"
    
    # Determine sample size dynamically to ensure correctness
    n_samples <- ncol(Edata)
    
    # ----------------------------------------------------------------------
    # Stage 1: Filter genes based on variance across samples
    # ----------------------------------------------------------------------
    variances<-apply(Edata,1,var)
    edata<-Edata[which(variances>quantile(variances,0.8)),]
    
    # ----------------------------------------------------------------------
    # Stage 2: Compute the sample covariance matrix
    # ----------------------------------------------------------------------
    covmat<-cov(t(edata))
    cormat<-cov2cor(covmat)
    
    # ----------------------------------------------------------------------
    # Stage 3: Estimate the shrunk covariance matrix using EBsingle
    # ----------------------------------------------------------------------
    # We use the dynamic sample size n_samples to match the input data structure
    out<-EBsingle(covmat,startlambda=0.5,n=n_samples)
    
    # ----------------------------------------------------------------------
    # Stage 4: Threshold the estimated covariance matrix and extract subgraphs
    # ----------------------------------------------------------------------
    outmat<-out
    outmat[abs(out)<0.5]<-0
    outmat[abs(out)>=0.5]<-1
    
    clusth<-clusters(graph.adjacency(outmat))
    
    # Robust fallback: If cluster 6 does not exist or is empty, select a valid cluster
    sel<-which(clusth\$membership==6)
    if (length(sel) < 2) {
      message("Cluster 6 has fewer than 2 nodes or does not exist. Selecting the largest available cluster for visualization.")
      cluster_sizes <- table(clusth\$membership)
      valid_clusters <- names(cluster_sizes)[cluster_sizes >= 2]
      if (length(valid_clusters) > 0) {
        # Select the largest cluster with at least 2 nodes
        best_cluster <- as.numeric(valid_clusters[which.max(cluster_sizes[valid_clusters])])
        sel <- which(clusth\$membership == best_cluster)
      } else {
        # Fallback to first few nodes if no clusters of size >= 2 exist
        sel <- seq_len(min(10, nrow(outmat)))
      }
    }
    
    subgraphEB<-outmat[sel,sel]
    subgraph<-cormat[sel,sel]
    subgraph[subgraph<0.5]<-0
    subgraph[subgraph>=0.5]<-1
    
    diag(subgraph)<-0
    diag(subgraphEB)<-0
    
    # ----------------------------------------------------------------------
    # Stage 5: Save Outputs
    # ----------------------------------------------------------------------
    # Save matrices
    write.csv(out, "shrunk_covariance_matrix.csv", row.names = TRUE)
    saveRDS(out, "shrunk_covariance_matrix.rds")
    write.csv(subgraph, "subgraph_original.csv", row.names = TRUE)
    write.csv(subgraphEB, "subgraph_covEB.csv", row.names = TRUE)
    
    # Save network plots
    pdf("network_subgraph_plots.pdf", width = 12, height = 6)
    par(mfrow = c(1, 2))
    tryCatch({
      plot(graph.adjacency(subgraph, mode = "undirected"), main = "Original Correlation Subgraph")
      plot(graph.adjacency(subgraphEB, mode = "undirected"), main = "covEB Shrunk Subgraph")
    }, error = function(e) {
      message("Plotting failed: ", e\$message)
    })
    dev.off()
    
    message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_COVEB_COV_ESTIMATION_UNKNOWN_BLOCKS":',
        paste0('    covEB: ', as.character(packageVersion('covEB')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cov_estimation_unknown_blocks.csv versions.yml
    """
}

workflow BIOC_COVEB_COV_ESTIMATION_UNKNOWN_BLOCKS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Edata ] ]

    main:
    BIOC_COVEB_COV_ESTIMATION_UNKNOWN_BLOCKS(ch_input)

    emit:
    tables   = BIOC_COVEB_COV_ESTIMATION_UNKNOWN_BLOCKS.out.tables
    plots    = BIOC_COVEB_COV_ESTIMATION_UNKNOWN_BLOCKS.out.plots
    objects  = BIOC_COVEB_COV_ESTIMATION_UNKNOWN_BLOCKS.out.objects
    versions = BIOC_COVEB_COV_ESTIMATION_UNKNOWN_BLOCKS.out.versions
}
