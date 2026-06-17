#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CytoMDS — standard_cytometry_flow
// Perform low-dimensional projection and visualization of cytometry samples from a flowSet object, including distance calculation, MDS projection, quality diagnos
// Input: BCRXL_fs_trans, phenoData
// Container: quay.io/biocontainers/bioconductor-cytomds:1.6.1--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: CytoMDS, flowCore, ggplot2, patchwork
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Calculate pairwise Earth Mover's Distances (EMD) between samples using pairwiseEMDDist
//  * 2. [Core Analysis] Analyze individual marker contributions to the distance matrix using distByFeature and ggplotDistFeatureImportance
//  * 3. [Core Analysis] Compute the metric MDS projection using computeMetricMDS
//  * 4. [Visualization & Output] Plot the MDS projection with sample metadata using ggplotSampleMDS
//  * 5. [Core Analysis] Assess projection quality using a Shepard diagram with ggplotSampleMDSShepard
//  * 6. [Visualization & Output] Calculate channel summary statistics using channelSummaryStats
//  * 7. [Visualization & Output] Generate bi-plots to interpret projection axes using ggplotSampleMDS with external variables
//  * 8. [Visualization & Output] Plot marginal densities of key markers using ggplotMarginalDensities

nextflow.enable.dsl = 2

process BIOC_CYTOMDS_STANDARD_CYTOMETRY_FLOW {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    .bm_deps <- c("CytoMDS", "flowCore", "ggplot2", "patchwork")
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
        
        # Load required libraries
        suppressPackageStartupMessages({
            library(CytoMDS)
            library(flowCore)
            library(ggplot2)
            library(patchwork)
        })
        
        # ==========================================
        # 0. Load User Input Files
        # ==========================================
        
        # Read scale-transformed cytometry samples (flowSet)
        if (file.exists("BCRXL_fs_trans.rds")) {
            BCRXL_fs_trans <- readRDS("BCRXL_fs_trans.rds")
        } else if (file.exists("BCRXL_fs_trans")) {
            BCRXL_fs_trans <- readRDS("BCRXL_fs_trans")
        } else {
            stop("Required input file 'BCRXL_fs_trans' or 'BCRXL_fs_trans.rds' not found in the working directory.")
        }
        
        # Read sample metadata (data.frame)
        if (file.exists("phenoData.rds")) {
            phenoData <- readRDS("phenoData.rds")
        } else if (file.exists("phenoData")) {
            phenoData <- readRDS("phenoData")
        } else {
            stop("Required input file 'phenoData' or 'phenoData.rds' not found in the working directory.")
        }
        
        # Ensure sample_id exists for grouping
        if (!"sample_id" %in% colnames(phenoData)) {
            phenoData\$sample_id <- rownames(phenoData)
        }
        
        # Attach phenoData to flowSet
        flowCore::pData(BCRXL_fs_trans) <- phenoData
        
        # Determine column names for plotting dynamically to avoid hardcoding errors
        color_col <- if ("group_id" %in% colnames(phenoData)) "group_id" else colnames(phenoData)[1]
        label_col <- if ("patient_id" %in% colnames(phenoData)) "patient_id" else colnames(phenoData)[min(2, ncol(phenoData))]
        
        # Extract marker and channel information robustly
        kw <- flowCore::keyword(BCRXL_fs_trans[[1]])
        markerInfo <- kw\$MARKER_INFO
        
        if (!is.null(markerInfo)) {
            chClass <- markerInfo\$marker_class
            chLabels <- markerInfo\$channel_name[chClass != "none"]
            chMarkers <- markerInfo\$marker_name[chClass != "none"]
        } else {
            # Fallback if MARKER_INFO keyword is not present
            all_channels <- flowCore::colnames(BCRXL_fs_trans)
            exclude_cols <- c("Time", "Cell_length", "Event_length", "sample_id", "population_id")
            chLabels <- all_channels[!all_channels %in% exclude_cols]
            
            m_names <- flowCore::markernames(BCRXL_fs_trans)
            chMarkers <- m_names[chLabels]
            chMarkers[is.na(chMarkers)] <- chLabels[is.na(chMarkers)]
            chMarkers <- unname(chMarkers)
        }
        
        # ==========================================
        # 1. Calculate Pairwise Earth Mover's Distances (EMD)
        # ==========================================
        pwDist <- pairwiseEMDDist(
            BCRXL_fs_trans,
            channels = chMarkers,
            verbose = FALSE
        )
        pwDistMatrix <- as.matrix(pwDist)
        
        # Save distance matrix
        write.csv(pwDistMatrix, "pairwise_emd_distance_matrix.csv", row.names = TRUE)
        
        # ==========================================
        # 2. Analyze Individual Marker Contributions
        # ==========================================
        DF <- distByFeature(pwDist)
        DF_ordered <- DF[order(DF\$percentage, decreasing = TRUE),]
        
        # Save feature importance table
        write.csv(DF_ordered, "marker_contributions.csv", row.names = FALSE)
        
        # Generate and save feature importance plot
        pBar <- ggplotDistFeatureImportance(pwDist)
        ggsave("feature_importance_plot.pdf", plot = pBar, width = 8, height = 6)
        
        # ==========================================
        # 3. Compute Metric MDS Projection
        # ==========================================
        mdsObj <- computeMetricMDS(pwDist, seed = 0)
        show(mdsObj)
        
        # Save MDS object
        saveRDS(mdsObj, "mds_object.rds")
        
        # ==========================================
        # 4. Plot MDS Projection with Metadata
        # ==========================================
        # Default plot
        p_simple <- ggplotSampleMDS(mdsObj)
        
        # Enhanced plot with metadata
        p12 <- ggplotSampleMDS(
            mdsObj,
            pData = phenoData,
            projectionAxes = c(1,2),
            pDataForColour = color_col,
            pDataForLabel = label_col
        )
        ggsave("mds_projection_plot.pdf", plot = p12, width = 8, height = 7)
        
        # ==========================================
        # 5. Assess Projection Quality (Shepard Diagram)
        # ==========================================
        p_shepard <- ggplotSampleMDSShepard(mdsObj)
        ggsave("shepard_diagram.pdf", plot = p_shepard, width = 6, height = 6)
        
        # ==========================================
        # 6. Calculate Channel Summary Statistics
        # ==========================================
        medians <- channelSummaryStats(BCRXL_fs_trans, 
                                       channels = chLabels, 
                                       statFUNs = median)
        
        # Save medians table
        write.csv(medians, "channel_medians.csv", row.names = TRUE)
        
        # ==========================================
        # 7. Generate Bi-plots to Interpret Projection Axes
        # ==========================================
        p_biplot <- ggplotSampleMDS(mdsObj,
                        pData = phenoData,
                        pDataForColour = color_col,
                        displayPointLabels = FALSE,
                        displayArrowLabels = TRUE,
                        repelArrowLabels = TRUE,
                        biplot = TRUE,
                        extVariables = medians)
        ggsave("mds_biplot.pdf", plot = p_biplot, width = 8, height = 7)
        
        # ==========================================
        # 8. Plot Marginal Densities of Key Markers
        # ==========================================
        p_densities <- ggplotMarginalDensities(
            BCRXL_fs_trans, 
            channels = chLabels,
            pDataForColour = color_col,
            pDataForGroup = "sample_id")
        ggsave("marginal_densities_plot.pdf", plot = p_densities, width = 10, height = 10)

    writeLines(c(
        '"BIOC_CYTOMDS_STANDARD_CYTOMETRY_FLOW":',
        paste0('    CytoMDS: ', as.character(packageVersion('CytoMDS')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_cytometry_flow.csv versions.yml
    """
}

workflow BIOC_CYTOMDS_STANDARD_CYTOMETRY_FLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ BCRXL_fs_trans, phenoData ] ]

    main:
    BIOC_CYTOMDS_STANDARD_CYTOMETRY_FLOW(ch_input)

    emit:
    tables   = BIOC_CYTOMDS_STANDARD_CYTOMETRY_FLOW.out.tables
    plots    = BIOC_CYTOMDS_STANDARD_CYTOMETRY_FLOW.out.plots
    objects  = BIOC_CYTOMDS_STANDARD_CYTOMETRY_FLOW.out.objects
    versions = BIOC_CYTOMDS_STANDARD_CYTOMETRY_FLOW.out.versions
}
