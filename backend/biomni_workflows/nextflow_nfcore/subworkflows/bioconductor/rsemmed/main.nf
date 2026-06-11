#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rsemmed — concept_path_exploration_and_reweighting
// Find, visualize, and refine shortest paths between two sets of biological concepts in SemMedDB using custom edge weights and node filtering.
// Input: g_small, e_feat
// Container: quay.io/biocontainers/bioconductor-rsemmed:1.20.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: dplyr, igraph, rsemmed
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Search and filter source and target nodes using find_nodes(). 2. Find initial shortest paths between the node sets using find_path

nextflow.enable.dsl = 2

process BIOC_RSEMMED_CONCEPT_PATH_EXPLORATION_AND_REWEIGHTING {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
        
        library(rsemmed)
        library(dplyr)
        library(igraph)
        
        # Helper function to read inputs robustly
        read_input <- function(name) {
          if (file.exists(name)) {
            return(readRDS(name))
          } else if (file.exists(paste0(name, ".rds"))) {
            return(readRDS(paste0(name, ".rds")))
          } else {
            stop(paste("Input file not found:", name))
          }
        }
        
        # Load user inputs from the working directory
        g_small <- read_input("g_small")
        e_feat <- read_input("e_feat")
        
        # 1. Search and filter source and target nodes using find_nodes()
        nodes_sickle <- find_nodes(g_small, pattern = "sickle")
        
        # Robust subsetting in case the input graph has fewer nodes matching the pattern
        idx_sickle <- c(1, 3, 5)
        idx_sickle <- idx_sickle[idx_sickle <= length(nodes_sickle)]
        if (length(idx_sickle) == 0) {
          idx_sickle <- seq_along(nodes_sickle)
        }
        nodes_sickle <- nodes_sickle[idx_sickle]
        
        nodes_malaria <- find_nodes(g_small, pattern = "malaria")
        nodes_malaria <- nodes_malaria %>%
            find_nodes(pattern = "anti", match = FALSE) %>%
            find_nodes(pattern = "test", match = FALSE) %>%
            find_nodes(pattern = "screening", match = FALSE) %>%
            find_nodes(pattern = "pigment", match = FALSE) %>%
            find_nodes(pattern = "smear", match = FALSE) %>%
            find_nodes(pattern = "parasite", match = FALSE) %>%
            find_nodes(pattern = "serology", match = FALSE) %>%
            find_nodes(pattern = "vaccine", match = FALSE)
        
        # 2. Find initial shortest paths between the node sets using find_paths()
        paths <- find_paths(graph = g_small, from = nodes_sickle, to = nodes_malaria)
        
        # Open PDF device to save path visualizations
        pdf("concept_paths_visualization.pdf", width = 11, height = 8.5)
        
        # 3. Inspect specific paths using text_path() and plot_path()
        tryCatch({
            this_path <- paths[[1]][[100]]
            tp <- text_path(g_small, this_path)
            plot_path(g_small, this_path)
        }, error = function(e) {
            # Fallback if the 100th path does not exist in the provided graph subset
            if (length(paths) > 0 && length(paths[[1]]) > 0) {
                this_path <<- paths[[1]][[1]]
                tp <<- text_path(g_small, this_path)
                plot_path(g_small, this_path)
            }
        })
        
        # 4. Extract edge features using get_edge_features()
        e_feat <- get_edge_features(g_small)
        
        node_from <- if (length(nodes_sickle) > 0) nodes_sickle[1] else nodes_sickle
        node_to <- if (length(nodes_malaria) > 0) nodes_malaria[1] else nodes_malaria
    
        paths_subset <- find_paths(
            graph = g_small,
            from = node_from,
            to = node_to
        )
        paths_subset <- if (length(paths_subset) > 0) paths_subset[[1]] else list()
        
        # 5. Generate custom edge weights using make_edge_weights()
        w <- make_edge_weights(g_small, e_feat, node_semtypes_out = c("humn", "popg"))
        
        paths_subset_reweight <- find_paths(
            graph = g_small,
            from = node_from,
            to = node_to,
            weights = w
        )
        
        # 6. Optionally extract and block middle nodes of initial paths using get_middle_nodes()
        out_names <- if (length(paths_subset) > 0) get_middle_nodes(g_small, paths_subset) else character(0)
        
        w <- make_edge_weights(g_small, e_feat,
            node_names_out = out_names, node_semtypes_out = c("humn", "popg")
        )
        
        # 7. Re-run find_paths() with the custom weights
        paths_subset_reweight <- find_paths(
            graph = g_small,
            from = node_from,
            to = node_to,
            weights = w
        )
        paths_subset_reweight <- if (length(paths_subset_reweight) > 0) paths_subset_reweight[[1]] else list()
        
        get_middle_nodes(g_small, paths, collapse = FALSE)
        
        w <- make_edge_weights(g_small, e_feat,
            node_semtypes_out = c("humn", "popg"),
            node_semtypes_in = c("gngm", "aapp")
        )
        
        paths_subset_reweight <- find_paths(
            graph = g_small,
            from = node_from,
            to = node_to,
            weights = w
        )
        paths_subset_reweight <- if (length(paths_subset_reweight) > 0) paths_subset_reweight[[1]] else list()
        
        # Plot the reweighted paths if available
        tryCatch({
            if (length(paths_subset_reweight) >= 1) {
                plot_path(g_small, paths_subset_reweight[[1]])
            }
            if (length(paths_subset_reweight) >= 2) {
                plot_path(g_small, paths_subset_reweight[[2]])
            }
        }, error = function(e) {
            message("Could not plot reweighted paths.")
        })
        
        dev.off()
        
        # 8. Summarize the semantic types and predicates along the discovered paths
        semtype_summary <- summarize_semtypes(g_small, paths_subset_reweight)
        semtype_summary_all <- summarize_semtypes(g_small, paths)
        edge_summary <- summarize_predicates(g_small, paths)
        
        # Save output objects to the working directory
        saveRDS(paths, "paths.rds")
        saveRDS(paths_subset_reweight, "paths_subset_reweight.rds")
        saveRDS(semtype_summary, "semtype_summary.rds")
        saveRDS(semtype_summary_all, "semtype_summary_all.rds")
        saveRDS(edge_summary, "edge_summary.rds")

    writeLines(c(
        '"BIOC_RSEMMED_CONCEPT_PATH_EXPLORATION_AND_REWEIGHTING":',
        paste0('    rsemmed: ', as.character(packageVersion('rsemmed')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_concept_path_exploration_and_reweighting.csv versions.yml
    """
}

workflow BIOC_RSEMMED_CONCEPT_PATH_EXPLORATION_AND_REWEIGHTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ g_small, e_feat ] ]

    main:
    BIOC_RSEMMED_CONCEPT_PATH_EXPLORATION_AND_REWEIGHTING(ch_input)

    emit:
    tables   = BIOC_RSEMMED_CONCEPT_PATH_EXPLORATION_AND_REWEIGHTING.out.tables
    plots    = BIOC_RSEMMED_CONCEPT_PATH_EXPLORATION_AND_REWEIGHTING.out.plots
    objects  = BIOC_RSEMMED_CONCEPT_PATH_EXPLORATION_AND_REWEIGHTING.out.objects
    versions = BIOC_RSEMMED_CONCEPT_PATH_EXPLORATION_AND_REWEIGHTING.out.versions
}
