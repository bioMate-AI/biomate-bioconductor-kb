#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RGraph2js — interactive_correlation_network
// Build an interactive correlation network from feature-by-sample expression data with customized node/edge properties and in-node barplots.
// Input: input.csv
// Container: 1.38.0--r45hdfd78af_0
// R packages: graph, RGraph2js, sna, xtable
// Bioconductor: 3.20 | R: 4.4
// Requires: RGraph2js
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RGRAPH2JS_INTERACTIVE_CORRELATION_NETWORK {
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
    .bm_deps <- c("graph", "RGraph2js", "sna", "xtable")
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
    library(RGraph2js)
    library(grDevices)
    
    # ==========================================
    # Stage 1: Robust Input Loading & Filtering
    # ==========================================
    
    if (!file.exists("input.csv")) {
        stop("Required input file 'input.csv' not found.")
    }
    
    # Read input defensively
    raw_data <- read.csv("input.csv", stringsAsFactors = FALSE, check.names = FALSE)
    
    # Determine feature identifier column and set row names
    if ("feature_id" %in% colnames(raw_data)) {
        rownames(raw_data) <- raw_data\$feature_id
        raw_data\$feature_id <- NULL
    } else {
        rownames(raw_data) <- raw_data[, 1]
        raw_data <- raw_data[, -1, drop = FALSE]
    }
    
    # Convert to numeric matrix
    mat <- as.matrix(raw_data)
    class(mat) <- "numeric"
    
    # Handle missing values by replacing with row means
    if (any(is.na(mat))) {
        row_means <- rowMeans(mat, na.rm = TRUE)
        na_idx <- which(is.na(mat), arr.ind = TRUE)
        mat[na_idx] <- row_means[na_idx[, 1]]
    }
    
    # Filter to top N most variable features to keep the network readable and performant
    top_n <- 30
    if (nrow(mat) > top_n) {
        row_vars <- apply(mat, 1, var, na.rm = TRUE)
        # Handle potential zero variance
        row_vars[is.na(row_vars)] <- 0
        top_idx <- order(row_vars, decreasing = TRUE)[1:top_n]
        mat <- mat[top_idx, , drop = FALSE]
    }
    
    # ==========================================
    # Stage 2: Network Construction (Correlation)
    # ==========================================
    
    # Compute pairwise Pearson correlation matrix
    adj_mat <- cor(t(mat), use = "pairwise.complete.obs")
    adj_mat[is.na(adj_mat)] <- 0
    
    # Apply threshold to define edges
    threshold <- 0.4
    adj_mat[abs(adj_mat) < threshold] <- 0
    
    # Remove self-loops
    diag(adj_mat) <- 0
    
    # Ensure there is at least one edge; if not, force-connect the top correlated pair
    if (all(adj_mat == 0) && nrow(adj_mat) > 1) {
        temp_cor <- cor(t(mat), use = "pairwise.complete.obs")
        diag(temp_cor) <- 0
        max_idx <- which(abs(temp_cor) == max(abs(temp_cor)), arr.ind = TRUE)[1, ]
        adj_mat[max_idx[1], max_idx[2]] <- temp_cor[max_idx[1], max_idx[2]]
        adj_mat[max_idx[2], max_idx[1]] <- temp_cor[max_idx[2], max_idx[1]]
    }
    
    # ==========================================
    # Stage 3: Node and Edge Customization
    # ==========================================
    
    # Calculate node metrics
    node_names <- rownames(adj_mat)
    node_degrees <- rowSums(adj_mat != 0)
    mean_expr <- rowMeans(mat)
    
    # Map mean expression to a color gradient (blue to red)
    color_palette <- colorRampPalette(c("#3182bd", "#e6550d"))(100)
    scaled_expr <- round((mean_expr - min(mean_expr)) / (max(mean_expr) - min(mean_expr) + 1e-5) * 99) + 1
    node_colors <- color_palette[scaled_expr]
    
    # Map degree to node shapes (high degree = rectangle, low degree = circle)
    node_shapes <- ifelse(node_degrees > mean(node_degrees), "rect", "circle")
    
    # Create node properties data frame
    nodes_prop <- data.frame(
        color = node_colors,
        shape = node_shapes,
        tooltip = paste0("<strong>Feature:</strong> ", node_names, 
                         "<br/><strong>Mean Expr:</strong> ", round(mean_expr, 2),
                         "<br/><strong>Degree:</strong> ", node_degrees),
        stringsAsFactors = FALSE
    )
    rownames(nodes_prop) <- node_names
    
    # Create edge properties data frame
    edges_base <- getEdgesDataFrame(adj_mat)
    edges_prop <- data.frame(
        from = edges_base\$from,
        to = edges_base\$to,
        width = abs(edges_base\$type) * 4, # Scale width by correlation strength
        color = ifelse(edges_base\$type > 0, "#3182bd", "#de2d26"), # Blue for positive, Red for negative
        stringsAsFactors = FALSE
    )
    
    # ==========================================
    # Stage 4: In-Node Barplot Data Preparation
    # ==========================================
    
    # Scale sample values to [0, 1] for barplot rendering inside nodes
    inner_values <- t(apply(mat, 1, function(x) {
        if (max(x) == min(x)) return(rep(0.5, length(x)))
        (x - min(x)) / (max(x) - min(x))
    }))
    rownames(inner_values) <- node_names
    
    # Generate a color palette for the samples
    sample_colors <- rainbow(ncol(mat))
    inner_colors <- matrix(sample_colors, nrow = nrow(mat), ncol = ncol(mat), byrow = TRUE)
    rownames(inner_colors) <- node_names
    
    # ==========================================
    # Stage 5: Interactive HTML Generation
    # ==========================================
    
    # Set up output directory
    output_dir <- "interactive_network"
    if (!dir.exists(output_dir)) {
        dir.create(output_dir, recursive = TRUE)
    }
    
    # Configure visualization options
    opts <- getDefaultOptions()
    opts\$displayBarPlotsInsideNodes <- TRUE
    opts\$barplotInNodeTooltips <- TRUE
    opts\$displayNodeLabels <- TRUE
    opts\$layout_forceCharge <- -800
    
    # Generate the interactive web page
    g <- graph2js(
        A = adj_mat,
        nodesProp = nodes_prop,
        edgesProp = edges_prop,
        innerValues = inner_values,
        innerColors = inner_colors,
        opts = opts,
        outputDir = output_dir,
        filename = "index.html"
    )
    
    # ==========================================
    # Stage 6: Export Summary Tables
    # ==========================================
    
    # Write node properties summary
    write.csv(nodes_prop, file = "network_nodes.csv", row.names = TRUE)
    
    # Write edge properties summary
    write.csv(edges_prop, file = "network_edges.csv", row.names = FALSE)
    
    cat("Pipeline completed successfully. Interactive network generated in 'interactive_network/index.html'.\n")

    writeLines(c(
        '"BIOC_RGRAPH2JS_INTERACTIVE_CORRELATION_NETWORK":',
        paste0('    RGraph2js: ', as.character(packageVersion('RGraph2js')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_interactive_correlation_network.csv versions.yml
    """
}

workflow BIOC_RGRAPH2JS_INTERACTIVE_CORRELATION_NETWORK_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_RGRAPH2JS_INTERACTIVE_CORRELATION_NETWORK(ch_input)

    emit:
    tables   = BIOC_RGRAPH2JS_INTERACTIVE_CORRELATION_NETWORK.out.tables
    plots    = BIOC_RGRAPH2JS_INTERACTIVE_CORRELATION_NETWORK.out.plots
    objects  = BIOC_RGRAPH2JS_INTERACTIVE_CORRELATION_NETWORK.out.objects
    versions = BIOC_RGRAPH2JS_INTERACTIVE_CORRELATION_NETWORK.out.versions
}
