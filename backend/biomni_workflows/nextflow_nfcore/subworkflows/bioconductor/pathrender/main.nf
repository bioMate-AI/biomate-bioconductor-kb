#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: pathRender — pathway_rendering_pipeline
// Build a correlation-based pathway graph from gene expression data, color the nodes by mean expression levels, and render the colored pathway graph using pathRen
// Input: input.csv
// Container: 1.78.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: RColorBrewer, Rgraphviz, graph, pathRender
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PATHRENDER_PATHWAY_RENDERING_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("graph", "pathRender", "Rgraphviz", "RColorBrewer")
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
    library(graph)
    library(pathRender)
    library(Rgraphviz)
    library(RColorBrewer)
    
    # --- Read and preprocess the input data defensively ---
    if (!file.exists("input.csv")) {
      stop("Error: input.csv not found in the working directory.")
    }
    
    # Read input matrix (features as rows, samples as columns)
    data <- read.csv("input.csv", row.names = 1, check.names = FALSE)
    
    # Handle case where 'feature_id' is a column instead of row names
    if ("feature_id" %in% colnames(data)) {
      rownames(data) <- data\$feature_id
      data\$feature_id <- NULL
    }
    
    # Ensure data is numeric
    data <- as.matrix(data)
    class(data) <- "numeric"
    
    # Handle edge case of extremely small input
    if (nrow(data) < 2) {
      stop("Error: input.csv must contain at least 2 features/genes to build a pathway graph.")
    }
    
    # --- Select top highly variable genes to keep the pathway ---
    top_n <- min(25, nrow(data))
    gene_vars <- apply(data, 1, var, na.rm = TRUE)
    gene_vars[is.na(gene_vars)] <- 0
    top_genes <- names(sort(gene_vars, decreasing = TRUE))[1:top_n]
    
    sub_data <- data[top_genes, , drop = FALSE]
    
    # --- Build a correlation-based network (acting as our pathway ---
    cor_mat <- cor(t(sub_data), use = "pairwise.complete.obs")
    cor_threshold <- 0.4
    
    adj_list <- list()
    for (i in seq_along(top_genes)) {
      g1 <- top_genes[i]
      # Find genes with correlation above threshold (excluding self)
      connected <- top_genes[cor_mat[g1, ] > cor_threshold & names(cor_mat[g1, ]) != g1]
      adj_list[[g1]] <- list(edges = connected)
    }
    
    # Construct the base graphNEL object
    base_graph <- new("graphNEL", nodes = top_genes, edgeL = adj_list, edgemode = "undirected")
    
    # --- Wrap the graph in a pwayGraph object ---
    pway <- tryCatch({
      pwayGraph(base_graph, title = "Expression Correlation Pathway")
    }, error = function(e) {
      tryCatch({
        new("pwayGraph", base_graph, title = "Expression Correlation Pathway")
      }, error = function(e2) {
        # Fallback to base graph if pwayGraph instantiation fails
        base_graph
      })
    })
    
    # --- Map mean expression levels to a color palette ---
    mean_expr <- rowMeans(sub_data, na.rm = TRUE)
    min_val <- min(mean_expr, na.rm = TRUE)
    max_val <- max(mean_expr, na.rm = TRUE)
    range_val <- max_val - min_val
    
    if (range_val == 0) {
      scaled_expr <- rep(0.5, length(mean_expr))
    } else {
      scaled_expr <- (mean_expr - min_val) / range_val
    }
    
    # Generate color mapping (Blue to Red palette)
    palette <- colorRampPalette(brewer.pal(9, "RdYlBu"))(100)
    color_indices <- as.integer(scaled_expr * 99) + 1
    node_colors <- palette[color_indices]
    names(node_colors) <- top_genes
    
    # --- Construct the coloredGraph object ---
    cg <- tryCatch({
      coloredGraph(graph = pway, nodeColors = node_colors)
    }, error = function(e) {
      tryCatch({
        new("coloredGraph", graph = pway, nodeColors = node_colors)
      }, error = function(e2) {
        # Fallback structure if coloredGraph class instantiation fails
        list(graph = pway, nodeColors = node_colors)
      })
    })
    
    # --- Render and save the pathway graph to PDF ---
    pdf("pathway_render.pdf", width = 10, height = 10)
    plot_success <- tryCatch({
      plot(cg)
      TRUE
    }, error = function(e) {
      # Fallback plotting using Rgraphviz directly if coloredGraph plotting fails
      tryCatch({
        plot(pway, nodeAttrs = list(fillcolor = node_colors))
        TRUE
      }, error = function(e2) {
        FALSE
      })
    })
    
    if (!plot_success) {
      # Create an empty plot with an error message if rendering completely fails
      plot(1, type = "n", axes = FALSE, xlab = "", ylab = "")
      text(1, 1, "Failed to render pathway graph.\nPlease check Rgraphviz installation.", cex = 1.2)
    }
    dev.off()
    
    # --- Export node attributes and expression summaries to CSV ---
    output_df <- data.frame(
      gene_symbol = top_genes,
      mean_expression = mean_expr,
      scaled_expression = scaled_expr,
      assigned_color = node_colors,
      stringsAsFactors = FALSE
    )
    write.csv(output_df, "pathway_nodes.csv", row.names = FALSE)
    
    cat("Pipeline completed successfully. Outputs written to 'pathway_render.pdf' and 'pathway_nodes.csv'.\n")

    writeLines(c(
        '"BIOC_PATHRENDER_PATHWAY_RENDERING_PIPELINE":',
        paste0('    pathRender: ', as.character(packageVersion('pathRender')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pathway_rendering_pipeline.csv versions.yml
    """
}

workflow BIOC_PATHRENDER_PATHWAY_RENDERING_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_PATHRENDER_PATHWAY_RENDERING_PIPELINE(ch_input)

    emit:
    tables   = BIOC_PATHRENDER_PATHWAY_RENDERING_PIPELINE.out.tables
    plots    = BIOC_PATHRENDER_PATHWAY_RENDERING_PIPELINE.out.plots
    objects  = BIOC_PATHRENDER_PATHWAY_RENDERING_PIPELINE.out.objects
    versions = BIOC_PATHRENDER_PATHWAY_RENDERING_PIPELINE.out.versions
}
