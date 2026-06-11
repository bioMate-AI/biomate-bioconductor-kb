#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: pageRank — graph_cleaning_and_adjustment
// Clean a graph by removing small subgraphs and adjust PageRank calculations with updated parameters.
// Input: raw_graph.RData
// Container: quay.io/biocontainers/bioconductor-pagerank:1.20.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: igraph, pageRank
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Clean the graph using clean_graph based on subgraph size
//  * 2. [Core Analysis] Recalculate/adjust PageRank using adjust_graph with a new damping factor

nextflow.enable.dsl = 2

process BIOC_PAGERANK_GRAPH_CLEANING_AND_ADJUSTMENT {
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
    .bm_deps <- c("pageRank", "igraph")
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
        library(pageRank)
        library(igraph)
        
        # Input file validation
        input_file <- "raw_graph.RData"
        if (!file.exists(input_file)) {
          stop(paste("Required input file missing:", input_file))
        }
        
        # Load the input RData file into a clean environment
        env <- new.env()
        load(input_file, envir = env)
        
        # Find the igraph object in the loaded environment
        objs <- ls(env)
        graph_var <- NULL
        for (o in objs) {
          if (inherits(env[[o]], "igraph")) {
            graph_var <- o
            break
          }
        }
        
        if (is.null(graph_var)) {
          stop("No igraph object found in raw_graph.RData")
        }
        
        graph <- env[[graph_var]]
        
        # Ensure required vertex attributes exist (fallback to defaults if missing)
        if (is.null(V(graph)\$name)) {
          V(graph)\$name <- as.character(seq_len(gorder(graph)))
        }
        if (is.null(V(graph)\$pagerank)) {
          V(graph)\$pagerank <- page_rank(graph)\$vector
        }
        
        # Stage 1: Clean the graph using clean_graph based on subgraph size
        cleaned_graph <- clean_graph(graph, size = 5)
        
        # Stage 2: Recalculate/adjust PageRank using adjust_graph with a new damping factor
        adjusted_graph <- adjust_graph(cleaned_graph, damping = 0.1)
        
        # Save RDS objects of the resulting graphs
        saveRDS(cleaned_graph, file = "cleaned_graph.rds")
        saveRDS(adjusted_graph, file = "adjusted_graph.rds")
        
        # Export vertex properties as CSV tables
        cleaned_df <- data.frame(
          vertex_name = V(cleaned_graph)\$name,
          pagerank = V(cleaned_graph)\$pagerank,
          stringsAsFactors = FALSE
        )
        write.csv(cleaned_df, file = "cleaned_vertices.csv", row.names = FALSE)
        
        adjusted_df <- data.frame(
          vertex_name = V(adjusted_graph)\$name,
          pagerank = V(adjusted_graph)\$pagerank,
          stringsAsFactors = FALSE
        )
        write.csv(adjusted_df, file = "adjusted_vertices.csv", row.names = FALSE)
        
        # Generate a PDF plot comparing PageRank distributions
        pdf("pagerank_comparison.pdf", width = 10, height = 5)
        par(mfrow = c(1, 2))
        
        # Plot 1: Cleaned Graph PageRank Distribution
        if (nrow(cleaned_df) > 0) {
          hist(cleaned_df\$pagerank, 
               main = "Cleaned Graph PageRank", 
               xlab = "PageRank Score", 
               col = "skyblue", 
               border = "white")
        } else {
          plot.new()
          text(0.5, 0.5, "No vertices in cleaned graph")
        }
        
        # Plot 2: Adjusted Graph PageRank Distribution
        if (nrow(adjusted_df) > 0) {
          hist(adjusted_df\$pagerank, 
               main = "Adjusted Graph PageRank (damping=0.1)", 
               xlab = "PageRank Score", 
               col = "salmon", 
               border = "white")
        } else {
          plot.new()
          text(0.5, 0.5, "No vertices in adjusted graph")
        }
        
        dev.off()
        
        cat("Pipeline completed successfully. Outputs saved:\n")
        cat("- cleaned_graph.rds\n")
        cat("- adjusted_graph.rds\n")
        cat("- cleaned_vertices.csv\n")
        cat("- adjusted_vertices.csv\n")
        cat("- pagerank_comparison.pdf\n")

    writeLines(c(
        '"BIOC_PAGERANK_GRAPH_CLEANING_AND_ADJUSTMENT":',
        paste0('    pageRank: ', as.character(packageVersion('pageRank')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_graph_cleaning_and_adjustment.csv versions.yml
    """
}

workflow BIOC_PAGERANK_GRAPH_CLEANING_AND_ADJUSTMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ raw_graph.RData ] ]

    main:
    BIOC_PAGERANK_GRAPH_CLEANING_AND_ADJUSTMENT(ch_input)

    emit:
    tables   = BIOC_PAGERANK_GRAPH_CLEANING_AND_ADJUSTMENT.out.tables
    plots    = BIOC_PAGERANK_GRAPH_CLEANING_AND_ADJUSTMENT.out.plots
    objects  = BIOC_PAGERANK_GRAPH_CLEANING_AND_ADJUSTMENT.out.objects
    versions = BIOC_PAGERANK_GRAPH_CLEANING_AND_ADJUSTMENT.out.versions
}
