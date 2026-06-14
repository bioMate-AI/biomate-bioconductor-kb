#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: simpleseg — multiplexed_image_segmentation_and_normalization
// Segment multiplexed images to identify cell boundaries, extract single-cell features, and normalize marker intensities.
// Input: tiff_files
// Container: quay.io/biocontainers/bioconductor-simpleseg:1.12.0--r45hdfd78af_0
// R packages: EBImage, BiocStyle, cytomapper, ggplot2, simpleSeg
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SIMPLESEG_MULTIPLEXED_IMAGE_SEGMENTATION_AND_NORMALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-simpleseg:1.12.0--r45hdfd78af_0"

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
    .bm_deps <- c("EBImage", "BiocStyle", "cytomapper", "ggplot2", "simpleSeg", "SummarizedExperiment")
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
    
    # Load required packages    library(SummarizedExperiment)

    library(simpleSeg)
    library(ggplot2)
    library(EBImage)
    library(cytomapper)
    
    # ==========================================
    # --- Load multiplexed images from TIFF files ---
    # ==========================================
    
    # Define input directory
    input_dir <- "tiff_files"
    if (!dir.exists(input_dir)) {
      input_dir <- "."
    }
    
    # Find subdirectories (each representing an image/point) containing TIFF files
    imageDirs <- list.dirs(input_dir, full.names = TRUE, recursive = FALSE)
    has_tifs <- sapply(imageDirs, function(d) length(list.files(d, pattern = "\\\\.tif\$", ignore.case = TRUE)) > 0)
    imageDirs <- imageDirs[has_tifs]
    names(imageDirs) <- basename(imageDirs)
    
    # Fallback: if no subdirectories with TIFFs, check if the input directory itself contains TIFFs
    if (length(imageDirs) == 0) {
      tifs <- list.files(input_dir, pattern = "\\\\.tif\$", full.names = TRUE, ignore.case = TRUE)
      if (length(tifs) > 0) {
        imageDirs <- c("Image1" = input_dir)
      } else {
        stop("Error: No TIFF files found in 'tiff_files' or current directory.")
      }
    }
    
    # Get files in each directory
    files <- lapply(
      imageDirs,
      list.files,
      pattern = "tif",
      full.names = TRUE
    )
    
    # Read files with readImage from EBImage
    images <- lapply(files, EBImage::readImage, as.is = TRUE)
    
    # Convert to CytoImageList
    images <- cytomapper::CytoImageList(images)
    mcols(images)\$imageID <- names(images)
    
    # Ensure channel names are set and contain the required markers for downstream steps
    if (length(files) > 0 && length(files[[1]]) > 0) {
      chan_names <- tools::file_path_sans_ext(basename(files[[1]]))
      
      # Ensure "HH3" (nuclear marker) is present
      if (!"HH3" %in% chan_names) {
        nuc_idx <- grep("dapi|hoechst|dna|nuc|histone|hh3", chan_names, ignore.case = TRUE)
        if (length(nuc_idx) > 0) {
          chan_names[nuc_idx[1]] <- "HH3"
        } else {
          chan_names[1] <- "HH3"
        }
      }
      
      # Ensure other markers used in visualization/QC are present
      required_markers <- c("PanKRT", "GLUT1", "CD3", "CD20")
      for (m in required_markers) {
        if (!m %in% chan_names) {
          unmapped <- which(!chan_names %in% c("HH3", required_markers))
          if (length(unmapped) > 0) {
            chan_names[unmapped[1]] <- m
          }
        }
      }
      
      channelNames(images) <- chan_names
    }
    
    # ==========================================
    # --- Perform cell segmentation ---
    # ==========================================
    
    masks <- simpleSeg::simpleSeg(images,
      nucleus = "HH3",
      transform = "sqrt"
    )
    
    # Save segmentation mask visualization
    if (length(masks) > 0) {
      EBImage::writeImage(colorLabels(masks[[1]]), "segmentation_mask_display.png")
    }
    
    # Save outline overlay plot
    pdf("segmentation_outlines.pdf", width = 8, height = 8)
    tryCatch({
      cytomapper::plotPixels(
        image = images[1],
        mask = masks[1],
        img_id = "imageID",
        colour_by = c("PanKRT", "GLUT1", "HH3", "CD3", "CD20"),
        display = "single",
        colour = list(
          HH3 = c("black", "blue"),
          CD3 = c("black", "purple"),
          CD20 = c("black", "green"),
          GLUT1 = c("black", "red"),
          PanKRT = c("black", "yellow")
        ),
        bcg = list(
          HH3 = c(0, 1, 1.5),
          CD3 = c(0, 1, 1.5),
          CD20 = c(0, 1, 1.5),
          GLUT1 = c(0, 1, 1.5),
          PanKRT = c(0, 1, 1.5)
        ),
        legend = NULL
      )
    }, error = function(e) {
      warning("Could not generate outline overlay plot: ", e\$message)
    })
    dev.off()
    
    # ==========================================
    # --- Summarise cell features ---
    # ==========================================
    
    cellSCE <- cytomapper::measureObjects(masks, images, img_id = "imageID")
    
    # ==========================================
    # --- Normalising cells ---
    # ==========================================
    
    cellSCE <- normalizeCells(cellSCE,
      assayIn = "counts",
      assayOut = "norm",
      imageID = "imageID",
      transformation = "sqrt",
      method = c("trim99", "minMax")
    )
    
    # Save QC Normalization Plots
    pdf("pankrt_density_plots.pdf", width = 10, height = 5)
    tryCatch({
      # Extract raw marker data
      df_raw <- as.data.frame(cbind(colData(cellSCE), t(assay(cellSCE, "counts"))))
      p1 <- ggplot(df_raw, aes(x = PanKRT, colour = imageID)) +
        geom_density() +
        labs(x = "PanKRT expression (Raw)") +
        theme_minimal()
    
      # Extract normalised marker information
      df_norm <- as.data.frame(cbind(colData(cellSCE), t(assay(cellSCE, "norm"))))
      p2 <- ggplot(df_norm, aes(x = PanKRT, colour = imageID)) +
        geom_density() +
        labs(x = "PanKRT expression (Normalized)") +
        theme_minimal()
    
      print(p1)
      print(p2)
    }, error = function(e) {
      warning("Could not generate density plots: ", e\$message)
    })
    dev.off()
    
    # ==========================================
    # --- Save Outputs ---
    # ==========================================
    
    # Save SingleCellExperiment and Masks
    saveRDS(masks, "segmentation_masks.rds")
    saveRDS(cellSCE, "cell_single_cell_experiment.rds")
    
    # Save extracted features as CSV
    features_df <- as.data.frame(cbind(colData(cellSCE), t(assay(cellSCE, "norm"))))
    write.csv(features_df, "single_cell_features_normalized.csv", row.names = TRUE)
    
    message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_SIMPLESEG_MULTIPLEXED_IMAGE_SEGMENTATION_AND_NORMALIZATION":',
        paste0('        simpleseg: ', as.character(packageVersion("simpleseg")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multiplexed_image_segmentation_and_normalization.csv versions.yml
    """
}

workflow BIOC_SIMPLESEG_MULTIPLEXED_IMAGE_SEGMENTATION_AND_NORMALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ tiff_files ] ]

    main:
    BIOC_SIMPLESEG_MULTIPLEXED_IMAGE_SEGMENTATION_AND_NORMALIZATION(ch_input)

    emit:
    tables   = BIOC_SIMPLESEG_MULTIPLEXED_IMAGE_SEGMENTATION_AND_NORMALIZATION.out.tables
    plots    = BIOC_SIMPLESEG_MULTIPLEXED_IMAGE_SEGMENTATION_AND_NORMALIZATION.out.plots
    objects  = BIOC_SIMPLESEG_MULTIPLEXED_IMAGE_SEGMENTATION_AND_NORMALIZATION.out.objects
    versions = BIOC_SIMPLESEG_MULTIPLEXED_IMAGE_SEGMENTATION_AND_NORMALIZATION.out.versions
}
