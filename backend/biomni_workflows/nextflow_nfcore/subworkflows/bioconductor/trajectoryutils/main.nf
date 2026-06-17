#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: TrajectoryUtils — trajectory_utils_mst_analysis
// Perform single-cell trajectory backbone construction and pseudotime ordering using TrajectoryUtils.
// Input: counts.csv, coldata.csv
// Container: 1.18.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocGenerics, S4Vectors, TrajectoryUtils
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TRAJECTORYUTILS_TRAJECTORY_UTILS_MST_ANALYSIS {
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
    .bm_deps <- c("TrajectoryUtils", "S4Vectors", "BiocGenerics")
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
    library(TrajectoryUtils)
    library(S4Vectors)
    library(BiocGenerics)
    
    # --- Read Input Data ---
    if (!file.exists("counts.csv") || !file.exists("coldata.csv")) {
        stop("Required input files 'counts.csv' and/or 'coldata.csv' are missing.")
    }
    
    counts <- read.csv("counts.csv", row.names = 1, check.names = FALSE)
    coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
    
    # Ensure sample alignment
    common_samples <- intersect(colnames(counts), coldata\$sample)
    if (length(common_samples) == 0) {
        stop("No overlapping samples found between counts.csv and coldata.csv.")
    }
    counts <- counts[, common_samples, drop = FALSE]
    coldata <- coldata[match(common_samples, coldata\$sample), , drop = FALSE]
    
    # --- Normalization and Dimensionality Reduction (PCA) ---
    # Simple CPM-like normalization and log-transformation
    lib_sizes <- colSums(counts)
    lib_sizes[lib_sizes == 0] <- 1 # Avoid division by zero
    norm_counts <- log2(t(t(counts) / lib_sizes * 1e6) + 1)
    
    # Filter out zero-variance genes
    gene_vars <- apply(norm_counts, 1, var)
    keep_genes <- gene_vars > 0
    if (sum(keep_genes) < 10) {
        stop("Too few genes with non-zero variance for PCA.")
    }
    norm_counts <- norm_counts[keep_genes, , drop = FALSE]
    
    # Run PCA
    pca_res <- prcomp(t(norm_counts), scale. = TRUE)
    pcs <- pca_res\$x[, 1:min(5, ncol(pca_res\$x)), drop = FALSE]
    
    # --- Clustering ---
    # Define clusters using k-means on PCA space
    n_clusters <- min(4, nrow(pcs))
    set.seed(42)
    clusters <- as.character(kmeans(pcs, centers = n_clusters)\$cluster)
    names(clusters) <- rownames(pcs)
    
    # --- Construct Minimum Spanning Tree (MST) ---
    # Compute cluster centroids robustly using rowmean or fallback
    compute_centroids <- function(pcs, clusters) {
        tryCatch({
            # TrajectoryUtils::rowmean groups columns of a matrix
            t(TrajectoryUtils::rowmean(t(pcs), clusters))
        }, error = function(e) {
            # Fallback to base R split and colMeans
            spl <- split(as.data.frame(pcs), clusters)
            do.call(rbind, lapply(spl, colMeans))
        })
    }
    centroids <- compute_centroids(pcs, clusters)
    
    # Create MST
    mst <- createClusterMST(pcs, clusters)
    
    # Save MST Plot
    pdf("mst_plot.pdf", width = 7, height = 7)
    plot(mst, main = "Cluster-level Minimum Spanning Tree (MST)")
    dev.off()
    
    # --- Define Paths and Roots ---
    # Guess root node maximizing steps to terminal nodes
    root_node <- guessMSTRoots(mst, method = "maxstep")
    
    # Define paths from the root
    paths <- defineMSTPaths(mst, roots = root_node)
    branches <- splitByBranches(mst)
    
    # --- Compute Pseudotime and Build PseudotimeOrdering ---
    n_cells <- nrow(pcs)
    n_paths <- length(paths)
    orderings <- matrix(NA_real_, nrow = n_cells, ncol = n_paths)
    colnames(orderings) <- paste0("Path", seq_len(n_paths))
    rownames(orderings) <- rownames(pcs)
    
    # Calculate distance-based pseudotime along each path
    for (j in seq_len(n_paths)) {
        path_clusters <- paths[[j]]
        root_cluster <- path_clusters[1]
        root_centroid <- centroids[root_cluster, , drop = FALSE]
        
        # Identify cells belonging to clusters in this path
        in_path <- clusters %in% path_clusters
        if (any(in_path)) {
            # Distance to root centroid as a proxy for pseudotime
            diffs <- sweep(pcs[in_path, , drop = FALSE], 2, root_centroid, "-")
            dists <- sqrt(rowSums(diffs^2))
            orderings[in_path, j] <- dists
        }
    }
    
    # Construct PseudotimeOrdering object
    pto <- PseudotimeOrdering(orderings)
    
    # Annotate cell metadata
    cellnames(pto) <- rownames(pcs)
    pto\$condition <- coldata\$condition
    pto\$cluster <- clusters
    
    # Annotate path metadata
    pathnames(pto) <- colnames(orderings)
    path_desc <- sapply(paths, function(p) paste(p, collapse = " -> "))
    pathData(pto)\$description <- path_desc
    
    # Add path statistics (e.g., dummy confidence scores)
    conf_matrix <- matrix(runif(n_cells * n_paths), n_cells, n_paths)
    pathStat(pto, "confidence") <- conf_matrix
    
    # Compute average pseudotime across paths
    avg_pseudo <- averagePseudotime(pto)
    
    # --- Save Results ---
    # Save path definitions
    path_df <- data.frame(
        Path = colnames(orderings),
        Trajectory = path_desc,
        stringsAsFactors = FALSE
    )
    write.csv(path_df, "path_definitions.csv", row.names = FALSE)
    
    # Save cell-level pseudotime results
    results_df <- data.frame(
        CellID = cellnames(pto),
        Cluster = pto\$cluster,
        Condition = pto\$condition,
        AveragePseudotime = avg_pseudo,
        as.data.frame(pathStats(pto)[[""]]), # Extract the default pseudotime matrix
        stringsAsFactors = FALSE
    )
    write.csv(results_df, "pseudotime_results.csv", row.names = FALSE)
    
    message("Trajectory analysis completed successfully.")

    writeLines(c(
        '"BIOC_TRAJECTORYUTILS_TRAJECTORY_UTILS_MST_ANALYSIS":',
        paste0('    TrajectoryUtils: ', as.character(packageVersion('TrajectoryUtils')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_trajectory_utils_mst_analysis.csv versions.yml
    """
}

workflow BIOC_TRAJECTORYUTILS_TRAJECTORY_UTILS_MST_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_TRAJECTORYUTILS_TRAJECTORY_UTILS_MST_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_TRAJECTORYUTILS_TRAJECTORY_UTILS_MST_ANALYSIS.out.tables
    plots    = BIOC_TRAJECTORYUTILS_TRAJECTORY_UTILS_MST_ANALYSIS.out.plots
    objects  = BIOC_TRAJECTORYUTILS_TRAJECTORY_UTILS_MST_ANALYSIS.out.objects
    versions = BIOC_TRAJECTORYUTILS_TRAJECTORY_UTILS_MST_ANALYSIS.out.versions
}
