#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: findIPs — binary_or_continuous_outcome_ip_detection
// Detect influential points affecting feature rankings for binary or continuous outcomes using t-test, Kruskal-Wallis, or custom ranking functions.
// Input: expression_matrix.csv, phenotype_labels.csv
// Container: quay.io/biocontainers/bioconductor-findips:1.6.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: findIPs
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Generate original and leave-one-out rankings using getdrop1ranks()
//  * 2. [Core Analysis] Calculate cumulative rank changes using sumRanks()
//  * 3. [Core Analysis] Run the complete detection in one step using findIPs()
//  * 4. [Visualization & Output] Visualize influential points, rank scatters, and adaptive weights using plotIPs(), plotRankScatters(), and plotAdaptiveWeights()

nextflow.enable.dsl = 2

process BIOC_FINDIPS_BINARY_OR_CONTINUOUS_OUTCOME_IP_DETECTION {
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
    library(findIPs)
    
    # -----------------------------------------------------------------------------
    # Stage 0: Read User Input Files
    # -----------------------------------------------------------------------------
    if (!file.exists("expression_matrix.csv") || !file.exists("phenotype_labels.csv")) {
      stop("Required input files 'expression_matrix.csv' and/or 'phenotype_labels.csv' are missing in the working directory.")
    }
    
    # Read expression matrix (samples as rows, genes as columns)
    X_df <- read.csv("expression_matrix.csv", row.names = 1, check.names = FALSE)
    X <- as.matrix(X_df)
    
    # Read phenotype labels
    y_df <- read.csv("phenotype_labels.csv", header = TRUE)
    if (ncol(y_df) >= 2) {
      y <- y_df[[2]]
      names(y) <- y_df[[1]]
    } else {
      y <- y_df[[1]]
      names(y) <- rownames(X)
    }
    
    # Align samples between expression matrix and phenotype labels
    common_samples <- intersect(rownames(X), names(y))
    if (length(common_samples) == 0) {
      stop("No matching sample IDs found between expression_matrix.csv and phenotype_labels.csv.")
    }
    X <- X[common_samples, , drop = FALSE]
    y <- y[common_samples]
    
    # Ensure y is a factor if it represents binary groups (required for t.test)
    # Dynamically set the ranking function based on phenotype type
    if (length(unique(y)) == 2) {
      y <- as.factor(y)
      my_fun <- "t.test"
    } else {
      my_fun <- function(x, y) { cor.test(x, y)\$p.value }
    }
    
    # Dynamically set the number of top features to avoid errors with small datasets
    n_features <- min(100, ncol(X))
    
    # -----------------------------------------------------------------------------
    # Stage 1: Generate original and leave-one-out rankings using getdrop1ranks()
    # -----------------------------------------------------------------------------
    obj <- getdrop1ranks(X, y,
                         fun = my_fun,
                         decreasing = FALSE,
                         topN = n_features)
    str(obj)
    
    # -----------------------------------------------------------------------------
    # Stage 2: Calculate cumulative rank changes using sumRanks()
    # -----------------------------------------------------------------------------
    results <- sumRanks(origRank = obj\$origRank,
                        drop1Rank = obj\$drop1Rank,
                        topN = n_features,
                        method = "adaptive")
    str(results)
    
    # -----------------------------------------------------------------------------
    # Stage 3: Run the complete detection in one step using findIPs()
    # -----------------------------------------------------------------------------
    results.ipsr <- findIPs(X, y, 
                            fun = my_fun,
                            decreasing = FALSE,
                            method = "adaptive")
    
    # Verify consistency between two-step and one-step approaches
    identical_check <- identical(results, results.ipsr)
    message("Two-step and one-step results are identical: ", identical_check)
    
    # -----------------------------------------------------------------------------
    # Stage 4: Visualize influential points, rank scatters, and adaptive weights
    # -----------------------------------------------------------------------------
    pdf("influential_points_plots.pdf", width = 8, height = 6)
    
    # Plot 1: Lollipop plot of influence scores
    par(mar = c(4, 4, 2, 2))
    plotIPs(results.ipsr, topn = 5)
    
    # Plot 2: Scatter plot of rank changes
    par(mar = c(4, 4, 2, 2))
    plotRankScatters(results.ipsr)
    
    # Plot 3: Adaptive weights function
    par(mar = c(4, 4, 2, 2))
    plotAdaptiveWeights(results.ipsr\$kappa, n = n_features, type = "line")
    
    dev.off()
    
    # -----------------------------------------------------------------------------
    # Stage 5: Customize the rank criteria (Kruskal-Wallis)
    # -----------------------------------------------------------------------------
    fun <- function(x, y){
      kruskal.test(x, y)\$p.value
    }
    
    kruskal.test1 <- getdrop1ranks(X, y, 
                                   fun = fun, 
                                   decreasing = FALSE)
    
    kruskal.test2 <- getdrop1ranks(X, y, 
                                   fun = "kruskal.test", 
                                   decreasing = FALSE)
    
    identical_kruskal <- identical(kruskal.test1, kruskal.test2)
    message("Custom Kruskal-Wallis and built-in Kruskal-Wallis results are identical: ", identical_kruskal)
    
    # -----------------------------------------------------------------------------
    # Stage 6: Comparison of rank comparison methods
    # -----------------------------------------------------------------------------
    re.unweighted <- findIPs(X, y, 
                             fun = my_fun,
                             decreasing = FALSE,
                             method = "unweighted")
    re.weighted <- findIPs(X, y, 
                           fun = my_fun,
                           decreasing = FALSE,
                           method = "weightedSpearman")
    re.adaptive <- findIPs(X, y, 
                           fun = my_fun,
                           decreasing = FALSE,
                           method = "adaptive")
    
    pdf("method_comparison_plots.pdf", width = 12, height = 5)
    par(mfrow = c(1, 3), mar = c(4, 4, 2, 2))
    plotIPs(re.unweighted)
    mtext("A, unweighted", side = 3, line = 0, adj = 0)
    plotIPs(re.weighted)
    mtext("B, weighted Spearman", side = 3, line = 0, adj = 0)
    plotIPs(re.adaptive)
    mtext("C, adaptive weights", side = 3, line = 0, adj = 0)
    dev.off()
    
    # -----------------------------------------------------------------------------
    # Stage 7: Save Outputs
    # -----------------------------------------------------------------------------
    # Save the main results object
    saveRDS(results.ipsr, "findIPs_results.rds")
    
    # Save influence scores to CSV
    scores_df <- data.frame(
      Sample = names(results.ipsr\$score),
      InfluenceScore = results.ipsr\$score,
      stringsAsFactors = FALSE
    )
    write.csv(scores_df, "influence_scores.csv", row.names = FALSE)
    
    # Save original feature rankings to CSV
    ranks_df <- data.frame(
      Rank = seq_along(results.ipsr\$origRank),
      Feature = results.ipsr\$origRank,
      stringsAsFactors = FALSE
    )
    write.csv(ranks_df, "original_feature_ranks.csv", row.names = FALSE)
    
    message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_FINDIPS_BINARY_OR_CONTINUOUS_OUTCOME_IP_DETECTION":',
        paste0('    findIPs: ', as.character(packageVersion('findIPs')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_binary_or_continuous_outcome_ip_detection.csv versions.yml
    """
}

workflow BIOC_FINDIPS_BINARY_OR_CONTINUOUS_OUTCOME_IP_DETECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.csv, phenotype_labels.csv ] ]

    main:
    BIOC_FINDIPS_BINARY_OR_CONTINUOUS_OUTCOME_IP_DETECTION(ch_input)

    emit:
    tables   = BIOC_FINDIPS_BINARY_OR_CONTINUOUS_OUTCOME_IP_DETECTION.out.tables
    plots    = BIOC_FINDIPS_BINARY_OR_CONTINUOUS_OUTCOME_IP_DETECTION.out.plots
    objects  = BIOC_FINDIPS_BINARY_OR_CONTINUOUS_OUTCOME_IP_DETECTION.out.objects
    versions = BIOC_FINDIPS_BINARY_OR_CONTINUOUS_OUTCOME_IP_DETECTION.out.versions
}
