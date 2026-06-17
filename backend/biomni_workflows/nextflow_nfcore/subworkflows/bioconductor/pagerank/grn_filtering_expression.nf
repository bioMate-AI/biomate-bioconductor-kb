#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: pageRank — grn_filtering_expression
// Filter a gene regulatory network using joint and marginal probability distributions from expression data.
// Input: expression_matrix.csv, network.csv
// Container: quay.io/biocontainers/bioconductor-pagerank:1.20.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, igraph, pageRank
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Prepare expression matrix and network data frame
//  * 2. [Core Analysis] Filter the network using P_graph

nextflow.enable.dsl = 2

process BIOC_PAGERANK_GRN_FILTERING_EXPRESSION {
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
    .bm_deps <- c("pageRank", "Biobase", "igraph")
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
    library(Biobase)
    library(igraph)
    
    # Stage 1: Prepare expression matrix and network data frame
    # Read the user-provided expression matrix
    expr_data <- read.csv("expression_matrix.csv", row.names = 1, check.names = FALSE)
    expr_mat <- as.matrix(expr_data)
    
    # Wrap in an ExpressionSet to faithfully execute the documented `exprs` call
    dset <- Biobase::ExpressionSet(assayData = expr_mat)
    dset <- exprs(dset)
    
    # Read the user-provided network data frame
    net <- read.csv("network.csv", stringsAsFactors = FALSE)
    
    # Ensure the network data frame has the expected column names 'reg' and 'target'
    if (!all(c("reg", "target") %in% colnames(net))) {
      colnames(net)[1:2] <- c("reg", "target")
    }
    
    # Stage 2: Filter the network using P_graph
    filtered_graph <- P_graph(dset, net, method="difference", null=NULL, threshold=0.05)
    
    # Save the meaningful results
    saveRDS(filtered_graph, "filtered_network.rds")
    
    if (inherits(filtered_graph, "igraph")) {
      # Export edges to CSV
      edge_df <- igraph::as_data_frame(filtered_graph, what = "edges")
      write.csv(edge_df, "filtered_network_edges.csv", row.names = FALSE)
      
      # Export vertices to CSV
      vertex_df <- igraph::as_data_frame(filtered_graph, what = "vertices")
      write.csv(vertex_df, "filtered_network_vertices.csv", row.names = FALSE)
    }

    writeLines(c(
        '"BIOC_PAGERANK_GRN_FILTERING_EXPRESSION":',
        paste0('    pageRank: ', as.character(packageVersion('pageRank')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_grn_filtering_expression.csv versions.yml
    """
}

workflow BIOC_PAGERANK_GRN_FILTERING_EXPRESSION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.csv, network.csv ] ]

    main:
    BIOC_PAGERANK_GRN_FILTERING_EXPRESSION(ch_input)

    emit:
    tables   = BIOC_PAGERANK_GRN_FILTERING_EXPRESSION.out.tables
    plots    = BIOC_PAGERANK_GRN_FILTERING_EXPRESSION.out.plots
    objects  = BIOC_PAGERANK_GRN_FILTERING_EXPRESSION.out.objects
    versions = BIOC_PAGERANK_GRN_FILTERING_EXPRESSION.out.versions
}
