#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ibh — clustering_evaluation
// Evaluate the fitness of clustering results of gene expression data against an interaction network.
// Input: expression_data.csv, custom_interactions.csv
// Container: quay.io/biocontainers/bioconductor-ibh:1.58.0--r45hdfd78af_0
// R packages: ibh
// Bioconductor: 3.20 | R: 4.4
// Requires: ibh
// Visualizations: bar plot, cluster plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load expression data and perform clustering (e.g., using kmeans)
//  * 2. [Core Analysis] Evaluate the clusters using ibhClusterEval (for custom networks) or ibhClusterEvalBioGRID (for BioGRID networks)

nextflow.enable.dsl = 2

process BIOC_IBH_CLUSTERING_EVALUATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    .bm_deps <- c("ibh")
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
    library(ibh)
    library(stats)
    
    # Parse command line arguments for BioGRID evaluation
    args <- commandArgs(trailingOnly = TRUE)
    organism_arg <- if (length(args) >= 1) args[1] else NA
    idType_arg <- if (length(args) >= 2) args[2] else NA
    
    # 1. Read User Input Files
    if (!file.exists("expression_data.csv")) {
      stop("Required input file 'expression_data.csv' is missing.")
    }
    
    # Read gene expression matrix
    expr_data <- read.csv("expression_data.csv", row.names = 1, check.names = FALSE)
    subset <- as.matrix(expr_data)
    
    # Read custom interactions using the package's built-in function
    custom_interactions <- NULL
    if (file.exists("custom_interactions.csv")) {
      custom_interactions <- readUndirectedInteractionsFromCsv("custom_interactions.csv")
    }
    
    # 2. Perform Clustering
    d <- dist(subset, method = "euclidean")
    k <- kmeans(d, 3)
    
    # 3. Evaluate Clusters using ibh functions
    # Evaluate using custom network only if provided
    eval_custom <- NULL
    if (!is.null(custom_interactions)) {
      eval_custom <- ibhClusterEval(k\$cluster, rownames(subset), custom_interactions)
    }
    
    # Evaluate using BioGRID network only if organism and idType are provided
    eval_biogrid <- NULL
    if (!is.na(organism_arg) && !is.na(idType_arg)) {
      eval_biogrid <- ibhClusterEvalBioGRID(k\$cluster, rownames(subset), organism = organism_arg, idType = idType_arg)
    }
    
    # 4. Save Results
    # Save numerical results to CSV
    n_clusters <- max(k\$cluster)
    results_df <- data.frame(
      Cluster = seq_len(n_clusters),
      IBH_Custom = if (!is.null(eval_custom) && length(eval_custom) > 0) eval_custom else NA,
      IBH_BioGRID = if (!is.null(eval_biogrid) && length(eval_biogrid) > 0) eval_biogrid else NA
    )
    write.csv(results_df, "ibh_clustering_evaluation.csv", row.names = FALSE)
    
    # Save visualization to PDF
    pdf("ibh_clustering_evaluation.pdf", width = 7, height = 5)
    plot_data <- numeric()
    legend_labels <- c()
    col_vec <- c()
    
    if (!is.null(eval_custom) && length(eval_custom) > 0 && !all(is.na(eval_custom))) {
      plot_data <- rbind(plot_data, Custom = eval_custom)
      legend_labels <- c(legend_labels, "Custom Network")
      col_vec <- c(col_vec, "skyblue")
    }
    if (!is.null(eval_biogrid) && length(eval_biogrid) > 0 && !all(is.na(eval_biogrid))) {
      plot_data <- rbind(plot_data, BioGRID = eval_biogrid)
      legend_labels <- c(legend_labels, "BioGRID Network")
      col_vec <- c(col_vec, "salmon")
    }
    
    if (length(plot_data) > 0) {
      barplot(plot_data, beside = TRUE, 
              names.arg = paste("Cluster", seq_len(ncol(plot_data))),
              col = col_vec,
              legend.text = legend_labels,
              main = "Interaction Based Homogeneity (IBH) Evaluation",
              ylab = "IBH Score")
    } else {
      plot(1, type = "n", axes = FALSE, xlab = "", ylab = "", main = "No IBH Scores to Plot")
      text(1, 1, "IBH scores could not be calculated (possibly no overlapping genes).")
    }
    dev.off()

    writeLines(c(
        '"BIOC_IBH_CLUSTERING_EVALUATION":',
        paste0('    ibh: ', as.character(packageVersion('ibh')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_clustering_evaluation.csv versions.yml
    """
}

workflow BIOC_IBH_CLUSTERING_EVALUATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_data.csv, custom_interactions.csv ] ]

    main:
    BIOC_IBH_CLUSTERING_EVALUATION(ch_input)

    emit:
    tables   = BIOC_IBH_CLUSTERING_EVALUATION.out.tables
    plots    = BIOC_IBH_CLUSTERING_EVALUATION.out.plots
    objects  = BIOC_IBH_CLUSTERING_EVALUATION.out.objects
    versions = BIOC_IBH_CLUSTERING_EVALUATION.out.versions
}
