#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: cytomapper — on_disk_image_handling
// Load and process large sets of images on disk using HDF5 format to minimize memory usage.
// Input: large_multi_channel_images.tiff, large_segmentation_masks.tiff
// Container: quay.io/biocontainers/bioconductor-cytomapper:1.22.0--r45hdfd78af_0
// R packages: HDF5Array, cytomapper
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CYTOMAPPER_ON_DISK_IMAGE_HANDLING {
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
    .bm_deps <- c("HDF5Array", "cytomapper")
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
    
    library(HDF5Array)
    library(cytomapper)
    
    # 1. Initialize a temporary or permanent directory for HDF5 files
    cur_dir <- getHDF5DumpDir()
    
    # Define path to user input files
    path.to.images <- "."
    
    # 2. Load images directly to disk using loadImages with on_disk = TRUE and h5FilesPath
    image.list <- loadImages(path.to.images, pattern = "large_segmentation_masks.tiff", on_disk = TRUE, h5FilesPath = cur_dir)
    
    # 3. Scale on-disk images using scaleImages
    image.list <- scaleImages(image.list, value = 2^16 - 1)
    
    # Load the user's multi-channel images in-memory first to replace the demo data() call
    pancreasImages <- loadImages(path.to.images, pattern = "large_multi_channel_images.tiff", on_disk = FALSE)
    
    # Ensure the loaded images have channel names for downstream operations
    get_channel_count <- function(cil) {
      img <- cil[[1]]
      d <- dim(img)
      if (length(d) < 3) return(1)
      return(d[3])
    }
    num_channels <- get_channel_count(pancreasImages)
    channelNames(pancreasImages) <- paste0("CH", 1:num_channels)
    
    # 4. Convert existing in-memory CytoImageList objects to on-disk representation using CytoImageList
    pancreasImages_onDisk <- CytoImageList(pancreasImages, on_disk = TRUE, h5FilesPath = cur_dir)
    
    # 5. Convert on-disk CytoImageList objects back to in-memory representation if needed
    pancreasImages_inMemory <- CytoImageList(pancreasImages_onDisk, on_disk = FALSE)
    
    # 6. Normalize on-disk images using normalize
    pancreasImages_norm <- normalize(pancreasImages_onDisk)
    
    # 7. Merge channels on-disk using mergeChannels
    channels1 <- getChannels(pancreasImages_onDisk, 1:2)
    channels2 <- getChannels(pancreasImages_onDisk, 3:4)
    dir.create(file.path(cur_dir, "test"), showWarnings = FALSE)
    cur_path_2 <- file.path(cur_dir, "test")
    channels3 <- mergeChannels(channels1, channels2, h5FilesPath = cur_path_2)
    
    # Save meaningful results to output files
    saveRDS(image.list, "scaled_masks_on_disk.rds")
    saveRDS(pancreasImages_norm, "normalized_images_on_disk.rds")
    saveRDS(channels3, "merged_channels_on_disk.rds")
    
    # Create and save a summary table of the workflow stages
    summary_df <- data.frame(
      Object = c("image.list", "pancreasImages", "pancreasImages_onDisk", "pancreasImages_norm", "channels3"),
      OnDisk = c(TRUE, FALSE, TRUE, TRUE, TRUE),
      Channels = c(get_channel_count(image.list), get_channel_count(pancreasImages), get_channel_count(pancreasImages_onDisk), get_channel_count(pancreasImages_norm), get_channel_count(channels3))
    )
    write.csv(summary_df, "on_disk_workflow_summary.csv", row.names = FALSE)
    
    # Generate a PDF plot of the normalized on-disk images
    pdf("normalized_images_plot.pdf")
    plotPixels(pancreasImages_norm, colour_by = channelNames(pancreasImages_norm)[1:min(3, num_channels)])
    dev.off()

    writeLines(c(
        '"BIOC_CYTOMAPPER_ON_DISK_IMAGE_HANDLING":',
        paste0('        cytomapper: ', as.character(packageVersion("cytomapper")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_on_disk_image_handling.csv versions.yml
    """
}

workflow BIOC_CYTOMAPPER_ON_DISK_IMAGE_HANDLING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ large_multi_channel_images.tiff, large_segmentation_masks.tiff ] ]

    main:
    BIOC_CYTOMAPPER_ON_DISK_IMAGE_HANDLING(ch_input)

    emit:
    tables   = BIOC_CYTOMAPPER_ON_DISK_IMAGE_HANDLING.out.tables
    plots    = BIOC_CYTOMAPPER_ON_DISK_IMAGE_HANDLING.out.plots
    objects  = BIOC_CYTOMAPPER_ON_DISK_IMAGE_HANDLING.out.objects
    versions = BIOC_CYTOMAPPER_ON_DISK_IMAGE_HANDLING.out.versions
}
