#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: clusterSeq — kmeans_coexpression_clustering
// Cluster genes based on K-means dissimilarity scores, optionally incorporating replicate structures and using either singleton agglomeration or full-matrix hiera
// Input: ratThymus, libsizes, replicates
// Container: quay.io/biocontainers/bioconductor-clusterseq:1.34.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: clusterSeq
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Replace zero counts with 1 and log2-transform normalized counts
//  * 2. [Core Analysis] Calculate dissimilarity scores using kCluster (optionally specifying replicates and saving the full matrix to a file)
//  * 3. [Visualization & Output] Build clusters using makeClusters (for singleton agglomeration) or makeClustersFF (for other hierarchical clustering methods on th

nextflow.enable.dsl = 2

process BIOC_CLUSTERSEQ_KMEANS_COEXPRESSION_CLUSTERING {
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
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(clusterSeq)
    
    # ==========================================
    # 1. READ USER INPUT FILES
    # ==========================================
    
    # Read ratThymus (matrix or data frame of raw count data)
    if (file.exists("ratThymus.rds")) {
      ratThymus <- readRDS("ratThymus.rds")
    } else if (file.exists("ratThymus.csv")) {
      ratThymus <- as.matrix(read.csv("ratThymus.csv", row.names = 1, check.names = FALSE))
    } else if (file.exists("ratThymus.txt")) {
      ratThymus <- as.matrix(read.table("ratThymus.txt", header = TRUE, row.names = 1))
    } else {
      stop("Required input file 'ratThymus' (RDS, CSV, or TXT) not found in the working directory.")
    }
    
    # Read libsizes (numeric vector of library scaling factors)
    if (file.exists("libsizes.rds")) {
      libsizes <- readRDS("libsizes.rds")
    } else if (file.exists("libsizes.txt")) {
      libsizes <- scan("libsizes.txt", quiet = TRUE)
    } else if (file.exists("libsizes.csv")) {
      libsizes <- as.numeric(read.csv("libsizes.csv", header = FALSE)[[1]])
    } else {
      stop("Required input file 'libsizes' (RDS, CSV, or TXT) not found in the working directory.")
    }
    
    # Read replicates (character vector defining replicate groups)
    if (file.exists("replicates.rds")) {
      replicates <- readRDS("replicates.rds")
    } else if (file.exists("replicates.txt")) {
      replicates <- scan("replicates.txt", what = character(), quiet = TRUE)
    } else if (file.exists("replicates.csv")) {
      replicates <- as.character(read.csv("replicates.csv", header = FALSE)[[1]])
    } else {
      stop("Required input file 'replicates' (RDS, CSV, or TXT) not found in the working directory.")
    }
    
    # Ensure ratThymus is a matrix for matrix multiplication
    ratThymus <- as.matrix(ratThymus)
    
    # ==========================================
    # 2. EXECUTING DOCUMENTED WORKFLOW
    # ==========================================
    
    ratThymus[ratThymus == 0] <- 1
    normRT <- log2(ratThymus %*% diag(1/libsizes) * mean(libsizes))
    
    # Subset to the first 1000 genes (or fewer if the input has fewer rows)
    n_genes <- min(1000, nrow(normRT))
    normRT <- normRT[1:n_genes, , drop = FALSE]
    
    # K-means clustering without replicates
    kClust <- kCluster(normRT, matrixFile = "kclust_matrix.txt.gz", B = 1000)
    head(kClust)
    
    # Build clusters using singleton agglomeration
    mkClust <- makeClusters(kClust, normRT, threshold = 1)
    
    # K-means clustering forcing replicate structures
    kClustR <- kCluster(normRT, replicates = replicates, matrixFile = "kclust_matrix_newForceReps.txt.gz", B = 1000)
    
    # Build clusters with replicates using singleton agglomeration
    mkClustR <- makeClusters(kClustR, normRT, threshold = 1)
    
    # Build clusters using complete linkage hierarchical clustering on the saved matrix file
    mkClustRC <- makeClustersFF("kclust_matrix_newForceReps.txt.gz", method = "complete", cut.height = 5)
    
    # ==========================================
    # 3. WRITE OUTPUTS
    # ==========================================
    
    # Save dissimilarity data frames
    write.csv(as.data.frame(kClust), "kClust_results.csv", row.names = TRUE)
    write.csv(as.data.frame(kClustR), "kClustR_results.csv", row.names = TRUE)
    
    # Save cluster objects
    saveRDS(mkClust, "mkClust.rds")
    saveRDS(mkClustR, "mkClustR.rds")
    saveRDS(mkClustRC, "mkClustRC.rds")
    
    # Write a text summary of the generated clusters
    tryCatch({
      sink("clustering_summary.txt")
      cat("=========================================\n")
      cat("clusterSeq K-means Clustering Summary\n")
      cat("=========================================\n\n")
      
      cat("--- mkClust (No Replicates, Singleton Agglomeration) ---\n")
      print(mkClust)
      cat("\n")
      
      cat("--- mkClustR (With Replicates, Singleton Agglomeration) ---\n")
      print(mkClustR)
      cat("\n")
      
      cat("--- mkClustRC (With Replicates, Complete Linkage FF) ---\n")
      print(mkClustRC)
      cat("\n")
      sink()
    }, error = function(e) {
      if (sink.number() > 0) sink()
      warning("Could not write text summary file: ", e\$message)
    })

    writeLines(c(
        '"BIOC_CLUSTERSEQ_KMEANS_COEXPRESSION_CLUSTERING":',
        paste0('    clusterSeq: ', as.character(packageVersion('clusterSeq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_kmeans_coexpression_clustering.csv versions.yml
    """
}

workflow BIOC_CLUSTERSEQ_KMEANS_COEXPRESSION_CLUSTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ratThymus, libsizes, replicates ] ]

    main:
    BIOC_CLUSTERSEQ_KMEANS_COEXPRESSION_CLUSTERING(ch_input)

    emit:
    tables   = BIOC_CLUSTERSEQ_KMEANS_COEXPRESSION_CLUSTERING.out.tables
    plots    = BIOC_CLUSTERSEQ_KMEANS_COEXPRESSION_CLUSTERING.out.plots
    objects  = BIOC_CLUSTERSEQ_KMEANS_COEXPRESSION_CLUSTERING.out.objects
    versions = BIOC_CLUSTERSEQ_KMEANS_COEXPRESSION_CLUSTERING.out.versions
}
