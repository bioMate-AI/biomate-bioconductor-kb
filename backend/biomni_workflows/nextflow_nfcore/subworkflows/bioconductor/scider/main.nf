#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scider — spatial_density_and_roi_analysis
// Model cell density, identify regions of interest (ROIs), test cell-type colocalization, and annotate cells by density contours in spatial transcriptomics data.
// Input: spe.rds
// Container: quay.io/biocontainers/bioconductor-scider:1.8.0--r45ha27e39d_0
// R packages: ggplot2, scider, SpatialExperiment
// Bioconductor: 3.20 | R: 4.4
// Requires: SpatialExperiment, scider
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load spatial transcriptomics data as a SpatialExperiment object
//  * 2. [Core Analysis] Calculate grid-based cell density using gridDensity
//  * 3. [Core Analysis] Identify Regions of Interest (ROIs) either algorithmically using findROI or manually using selectRegion and postSelRegion
//  * 4. [Core Analysis] Test spatial correlation/colocalization between cell types using corDensity
//  * 5. [Input & Preparation] Define density contours using getContour and allocate cells to these contours using allocateCells
//  * 6. [Visualization & Output] Visualize cell composition and spatial distributions using plotSpatial, plotDensity, plotROI, plotDensCor, plotCorHeatmap, plotCon

nextflow.enable.dsl = 2

process BIOC_SCIDER_SPATIAL_DENSITY_AND_ROI_ANALYSIS {
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
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("ggplot2", "scider", "SpatialExperiment")
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
    library(scider)
    library(SpatialExperiment)
    
    # 1. Load spatial transcriptomics data as a SpatialExperiment object
    if (!file.exists("spe.rds")) {
      stop("Error: Input file 'spe.rds' not found in the working directory.")
    }
    
    spe <- readRDS("spe.rds")
    
    # Validate that the required cell types exist in the input dataset
    actual_cell_types <- unique(colData(spe)\$cell_type)
    actual_cell_types <- as.character(actual_cell_types[!is.na(actual_cell_types)])
    
    if (length(actual_cell_types) < 2) {
      stop("Error: The input 'spe.rds' must contain at least two cell types in colData(spe)\$cell_type to run this workflow.")
    }
    
    # Dynamically assign cell types for analysis
    coi_cell_type <- actual_cell_types[1]
    other_cell_type <- actual_cell_types[2]
    
    # Display basic dataset information
    print(spe)
    print(table(colData(spe)\$cell_type))
    
    # Open a PDF device to save all visualizations
    pdf("scider_analysis_plots.pdf", width = 8, height = 6)
    
    # Plot spatial distribution of cell types
    p_spatial <- plotSpatial(spe, group.by = "cell_type", pt.alpha = 0.8)
    print(p_spatial)
    
    # 2. Calculate grid-based cell density using gridDensity
    spe <- gridDensity(spe)
    print(names(metadata(spe)))
    print(head(metadata(spe)\$grid_density))
    
    # Save grid density table
    write.csv(as.data.frame(metadata(spe)\$grid_density), "grid_density.csv", row.names = FALSE)
    
    # Plot overall density and density of the dynamically selected cell type
    p_dens_overall <- plotDensity(spe)
    print(p_dens_overall)
    
    p_dens_coi <- plotDensity(spe, coi = coi_cell_type)
    print(p_dens_coi)
    
    # 3. Identify Regions of Interest (ROIs) algorithmically using findROI
    spe <- findROI(spe, coi = coi_cell_type)
    
    # Dynamically find the ROI metadata column name
    roi_meta_name <- grep(".+_roi\$", names(metadata(spe)), value = TRUE)[1]
    print(head(metadata(spe)[[roi_meta_name]]))
    
    # Save identified ROIs
    write.csv(as.data.frame(metadata(spe)[[roi_meta_name]]), paste0(roi_meta_name, ".csv"), row.names = FALSE)
    
    p_roi <- plotROI(spe, roi = coi_cell_type)
    print(p_roi)
    
    # Handle manual ROI selection (selectRegion and postSelRegion)
    # Since selectRegion is interactive and will hang in headless environments,
    # we mock the 'sel_region' output using a high-density subset of the grid density
    # to ensure the pipeline remains fully runnable and automated.
    grid_df <- as.data.frame(metadata(spe)\$grid_density)
    
    # Dynamically determine the density column name for the selected cell type
    density_cols <- grep("^density_", colnames(grid_df), value = TRUE)
    density_cols <- density_cols[density_cols != "density_overall"]
    
    coi_formatted <- gsub("[^[:alnum:]]+", "_", tolower(coi_cell_type))
    coi_formatted <- gsub("^_|_\$", "", coi_formatted)
    density_col <- paste0("density_", coi_formatted)
    
    if (!density_col %in% colnames(grid_df)) {
      density_col <- density_cols[1] # Fallback to the first available specific density column
    }
    
    sel_region <- grid_df[grid_df[[density_col]] > quantile(grid_df[[density_col]], 0.9, na.rm = TRUE), ]
    
    if (interactive()) {
      tryCatch({
        interactive_sel <- selectRegion(metadata(spe)\$grid_density, x.col = "x_grid", y.col = "y_grid")
        if (!is.null(interactive_sel)) {
          sel_region <- interactive_sel
        }
      }, error = function(e) {
        warning("Interactive selectRegion failed or was skipped: ", e\$message)
      })
    } else {
      message("Running in non-interactive mode. Using automated high-density subset for 'sel_region'.")
    }
    
    spe1 <- postSelRegion(spe, sel_region = sel_region)
    print(metadata(spe1)\$roi)
    
    p_roi_manual <- plotROI(spe1)
    print(p_roi_manual)
    
    # 4. Test spatial correlation/colocalization between cell types using corDensity
    results <- corDensity(spe, roi = coi_cell_type)
    print(results\$ROI)
    print(results\$overall)
    
    # Save correlation results
    write.csv(as.data.frame(results\$ROI), "correlation_results_ROI.csv", row.names = FALSE)
    write.csv(as.data.frame(results\$overall), "correlation_results_overall.csv", row.names = FALSE)
    
    # Visualize density correlations and heatmaps
    p_dens_cor <- plotDensCor(spe, celltype1 = other_cell_type, celltype2 = coi_cell_type)
    print(p_dens_cor)
    
    p_heatmap_roi <- plotCorHeatmap(results\$ROI)
    print(p_heatmap_roi)
    
    p_heatmap_overall <- plotCorHeatmap(results\$overall)
    print(p_heatmap_overall)
    
    # 5. Define density contours using getContour and allocate cells using allocateCells
    spe <- getContour(spe, coi = coi_cell_type, equal.cell = TRUE)
    
    p_contour <- plotContour(spe, coi = coi_cell_type)
    print(p_contour)
    
    spe <- allocateCells(spe)
    
    # 6. Visualize cell composition and spatial distributions
    # Dynamically find the contour column name in colData
    contour_col <- grep("_contour\$", colnames(colData(spe)), value = TRUE)[1]
    
    p_spatial_contour <- plotSpatial(spe, group.by = contour_col, pt.alpha = 0.5)
    print(p_spatial_contour)
    
    p_compo_contour <- plotCellCompo(spe, contour = coi_cell_type)
    print(p_compo_contour)
    
    p_compo_roi <- plotCellCompo(spe, contour = coi_cell_type, roi = coi_cell_type)
    print(p_compo_roi)
    
    # Close the PDF device
    dev.off()
    
    # Save the final analyzed SpatialExperiment object
    saveRDS(spe, "spe_analyzed.rds")
    
    message("Pipeline completed successfully. Outputs saved to the working directory.")

    writeLines(c(
        '"BIOC_SCIDER_SPATIAL_DENSITY_AND_ROI_ANALYSIS":',
        paste0('    scider: ', as.character(packageVersion('scider')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_spatial_density_and_roi_analysis.csv versions.yml
    """
}

workflow BIOC_SCIDER_SPATIAL_DENSITY_AND_ROI_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ spe.rds ] ]

    main:
    BIOC_SCIDER_SPATIAL_DENSITY_AND_ROI_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SCIDER_SPATIAL_DENSITY_AND_ROI_ANALYSIS.out.tables
    plots    = BIOC_SCIDER_SPATIAL_DENSITY_AND_ROI_ANALYSIS.out.plots
    objects  = BIOC_SCIDER_SPATIAL_DENSITY_AND_ROI_ANALYSIS.out.objects
    versions = BIOC_SCIDER_SPATIAL_DENSITY_AND_ROI_ANALYSIS.out.versions
}
