#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scBubbletree — sc_bubbletree_comparison
// Compare two different bubbletree clustering solutions (e.g., Louvain vs. k-means) visually and quantitatively.
// Input: A
// Container: quay.io/biocontainers/bioconductor-scbubbletree:1.12.0--r45hdfd78af_0
// R packages: ggplot2, ggtree, patchwork, scBubbletree
// Bioconductor: 3.20 | R: 4.4
// Requires: ggplot2, ggtree, patchwork, scBubbletree
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Generate the first bubbletree (Louvain) using
//  * 2. [Core Analysis] Generate the second bubbletree (k-means) using
//  * 3. [Core Analysis] Compare the two bubbletrees using compare_bubbletrees

nextflow.enable.dsl = 2

process BIOC_SCBUBBLETREE_SC_BUBBLETREE_COMPARISON {
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
    .bm_deps <- c("ggplot2", "ggtree", "patchwork", "scBubbletree")
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
    library(scBubbletree)
    library(ggplot2)
    library(ggtree)
    library(patchwork)
    
    # Read user input file 'A' (low-dimensional PCA embedding matrix)
    # Supports RDS or CSV format
    if (file.exists("A.rds")) {
      A <- readRDS("A.rds")
    } else if (file.exists("A.csv")) {
      A <- as.matrix(read.csv("A.csv", row.names = 1))
    } else {
      stop("Required input file 'A.rds' or 'A.csv' not found in the working directory.")
    }
    
    # Ensure A is a matrix
    A <- as.matrix(A)
    
    # Determine optimal resolution r dynamically based on the Gap statistic
    message("Determining optimal resolution r...")
    b_r <- get_r(B_gap = 5,
                 rs = 10^seq(from = -4, to = 0.5, by = 0.5),
                 x = A,
                 n_start = 10,
                 iter_max = 50,
                 algorithm = "original",
                 knn_k = 50,
                 cores = 1)
    
    optimal_r <- b_r\$gap_stats_summary\$r[which.max(b_r\$gap_stats_summary\$gap_mean)]
    
    # --- Generate the first bubbletree (Louvain) using ---
    message("Generating Louvain bubbletree...")
    l <- get_bubbletree_graph(x = A,
                              r = optimal_r,
                              algorithm = "original",
                              n_start = 20,
                              iter_max = 100,
                              knn_k = 50,
                              cores = 1,
                              B = 300,
                              N_eff = 200,
                              round_digits = 1,
                              show_simple_count = FALSE)
    
    # Determine the number of clusters found by Louvain to ensure a balanced comparison
    optimal_k <- length(unique(l\$cluster))
    if (is.null(optimal_k) || optimal_k < 2) {
      optimal_k <- 2
    }
    
    # --- Generate the second bubbletree (k-means) using ---
    message("Generating k-means bubbletree...")
    k <- get_bubbletree_kmeans(x = A,
                               k = optimal_k,
                               cores = 1,
                               B = 300,
                               N_eff = 200,
                               round_digits = 1,
                               show_simple_count = FALSE,
                               kmeans_algorithm = "MacQueen")
    
    # --- Compare the two bubbletrees using compare_bubbletrees ---
    message("Comparing bubbletrees...")
    cp <- compare_bubbletrees(btd_1 = l, 
                              btd_2 = k,
                              ratio_heatmap = 0.6,
                              tile_bw = F,
                              tile_text_size = 3)
    
    # Save RDS objects
    message("Saving RDS outputs...")
    saveRDS(l, "bubbletree_graph.rds")
    saveRDS(k, "bubbletree_kmeans.rds")
    saveRDS(cp, "bubbletree_comparison.rds")
    
    # Save CSV tables
    message("Saving CSV tables...")
    if (!is.null(l\$tree_meta)) {
      write.csv(l\$tree_meta, "tree_meta_graph.csv", row.names = FALSE)
    }
    if (!is.null(k\$tree_meta)) {
      write.csv(k\$tree_meta, "tree_meta_kmeans.csv", row.names = FALSE)
    }
    
    # Save comparison plot
    message("Saving comparison plot...")
    pdf("bubbletree_comparison.pdf", width = 10, height = 8)
    print(cp\$comparison)
    dev.off()
    
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_SCBUBBLETREE_SC_BUBBLETREE_COMPARISON":',
        paste0('    scBubbletree: ', as.character(packageVersion('scBubbletree')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sc_bubbletree_comparison.csv versions.yml
    """
}

workflow BIOC_SCBUBBLETREE_SC_BUBBLETREE_COMPARISON_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ A ] ]

    main:
    BIOC_SCBUBBLETREE_SC_BUBBLETREE_COMPARISON(ch_input)

    emit:
    tables   = BIOC_SCBUBBLETREE_SC_BUBBLETREE_COMPARISON.out.tables
    plots    = BIOC_SCBUBBLETREE_SC_BUBBLETREE_COMPARISON.out.plots
    objects  = BIOC_SCBUBBLETREE_SC_BUBBLETREE_COMPARISON.out.objects
    versions = BIOC_SCBUBBLETREE_SC_BUBBLETREE_COMPARISON.out.versions
}
