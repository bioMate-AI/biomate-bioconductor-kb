#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: wppi — gene_prioritization_ppi
// Prioritize candidate genes in the network neighborhood of a user-specified set of genes of interest using PPI networks and functional annotations.
// Input: genes_interest
// Container: quay.io/biocontainers/bioconductor-wppi:1.18.0--r45hdfd78af_0
// R packages: dplyr, igraph, knitr, readr, wppi
// Bioconductor: 3.20 | R: 4.4
// Requires: dplyr, igraph, readr, wppi
// Visualizations: network plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Retrieve database knowledge (PPI, GO, HPO, UniProt)
//  * 2. [Core Analysis] Convert PPI interactions to an igraph object
//  * 3. [Core Analysis] Extract a subgraph of the neighborhood around the genes of interest
//  * 4. [Core Analysis] Calculate a weighted adjacency matrix based on common neighbors and functional annotations
//  * 5. [Core Analysis] Perform a random walk with restarts on the weighted matrix
//  * 6. [Core Analysis] Prioritize and score candidate genes (or execute the entire workflow in one step using score_candidate_genes_from_PPI)

nextflow.enable.dsl = 2

process BIOC_WPPI_GENE_PRIORITIZATION_PPI {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20-slim"

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
    .bm_deps <- c("dplyr", "igraph", "knitr", "readr", "wppi")
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
    library(wppi)
    library(dplyr)
    library(readr)
    library(igraph)
    
    # 1. Read User Input
    if (!file.exists("genes_interest")) {
      stop("Error: Input file 'genes_interest' not found in the working directory.")
    }
    
    genes_interest <- readLines("genes_interest")
    genes_interest <- trimws(genes_interest)
    genes_interest <- genes_interest[genes_interest != ""]
    
    if (length(genes_interest) == 0) {
      stop("Error: 'genes_interest' file is empty.")
    }
    
    # 2. Run Full Workflow in One Step
    message("Running full workflow...")
    scores <- score_candidate_genes_from_PPI(genes_interest)
    readr::write_csv(scores, "scores_full_workflow.csv")
    
    # 3. Step-by-Step Workflow
    message("Retrieving database knowledge...")
    omnipath_data <- wppi_omnipath_data(datasets = 'omnipath')
    db <- wppi_data(datasets = c('omnipath', 'kinaseextra'))
    
    message("Retrieving HPO data...")
    HPO_data <- wppi_hpo_data()
    HPO_interest <- unique(dplyr::filter(HPO_data, grepl('Diabetes', Name))\$Name)
    
    message("Converting interactions to igraph...")
    graph_op <- graph_from_op(db\$omnipath)
    
    message("Extracting subgraph...")
    graph_op_1 <- subgraph_op(graph_op, genes_interest)
    
    message("Calculating weighted adjacency matrix...")
    w_adj <- weighted_adj(graph_op_1, db\$go, db\$hpo)
    
    message("Performing random walk...")
    w_rw <- random_walk(w_adj)
    
    message("Prioritizing genes...")
    scores <- prioritization_genes(graph_op_1, w_rw, genes_interest)
    readr::write_csv(scores, "scores_stepwise.csv")
    
    # 4. Network Visualization
    message("Generating network visualization...")
    pdf("ppi_network.pdf", width = 10, height = 10)
    idx_neighbors <- which(!igraph::V(graph_op_1)\$Gene_Symbol %in% genes_interest)
    cols <- rep("lightsteelblue2", igraph::vcount(graph_op_1))
    cols[idx_neighbors] <- "#57da83"
    
    scores.vertex <- rep(1, igraph::vcount(graph_op_1))
    matched_idx <- match(igraph::V(graph_op_1)\$Gene_Symbol, scores\$gene_symbol)
    scores.vertex[idx_neighbors] <- 8 * scores\$score[matched_idx[idx_neighbors]]
    scores.vertex[is.na(scores.vertex)] <- 1
    
    par(mar=c(0.1,0.1,0.1,0.1))
    igraph::plot.igraph(
      graph_op_1,
      vertex.label = ifelse(scores.vertex >= 1, igraph::V(graph_op_1)\$Gene_Symbol, NA),
      layout = igraph::layout_with_fr,
      vertex.color = cols,
      vertex.size = 7 * scores.vertex,
      edge.width = 0.5,
      edge.arrow.mode = 0,
      vertex.label.font = 1,
      vertex.label.cex = 0.45
    )
    dev.off()
    
    message("Pipeline completed successfully. Outputs saved to 'scores_full_workflow.csv', 'scores_stepwise.csv', and 'ppi_network.pdf'.")

    writeLines(c(
        '"BIOC_WPPI_GENE_PRIORITIZATION_PPI":',
        paste0('    wppi: ', as.character(packageVersion('wppi')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gene_prioritization_ppi.csv versions.yml
    """
}

workflow BIOC_WPPI_GENE_PRIORITIZATION_PPI_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ genes_interest ] ]

    main:
    BIOC_WPPI_GENE_PRIORITIZATION_PPI(ch_input)

    emit:
    tables   = BIOC_WPPI_GENE_PRIORITIZATION_PPI.out.tables
    plots    = BIOC_WPPI_GENE_PRIORITIZATION_PPI.out.plots
    objects  = BIOC_WPPI_GENE_PRIORITIZATION_PPI.out.objects
    versions = BIOC_WPPI_GENE_PRIORITIZATION_PPI.out.versions
}
