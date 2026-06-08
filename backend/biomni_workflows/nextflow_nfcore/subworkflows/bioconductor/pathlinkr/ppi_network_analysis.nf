#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: pathlinkR — ppi_network_analysis
// Build, visualize, enrich, and extract subnetworks from Protein-Protein Interaction (PPI) networks using DEG results.
// Input: rnaseq_results.rds
// Container: quay.io/biocontainers/bioconductor-pathlinkr:1.6.0--r45hdfd78af_0
// Requires: dplyr, pathlinkR
// Visualizations: network plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Build a PPI network using ppiBuildNetwork()
//  * 2. [Visualization & Output] Plot the PPI network using ppiPlotNetwork()
//  * 3. [Core Analysis] Enrich the network nodes for pathways using ppiEnrichNetwork()
//  * 4. [Core Analysis] Extract a subnetwork based on an enriched pathway using ppiExtractSubnetwork()
//  * 5. [Visualization & Output] Plot the extracted subnetwork using ppiPlotNetwork()

nextflow.enable.dsl = 2

process BIOC_PATHLINKR_PPI_NETWORK_ANALYSIS {
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
        library(dplyr)
        library(pathlinkR)
        
        # ==========================================
        # 1. Read User Input
        # ==========================================
        input_file <- "rnaseq_results.rds"
        if (!file.exists(input_file)) {
            stop(paste("Error: Input file", input_file, "not found in the working directory."))
        }
        
        # Read the DESeq2 results list
        exampleDESeqResults <- readRDS(input_file)
        
        # Ensure the list elements have names for plotting titles
        if (is.null(names(exampleDESeqResults))) {
            names(exampleDESeqResults) <- paste0("Comparison_", seq_along(exampleDESeqResults))
        }
        
        # ==========================================
        # 2. Build PPI Network
        # ==========================================
        exNetwork <- ppiBuildNetwork(
            rnaseqResult=exampleDESeqResults[[1]],
            filterInput=TRUE,
            order="zero"
        )
        
        # Save the built network object
        saveRDS(exNetwork, "ppi_network.rds")
        
        # ==========================================
        # 3. Plot PPI Network
        # ==========================================
        pdf("ppi_network_plot.pdf", width = 10, height = 8)
        print(ppiPlotNetwork(
            network=exNetwork,
            title=names(exampleDESeqResults)[1],
            fillColumn=LogFoldChange,
            fillType="foldChange",
            label=TRUE,
            labelColumn=hgncSymbol,
            legend=TRUE
        ))
        dev.off()
        
        # ==========================================
        # 4. Enrich Network Nodes for Pathways
        # ==========================================
        exNetworkPathways <- ppiEnrichNetwork(
            network=exNetwork,
            analysis="hallmark",
            filterResults="default",
            geneUniverse = rownames(exampleDESeqResults[[1]])
        )
        
        # Save enrichment results
        saveRDS(exNetworkPathways, "ppi_network_pathways.rds")
        write.csv(exNetworkPathways, "ppi_network_pathways.csv", row.names = FALSE)
        
        # ==========================================
        # 5. Extract Subnetwork
        # ==========================================
        if (nrow(exNetworkPathways) == 0) {
            stop("No enriched pathways found to extract a subnetwork.")
        }
        
        # Extract a subnetwork based on the top enriched pathway
        top_pathway <- exNetworkPathways\$pathwayName[1]
        
        exSubnetwork <- ppiExtractSubnetwork(
            network=exNetwork,
            pathwayEnrichmentResult=exNetworkPathways,
            pathwayToExtract=top_pathway
        )
        
        # Save the extracted subnetwork object
        saveRDS(exSubnetwork, "ppi_subnetwork.rds")
        
        # ==========================================
        # 6. Plot Extracted Subnetwork
        # ==========================================
        pdf("ppi_subnetwork_plot.pdf", width = 10, height = 8)
        print(ppiPlotNetwork(
            network=exSubnetwork,
            fillType="oneSided",
            fillColumn=degree,
            label=TRUE,
            labelColumn=hgncSymbol,
            legendTitle="Degree"
        ))
        dev.off()
        
        cat("Pipeline completed successfully. Outputs saved to working directory.\n")

    writeLines(c(
        '"BIOC_PATHLINKR_PPI_NETWORK_ANALYSIS":',
        paste0('    pathlinkR: ', as.character(packageVersion('pathlinkR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ppi_network_analysis.csv versions.yml
    """
}

workflow BIOC_PATHLINKR_PPI_NETWORK_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ rnaseq_results.rds ] ]

    main:
    BIOC_PATHLINKR_PPI_NETWORK_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_PATHLINKR_PPI_NETWORK_ANALYSIS.out.tables
    plots    = BIOC_PATHLINKR_PPI_NETWORK_ANALYSIS.out.plots
    objects  = BIOC_PATHLINKR_PPI_NETWORK_ANALYSIS.out.objects
    versions = BIOC_PATHLINKR_PPI_NETWORK_ANALYSIS.out.versions
}
