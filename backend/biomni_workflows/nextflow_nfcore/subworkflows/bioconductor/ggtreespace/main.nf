#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ggtreeSpace — basic_phylomorphospace
// Create a basic 2D phylomorphospace plot or add it as a graphic layer to a ggplot object
// Input: tree_file.nwk, trait_data.csv
// Container: quay.io/biocontainers/bioconductor-ggtreespace:1.6.0--r45h84498cf_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ape, dplyr, ggplot2, ggtree, ggtreeSpace
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the phylogenetic tree and trait data
//  * 2. [Visualization & Output] Generate the phylomorphospace plot using ggtreespace or add it as a layer using geom_treespace
//  * 3. [Core Analysis] Add tip annotations using geom_tippoint

nextflow.enable.dsl = 2

process BIOC_GGTREESPACE_BASIC_PHYLOMORPHOSPACE {
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
    .bm_deps <- c("ape", "ggtree", "ggtreeSpace", "ggplot2", "dplyr")
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
    library(ape)
    library(ggtree)
    library(ggtreeSpace)
    library(ggplot2)
    library(dplyr)
    
    # 1. Load the phylogenetic tree and trait data
    tr <- ape::read.tree("tree_file.nwk")
    trait_data <- read.csv("trait_data.csv", stringsAsFactors = FALSE)
    
    # Identify the column containing the tree tip labels
    tip_col_idx <- which(sapply(trait_data, function(col) any(col %in% tr\$tip.label)))
    if (length(tip_col_idx) == 0) {
      tip_col_idx <- 1
    } else {
      tip_col_idx <- tip_col_idx[1]
    }
    
    rownames(trait_data) <- trait_data[, tip_col_idx]
    
    # Select the first two numeric columns for 2D morphospace coordinates
    numeric_cols <- sapply(trait_data, is.numeric)
    td_matrix <- as.matrix(trait_data[, numeric_cols, drop = FALSE])
    
    if (ncol(td_matrix) < 2) {
      stop("Error: Trait data must contain at least 2 numeric columns for 2D morphospace.")
    }
    td <- td_matrix[, 1:2]
    
    # Subset and align tree and trait data to matching tips
    common_tips <- intersect(tr\$tip.label, rownames(td))
    if (length(common_tips) == 0) {
      stop("Error: No matching tip labels found between the tree and the trait data.")
    }
    
    tr <- ape::keep.tip(tr, common_tips)
    td <- td[tr\$tip.label, , drop = FALSE]
    
    # Assign tr1 and td1 for the second workflow stage
    tr1 <- tr
    td1 <- td
    
    # 2. Generate the phylomorphospace plot using ggtreespace and add tip annotations
    p1 <- ggtreespace(tr, td) +
        geom_tippoint()
    
    # Save the first plot
    ggsave("phylomorphospace_ggtreespace.pdf", plot = p1, width = 8, height = 7)
    
    # 3. Add phylomorphospace as a graphic layer using geom_treespace
    p2 <- ggplot() +
        geom_treespace(tr1, td1)
    
    # Save the second plot
    ggsave("phylomorphospace_geom_treespace.pdf", plot = p2, width = 8, height = 7)

    writeLines(c(
        '"BIOC_GGTREESPACE_BASIC_PHYLOMORPHOSPACE":',
        paste0('    ggtreeSpace: ', as.character(packageVersion('ggtreeSpace')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_basic_phylomorphospace.csv versions.yml
    """
}

workflow BIOC_GGTREESPACE_BASIC_PHYLOMORPHOSPACE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ tree_file.nwk, trait_data.csv ] ]

    main:
    BIOC_GGTREESPACE_BASIC_PHYLOMORPHOSPACE(ch_input)

    emit:
    tables   = BIOC_GGTREESPACE_BASIC_PHYLOMORPHOSPACE.out.tables
    plots    = BIOC_GGTREESPACE_BASIC_PHYLOMORPHOSPACE.out.plots
    objects  = BIOC_GGTREESPACE_BASIC_PHYLOMORPHOSPACE.out.objects
    versions = BIOC_GGTREESPACE_BASIC_PHYLOMORPHOSPACE.out.versions
}
