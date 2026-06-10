#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: diffuStats — single_network_diffusion
// Propagate node labels over a network using a specific diffusion method to prioritize candidates and visualize the smoothed scores.
// Input: network.graph, node_scores.csv
// Container: quay.io/biocontainers/bioconductor-diffustats:1.30.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: diffuStats, igraph
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load the network and input scores. 2. Run diffusion using the diffuse function with a specified method (e.g., "raw" or "mc"). 3. M

nextflow.enable.dsl = 2

process BIOC_DIFFUSTATS_SINGLE_NETWORK_DIFFUSION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(igraph)
    library(diffuStats)
    
    # 1. Load the network and input scores
    # Read the igraph network object
    graph_toy <- readRDS("network.graph")
    
    # Read the node scores from CSV
    scores_df <- read.csv("node_scores.csv", row.names = 1, check.names = FALSE)
    input_mat <- as.matrix(scores_df)
    
    # Extract the first column as a named vector for the vector-based diffusion
    input_vec <- input_mat[, 1]
    names(input_vec) <- rownames(input_mat)
    
    # 2. Run diffusion using the diffuse function with a specified method ("raw")
    output_vec <- diffuStats::diffuse(
        graph = graph_toy,
        method = "raw",
        scores = input_vec)
    
    # 3. Map scores to colors and shapes using scores2colours and scores2shapes for network visualization
    # Save the visualization to a PDF file
    pdf("diffusion_plot.pdf", width = 8, height = 8)
    igraph::plot.igraph(
        graph_toy, 
        vertex.color = diffuStats::scores2colours(output_vec),
        vertex.shape = diffuStats::scores2shapes(input_vec),
        main = "Diffusion scores in our lattice"
    )
    dev.off()
    
    # Run diffusion using the diffuse function with "mc" method on the matrix
    output_mc <- diffuStats::diffuse(
        graph = graph_toy, 
        method = "mc", 
        scores = input_mat)
    
    # Save the meaningful results to output files
    write.csv(as.data.frame(output_vec), "output_vec.csv", row.names = TRUE)
    write.csv(as.data.frame(output_mc), "output_mc.csv", row.names = TRUE)
    saveRDS(output_vec, "output_vec.rds")
    saveRDS(output_mc, "output_mc.rds")

    writeLines(c(
        '"BIOC_DIFFUSTATS_SINGLE_NETWORK_DIFFUSION":',
        paste0('    diffuStats: ', as.character(packageVersion('diffuStats')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_network_diffusion.csv versions.yml
    """
}

workflow BIOC_DIFFUSTATS_SINGLE_NETWORK_DIFFUSION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ network.graph, node_scores.csv ] ]

    main:
    BIOC_DIFFUSTATS_SINGLE_NETWORK_DIFFUSION(ch_input)

    emit:
    tables   = BIOC_DIFFUSTATS_SINGLE_NETWORK_DIFFUSION.out.tables
    plots    = BIOC_DIFFUSTATS_SINGLE_NETWORK_DIFFUSION.out.plots
    objects  = BIOC_DIFFUSTATS_SINGLE_NETWORK_DIFFUSION.out.objects
    versions = BIOC_DIFFUSTATS_SINGLE_NETWORK_DIFFUSION.out.versions
}
