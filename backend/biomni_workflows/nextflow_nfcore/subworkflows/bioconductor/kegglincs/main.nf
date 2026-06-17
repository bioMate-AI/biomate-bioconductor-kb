#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: KEGGlincs — visualize_expanded_kegg_pathway
// Reconstruct and visualize detailed "expanded" KEGG pathways from KGML files without adding experimental data.
// Input: hsa04068
// Container: quay.io/biocontainers/bioconductor-kegglincs:1.36.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: KEGGlincs, graph, igraph
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Download and parse KGML file using get_KGML
//  * 2. [Core Analysis] Expand node mappings using expand_KEGG_mappings
//  * 3. [Core Analysis] Expand edge mappings using expand_KEGG_edges
//  * 4. [Core Analysis] Generate node and edge mapping info using node_mapping_info and edge_mapping_info
//  * 5. [Input & Preparation] Create an igraph object using get_graph_object
//  * 6. [Visualization & Output] Visualize in Cytoscape using cyto_vis (or use the master function KEGG_lincs)

nextflow.enable.dsl = 2

process BIOC_KEGGLINCS_VISUALIZE_EXPANDED_KEGG_PATHWAY {
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
    .bm_deps <- c("KEGGlincs", "graph", "igraph")
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
    library(KEGGlincs)
    library(graph)
    library(igraph)
    
    # Read user input file
    # The user input is a file named "hsa04068" containing the KEGG pathway ID string (e.g., "hsa04068")
    input_file <- "hsa04068"
    if (!file.exists(input_file)) {
      stop(paste("Required input file", input_file, "does not exist in the working directory."))
    }
    pathway_id <- trimws(readLines(input_file, n = 1, warn = FALSE))
    
    # 1. Download and parse KGML file using get_KGML
    FoxO_KGML <- get_KGML(pathway_id)
    slot(FoxO_KGML, "pathwayInfo")
    slot(slot(FoxO_KGML, "pathwayInfo"), "image")
    
    # 2. Expand node mappings using expand_KEGG_mappings
    FoxO_KEGG_mappings <- expand_KEGG_mappings(FoxO_KGML)
    
    # 3. Expand edge mappings using expand_KEGG_edges
    FoxO_edges <- expand_KEGG_edges(FoxO_KGML, FoxO_KEGG_mappings)
    
    # Compare counts
    length(graph::nodes(FoxO_KGML))
    nrow(FoxO_KEGG_mappings)
    length(graph::edges(FoxO_KGML))
    nrow(FoxO_edges)
    
    # 4. Generate node and edge mapping info using node_mapping_info and edge_mapping_info
    FoxO_node_mapping_info <- node_mapping_info(FoxO_KEGG_mappings)
    FoxO_edge_mapping_info <- edge_mapping_info(FoxO_edges)
    
    # 5. Create an igraph object using get_graph_object
    GO <- get_graph_object(FoxO_node_mapping_info, FoxO_edge_mapping_info)
    class(GO)
    
    # 6. Visualize in Cytoscape using cyto_vis (or use the master function KEGG_lincs)
    # Since Cytoscape might not be running in a headless/automated environment,
    # we wrap these calls in tryCatch to ensure the pipeline completes and writes outputs.
    tryCatch({
      cyto_vis(GO, "FoxO Pathway with Expanded Edges[no data added]")
    }, error = function(e) {
      message("Cytoscape visualization skipped or failed (is Cytoscape running?): ", e\$message)
    })
    
    tryCatch({
      KEGG_lincs(pathway_id)
    }, error = function(e) {
      message("KEGG_lincs call 1 failed: ", e\$message)
    })
    
    tryCatch({
      FoxO_edges <- KEGG_lincs(pathway_id)
    }, error = function(e) {
      message("KEGG_lincs call 2 failed: ", e\$message)
    })
    
    tryCatch({
      KEGG_lincs(pathway_id, convert_KEGG_IDs = FALSE)
    }, error = function(e) {
      message("KEGG_lincs call 3 failed: ", e\$message)
    })
    
    # Save outputs to the working directory
    saveRDS(FoxO_KGML, "FoxO_KGML.rds")
    write.csv(FoxO_KEGG_mappings, "FoxO_KEGG_mappings.csv", row.names = FALSE)
    write.csv(FoxO_edges, "FoxO_edges.csv", row.names = FALSE)
    write.csv(FoxO_node_mapping_info, "FoxO_node_mapping_info.csv", row.names = FALSE)
    write.csv(FoxO_edge_mapping_info, "FoxO_edge_mapping_info.csv", row.names = FALSE)
    saveRDS(GO, "GO_graph.rds")
    
    message("Pipeline completed successfully. Outputs saved.")

    writeLines(c(
        '"BIOC_KEGGLINCS_VISUALIZE_EXPANDED_KEGG_PATHWAY":',
        paste0('    KEGGlincs: ', as.character(packageVersion('KEGGlincs')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_visualize_expanded_kegg_pathway.csv versions.yml
    """
}

workflow BIOC_KEGGLINCS_VISUALIZE_EXPANDED_KEGG_PATHWAY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ hsa04068 ] ]

    main:
    BIOC_KEGGLINCS_VISUALIZE_EXPANDED_KEGG_PATHWAY(ch_input)

    emit:
    tables   = BIOC_KEGGLINCS_VISUALIZE_EXPANDED_KEGG_PATHWAY.out.tables
    plots    = BIOC_KEGGLINCS_VISUALIZE_EXPANDED_KEGG_PATHWAY.out.plots
    objects  = BIOC_KEGGLINCS_VISUALIZE_EXPANDED_KEGG_PATHWAY.out.objects
    versions = BIOC_KEGGLINCS_VISUALIZE_EXPANDED_KEGG_PATHWAY.out.versions
}
