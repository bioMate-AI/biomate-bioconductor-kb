#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: pageRank — multiplex_pagerank
// Calculate multiplex PageRank using a base network and a supplemental network.
// Input: base_graph.RData, supp_graph.RData
// Container: quay.io/biocontainers/bioconductor-pagerank:1.20.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: igraph, pageRank
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load or create base and supplemental igraph objects
//  * 2. [Core Analysis] Assign vertex names and pre-calculate standard PageRank for both graphs
//  * 3. [Core Analysis] Calculate multiplex PageRank using multiplex_page_rank

nextflow.enable.dsl = 2

process BIOC_PAGERANK_MULTIPLEX_PAGERANK {
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
    library(pageRank)
    library(igraph)
    
    # 1. Load base and supplemental igraph objects from user input files
    if (!file.exists("base_graph.RData")) {
      stop("Required input file 'base_graph.RData' not found in the working directory.")
    }
    if (!file.exists("supp_graph.RData")) {
      stop("Required input file 'supp_graph.RData' not found in the working directory.")
    }
    
    # Load base graph
    env1 <- new.env()
    load("base_graph.RData", envir = env1)
    graph1 <- NULL
    for (obj_name in names(env1)) {
      if (inherits(env1[[obj_name]], "igraph")) {
        graph1 <- env1[[obj_name]]
        break
      }
    }
    if (is.null(graph1)) {
      stop("No igraph object found in base_graph.RData")
    }
    
    # Load supplemental graph
    env2 <- new.env()
    load("supp_graph.RData", envir = env2)
    graph2 <- NULL
    for (obj_name in names(env2)) {
      if (inherits(env2[[obj_name]], "igraph")) {
        graph2 <- env2[[obj_name]]
        break
      }
    }
    if (is.null(graph2)) {
      stop("No igraph object found in supp_graph.RData")
    }
    
    # 2. Assign vertex names and pre-calculate standard PageRank for both graphs
    if (is.null(igraph::V(graph1)\$name)) {
      igraph::V(graph1)\$name <- as.character(seq_len(igraph::vcount(graph1)))
    }
    igraph::V(graph1)\$pagerank <- igraph::page_rank(graph1)\$vector
    
    if (is.null(igraph::V(graph2)\$name)) {
      igraph::V(graph2)\$name <- as.character(seq_len(igraph::vcount(graph2)))
    }
    igraph::V(graph2)\$pagerank <- igraph::page_rank(graph2)\$vector
    
    # 3. Calculate multiplex PageRank using multiplex_page_rank
    mpr_results <- multiplex_page_rank(graph1, graph2)
    
    # 4. Write named output files for the results
    # Save as RDS object
    saveRDS(mpr_results, file = "multiplex_pagerank_results.rds")
    
    # Save as CSV table
    mpr_df <- data.frame(
      node = names(mpr_results),
      multiplex_pagerank = as.numeric(mpr_results),
      stringsAsFactors = FALSE
    )
    write.csv(mpr_df, file = "multiplex_pagerank_results.csv", row.names = FALSE)
    
    # Generate and save a PDF plot of the distribution
    pdf("multiplex_pagerank_distribution.pdf", width = 7, height = 5)
    hist(mpr_df\$multiplex_pagerank, 
         main = "Distribution of Multiplex PageRank Scores",
         xlab = "Multiplex PageRank Score", 
         col = "skyblue", 
         border = "white")
    dev.off()

    writeLines(c(
        '"BIOC_PAGERANK_MULTIPLEX_PAGERANK":',
        paste0('    pageRank: ', as.character(packageVersion('pageRank')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multiplex_pagerank.csv versions.yml
    """
}

workflow BIOC_PAGERANK_MULTIPLEX_PAGERANK_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ base_graph.RData, supp_graph.RData ] ]

    main:
    BIOC_PAGERANK_MULTIPLEX_PAGERANK(ch_input)

    emit:
    tables   = BIOC_PAGERANK_MULTIPLEX_PAGERANK.out.tables
    plots    = BIOC_PAGERANK_MULTIPLEX_PAGERANK.out.plots
    objects  = BIOC_PAGERANK_MULTIPLEX_PAGERANK.out.objects
    versions = BIOC_PAGERANK_MULTIPLEX_PAGERANK.out.versions
}
