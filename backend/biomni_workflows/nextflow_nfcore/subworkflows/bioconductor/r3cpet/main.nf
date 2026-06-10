#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: R3CPET — chromatin_maintainer_network_inference
// Infer and analyze the protein networks that maintain chromatin interactions using ChIA-PET, TFBS, and PPI data.
// Input: HepG2_interactions.txt, HepG2_TF.txt.gz, RPKMS
// Container: quay.io/biocontainers/bioconductor-r3cpet:1.42.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: R3CPET
// Visualizations: network plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Initialize the ChiapetExperimentData object with ChIA-PET and TFBS files
//  * 2. [Input & Preparation] Load PET interactions using loadPETs
//  * 3. [Input & Preparation] Load TFBS data using loadTFBS
//  * 4. [Input & Preparation] Load and filter the background PPI network using loadPPI
//  * 5. [Input & Preparation] Create indexes for processing using createIndexes
//  * 6. [Input & Preparation] Build protein interaction networks for each chromatin loop using buildNetworks
//  * 7. [Core Analysis] Infer chromatin maintainer networks using the HLDA algorithm with InferNetworks
//  * 8. [Core Analysis] Convert top edges to igraph networks using GenerateNetworks
//  * 9. [Core Analysis] Annotate network proteins with gene expression using annotateExpression
//  * 10. [Core Analysis] Cluster DNA interactions by enrichment profile using clusterInteractions
//  * 11. [Visualization & Output] Visualize results (heatmaps, curves, networks, circos) using plot3CPETRes and visualizeCircos

nextflow.enable.dsl = 2

process BIOC_R3CPET_CHROMATIN_MAINTAINER_NETWORK_INFERENCE {
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
        library(R3CPET)
        
        # Define input file paths in the working directory
        petFile <- "HepG2_interactions.txt"
        tfbsFile <- "HepG2_TF.txt.gz"
        
        # Robustly load the RPKMS expression data from the working directory
        if (file.exists("RPKMS")) {
          RPKMS <- tryCatch({
            readRDS("RPKMS")
          }, error = function(e) {
            tryCatch({
              env <- new.env()
              load("RPKMS", envir = env)
              env[[ls(env)[1]]]
            }, error = function(e2) {
              read.table("RPKMS", header = TRUE, sep = "\t", stringsAsFactors = FALSE)
            })
          })
        } else if (file.exists("RPKMS.txt")) {
          RPKMS <- read.table("RPKMS.txt", header = TRUE, sep = "\t", stringsAsFactors = FALSE)
        } else if (file.exists("RPKMS.csv")) {
          RPKMS <- read.csv("RPKMS.csv", header = TRUE, stringsAsFactors = FALSE)
        } else {
          RPKMS <- NULL
          warning("Optional input file 'RPKMS' (or RPKMS.txt/RPKMS.csv) not found in the working directory. Proceeding without expression annotation.")
        }
        
        # 1. Initialize the ChiapetExperimentData object
        x <- ChiapetExperimentData(pet = petFile, tfbs = tfbsFile, IsBed = FALSE, ppiType = "HPRD", filter = TRUE)
        
        # 2. Load PET interactions
        petPath <- "HepG2_interactions.txt"
        x <- loadPETs(x, petFile = petPath, IsBed = FALSE)
        
        # 3. Load TFBS data
        TFPath <- "HepG2_TF.txt.gz"
        x <- loadTFBS(x, tfbsFile = TFPath)
        
        # 4. Load and filter the background PPI network
        x <- loadPPI(x, type = "HPRD", filter = TRUE)
        
        # 5. Create indexes for processing
        x <- createIndexes(x)
        
        # Save the initialized experiment data object
        saveRDS(x, "ChiapetExperimentData_object.rds")
        
        # 6. Build protein interaction networks for each chromatin loop
        nets <- buildNetworks(x, minFreq = 0.1, maxFreq = 0.9)
        saveRDS(nets, "NetworkCollection_object.rds")
        
        # 7. Infer chromatin maintainer networks using the HLDA algorithm
        hlda <- InferNetworks(nets)
        
        # 8. Convert top edges to igraph networks
        hlda <- GenerateNetworks(hlda)
        
        # 9. Annotate network proteins with gene expression
        if (!is.null(RPKMS)) {
          hlda <- annotateExpression(hlda, RPKMS)
        }
        
        # 10. Cluster DNA interactions by enrichment profile
        hlda <- clusterInteractions(hlda, method = "sota", nbClus = 6)
        saveRDS(hlda, "ChromMaintainers_object.rds")
        
        # Extract and save genomic coordinates of regions in cluster 3
        regions_cluster3 <- getRegionsIncluster(hlda, x, cluster = 3)
        write.csv(as.data.frame(regions_cluster3), "regions_in_cluster_3.csv", row.names = FALSE)
        
        # 11. Visualize results and save plots to PDF files
        pdf("R3CPET_plots.pdf", width = 10, height = 8)
        
        # Heatmap
        tryCatch({
          print(plot3CPETRes(hlda, type = 'heatmap'))
        }, error = function(e) {
          warning("Failed to plot heatmap: ", e\$message)
        })
        
        # Curve
        tryCatch({
          print(plot3CPETRes(hlda, type = 'curve'))
        }, error = function(e) {
          warning("Failed to plot curve: ", e\$message)
        })
        
        # Average Curve
        tryCatch({
          print(plot3CPETRes(hlda, type = 'avgCurve'))
        }, error = function(e) {
          warning("Failed to plot avgCurve: ", e\$message)
        })
        
        # Network Similarity
        tryCatch({
          print(plot3CPETRes(hlda, type = 'netSim'))
        }, error = function(e) {
          warning("Failed to plot netSim: ", e\$message)
        })
        
        # Circos plot for cluster 4
        tryCatch({
          visualizeCircos(hlda, x, cluster = 4)
        }, error = function(e) {
          warning("Failed to plot visualizeCircos: ", e\$message)
        })
        
        dev.off()
        
        # Generate and plot networks (this also automatically creates 'AllGraphs.pdf')
        pdf("R3CPET_network_4.pdf", width = 8, height = 8)
        tryCatch({
          nets_plot <- plot3CPETRes(hlda, type = 'networks')
          if (length(nets_plot) >= 4) {
            print(nets_plot[[4]])
          } else if (length(nets_plot) > 0) {
            print(nets_plot[[1]])
          }
        }, error = function(e) {
          warning("Failed to plot networks: ", e\$message)
        })
        dev.off()

    writeLines(c(
        '"BIOC_R3CPET_CHROMATIN_MAINTAINER_NETWORK_INFERENCE":',
        paste0('    R3CPET: ', as.character(packageVersion('R3CPET')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_chromatin_maintainer_network_inference.csv versions.yml
    """
}

workflow BIOC_R3CPET_CHROMATIN_MAINTAINER_NETWORK_INFERENCE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ HepG2_interactions.txt, HepG2_TF.txt.gz, RPKMS ] ]

    main:
    BIOC_R3CPET_CHROMATIN_MAINTAINER_NETWORK_INFERENCE(ch_input)

    emit:
    tables   = BIOC_R3CPET_CHROMATIN_MAINTAINER_NETWORK_INFERENCE.out.tables
    plots    = BIOC_R3CPET_CHROMATIN_MAINTAINER_NETWORK_INFERENCE.out.plots
    objects  = BIOC_R3CPET_CHROMATIN_MAINTAINER_NETWORK_INFERENCE.out.objects
    versions = BIOC_R3CPET_CHROMATIN_MAINTAINER_NETWORK_INFERENCE.out.versions
}
