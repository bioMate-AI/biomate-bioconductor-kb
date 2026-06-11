#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RCSL — sc_clustering_and_trajectory_analysis
// Perform single-cell clustering and trajectory analysis on scRNA-seq expression data.
// Input: origData, label
// Container: quay.io/biocontainers/bioconductor-rcsl:1.18.0--r45ha27e39d_0
// R packages: ggplot2, igraph, RCSL, SingleCellExperiment, umap
// Bioconductor: 3.20 | R: 4.4
// Requires: RCSL, SingleCellExperiment, ggplot2, igraph, umap
// Visualizations: trajectory plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Log-transform the raw expression matrix
//  * 2. [Core Analysis] Filter genes using GenesFilter
//  * 3. [Core Analysis] Calculate the initial similarity matrix and dimensionality reduction data using SimS
//  * 4. [Core Analysis] Estimate the number of clusters using EstClusters
//  * 5. [Core Analysis] Calculate the block diagonal matrix and cluster assignments using BDSM
//  * 6. [Core Analysis] Calculate clustering accuracy using igraph::compare
//  * 7. [Core Analysis] Perform trajectory analysis using TrajectoryAnalysis
//  * 8. [Visualization & Output] Visualize the minimum spanning tree, pseudo-temporal ordering, and developmental trajectory

nextflow.enable.dsl = 2

process BIOC_RCSL_SC_CLUSTERING_AND_TRAJECTORY_ANALYSIS {
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
    .bm_deps <- c("ggplot2", "igraph", "RCSL", "SingleCellExperiment", "umap")
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
    library(RCSL)
    library(ggplot2)
    library(igraph)
    library(umap)
    
    # ==========================================
    # 1. Read User Input Files
    # ==========================================
    
    # Read origData (matrix of raw single-cell RNA-seq expression values)
    if (file.exists("origData.rds")) {
      origData <- readRDS("origData.rds")
    } else if (file.exists("origData.csv")) {
      origData <- read.csv("origData.csv", row.names = 1, check.names = FALSE)
    } else if (file.exists("origData.tsv")) {
      origData <- read.delim("origData.tsv", row.names = 1, check.names = FALSE)
    } else if (file.exists("origData.txt")) {
      origData <- read.table("origData.txt", header = TRUE, row.names = 1, check.names = FALSE)
    } else {
      stop("Error: origData file not found in the working directory (expected origData.rds, origData.csv, origData.tsv, or origData.txt).")
    }
    
    # Read label (vector of true cell type annotations, optional for validation)
    label <- NULL
    if (file.exists("label.rds")) {
      label <- readRDS("label.rds")
    } else if (file.exists("label.csv")) {
      label_df <- read.csv("label.csv", header = FALSE)
      label <- as.vector(label_df[[1]])
    } else if (file.exists("label.tsv")) {
      label_df <- read.delim("label.tsv", header = FALSE)
      label <- as.vector(label_df[[1]])
    } else if (file.exists("label.txt")) {
      label_df <- read.table("label.txt", header = FALSE)
      label <- as.vector(label_df[[1]])
    } else {
      warning("Optional label file not found. Proceeding with label = NULL.")
    }
    
    # ==========================================
    # 2. Pre-processing
    # ==========================================
    data <- log2(as.matrix(origData) + 1)
    gfData <- GenesFilter(data)
    
    # ==========================================
    # 3. Calculate the initial similarity matrix S
    # ==========================================
    resSimS <- SimS(gfData)
    
    # ==========================================
    # 4. Estimate the number of clusters C
    # ==========================================
    Estimated_C <- EstClusters(resSimS\$drData,resSimS\$S)
    
    # ==========================================
    # 5. Calculate the block diagonal matrix B
    # ==========================================
    resBDSM <- BDSM(resSimS\$S, Estimated_C)
    
    # ==========================================
    # 6. Calculate accuracy of the clustering
    # ==========================================
    if (!is.null(label)) {
      ARI_RCSL <- igraph::compare(resBDSM\$y, label, method = "adjusted.rand")
      writeLines(paste("Adjusted Rand Index (ARI):", ARI_RCSL), "ari_score.txt")
    }
    
    # ==========================================
    # 7. Trajectory analysis
    # ==========================================
    DataName <- "Dataset"
    res_TrajecAnalysis <- TrajectoryAnalysis(gfData, resSimS\$drData, resSimS\$S,
                                             clustRes = resBDSM\$y, TrueLabel = label, 
                                             startPoint = 1, dataName = DataName)
    
    # ==========================================
    # 8. Save Outputs and Visualizations
    # ==========================================
    
    # Save clustering assignments
    clustering_results <- data.frame(
      Cell = colnames(gfData),
      Cluster = resBDSM\$y
    )
    write.csv(clustering_results, "clustering_results.csv", row.names = FALSE)
    
    # Save full trajectory analysis object
    saveRDS(res_TrajecAnalysis, "trajectory_analysis_output.rds")
    
    # Save plots to a multi-page PDF
    pdf("trajectory_plots.pdf", width = 8, height = 6)
    if (!is.null(res_TrajecAnalysis\$MSTPlot)) {
      print(res_TrajecAnalysis\$MSTPlot)
    }
    if (!is.null(res_TrajecAnalysis\$PseudoTimePlot)) {
      print(res_TrajecAnalysis\$PseudoTimePlot)
    }
    if (!is.null(res_TrajecAnalysis\$TrajectoryPlot)) {
      print(res_TrajecAnalysis\$TrajectoryPlot)
    }
    dev.off()

    writeLines(c(
        '"BIOC_RCSL_SC_CLUSTERING_AND_TRAJECTORY_ANALYSIS":',
        paste0('    RCSL: ', as.character(packageVersion('RCSL')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sc_clustering_and_trajectory_analysis.csv versions.yml
    """
}

workflow BIOC_RCSL_SC_CLUSTERING_AND_TRAJECTORY_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ origData, label ] ]

    main:
    BIOC_RCSL_SC_CLUSTERING_AND_TRAJECTORY_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_RCSL_SC_CLUSTERING_AND_TRAJECTORY_ANALYSIS.out.tables
    plots    = BIOC_RCSL_SC_CLUSTERING_AND_TRAJECTORY_ANALYSIS.out.plots
    objects  = BIOC_RCSL_SC_CLUSTERING_AND_TRAJECTORY_ANALYSIS.out.objects
    versions = BIOC_RCSL_SC_CLUSTERING_AND_TRAJECTORY_ANALYSIS.out.versions
}
