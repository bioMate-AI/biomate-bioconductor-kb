#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: FamAgg — pedigree_management_and_visualization
// Import pedigree data, manipulate relationships, prune pedigrees, and visualize them as standard pedigree plots or graphs.
// Input: pedigree_data.txt, pedigree_data.ped
// Container: quay.io/biocontainers/bioconductor-famagg:1.38.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: FamAgg, igraph
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create FAData object from file or data.frame
//  * 2. [Core Analysis] Extract family or individual pedigree information
//  * 3. [Core Analysis] Find founders or common ancestors
//  * 4. [Visualization & Output] Plot pedigrees
//  * 5. [Core Analysis] Convert pedigree to graph and find subgraphs

nextflow.enable.dsl = 2

process BIOC_FAMAGG_PEDIGREE_MANAGEMENT_AND_VISUALIZATION {
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
    
    # Load required libraries
    library(FamAgg)
    library(igraph)
    
    # 1. Read the declared USER INPUT files from the working directory
    # pedigree_data.txt: tab-delimited text file containing pedigree columns: family, id, father, mother, sex
    mbped <- read.delim("pedigree_data.txt", header = TRUE, stringsAsFactors = FALSE)
    
    # Extract age if present, otherwise handle gracefully
    if ("age" %in% colnames(mbped)) {
      endage <- mbped\$age
      names(endage) <- mbped\$id
    } else {
      endage <- rep(NA, nrow(mbped))
      names(endage) <- mbped\$id
    }
    
    # Create FAData object
    fad <- FAData(pedigree = mbped, age = endage)
    
    # Dynamically select IDs for downstream analysis to avoid hardcoding
    fam_ids <- unique(fad\$family)
    if (length(fam_ids) == 0) stop("No families found in the pedigree data.")
    fam_id <- as.character(fam_ids[1])
    
    fam_inds <- fad\$id[fad\$family == fam_id]
    if (length(fam_inds) == 0) stop("No individuals found in the selected family.")
    ind_id <- as.character(fam_inds[1])
    
    # Select a subset of individuals for pruned pedigree and common ancestor functions
    inds_subset <- as.character(head(fam_inds, 3))
    
    # 2. Extract family or individual pedigree information
    ped_info <- pedigree(fad)
    write.csv(head(ped_info), "head_pedigree.csv", row.names = FALSE)
    
    father_info <- fad\$father
    write.csv(head(father_info), "head_father.csv")
    
    # Extract family
    tryCatch({
      fam_ped <- family(fad, family = fam_id)
      write.csv(head(fam_ped), paste0("head_family_", fam_id, ".csv"), row.names = FALSE)
    }, error = function(e) {
      message("Family ", fam_id, " not found or error: ", e\$message)
    })
    
    # 3. Plotting setup
    pdf("pedigree_plots.pdf")
    
    switchPlotfun("ks2paint")
    
    tryCatch({
      plotPed(fad, id = ind_id, device = "plot")
    }, error = function(e) {
      message("Error plotting id ", ind_id, ": ", e\$message)
    })
    
    # 4. Build pedigree and prune
    tryCatch({
      fullPed <- buildPed(fad, id = ind_id)
      write.csv(fullPed, paste0("fullPed_id_", ind_id, ".csv"), row.names = FALSE)
    }, error = function(e) {
      message("Error building pedigree for id ", ind_id, ": ", e\$message)
    })
    
    tryCatch({
      pruned_ped <- buildPed(fad, id = inds_subset, prune = TRUE)
      write.csv(pruned_ped, "pruned_ped_subset.csv", row.names = FALSE)
    }, error = function(e) {
      message("Error building pruned pedigree: ", e\$message)
    })
    
    tryCatch({
      plotPed(fad, id = inds_subset, prune = TRUE)
    }, error = function(e) {
      message("Error plotting pruned pedigree: ", e\$message)
    })
    
    # 5. Find founders or common ancestors
    tryCatch({
      founders_fam <- findFounders(fad, fam_id)
      write.csv(data.frame(founder = founders_fam), paste0("founders_family_", fam_id, ".csv"), row.names = FALSE)
    }, error = function(e) {
      message("Error finding founders for family ", fam_id, ": ", e\$message)
    })
    
    tryCatch({
      common_anc <- getCommonAncestor(fad, id = inds_subset)
      write.csv(data.frame(common_ancestor = common_anc), "common_ancestor_subset.csv", row.names = FALSE)
    }, error = function(e) {
      message("Error getting common ancestor: ", e\$message)
    })
    
    tryCatch({
      children_ind <- getChildren(fad, id = ind_id, max.generations = 1)
      write.csv(data.frame(children = children_ind), paste0("children_id_", ind_id, ".csv"), row.names = FALSE)
    }, error = function(e) {
      message("Error getting children: ", e\$message)
    })
    
    tryCatch({
      ancestors_ind <- getAncestors(fad, id = ind_id)
      write.csv(data.frame(ancestors = ancestors_ind), paste0("ancestors_id_", ind_id, ".csv"), row.names = FALSE)
    }, error = function(e) {
      message("Error getting ancestors: ", e\$message)
    })
    
    tryCatch({
      siblings_ind <- getSiblings(fad, id = ind_id)
      write.csv(data.frame(siblings = siblings_ind), paste0("siblings_id_", ind_id, ".csv"), row.names = FALSE)
    }, error = function(e) {
      message("Error getting siblings: ", e\$message)
    })
    
    # 6. Convert pedigree to graph and find subgraphs
    fullGraph <- ped2graph(pedigree(fad))
    saveRDS(fullGraph, "fullGraph.rds")
    
    tryCatch({
      singleFam <- ped2graph(family(fad, family = fam_id))
      saveRDS(singleFam, "singleFam_graph.rds")
      
      # Dynamically select nodes present in the single family graph
      graph_nodes <- head(V(singleFam)\$name, 4)
      subgr <- connectedSubgraph(singleFam, nodes = graph_nodes)
      saveRDS(subgr, "connected_subgraph.rds")
      
      # Plot the subgraph to the PDF
      plot(subgr)
    }, error = function(e) {
      message("Error with graph operations: ", e\$message)
    })
    
    dev.off() # Close PDF device
    
    # 7. Import from PLINK format pedigree file
    pedFile <- "pedigree_data.ped"
    fad <- FAData(pedFile)
    saveRDS(fad, "fad_from_ped.rds")
    
    # 8. Export pedigree data
    tryCatch({
      fam_ids_ped <- unique(fad\$family)
      if (length(fam_ids_ped) > 0) {
        fam_id_ped <- fam_ids_ped[1]
        fam_export <- fad[fad\$family == fam_id_ped, ]
        tmpF <- paste0("exported_family_", fam_id_ped, ".ped")
        export(fam_export, tmpF, format = "ped")
      } else {
        message("No families found in the PLINK pedigree data.")
      }
    }, error = function(e) {
      message("Error exporting family: ", e\$message)
    })

    writeLines(c(
        '"BIOC_FAMAGG_PEDIGREE_MANAGEMENT_AND_VISUALIZATION":',
        paste0('    FamAgg: ', as.character(packageVersion('FamAgg')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pedigree_management_and_visualization.csv versions.yml
    """
}

workflow BIOC_FAMAGG_PEDIGREE_MANAGEMENT_AND_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pedigree_data.txt, pedigree_data.ped ] ]

    main:
    BIOC_FAMAGG_PEDIGREE_MANAGEMENT_AND_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_FAMAGG_PEDIGREE_MANAGEMENT_AND_VISUALIZATION.out.tables
    plots    = BIOC_FAMAGG_PEDIGREE_MANAGEMENT_AND_VISUALIZATION.out.plots
    objects  = BIOC_FAMAGG_PEDIGREE_MANAGEMENT_AND_VISUALIZATION.out.objects
    versions = BIOC_FAMAGG_PEDIGREE_MANAGEMENT_AND_VISUALIZATION.out.versions
}
