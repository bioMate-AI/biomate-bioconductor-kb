#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: tanggle — explicit_networks
// Visualize rooted, directed phylogenetic networks with reticulations from extended Newick format.
// Input: network.nwk
// Container: quay.io/biocontainers/bioconductor-tanggle:1.16.0--r45hdfd78af_0
// Requires: ape, ggplot2, ggtree, phangorn, tanggle
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read the explicit network using read.evonet
//  * 2. [Visualization & Output] Plot the explicit network using ggevonet with a rectangular or slanted layout
//  * 3. [Core Analysis] Add tip and node labels using geom_tiplab and geom_nodelab
//  * 4. [Core Analysis] Customize node points and tip label aesthetics

nextflow.enable.dsl = 2

process BIOC_TANGGLE_EXPLICIT_NETWORKS {
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
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
    
    # Load required libraries
    library(tanggle)
    library(phangorn)
    library(ggtree)
    library(ape)
    library(ggplot2)
    
    # 1. Read the explicit network from the user input file
    z <- read.evonet(file = "network.nwk")
    
    # Save the parsed network object
    saveRDS(z, "network_object.rds")
    
    # 2. Plot the explicit network using ggevonet with a rectangular layout
    p_rect <- ggevonet(z, layout = "rectangular") + geom_tiplab() + geom_nodelab()
    ggsave("plot_rectangular.pdf", plot = p_rect, width = 8, height = 6)
    
    # 3. Plot the explicit network using ggevonet with a slanted layout
    p <- ggevonet(z, layout = "slanted") + geom_tiplab() + geom_nodelab()
    ggsave("plot_slanted.pdf", plot = p, width = 8, height = 6)
    
    # 4. Customize tip label aesthetics
    p_custom_tip <- p + geom_tiplab(size=3, color="purple")
    ggsave("plot_slanted_custom_tiplab.pdf", plot = p_custom_tip, width = 8, height = 6)
    
    # 5. Customize node points aesthetics
    p_custom_node <- p + geom_nodepoint(color="#b5e521", alpha=1/4, size=10)
    ggsave("plot_slanted_custom_nodepoint.pdf", plot = p_custom_node, width = 8, height = 6)

    writeLines(c(
        '"BIOC_TANGGLE_EXPLICIT_NETWORKS":',
        paste0('    tanggle: ', as.character(packageVersion('tanggle')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_explicit_networks.csv versions.yml
    """
}

workflow BIOC_TANGGLE_EXPLICIT_NETWORKS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ network.nwk ] ]

    main:
    BIOC_TANGGLE_EXPLICIT_NETWORKS(ch_input)

    emit:
    tables   = BIOC_TANGGLE_EXPLICIT_NETWORKS.out.tables
    plots    = BIOC_TANGGLE_EXPLICIT_NETWORKS.out.plots
    objects  = BIOC_TANGGLE_EXPLICIT_NETWORKS.out.objects
    versions = BIOC_TANGGLE_EXPLICIT_NETWORKS.out.versions
}
