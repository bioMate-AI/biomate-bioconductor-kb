#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: pageRank — temporal_pagerank
// Calculate temporal PageRank on two temporally adjacent graphs to identify gained and lost interactions.
// Input: graph1.RData, graph2.RData
// Container: quay.io/biocontainers/bioconductor-pagerank:1.20.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: igraph, pageRank
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load or create two igraph objects
//  * 2. [Core Analysis] Assign vertex names to both graphs
//  * 3. [Core Analysis] Calculate temporal PageRank using diff_graph

nextflow.enable.dsl = 2

process BIOC_PAGERANK_TEMPORAL_PAGERANK {
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
    
    # Function to robustly load an igraph object from RData
    load_igraph <- function(file_path) {
      env <- new.env()
      load(file_path, envir = env)
      objs <- as.list(env)
      igraph_objs <- objs[sapply(objs, igraph::is.igraph)]
      if (length(igraph_objs) > 0) {
        return(igraph_objs[[1]])
      } else if (length(objs) > 0) {
        return(objs[[1]])
      } else {
        stop(paste("No objects found in", file_path))
      }
    }
    
    # 1. Load two igraph objects from the declared user input files
    if (!file.exists("graph1.RData") || !file.exists("graph2.RData")) {
      stop("Required input files 'graph1.RData' and/or 'graph2.RData' are missing in the working directory.")
    }
    
    graph1 <- load_igraph("graph1.RData")
    graph2 <- load_igraph("graph2.RData")
    
    # 2. Assign vertex names to both graphs (ensuring they are character vectors)
    if (is.null(igraph::V(graph1)\$name)) {
      igraph::V(graph1)\$name <- as.character(seq_len(igraph::vcount(graph1)))
    } else {
      igraph::V(graph1)\$name <- as.character(igraph::V(graph1)\$name)
    }
    
    if (is.null(igraph::V(graph2)\$name)) {
      igraph::V(graph2)\$name <- as.character(seq_len(igraph::vcount(graph2)))
    } else {
      igraph::V(graph2)\$name <- as.character(igraph::V(graph2)\$name)
    }
    
    # 3. Calculate temporal PageRank using diff_graph
    res_graph <- diff_graph(graph1, graph2)
    
    # 4. Write named output files for the meaningful results
    # Save the resulting igraph object
    saveRDS(res_graph, "temporal_pagerank_graph.rds")
    
    # Export vertex attributes (PageRank scores)
    if (!is.null(igraph::V(res_graph)\$name)) {
      v_df <- data.frame(
        name = igraph::V(res_graph)\$name,
        pagerank = if (!is.null(igraph::V(res_graph)\$pagerank)) igraph::V(res_graph)\$pagerank else NA,
        stringsAsFactors = FALSE
      )
      write.csv(v_df, "temporal_pagerank_vertices.csv", row.names = FALSE)
    }
    
    # Export edge attributes (gained/lost interactions indicated by 'moi')
    edges_df <- igraph::as_data_frame(res_graph, what = "edges")
    write.csv(edges_df, "temporal_pagerank_edges.csv", row.names = FALSE)
    
    cat("Temporal PageRank pipeline completed successfully. Outputs saved to 'temporal_pagerank_graph.rds', 'temporal_pagerank_vertices.csv', and 'temporal_pagerank_edges.csv'.\n")

    writeLines(c(
        '"BIOC_PAGERANK_TEMPORAL_PAGERANK":',
        paste0('    pageRank: ', as.character(packageVersion('pageRank')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_temporal_pagerank.csv versions.yml
    """
}

workflow BIOC_PAGERANK_TEMPORAL_PAGERANK_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ graph1.RData, graph2.RData ] ]

    main:
    BIOC_PAGERANK_TEMPORAL_PAGERANK(ch_input)

    emit:
    tables   = BIOC_PAGERANK_TEMPORAL_PAGERANK.out.tables
    plots    = BIOC_PAGERANK_TEMPORAL_PAGERANK.out.plots
    objects  = BIOC_PAGERANK_TEMPORAL_PAGERANK.out.objects
    versions = BIOC_PAGERANK_TEMPORAL_PAGERANK.out.versions
}
