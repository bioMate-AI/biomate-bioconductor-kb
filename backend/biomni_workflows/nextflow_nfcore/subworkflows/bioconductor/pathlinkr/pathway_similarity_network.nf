#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: pathlinkR — pathway_similarity_network
// Construct and visualize pathway-to-pathway similarity networks from enriched pathway results.
// Input: enriched_pathways.rds
// Container: quay.io/biocontainers/bioconductor-pathlinkr:1.6.0--r45hdfd78af_0
// R packages: dplyr, ggplot2, pathlinkR
// Bioconductor: 3.20 | R: 4.4
// Requires: dplyr, ggplot2, pathlinkR
// Visualizations: network plot, pathway diagram
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the Sigora database and calculate pathway distances using getPathwayDistances()
//  * 2. [Input & Preparation] Create a foundation network of pathways using pathnetFoundation()
//  * 3. [Core Analysis] Filter enriched pathways for a specific comparison
//  * 4. [Input & Preparation] Create the pathway network using pathnetCreate()
//  * 5. [Visualization & Output] Visualize the pathway network using pathnetGGraph()

nextflow.enable.dsl = 2

process BIOC_PATHLINKR_PATHWAY_SIMILARITY_NETWORK {
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
    .bm_deps <- c("dplyr", "ggplot2", "pathlinkR")
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
    library(dplyr)
    library(pathlinkR)
    library(ggplot2)
    
    # Check for the existence of the required input file
    input_file <- "enriched_pathways.rds"
    if (!file.exists(input_file)) {
        stop(paste("Required input file missing:", input_file))
    }
    
    # Read the user input file
    enrichedResultsSigora <- readRDS(input_file)
    
    # Retrieve the Sigora database from the package namespace
    sigoraDatabase <- pathlinkR::sigoraDatabase
    
    # 1. Calculate pathway distances using getPathwayDistances()
    pathwayDistancesJaccard <- getPathwayDistances(pathwayData = sigoraDatabase)
    
    # 2. Create a foundation network of pathways using pathnetFoundation()
    startingPathways <- pathnetFoundation(
        mat=pathwayDistancesJaccard,
        maxDistance=0.8
    )
    
    # 3. Filter enriched pathways for a specific comparison
    # Robustly select "COVID Pos Over Time" if present, otherwise default to the first available comparison
    target_comparison <- "COVID Pos Over Time"
    available_comparisons <- unique(enrichedResultsSigora\$comparison)
    
    if (!(target_comparison %in% available_comparisons)) {
        if (length(available_comparisons) > 0) {
            target_comparison <- available_comparisons[1]
        } else {
            stop("No comparisons found in the enriched pathways input.")
        }
    }
    
    exPathwayNetworkInput <- enrichedResultsSigora %>%
        filter(comparison == target_comparison)
    
    # 4. Create the pathway network using pathnetCreate()
    myPathwayNetwork <- pathnetCreate(
        pathwayEnrichmentResult=exPathwayNetworkInput,
        foundation=startingPathways
    )
    
    # 5. Visualize the pathway network using pathnetGGraph()
    pathway_plot <- pathnetGGraph(
        myPathwayNetwork,
        labelProp=0.1,
        nodeLabelSize=3,
        nodeLabelOverlaps=8,
        segColour="red",
        themeBaseSize = 12
    )
    
    # Save meaningful results to the working directory
    saveRDS(startingPathways, "starting_pathways.rds")
    saveRDS(myPathwayNetwork, "pathway_network.rds")
    
    # Save the visualization as PDF and PNG
    ggsave(
        filename = "pathway_similarity_network.pdf",
        plot = pathway_plot,
        width = 12,
        height = 10
    )
    
    ggsave(
        filename = "pathway_similarity_network.png",
        plot = pathway_plot,
        width = 12,
        height = 10,
        dpi = 300
    )

    writeLines(c(
        '"BIOC_PATHLINKR_PATHWAY_SIMILARITY_NETWORK":',
        paste0('    pathlinkR: ', as.character(packageVersion('pathlinkR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pathway_similarity_network.csv versions.yml
    """
}

workflow BIOC_PATHLINKR_PATHWAY_SIMILARITY_NETWORK_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ enriched_pathways.rds ] ]

    main:
    BIOC_PATHLINKR_PATHWAY_SIMILARITY_NETWORK(ch_input)

    emit:
    tables   = BIOC_PATHLINKR_PATHWAY_SIMILARITY_NETWORK.out.tables
    plots    = BIOC_PATHLINKR_PATHWAY_SIMILARITY_NETWORK.out.plots
    objects  = BIOC_PATHLINKR_PATHWAY_SIMILARITY_NETWORK.out.objects
    versions = BIOC_PATHLINKR_PATHWAY_SIMILARITY_NETWORK.out.versions
}
