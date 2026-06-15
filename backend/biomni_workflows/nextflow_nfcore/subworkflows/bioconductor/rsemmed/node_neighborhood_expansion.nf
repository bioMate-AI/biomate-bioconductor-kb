#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rsemmed — node_neighborhood_expansion
// Expand a seed set of biological concepts to discover directly connected neighboring concepts and filter them.
// Input: g_small
// Container: quay.io/biocontainers/bioconductor-rsemmed:1.20.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: igraph, magrittr, rsemmed
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Identify seed nodes of interest using find_nodes()
//  * 2. [Visualization & Output] Expand the seed nodes to their 1-neighborhood using
//  * 3. [Visualization & Output] Summarize the semantic types of the neighboring nodes
//  * 4. [Visualization & Output] Filter out uninteresting neighbor nodes using

nextflow.enable.dsl = 2

process BIOC_RSEMMED_NODE_NEIGHBORHOOD_EXPANSION {
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
    .bm_deps <- c("rsemmed", "magrittr", "igraph")
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
        
    library(rsemmed)
    library(magrittr)
    library(igraph)
    
    # Read the user input file 'g_small' from the working directory
    if (file.exists("g_small")) {
        g_small <- readRDS("g_small")
    } else if (file.exists("g_small.rds")) {
        g_small <- readRDS("g_small.rds")
    } else {
        stop("Required input file 'g_small' or 'g_small.rds' not found in the working directory.")
    }
    
    # --- Identify seed nodes of interest using find_nodes() ---
    nodes_sickle <- find_nodes(g_small, pattern = "sickle")
    nodes_sickle_trait <- nodes_sickle[intersect(2:3, seq_along(nodes_sickle))]
    
    # --- Expand the seed nodes to their 1-neighborhood using ---
    nbrs_sickle_trait <- grow_nodes(g_small, nodes_sickle_trait)
    
    # --- Summarize the semantic types of the neighboring nodes ---
    nbrs_sickle_trait_summ <- summarize_semtypes(g_small, nbrs_sickle_trait, is_path = FALSE)
    
    # --- Filter out uninteresting neighbor nodes using ---
    nbrs_sickle_trait2 <- nbrs_sickle_trait %>%
        find_nodes(
            pattern = "^Mice",
            semtypes = c("humn", "popg", "plnt", 
                "fish", "food", "edac", "dora", "aggp"),
            names = c("Polymerase Chain Reaction", "Mus"),
            match = FALSE
        )
    
    # Save meaningful results to output files
    saveRDS(nodes_sickle, "nodes_sickle.rds")
    saveRDS(nodes_sickle_trait, "nodes_sickle_trait.rds")
    saveRDS(nbrs_sickle_trait, "nbrs_sickle_trait.rds")
    saveRDS(nbrs_sickle_trait2, "nbrs_sickle_trait_filtered.rds")
    saveRDS(nbrs_sickle_trait_summ, "nbrs_sickle_trait_summ.rds")
    
    if (is.data.frame(nbrs_sickle_trait_summ)) {
        write.csv(nbrs_sickle_trait_summ, "nbrs_sickle_trait_summ.csv", row.names = FALSE)
    }

    writeLines(c(
        '"BIOC_RSEMMED_NODE_NEIGHBORHOOD_EXPANSION":',
        paste0('    rsemmed: ', as.character(packageVersion('rsemmed')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_node_neighborhood_expansion.csv versions.yml
    """
}

workflow BIOC_RSEMMED_NODE_NEIGHBORHOOD_EXPANSION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ g_small ] ]

    main:
    BIOC_RSEMMED_NODE_NEIGHBORHOOD_EXPANSION(ch_input)

    emit:
    tables   = BIOC_RSEMMED_NODE_NEIGHBORHOOD_EXPANSION.out.tables
    plots    = BIOC_RSEMMED_NODE_NEIGHBORHOOD_EXPANSION.out.plots
    objects  = BIOC_RSEMMED_NODE_NEIGHBORHOOD_EXPANSION.out.objects
    versions = BIOC_RSEMMED_NODE_NEIGHBORHOOD_EXPANSION.out.versions
}
