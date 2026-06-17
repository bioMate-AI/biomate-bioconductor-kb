#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: cytomapper — pixel_and_cell_visualization
// Load, scale, measure, and visualize pixel-level intensities and cell-level expression/metadata from multiplexed images and segmentation masks in memory.
// Input: multi_channel_images.tiff, segmentation_masks.tiff
// Container: quay.io/biocontainers/bioconductor-cytomapper:1.22.0--r45hdfd78af_0
// R packages: SingleCellExperiment, cowplot, cytomapper, ggplot2, HDF5Array
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CYTOMAPPER_PIXEL_AND_CELL_VISUALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-cytomapper:1.22.0--r45hdfd78af_0"

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
    .bm_deps <- c("SingleCellExperiment", "cowplot", "cytomapper", "ggplot2", "HDF5Array", "SummarizedExperiment")
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
    library(SummarizedExperiment)
    library(cytomapper)
    library(SingleCellExperiment)
    
    # --- Load segmentation masks and multi-channel images ---
    all_masks <- loadImages("segmentation_masks.tiff")
    all_stacks <- loadImages("multi_channel_images.tiff")
    
    # --- Add image metadata to the elementMetadata slot of both ---
    mcols(all_masks)\$ImageNb <- as.character(seq_along(all_masks))
    mcols(all_stacks)\$ImageNb <- as.character(seq_along(all_stacks))
    
    # --- Scale segmentation masks to restore integer cell IDs ---
    all_masks <- scaleImages(all_masks, 2^16-1)
    
    # --- Set channel names ---
    channelNames(all_stacks) <- c("H3", "CD99", "PIN", "CD8a", "CDH")
    
    # --- Measure cell-specific intensities and morphological ---
    sce <- measureObjects(all_masks, all_stacks, img_id = "ImageNb")
    
    # Prepare the SingleCellExperiment object with required metadata columns for plotting
    sce\$CellNb <- sce\$object_id
    cd99_expr <- assay(sce, "counts")["CD99", ]
    sce\$CellType <- ifelse(cd99_expr > median(cd99_expr), "CD99_high", "CD99_low")
    
    # --- Plot pixel-level intensities and save to PDF ---
    pdf("pixel_intensities_plot.pdf")
    plotPixels(image = all_stacks, colour_by = c("H3", "CD99", "CDH"))
    dev.off()
    
    # --- Plot cell-level expression and metadata on segmentation ---
    pdf("cell_expression_plot.pdf")
    plotCells(mask = all_masks, object = sce, cell_id = "CellNb", img_id = "ImageNb", colour_by = "CD99", outline_by = "CellType")
    dev.off()
    
    pdf("cell_metadata_plot.pdf")
    plotCells(mask = all_masks, object = sce, cell_id = "CellNb", img_id = "ImageNb", colour_by = "CellType")
    dev.off()
    
    # --- Write named output files for the results ---
    saveRDS(sce, "measured_cells_sce.rds")
    write.csv(as.data.frame(colData(sce)), "cell_metadata.csv", row.names = FALSE)
    write.csv(as.data.frame(assay(sce, "counts")), "cell_counts.csv", row.names = TRUE)

    writeLines(c(
        '"BIOC_CYTOMAPPER_PIXEL_AND_CELL_VISUALIZATION":',
        paste0('        cytomapper: ', as.character(packageVersion("cytomapper")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pixel_and_cell_visualization.csv versions.yml
    """
}

workflow BIOC_CYTOMAPPER_PIXEL_AND_CELL_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ multi_channel_images.tiff, segmentation_masks.tiff ] ]

    main:
    BIOC_CYTOMAPPER_PIXEL_AND_CELL_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_CYTOMAPPER_PIXEL_AND_CELL_VISUALIZATION.out.tables
    plots    = BIOC_CYTOMAPPER_PIXEL_AND_CELL_VISUALIZATION.out.plots
    objects  = BIOC_CYTOMAPPER_PIXEL_AND_CELL_VISUALIZATION.out.objects
    versions = BIOC_CYTOMAPPER_PIXEL_AND_CELL_VISUALIZATION.out.versions
}
