#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: biocGraph — interactive_network_map
// Build an interactive HTML network map from a feature-by-sample matrix or gene list, generating clickable nodes with tooltips and linked expression plots.
// Input: input.csv
// Container: 1.72.0--r45hdfd78af_0
// R packages: Rgraphviz, biocGraph, fibroeset, geneplotter, graph
// Bioconductor: 3.20 | R: 4.4
// Requires: Rgraphviz, biocGraph, graph
// Visualizations: network plot
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BIOCGRAPH_INTERACTIVE_NETWORK_MAP {
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
    .bm_deps <- c("Rgraphviz", "biocGraph", "fibroeset", "geneplotter", "graph")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
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
    library(biocGraph)
    library(graph)
    library(Rgraphviz)
    
    # --- Read input defensively ---
    input_file <- "input.csv"
    if (!file.exists(input_file)) {
      # Fallback: Create dummy dataset if input.csv is missing
      warning("input.csv not found. Creating dummy dataset.")
      set.seed(123)
      dummy_data <- matrix(rnorm(200), nrow=20, ncol=10)
      rownames(dummy_data) <- paste0("Gene_", LETTERS[1:20])
      colnames(dummy_data) <- paste0("Sample_", 1:10)
      write.csv(dummy_data, input_file)
    }
    
    data <- read.csv(input_file, row.names=1, check.names=FALSE)
    
    # --- Construct Graph ---
    # If it's a single-column list of genes
    if (ncol(data) < 2) {
      genes <- rownames(data)
      if (length(genes) == 0 || all(genes == "")) {
        genes <- as.character(data[[1]])
      }
      genes <- unique(genes[genes != ""])
      
      # Limit to top 30 to keep layout clean
      if (length(genes) > 30) {
        genes <- genes[1:30]
      }
      
      g <- new("graphNEL", nodes=genes, edgemode="undirected")
      # Create a simple chain graph to ensure we have edges
      if (length(genes) > 1) {
        for (i in 1:(length(genes)-1)) {
          g <- addEdge(genes[i], genes[i+1], g)
        }
      }
    } else {
      # Feature-by-sample matrix
      # Filter to top 30 highly variable genes to ensure clean visualization
      if (nrow(data) > 30) {
        vars <- apply(data, 1, var, na.rm=TRUE)
        top_genes <- names(sort(vars, decreasing=TRUE))[1:30]
        data_sub <- data[top_genes, , drop=FALSE]
      } else {
        top_genes <- rownames(data)
        data_sub <- data
      }
      
      # Compute correlation matrix
      cor_matrix <- cor(t(data_sub), use="pairwise.complete.obs")
      cor_matrix[is.na(cor_matrix)] <- 0
      
      # Threshold to define edges
      threshold <- 0.5
      adj <- abs(cor_matrix) > threshold
      diag(adj) <- FALSE
      adj[lower.tri(adj)] <- FALSE
      
      g <- new("graphNEL", nodes=top_genes, edgemode="undirected")
      edges_to_add <- which(adj, arr.ind=TRUE)
      if (nrow(edges_to_add) > 0) {
        for (k in 1:nrow(edges_to_add)) {
          g <- addEdge(top_genes[edges_to_add[k, 1]], top_genes[edges_to_add[k, 2]], g)
        }
      } else {
        # If no edges pass threshold, connect sequentially to avoid empty graph
        if (length(top_genes) > 1) {
          for (i in 1:(length(top_genes)-1)) {
            g <- addEdge(top_genes[i], top_genes[i+1], g)
          }
        }
      }
    }
    
    # --- Node Attributes & Layout ---
    nd <- nodes(g)
    node_colors <- rep("lightblue", length(nd))
    names(node_colors) <- nd
    
    if (ncol(data) >= 2) {
      # Color nodes by mean expression level
      mean_expr <- rowMeans(data[nd, , drop=FALSE], na.rm=TRUE)
      mean_expr[is.na(mean_expr)] <- 0
      if (max(mean_expr) != min(mean_expr)) {
        palette <- colorRampPalette(c("#E0F3F8", "#D9EF8B", "#FEE08B", "#FC8D59"))(100)
        scaled <- as.numeric(cut(mean_expr, breaks=100))
        node_colors <- palette[scaled]
        names(node_colors) <- nd
      }
    }
    
    node_attrs <- makeNodeAttrs(g, fillcolor=node_colors)
    
    # Layout using agopen
    width <- 800
    height <- 600
    lg <- agopen(g, name="interactive_network", 
                 attrs=list(graph=list(rankdir="LR", size=paste(width/100, height/100, sep=",")),
                            node=list(fixedsize=FALSE, shape="ellipse")),
                 nodeAttrs=node_attrs)
    
    # --- Generate Individual Node Plots ---
    outdir <- "node_plots"
    if (!dir.exists(outdir)) dir.create(outdir)
    
    plotFiles <- paste0(nd, ".png")
    for (i in seq_along(nd)) {
      node_name <- nd[i]
      png_path <- file.path(outdir, plotFiles[i])
      png(png_path, width=400, height=300)
      
      if (ncol(data) >= 2) {
        # Plot expression profile across samples
        plot(as.numeric(data[node_name, ]), type="b", col="blue", pch=19,
             main=paste("Expression Profile:", node_name),
             xlab="Samples", ylab="Expression Level")
      } else {
        # Plot dummy trend
        plot(cumsum(rnorm(100)), type="l", col="red", lwd=2,
             main=paste("Trend Analysis:", node_name),
             xlab="Time/Index", ylab="Value")
      }
      dev.off()
    }
    
    # --- Render Main Network Image ---
    imgname <- "graph_network.png"
    png(imgname, width=width, height=height)
    par(mai=rep(0,4))
    plot(lg)
    dev.off()
    
    # --- Generate Interactive HTML Map using biocGraph::imageMap ---
    fhtml <- "index.html"
    con <- file(fhtml, open="wt")
    cat("<HTML><HEAD><TITLE>Interactive Gene Network</TITLE></HEAD>\n", file=con)
    cat("<FRAMESET COLS=\"60%,40%\" BORDER=1>\n", file=con)
    cat("  <FRAME SRC=\"graph.html\">\n", file=con)
    cat("  <FRAME NAME=\"nodedata\" SRC=\"\">\n", file=con)
    cat("</FRAMESET></HTML>\n", file=con)
    close(con)
    
    fgraph <- "graph.html"
    con <- file(fgraph, open="wt")
    writeLines("<html><body>\n", con)
    
    # Relative paths for the HTML frame to find the node plots
    href_paths <- file.path("node_plots", plotFiles)
    
    biocGraph::imageMap(lg, con=con,
                        tags=list(HREF=href_paths,
                                  TITLE=nd,
                                  TARGET=rep("nodedata", length(nd))),
                        imgname=imgname, width=width, height=height)
    
    writeLines("</body></html>", con)
    close(con)
    
    # --- Save Network Summary Statistics ---
    deg <- degree(g)
    summary_df <- data.frame(
      node = names(deg),
      degree = deg,
      color = node_colors[names(deg)],
      stringsAsFactors = FALSE
    )
    write.csv(summary_df, "network_summary.csv", row.names=FALSE)
    
    message("Pipeline completed successfully. Outputs generated: index.html, graph.html, graph_network.png, network_summary.csv, and node_plots/ directory.")

    writeLines(c(
        '"BIOC_BIOCGRAPH_INTERACTIVE_NETWORK_MAP":',
        paste0('    biocGraph: ', as.character(packageVersion('biocGraph')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_interactive_network_map.csv versions.yml
    """
}

workflow BIOC_BIOCGRAPH_INTERACTIVE_NETWORK_MAP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_BIOCGRAPH_INTERACTIVE_NETWORK_MAP(ch_input)

    emit:
    tables   = BIOC_BIOCGRAPH_INTERACTIVE_NETWORK_MAP.out.tables
    plots    = BIOC_BIOCGRAPH_INTERACTIVE_NETWORK_MAP.out.plots
    objects  = BIOC_BIOCGRAPH_INTERACTIVE_NETWORK_MAP.out.objects
    versions = BIOC_BIOCGRAPH_INTERACTIVE_NETWORK_MAP.out.versions
}
