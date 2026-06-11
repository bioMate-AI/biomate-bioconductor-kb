#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RCy3 — igraph_interoperability
// Convert an igraph network to Cytoscape, and retrieve a Cytoscape network back into R as an igraph object.
// Input: ig
// Container: quay.io/biocontainers/bioconductor-rcy3:2.30.1--r45hdfd78af_0
// R packages: RCy3, igraph
// Bioconductor: 3.20 | R: 4.4
// Requires: RCy3, igraph
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Verify Cytoscape connection
//  * 2. [Core Analysis] Convert igraph network to Cytoscape
//  * 3. [Core Analysis] Retrieve Cytoscape network as igraph

nextflow.enable.dsl = 2

process BIOC_RCY3_IGRAPH_INTEROPERABILITY {
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
    .bm_deps <- c("RCy3", "igraph")
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
    library(RCy3)
    library(igraph)
    
    # 1. Verify Cytoscape connection
    # Cytoscape must be running for RCy3 to communicate with it.
    tryCatch({
        cytoscapePing()
    }, error = function(e) {
        stop("Cytoscape is not running or cannot be reached. Please launch Cytoscape before running this pipeline.")
    })
    
    # Read user input: ig (an igraph network object)
    # We expect the igraph object to be saved as an RDS file named "ig.rds" in the working directory.
    if (!file.exists("ig.rds")) {
        stop("Required input file 'ig.rds' not found in the working directory.")
    }
    ig <- readRDS("ig.rds")
    
    # 2. Convert igraph network to Cytoscape
    # Documented function call: createNetworkFromIgraph(ig,"myIgraph")
    createNetworkFromIgraph(ig, "myIgraph")
    
    # 3. Retrieve Cytoscape network as igraph
    # Documented function call: ig2 <- createIgraphFromNetwork("myIgraph")
    ig2 <- createIgraphFromNetwork("myIgraph")
    
    # Write named output files for the meaningful results
    saveRDS(ig2, "ig2.rds")
    
    # Export retrieved network vertices and edges as CSV tables
    vertices_df <- igraph::as_data_frame(ig2, what = "vertices")
    edges_df <- igraph::as_data_frame(ig2, what = "edges")
    
    write.csv(vertices_df, "ig2_vertices.csv", row.names = FALSE)
    write.csv(edges_df, "ig2_edges.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_RCY3_IGRAPH_INTEROPERABILITY":',
        paste0('    RCy3: ', as.character(packageVersion('RCy3')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_igraph_interoperability.csv versions.yml
    """
}

workflow BIOC_RCY3_IGRAPH_INTEROPERABILITY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ig ] ]

    main:
    BIOC_RCY3_IGRAPH_INTEROPERABILITY(ch_input)

    emit:
    tables   = BIOC_RCY3_IGRAPH_INTEROPERABILITY.out.tables
    plots    = BIOC_RCY3_IGRAPH_INTEROPERABILITY.out.plots
    objects  = BIOC_RCY3_IGRAPH_INTEROPERABILITY.out.objects
    versions = BIOC_RCY3_IGRAPH_INTEROPERABILITY.out.versions
}
