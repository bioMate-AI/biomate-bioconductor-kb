#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ggtreeSpace — annotated_phylomorphospace_heatmap
// Create an advanced phylomorphospace visualization annotated with a continuous trait heatmap
// Input: tree_file.nwk, trait_coords.csv, additional_traits.csv
// Container: quay.io/biocontainers/bioconductor-ggtreespace:1.6.0--r45h84498cf_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ape, dplyr, ggplot2, ggtree, ggtreeSpace, phytools
// Visualizations: heatmap, phylogenetic tree
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the tree and trait data
//  * 2. [Visualization & Output] Initialize the base phylomorphospace plot
//  * 3. [Core Analysis] Attach additional trait data using the %<+% operator
//  * 4. [Visualization & Output] Add a heatmap layer using geom_tsheatmap and customize the color scale and theme

nextflow.enable.dsl = 2

process BIOC_GGTREESPACE_ANNOTATED_PHYLOMORPHOSPACE_HEATMAP {
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
    .bm_deps <- c("ggtree", "ggtreeSpace", "phytools", "ggplot2", "dplyr")
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
    library(ggtree)
    library(ggtreeSpace)
    library(phytools)
    library(ggplot2)
    library(dplyr)
    
    # 1. Load the tree and trait data from user-provided files
    tr <- ape::read.tree("tree_file.nwk")
    
    # Read 2D coordinates for morphospace
    trait_coords <- read.csv("trait_coords.csv", header = TRUE, stringsAsFactors = FALSE)
    # Set row names to the first column (tip labels) and convert the coordinate columns to a matrix
    rownames(trait_coords) <- trait_coords[, 1]
    td <- as.matrix(trait_coords[, 2:3])
    
    # Read additional trait values for heatmap mapping
    tdex <- read.csv("additional_traits.csv", header = TRUE, stringsAsFactors = FALSE)
    
    # Define the color palette for the heatmap
    col <- colorRampPalette(c(
        "#FFFFCC", "#FFEDA0", "#FED976", "#FEB24C",
        "#FD8D3C", "#FC4E2A", "#E31A1C", "#B10026"
    ))(24)
    
    # 2. Initialize the base phylomorphospace plot
    p <- ggtreespace(tr, td)
    
    # 3. Attach additional trait data and add the heatmap layer
    p_final <- p %<+% tdex +
        geom_tippoint() +
        geom_tsheatmap(
            trait = "z", alpha = 0.7,
            resolution = 0.01, bin = 24
        ) +
        scale_fill_manual(
            values = col,
            guide = guide_colorsteps(show.limits = TRUE)
        ) +
        theme_treespace2() +
        theme(
            legend.key.height = unit(1, "null"),
            legend.justification.top = "right"
        )
    
    # 4. Save the outputs
    ggsave("phylomorphospace_heatmap.pdf", plot = p_final, width = 10, height = 8)
    saveRDS(p_final, "phylomorphospace_plot.rds")

    writeLines(c(
        '"BIOC_GGTREESPACE_ANNOTATED_PHYLOMORPHOSPACE_HEATMAP":',
        paste0('    ggtreeSpace: ', as.character(packageVersion('ggtreeSpace')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_annotated_phylomorphospace_heatmap.csv versions.yml
    """
}

workflow BIOC_GGTREESPACE_ANNOTATED_PHYLOMORPHOSPACE_HEATMAP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ tree_file.nwk, trait_coords.csv, additional_traits.csv ] ]

    main:
    BIOC_GGTREESPACE_ANNOTATED_PHYLOMORPHOSPACE_HEATMAP(ch_input)

    emit:
    tables   = BIOC_GGTREESPACE_ANNOTATED_PHYLOMORPHOSPACE_HEATMAP.out.tables
    plots    = BIOC_GGTREESPACE_ANNOTATED_PHYLOMORPHOSPACE_HEATMAP.out.plots
    objects  = BIOC_GGTREESPACE_ANNOTATED_PHYLOMORPHOSPACE_HEATMAP.out.objects
    versions = BIOC_GGTREESPACE_ANNOTATED_PHYLOMORPHOSPACE_HEATMAP.out.versions
}
