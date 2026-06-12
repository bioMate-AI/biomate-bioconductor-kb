#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rScudo — unsupervised_network_analysis
// Identify sample-specific signatures, construct similarity networks, and cluster samples.
// Input: trainData, testData
// Container: quay.io/biocontainers/bioconductor-rscudo:1.26.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, igraph, rScudo
// Visualizations: network plot, cluster plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Train SCUDO model and extract signatures using scudoTrain
//  * 2. [Core Analysis] Inspect signatures using upSignatures and consensusUpSignatures
//  * 3. [Core Analysis] Generate sample network using scudoNetwork
//  * 4. [Visualization & Output] Visualize network using scudoPlot or scudoCytoscape
//  * 5. [Core Analysis] Analyze test set using scudoTest
//  * 6. [Core Analysis] Cluster network using igraph::cluster_spinglass

nextflow.enable.dsl = 2

process BIOC_RSCUDO_UNSUPERVISED_NETWORK_ANALYSIS {
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
    .bm_deps <- c("rScudo", "Biobase", "igraph")
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
    library(rScudo)
    library(Biobase)
    library(igraph)
    
    # -----------------------------------------------------------------------------
    # 1. Read User Input Files
    # -----------------------------------------------------------------------------
    
    # The pipeline expects trainData and testData in the working directory.
    # They can be either ExpressionSet objects (saved as RDS) or gene expression matrices (RDS or CSV).
    
    if (file.exists("trainData.rds")) {
      trainData <- readRDS("trainData.rds")
    } else if (file.exists("trainData.csv")) {
      trainData <- as.matrix(read.csv("trainData.csv", row.names = 1))
    } else {
      stop("Error: trainData file not found in the working directory (expected trainData.rds or trainData.csv).")
    }
    
    if (file.exists("testData.rds")) {
      testData <- readRDS("testData.rds")
    } else if (file.exists("testData.csv")) {
      testData <- as.matrix(read.csv("testData.csv", row.names = 1))
    } else {
      stop("Error: testData file not found in the working directory (expected testData.rds or testData.csv).")
    }
    
    # Helper function to extract group/class factor from ExpressionSet or matrix
    get_groups <- function(dataset) {
      if (inherits(dataset, "ExpressionSet")) {
        if ("group" %in% colnames(Biobase::pData(dataset))) {
          return(as.factor(dataset\$group))
        } else if ("class" %in% colnames(Biobase::pData(dataset))) {
          return(as.factor(dataset\$class))
        } else {
          # Fallback to the first phenoData column
          return(as.factor(Biobase::pData(dataset)[, 1]))
        }
      } else {
        # If it's a matrix, check for a "groups" attribute, otherwise parse from column names
        if (!is.null(attr(dataset, "groups"))) {
          return(as.factor(attr(dataset, "groups")))
        }
        # Fallback: extract prefix from column names (e.g., "Group1_Sample1" -> "Group1")
        return(as.factor(sub("[_\\\\.].*", "", colnames(dataset))))
      }
    }
    
    # Extract groups for training and testing sets
    trainGroups <- get_groups(trainData)
    testGroups <- get_groups(testData)
    
    # Reconstruct the 'bt' and 'inTrain' variables to match the documented code exactly
    nTrain <- if (inherits(trainData, "ExpressionSet")) ncol(exprs(trainData)) else ncol(trainData)
    nTest <- if (inherits(testData, "ExpressionSet")) ncol(exprs(testData)) else ncol(testData)
    
    inTrain <- 1:nTrain
    bt <- factor(c(as.character(trainGroups), as.character(testGroups)))
    
    # -----------------------------------------------------------------------------
    # 2. Train SCUDO Model and Extract Signatures
    # -----------------------------------------------------------------------------
    
    trainRes <- scudoTrain(trainData, groups = bt[inTrain], nTop = 100,
        nBottom = 100, alpha = 0.1)
    print(trainRes)
    
    # Inspect signatures
    train_up_sig_preview <- upSignatures(trainRes)[1:5, 1:5]
    print(train_up_sig_preview)
    
    train_consensus_up_preview <- consensusUpSignatures(trainRes)[1:5, ]
    print(train_consensus_up_preview)
    
    # Save signatures to files
    write.csv(upSignatures(trainRes), "train_up_signatures.csv")
    write.csv(consensusUpSignatures(trainRes), "train_consensus_up_signatures.csv")
    
    # -----------------------------------------------------------------------------
    # 3. Generate and Visualize Training Network
    # -----------------------------------------------------------------------------
    
    trainNet <- scudoNetwork(trainRes, N = 0.25)
    
    # Save training network plot
    pdf("train_network_plot.pdf", width = 8, height = 8)
    scudoPlot(trainNet, vertex.label = NA)
    dev.off()
    
    # -----------------------------------------------------------------------------
    # 4. Analyze Testing Set
    # -----------------------------------------------------------------------------
    
    testRes <- scudoTest(trainRes, testData, bt[-inTrain], nTop = 100,
        nBottom = 100)
    print(testRes)
    
    # -----------------------------------------------------------------------------
    # 5. Generate and Visualize Testing Network
    # -----------------------------------------------------------------------------
    
    testNet <- scudoNetwork(testRes, N = 0.25)
    
    pdf("test_network_plot.pdf", width = 8, height = 8)
    scudoPlot(testNet, vertex.label = NA)
    dev.off()
    
    # -----------------------------------------------------------------------------
    # 6. Cluster Network
    # -----------------------------------------------------------------------------
    
    # Use tryCatch to handle cases where the network is disconnected or unsuitable for spinglass
    testClust <- tryCatch({
      igraph::cluster_spinglass(testNet, spins = 2)
    }, error = function(e) {
      warning("cluster_spinglass failed (possibly due to disconnected components). Falling back to cluster_walktrap.")
      igraph::cluster_walktrap(testNet)
    })
    
    # Save clustering plot
    pdf("test_clustering_plot.pdf", width = 8, height = 8)
    plot(testClust, testNet, vertex.label = NA)
    dev.off()
    
    # Save clustering membership results
    clust_df <- data.frame(
      sample = names(igraph::membership(testClust)),
      cluster = as.vector(igraph::membership(testClust))
    )
    write.csv(clust_df, "test_clusters.csv", row.names = FALSE)
    
    # Save RDS objects for downstream analysis
    saveRDS(trainRes, "trainRes.rds")
    saveRDS(testRes, "testRes.rds")
    saveRDS(trainNet, "trainNet.rds")
    saveRDS(testNet, "testNet.rds")
    saveRDS(testClust, "testClust.rds")
    
    message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_RSCUDO_UNSUPERVISED_NETWORK_ANALYSIS":',
        paste0('    rScudo: ', as.character(packageVersion('rScudo')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_unsupervised_network_analysis.csv versions.yml
    """
}

workflow BIOC_RSCUDO_UNSUPERVISED_NETWORK_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ trainData, testData ] ]

    main:
    BIOC_RSCUDO_UNSUPERVISED_NETWORK_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_RSCUDO_UNSUPERVISED_NETWORK_ANALYSIS.out.tables
    plots    = BIOC_RSCUDO_UNSUPERVISED_NETWORK_ANALYSIS.out.plots
    objects  = BIOC_RSCUDO_UNSUPERVISED_NETWORK_ANALYSIS.out.objects
    versions = BIOC_RSCUDO_UNSUPERVISED_NETWORK_ANALYSIS.out.versions
}
