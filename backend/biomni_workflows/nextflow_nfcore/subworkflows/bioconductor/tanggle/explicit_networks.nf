#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: tanggle — explicit_networks
// Visualize explicit, rooted phylogenetic networks with reticulations from extended Newick format.
// Input: network_text
// Container: quay.io/biocontainers/bioconductor-tanggle:1.16.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TANGGLE_EXPLICIT_NETWORKS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-tanggle:1.16.0--r45hdfd78af_0"

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
    .bm_deps <- c("ape", "ggplot2", "ggtree", "phangorn", "tanggle")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(ape)
    library(ggplot2)
    library(ggtree)
    library(phangorn)
    library(tanggle)
    
    # 1. Read the explicit network from the user input file 'network_text'
    input_file <- "network_text"
    if (!file.exists(input_file)) {
      stop("Error: Required input file 'network_text' not found in the working directory.")
    }
    
    # Read the extended Newick string from the file
    network_string <- paste(readLines(input_file, warn = FALSE), collapse = "\n")
    
    # Parse the network using read.evonet
    z <- read.evonet(text = network_string)
    
    # Save the parsed network object as an RDS file
    saveRDS(z, file = "evonet_object.rds")
    
    # 2. Plot the network using ggevonet with a rectangular layout and add tip and node labels
    p_rect <- ggevonet(z, layout = "rectangular") + geom_tiplab() + geom_nodelab()
    
    # Save the rectangular layout plot
    ggsave("network_rectangular.pdf", plot = p_rect, width = 8, height = 6)
    
    # 3. Plot the network using a slanted layout and customize tip label colors and node point aesthetics
    p <- ggevonet(z, layout = "slanted") + geom_tiplab() + geom_nodelab()
    
    # Save the base slanted layout plot
    ggsave("network_slanted_base.pdf", plot = p, width = 8, height = 6)
    
    # Customize tip labels (size=3, color="purple")
    p_custom_tips <- p + geom_tiplab(size=3, color="purple")
    ggsave("network_slanted_custom_tips.pdf", plot = p_custom_tips, width = 8, height = 6)
    
    # Customize node points (color="#b5e521", alpha=1/4, size=10)
    p_custom_nodes <- p + geom_nodepoint(color="#b5e521", alpha=1/4, size=10)
    ggsave("network_slanted_custom_nodes.pdf", plot = p_custom_nodes, width = 8, height = 6)

    cat <<-END_VERSIONS > versions.yml
    "BIOC_TANGGLE_EXPLICIT_NETWORKS":
        tanggle: \$(Rscript -e 'cat(as.character(packageVersion("tanggle")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_explicit_networks.csv versions.yml
    """
}

workflow BIOC_TANGGLE_EXPLICIT_NETWORKS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ network_text ] ]

    main:
    BIOC_TANGGLE_EXPLICIT_NETWORKS(ch_input)

    emit:
    tables   = BIOC_TANGGLE_EXPLICIT_NETWORKS.out.tables
    plots    = BIOC_TANGGLE_EXPLICIT_NETWORKS.out.plots
    objects  = BIOC_TANGGLE_EXPLICIT_NETWORKS.out.objects
    versions = BIOC_TANGGLE_EXPLICIT_NETWORKS.out.versions
}
