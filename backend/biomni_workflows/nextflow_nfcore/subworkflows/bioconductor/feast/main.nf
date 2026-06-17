#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: FEAST — step_by_step_evaluation
// Perform consensus clustering, calculate gene-level F-statistics, evaluate multiple top feature subsets using TSCAN or SC3, and validate using Mean Squared Error
// Input: Y, k
// Container: quay.io/biocontainers/bioconductor-feast:1.18.0--r45h01b2380_0
// R packages: FEAST, ggpubr
// Bioconductor: 3.20 | R: 4.4
// Requires: FEAST
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Read User Input Files
//  * 2. [Core Analysis] Run FEAST Workflow
//  * 3. [Core Analysis] Save Outputs

nextflow.enable.dsl = 2

process BIOC_FEAST_STEP_BY_STEP_EVALUATION {
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
    .bm_deps <- c("FEAST", "ggpubr")
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
    library(FEAST)
    
    # ==========================================
    # --- Read User Input Files ---
    # ==========================================
    
    # Read raw count expression matrix Y
    if (file.exists("Y.rds")) {
      Y <- readRDS("Y.rds")
    } else if (file.exists("Y.csv")) {
      Y <- as.matrix(read.csv("Y.csv", row.names = 1, check.names = FALSE))
    } else if (file.exists("Y.tsv")) {
      Y <- as.matrix(read.delim("Y.tsv", row.names = 1, check.names = FALSE))
    } else {
      stop("Error: Could not find Y.rds, Y.csv, or Y.tsv in the working directory.")
    }
    
    # Read number of clusters k
    if (file.exists("k.rds")) {
      k <- readRDS("k.rds")
    } else if (file.exists("k.txt")) {
      k <- as.integer(readLines("k.txt", n = 1))
    } else {
      stop("Error: Could not find k.rds or k.txt in the working directory.")
    }
    
    # Ensure Y is a matrix
    Y <- as.matrix(Y)
    
    # ==========================================
    # --- Run FEAST Workflow ---
    # ==========================================
    
    # Preprocess the count matrix using process_Y to filter genes based on dropout rate
    Y = process_Y(Y, thre = 2)
    
    # Perform consensus clustering using Consensus to get initial cluster labels
    con_res = Consensus(Y, k=k)
    
    # Calculate gene-level significance using cal_F2 and rank genes
    F_res = cal_F2(Y, con_res\$cluster)
    ixs = order(F_res\$F_scores, decreasing = TRUE)
    
    # Define top feature subsets to evaluate (adjusting dynamically to not exceed available genes)
    tops = c(500, 1000, 2000)
    tops = tops[tops <= nrow(Y)]
    if (length(tops) == 0) {
        tops = c(nrow(Y))
    }
    
    # Perform downstream clustering (TSCAN_Clust) on different top feature subsets
    cluster_res = NULL
    for (top in tops){
        tmp_ixs = ixs[1:top]
        tmp_markers = rownames(Y)[tmp_ixs]
        tmp_res = TSCAN_Clust(Y, k = k, input_markers = tmp_markers)
        cluster_res[[toString(top)]] = tmp_res
    }
    
    # Normalize the matrix using Norm_Y
    Ynorm = Norm_Y(Y)
    
    # Calculate Mean Squared Error (MSE) using cal_MSE to identify the optimal feature set
    mse_res = NULL
    for (top in names(cluster_res)){
        tmp_res = cluster_res[[top]]
        tmp_cluster = tmp_res\$cluster
        tmp_mse = cal_MSE(Ynorm = Ynorm, cluster = tmp_cluster)
        mse_res = c(mse_res, tmp_mse)
    }
    names(mse_res) = names(cluster_res)
    
    # ==========================================
    # --- Save Outputs ---
    # ==========================================
    
    # Save consensus clustering results
    write.csv(data.frame(Cell = colnames(Y), Consensus_Cluster = con_res\$cluster), 
              "consensus_clustering.csv", row.names = FALSE)
    
    # Save gene-level F-statistics and rankings
    f_stats_df <- data.frame(
      Gene = rownames(Y),
      F_score = F_res\$F_scores,
      Rank = match(1:nrow(Y), ixs)
    )
    write.csv(f_stats_df, "gene_f_statistics.csv", row.names = FALSE)
    
    # Save MSE evaluation results
    mse_df <- data.frame(
      Top_Features = names(mse_res),
      MSE = mse_res
    )
    write.csv(mse_df, "mse_evaluation_results.csv", row.names = FALSE)
    
    # Save all clustering results as an RDS object
    saveRDS(cluster_res, "downstream_clustering_results.rds")
    
    # Identify and save the optimal clustering configuration (minimum MSE)
    opt_top <- names(mse_res)[which.min(mse_res)]
    opt_cluster <- cluster_res[[opt_top]]\$cluster
    optimal_df <- data.frame(
      Cell = colnames(Y),
      Optimal_Cluster = opt_cluster
    )
    write.csv(optimal_df, "optimal_clusters.csv", row.names = FALSE)
    
    # Write a summary text file
    summary_conn <- file("summary_metrics.txt", "w")
    writeLines(c(
      "FEAST Workflow Summary",
      "======================",
      paste("Input cells:", ncol(Y)),
      paste("Input genes (after filtering):", nrow(Y)),
      paste("Number of clusters (k):", k),
      paste("Evaluated feature subsets:", paste(names(mse_res), collapse = ", ")),
      paste("Optimal feature subset (lowest MSE):", opt_top),
      paste("Minimum MSE:", min(mse_res))
    ), summary_conn)
    close(summary_conn)

    writeLines(c(
        '"BIOC_FEAST_STEP_BY_STEP_EVALUATION":',
        paste0('    FEAST: ', as.character(packageVersion('FEAST')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_step_by_step_evaluation.csv versions.yml
    """
}

workflow BIOC_FEAST_STEP_BY_STEP_EVALUATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Y, k ] ]

    main:
    BIOC_FEAST_STEP_BY_STEP_EVALUATION(ch_input)

    emit:
    tables   = BIOC_FEAST_STEP_BY_STEP_EVALUATION.out.tables
    plots    = BIOC_FEAST_STEP_BY_STEP_EVALUATION.out.plots
    objects  = BIOC_FEAST_STEP_BY_STEP_EVALUATION.out.objects
    versions = BIOC_FEAST_STEP_BY_STEP_EVALUATION.out.versions
}
