#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: geomeTriD — chromatin_3d_visualization
// Generate 3D coordinates from a genomic interaction matrix, add gene annotations and genomic signals, and render the interactive 3D plot.
// Input: gi_nij.rds, ctcf.sample.rds
// Container: quay.io/biocontainers/bioconductor-geometrid:1.4.1--r45h575d39b_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: InteractionSet, TxDb.Hsapiens.UCSC.hg19.knownGene, geomeTriD, htmlwidgets, org.Hs.eg.db, trackViewer
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load interaction data and define genomic range of interest
//  * 2. [Input & Preparation] Prepare gene and cis-regulatory element (cRE) annotations
//  * 3. [Core Analysis] Run multidimensional scaling (MDS) to calculate 3D coordinates and generate geometry objects
//  * 4. [Core Analysis] Extract backbone positions and add interaction loops
//  * 5. [Visualization & Output] Render the final 3D scene using threeJsViewer

nextflow.enable.dsl = 2

process BIOC_GEOMETRID_CHROMATIN_3D_VISUALIZATION {
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
        library(geomeTriD)
        library(trackViewer)
        library(InteractionSet)
        library(TxDb.Hsapiens.UCSC.hg19.knownGene)
        library(org.Hs.eg.db)
        library(htmlwidgets)
        
        # ==========================================
        # 1. Load interaction data and define genomic range of interest
        # ==========================================
        
        # Read the user-provided GInteractions object
        gi_nij <- readRDS("gi_nij.rds")
        
        # Define the genomic range of interest dynamically from the input data
        target_range <- range(regions(gi_nij))
        
        # ==========================================
        # 2. Prepare gene and cis-regulatory element (cRE) annotations
        # ==========================================
        
        # Get all genes from the hg19 TxDb package
        feature.gr <- genes(TxDb.Hsapiens.UCSC.hg19.knownGene)
        
        # Subset the data by target viewer region
        feature.gr <- subsetByOverlaps(feature.gr, target_range)
        
        # Assign symbols for each gene
        symbols <- mget(feature.gr\$gene_id, org.Hs.egSYMBOL, ifnotfound = NA)
        feature.gr\$label[lengths(symbols) == 1] <- 
          unlist(symbols[lengths(symbols) == 1])
        
        # Assign colors for each gene
        feature.gr\$col <- sample(1:7, length(feature.gr), replace = TRUE)
        
        # Replace some gene features as cis-regulatory elements (cRE)
        feature.gr\$type <- sample(c("cRE", "gene"),
          length(feature.gr),
          replace = TRUE,
          prob = c(0.1, 0.9)
        )
        
        # Set the size of the cRE in the plot
        feature.gr\$pch <- rep(NA, length(feature.gr))
        feature.gr\$pch[feature.gr\$type == "cRE"] <- 0.5
        
        # Save the prepared feature annotations
        saveRDS(feature.gr, "prepared_features.rds")
        write.csv(as.data.frame(feature.gr), "prepared_features.csv", row.names = FALSE)
        
        # ==========================================
        # 3. Run multidimensional scaling (MDS) to calculate 3D coordinates
        # ==========================================
        
        # Load the user-provided CTCF track object
        ctcf <- readRDS("ctcf.sample.rds")
        
        # Create a random signal for demonstration
        set.seed(1)
        randomSig <- ctcf\$dat
        randomSig <- randomSig[sort(sample(seq_along(randomSig), 50))]
        randomSig\$score <- randomSig\$score * 2 * runif(50)
        
        # Run MDS to generate 3D coordinates and geometry objects
        objs <- mdsPlot(gi_nij,
          range = target_range, feature.gr = feature.gr,
          genomicSigs = list(ctcf = ctcf, test = randomSig),
          reverseGenomicSigs = c(TRUE, FALSE),
          k = 3, render = "none"
        )
        
        # Save the MDS objects
        saveRDS(objs, "mds_objects.rds")
        
        # ==========================================
        # 4. Extract backbone positions and add interaction loops
        # ==========================================
        
        # Get the backbone 3D positions
        xyz <- extractBackbonePositions(objs)
        write.csv(as.data.frame(xyz), "backbone_positions.csv", row.names = FALSE)
        
        # Subset interactions to make the visualization clearer
        gi.subset <- gi_nij[distance(first(gi_nij), second(gi_nij)) > 50000]
        
        # Create 3D genomic signals for segment type (top 3 events)
        hic <- create3dGenomicSignals(
          gi.subset, 
          xyz,
          name = 'segment', 
          tag = 'hic', 
          color = c('green', 'darkred'),
          topN = 3, 
          lwd.maxGenomicSigs = 3,
          alpha = 0.5
        )
        
        # Create 3D genomic signals for polygon type (top 4-10 events)
        hic2 <- create3dGenomicSignals(
          gi.subset,
          xyz,
          name = 'polygon', 
          tag = 'hic', 
          color = c('blue', 'darkred'),
          topN = seq(4, 10), 
          type = 'polygon'
        )
        
        # Adjust width for high resolution input
        width(regions(gi.subset)) <- 101
        
        # Create 3D genomic signals for all subsetted interactions
        hic3 <- create3dGenomicSignals(
          gi.subset, 
          xyz,
          name = 'segment', 
          tag = 'hic', 
          color = rainbow(40),
          topN = length(gi.subset),
          lwd.maxGenomicSigs = 5,
          alpha = 0.1
        )
        
        # Save the generated 3D genomic signals
        saveRDS(list(hic = hic, hic2 = hic2, hic3 = hic3), "hic_3d_signals.rds")
        
        # ==========================================
        # 5. Render the final 3D scene using threeJsViewer
        # ==========================================
        
        # Combine all objects and render the interactive 3D plot
        combined_scene <- c(objs, hic, hic2, hic3)
        widget <- threeJsViewer(combined_scene)
        
        # Save the interactive widget as an HTML file
        htmlwidgets::saveWidget(widget, file = "chromatin_3d_structure.html", selfcontained = TRUE)
        
        cat("Pipeline completed successfully. Outputs saved:\n")
        cat("- prepared_features.rds / .csv\n")
        cat("- mds_objects.rds\n")
        cat("- backbone_positions.csv\n")
        cat("- hic_3d_signals.rds\n")
        cat("- chromatin_3d_structure.html (Interactive 3D Visualization)\n")

    writeLines(c(
        '"BIOC_GEOMETRID_CHROMATIN_3D_VISUALIZATION":',
        paste0('    geomeTriD: ', as.character(packageVersion('geomeTriD')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_chromatin_3d_visualization.csv versions.yml
    """
}

workflow BIOC_GEOMETRID_CHROMATIN_3D_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gi_nij.rds, ctcf.sample.rds ] ]

    main:
    BIOC_GEOMETRID_CHROMATIN_3D_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_GEOMETRID_CHROMATIN_3D_VISUALIZATION.out.tables
    plots    = BIOC_GEOMETRID_CHROMATIN_3D_VISUALIZATION.out.plots
    objects  = BIOC_GEOMETRID_CHROMATIN_3D_VISUALIZATION.out.objects
    versions = BIOC_GEOMETRID_CHROMATIN_3D_VISUALIZATION.out.versions
}
