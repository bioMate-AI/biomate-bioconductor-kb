#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SpatialOmicsOverlay — spatial_overlay_visualization
// Reconstruct ROI overlays from GeoMx OME-TIFF and lab worksheets, add gene expression or segment annotations, manipulate the image (crop/flip/recolor), and plot 
// Input: scan_image.ome.tiff, lab_worksheet.txt, geomx_data.rds
// Container: quay.io/biocontainers/bioconductor-spatialomicsoverlay:1.10.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GeomxTools, RBioFormats, SpatialOmicsOverlay, cowplot, ggplot2, viridis
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Set Java memory parameters and load libraries
//  * 2. [Input & Preparation] Read spatial overlay data using readSpatialOverlay
//  * 3. [Visualization & Output] Add plotting factors (annotations or gene expression) using addPlottingFactor
//  * 4. [Core Analysis] Add the OME-TIFF image at a specific resolution using addImageOmeTiff
//  * 5. [Core Analysis] Manipulate the image/coordinates (e.g., flipY, cropTissue, cropSamples)
//  * 6. [Core Analysis] Customize image coloring (optional) using add4ChannelImage, changeImageColoring, changeColoringIntensity, and recolor
//  * 7. [Visualization & Output] Plot the spatial overlay using plotSpatialOverlay and optionally add a fluorophore legend using fluorLegend

nextflow.enable.dsl = 2

process BIOC_SPATIALOMICSOVERLAY_SPATIAL_OVERLAY_VISUALIZATION {
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
    .bm_deps <- c("RBioFormats", "SpatialOmicsOverlay", "GeomxTools", "cowplot", "ggplot2", "viridis")
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
    
    # Set Java memory parameters before loading RBioFormats
    options(java.parameters = "-Xmx4g")
    
    # Load required libraries
    library(RBioFormats)
    library(SpatialOmicsOverlay)
    library(GeomxTools)
    library(cowplot)
    library(ggplot2)
    library(viridis)
    
    # Define input file paths from the working directory
    tifFile <- "scan_image.ome.tiff"
    muBrainLW <- "lab_worksheet.txt"
    geomx_rds <- "geomx_data.rds"
    
    # Verify input files exist
    if (!file.exists(tifFile)) {
      stop(paste("Required input file missing:", tifFile))
    }
    if (!file.exists(muBrainLW)) {
      stop(paste("Required input file missing:", muBrainLW))
    }
    if (!file.exists(geomx_rds)) {
      stop(paste("Required input file missing:", geomx_rds))
    }
    
    # Dynamically extract slide name from the lab worksheet
    slide_name <- "D5761 (3)" # Default fallback
    tryCatch({
      lw_data <- read.delim(muBrainLW, sep = "\t", check.names = FALSE, stringsAsFactors = FALSE)
      slide_col <- grep("slide", colnames(lw_data), ignore.case = TRUE, value = TRUE)
      if (length(slide_col) > 0) {
        slide_name <- unique(lw_data[[slide_col[1]]])[1]
      }
    }, error = function(e) {
      message("Could not dynamically detect slide name from lab worksheet. Using default.")
    })
    
    # 1. Read spatial overlay data
    muBrain <- readSpatialOverlay(
      ometiff = tifFile, 
      annots = muBrainLW, 
      slideName = slide_name, 
      image = FALSE, 
      saveFile = FALSE, 
      outline = FALSE
    )
    
    # 2. Read annotations and GeomxSet object
    muBrainAnnots <- readLabWorksheet(lw = muBrainLW, slideName = slide_name)
    muBrainGeomxSet <- readRDS(geomx_rds)
    
    # Dynamically determine valid plotting factors to prevent crashes on custom datasets
    segment_col <- "segment"
    if (!segment_col %in% colnames(muBrainAnnots)) {
      found_cols <- colnames(muBrainAnnots)[grep("segment", colnames(muBrainAnnots), ignore.case = TRUE)]
      if (length(found_cols) > 0) {
        segment_col <- found_cols[1]
      } else {
        segment_col <- colnames(muBrainAnnots)[1]
      }
    }
    
    plotting_gene <- "Calm1"
    if (!plotting_gene %in% rownames(muBrainGeomxSet)) {
      plotting_gene <- rownames(muBrainGeomxSet)[1]
    }
    
    # Add plotting factors
    muBrain <- addPlottingFactor(overlay = muBrain, annots = muBrainAnnots, plottingFactor = segment_col)
    muBrain <- addPlottingFactor(overlay = muBrain, annots = muBrainGeomxSet, plottingFactor = plotting_gene)
    muBrain <- addPlottingFactor(overlay = muBrain, annots = 1:length(sampNames(muBrain)), plottingFactor = "ROILabel")
    
    # Open PDF device to save all generated plots
    pdf("spatial_overlay_plots.pdf", width = 11, height = 8.5)
    
    # 3. Add the OME-TIFF image at a specific resolution
    valid_res <- checkValidRes(ometiff = tifFile)
    res <- max(valid_res) # Use the lowest resolution (highest number) for speed and safety
    muBrain <- addImageOmeTiff(overlay = muBrain, ometiff = tifFile, res = res)
    showImage(muBrain)
    
    # 4. Plot the spatial overlay
    p1 <- plotSpatialOverlay(
      overlay = muBrain, 
      colorBy = segment_col, 
      corner = "topcenter", 
      scaleBarWidth = 0.5, 
      textDistance = 130, 
      scaleBarColor = "cyan"
    )
    print(p1)
    
    p2 <- plotSpatialOverlay(
      overlay = muBrain, 
      colorBy = segment_col, 
      corner = "topcenter", 
      scaleBarWidth = 0.5, 
      textDistance = 130, 
      scaleBarColor = "cyan", 
      fluorLegend = TRUE
    )
    print(p2)
    
    # Create a publication-ready figure with a custom fluorophore legend
    gp <- plotSpatialOverlay(overlay = muBrain, colorBy = segment_col, corner = "bottomright")
    legend <- fluorLegend(muBrain, nrow = 2, textSize = 4, boxColor = "grey85", alpha = 0.3)
    p_cow <- cowplot::ggdraw() + 
      cowplot::draw_plot(gp) + 
      cowplot::draw_plot(legend, scale = 0.105, x = 0.1, y = -0.25)
    print(p_cow)
    
    # 5. Manipulate the image/coordinates (Flipping and Cropping)
    muBrain <- flipY(muBrain)
    p_flip1 <- plotSpatialOverlay(overlay = muBrain, colorBy = segment_col, scaleBar = FALSE)
    print(p_flip1)
    
    p_flip2 <- plotSpatialOverlay(overlay = flipX(muBrain), colorBy = segment_col, scaleBar = FALSE)
    print(p_flip2)
    
    # Crop tissue
    muBrain <- cropTissue(overlay = muBrain, buffer = 0.05)
    p_crop_tissue <- plotSpatialOverlay(overlay = muBrain, colorBy = "ROILabel", legend = FALSE, scaleBar = FALSE) + 
      viridis::scale_fill_viridis(option = "C")
    print(p_crop_tissue)
    
    # Crop samples dynamically based on segment values
    seg_values <- unique(muBrainAnnots[[segment_col]])
    seg_val_to_use <- if ("Full ROI" %in% seg_values) "Full ROI" else seg_values[1]
    
    samps <- muBrainAnnots\$Sample_ID[muBrainAnnots[[segment_col]] == seg_val_to_use & muBrainAnnots\$slide.name == slideName(muBrain)]
    if (length(samps) == 0) {
      samps <- head(sampNames(muBrain), 5)
    }
    
    # Calculate a robust midpoint for the gradient scale
    expr_vals <- exprs(muBrainGeomxSet)[plotting_gene, ]
    mid_val <- median(expr_vals, na.rm = TRUE)
    if (is.na(mid_val) || mid_val == 0) mid_val <- 2500
    
    muBrainCrop <- cropSamples(overlay = muBrain, sampleIDs = samps, sampsOnly = TRUE)
    p_crop_samps1 <- plotSpatialOverlay(
      overlay = muBrainCrop, 
      colorBy = plotting_gene, 
      scaleBar = TRUE, 
      corner = "bottomleft", 
      textDistance = 5
    ) + ggplot2::scale_fill_gradient2(low = "grey", high = "red", mid = "yellow", midpoint = mid_val)
    print(p_crop_samps1)
    
    muBrainCrop <- cropSamples(overlay = muBrain, sampleIDs = samps, sampsOnly = FALSE)
    p_crop_samps2 <- plotSpatialOverlay(
      overlay = muBrainCrop, 
      colorBy = segment_col, 
      scaleBar = TRUE, 
      corner = "bottomleft", 
      textDistance = 5
    )
    print(p_crop_samps2)
    
    # 6. Customize image coloring
    chan4 <- add4ChannelImage(overlay = muBrain)
    fluor_df <- fluor(chan4)
    
    # Extract available dyes dynamically
    dyes <- fluor_df\$DisplayName
    if (is.null(dyes)) dyes <- fluor_df\$Dye
    
    dye1 <- if ("FITC" %in% dyes) "FITC" else dyes[1]
    dye2 <- if ("Alexa 647" %in% dyes) "Alexa 647" else (if (length(dyes) >= 2) dyes[2] else dyes[1])
    dye3 <- if ("Cy5" %in% dyes) "Cy5" else dyes[length(dyes)]
    
    chan4 <- changeImageColoring(overlay = chan4, color = "#32a8a4", dye = dye1)
    chan4 <- changeImageColoring(overlay = chan4, color = "magenta", dye = dye2)
    chan4 <- changeColoringIntensity(overlay = chan4, minInten = 500, maxInten = 10000, dye = dye3)
    
    fluor(chan4)
    chan4 <- recolor(chan4)
    showImage(chan4)
    
    # Close PDF device
    dev.off()
    
    # Save final spatial overlay object and plotting factors
    saveRDS(muBrain, "spatial_overlay_final.rds")
    write.csv(plotFactors(muBrain), "plotting_factors.csv", row.names = TRUE)
    
    message("Pipeline completed successfully. Outputs saved to 'spatial_overlay_plots.pdf', 'spatial_overlay_final.rds', and 'plotting_factors.csv'.")

    writeLines(c(
        '"BIOC_SPATIALOMICSOVERLAY_SPATIAL_OVERLAY_VISUALIZATION":',
        paste0('    SpatialOmicsOverlay: ', as.character(packageVersion('SpatialOmicsOverlay')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_spatial_overlay_visualization.csv versions.yml
    """
}

workflow BIOC_SPATIALOMICSOVERLAY_SPATIAL_OVERLAY_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ scan_image.ome.tiff, lab_worksheet.txt, geomx_data.rds ] ]

    main:
    BIOC_SPATIALOMICSOVERLAY_SPATIAL_OVERLAY_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_SPATIALOMICSOVERLAY_SPATIAL_OVERLAY_VISUALIZATION.out.tables
    plots    = BIOC_SPATIALOMICSOVERLAY_SPATIAL_OVERLAY_VISUALIZATION.out.plots
    objects  = BIOC_SPATIALOMICSOVERLAY_SPATIAL_OVERLAY_VISUALIZATION.out.objects
    versions = BIOC_SPATIALOMICSOVERLAY_SPATIAL_OVERLAY_VISUALIZATION.out.versions
}
