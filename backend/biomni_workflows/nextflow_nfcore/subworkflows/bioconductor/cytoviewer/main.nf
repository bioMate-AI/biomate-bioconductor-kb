#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: cytoviewer — cytoviewer_interactive_pipeline
// Build an interactive multi-channel visualization and cell-level analysis pipeline using cytoviewer from a raw microscopy image.
// Input: image.tif
// Container: 1.10.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: EBImage, S4Vectors, SingleCellExperiment, SummarizedExperiment, cytomapper, cytoviewer
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CYTOVIEWER_CYTOVIEWER_INTERACTIVE_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-imaging:3.20-deps"

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
    .bm_deps <- c("cytoviewer", "cytomapper", "EBImage", "S4Vectors", "SummarizedExperiment")
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
    
    # --- Load required libraries ---
    library(SummarizedExperiment)
    library(cytoviewer)
    library(cytomapper)
    library(EBImage)
    library(S4Vectors)
    
    # --- Read input image from the working directory ---
    message("Reading input image...")
    img_raw <- EBImage::readImage("image.tif")
    
    # --- Preprocess and construct CytoImageList for images ---
    message("Preparing image CytoImageList...")
    img_list <- list(sample_image = img_raw)
    img_cil <- cytomapper::CytoImageList(img_list)
    
    # Assign channel names based on image dimensions
    img_dim <- dim(img_raw)
    if (length(img_dim) == 2) {
      channelNames(img_cil) <- "Channel1"
    } else if (length(img_dim) == 3) {
      channelNames(img_cil) <- paste0("Channel", seq_len(img_dim[3]))
    }
    
    # --- Generate a segmentation mask from the image ---
    message("Generating segmentation mask...")
    if (length(img_dim) == 3) {
      # Use the first channel for segmentation
      img_for_seg <- img_raw[,,1]
    } else {
      img_for_seg <- img_raw
    }
    
    # Apply Otsu's thresholding to identify foreground objects (cells)
    thr <- EBImage::otsu(img_for_seg)
    binary_mask <- img_for_seg > thr
    labeled_mask <- EBImage::bwlabel(binary_mask)
    
    # Save the segmentation mask to disk
    EBImage::writeImage(labeled_mask, "segmentation_mask.tiff")
    
    # Wrap the mask in a CytoImageList
    mask_cil <- cytomapper::CytoImageList(list(sample_image = labeled_mask))
    
    # --- Link images and masks using metadata ---
    message("Linking image and mask metadata...")
    S4Vectors::mcols(img_cil)\$ImageNb <- "Image1"
    S4Vectors::mcols(mask_cil)\$ImageNb <- "Image1"
    
    # --- Measure cell-specific features to generate a ---
    message("Measuring object features...")
    sce <- cytomapper::measureObjects(
      image = img_cil, 
      mask = mask_cil, 
      img_id = "ImageNb"
    )
    
    # Export cell measurements to CSV
    measurements_df <- as.data.frame(SummarizedExperiment::colData(sce))
    write.csv(measurements_df, "cell_measurements.csv", row.names = FALSE)
    
    # --- Build and serialize the cytoviewer Shiny application ---
    message("Building cytoviewer application...")
    app <- cytoviewer(
      image = img_cil,
      mask = mask_cil,
      object = sce,
      img_id = "ImageNb",
      cell_id = "object_id"
    )
    
    # Save the app object for deployment or future interactive sessions
    saveRDS(app, "cytoviewer_app.rds")
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_CYTOVIEWER_CYTOVIEWER_INTERACTIVE_PIPELINE":',
        paste0('    cytoviewer: ', as.character(packageVersion('cytoviewer')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cytoviewer_interactive_pipeline.csv versions.yml
    """
}

workflow BIOC_CYTOVIEWER_CYTOVIEWER_INTERACTIVE_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_CYTOVIEWER_CYTOVIEWER_INTERACTIVE_PIPELINE(ch_input)

    emit:
    tables   = BIOC_CYTOVIEWER_CYTOVIEWER_INTERACTIVE_PIPELINE.out.tables
    plots    = BIOC_CYTOVIEWER_CYTOVIEWER_INTERACTIVE_PIPELINE.out.plots
    objects  = BIOC_CYTOVIEWER_CYTOVIEWER_INTERACTIVE_PIPELINE.out.objects
    versions = BIOC_CYTOVIEWER_CYTOVIEWER_INTERACTIVE_PIPELINE.out.versions
}
