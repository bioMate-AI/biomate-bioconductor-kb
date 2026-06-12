#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ncdfFlow — ncdf_flow_image_cytometry
// Convert a multi-channel microscopy image into a flow cytometry data representation, store it efficiently using HDF5-backed ncdfFlowSet, and perform compensation
// Input: image.tif
// Container: 2.56.0--r45ha27e39d_0
// R packages: EBImage, flowCore, flowStats, ncdfFlow
// Bioconductor: 3.20 | R: 4.4
// Requires: EBImage, flowCore, ncdfFlow
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_NCDFFLOW_NCDF_FLOW_IMAGE_CYTOMETRY {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-imaging:3.20"

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
    .bm_deps <- c("EBImage", "flowCore", "flowStats", "ncdfFlow")
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
    
    # --- Load required libraries ---
    library(EBImage)
    library(flowCore)
    library(ncdfFlow)
    
    # --- Read and preprocess the microscopy image ---
    message("Reading input image...")
    img <- EBImage::readImage("image.tif")
    img_data <- as.array(img)
    dims <- dim(img_data)
    
    # Downsample image if it is too large to optimize memory and processing speed
    downsample_factor <- 4
    if (dims[1] > 200 || dims[2] > 200) {
      message("Downsampling image for efficient flow processing...")
      if (length(dims) == 2) {
        img_data <- img_data[seq(1, dims[1], by = downsample_factor), 
                             seq(1, dims[2], by = downsample_factor)]
      } else {
        img_data <- img_data[seq(1, dims[1], by = downsample_factor), 
                             seq(1, dims[2], by = downsample_factor), , drop = FALSE]
      }
      dims <- dim(img_data)
    }
    
    # --- Convert image slices into flowFrames and write to FCS ---
    # We split the image into 3 horizontal slices to represent 3 distinct samples
    num_samples <- 3
    slice_width <- floor(dims[1] / num_samples)
    fcs_files <- c()
    
    message("Converting image slices to FCS files...")
    for (i in 1:num_samples) {
      x_start <- (i - 1) * slice_width + 1
      x_end <- i * slice_width
      
      # Extract spatial coordinates and pixel intensities
      coords <- expand.grid(X = x_start:x_end, Y = 1:dims[2])
      
      if (length(dims) == 2) {
        # Grayscale image
        slice <- img_data[x_start:x_end, ]
        intensities <- as.vector(slice)
        mat <- cbind(coords\$X, coords\$Y, intensities, intensities * 0.8, intensities * 0.5)
      } else {
        # Multichannel/Color image
        slice <- img_data[x_start:x_end, , , drop = FALSE]
        r <- as.vector(slice[, , 1])
        g <- if (dims[3] >= 2) as.vector(slice[, , 2]) else r * 0.8
        b <- if (dims[3] >= 3) as.vector(slice[, , 3]) else r * 0.5
        mat <- cbind(coords\$X, coords\$Y, r, g, b)
      }
      
      # Map image channels to standard flow cytometry parameters
      colnames(mat) <- c("FSC-H", "SSC-H", "FL1-H", "FL2-H", "FL3-H")
      
      # Create flowFrame and write to disk
      ff <- flowFrame(exprs = mat)
      fcs_file <- paste0("sample_", i, ".fcs")
      write.FCS(ff, fcs_file)
      fcs_files <- c(fcs_files, fcs_file)
    }
    
    # --- Create HDF5-backed ncdfFlowSet ---
    message("Creating ncdfFlowSet from FCS files...")
    nc <- read.ncdfFlowSet(files = fcs_files, ncdfFile = "image_flow.nc")
    
    # Annotate the dataset with metadata
    sample_metadata <- data.frame(
      row.names = sampleNames(nc),
      SampleID = paste0("Slice_", 1:num_samples),
      Treatment = c("Control", "Treated_A", "Treated_B")
    )
    pData(nc) <- sample_metadata
    
    # --- Compensation ---
    message("Applying compensation...")
    # Create a dummy diagonal compensation matrix for the 3 fluorescent channels
    comp_mat <- diag(3)
    colnames(comp_mat) <- c("FL1-H", "FL2-H", "FL3-H")
    rownames(comp_mat) <- c("FL1-H", "FL2-H", "FL3-H")
    comp_obj <- compensation(comp_mat)
    nc_comp <- compensate(nc, comp_obj)
    
    # --- Gating and Subsetting ---
    message("Gating and subsetting background pixels...")
    # Define a rectangle gate to filter out low-intensity background pixels
    rect_gate <- rectangleGate(filterId = "SignalGate", "FL1-H" = c(0.1, Inf))
    filter_results <- filter(nc_comp, rect_gate)
    
    # Subset the ncdfFlowSet to keep only signal-positive pixels
    nc_subset <- Subset(nc_comp, rect_gate)
    
    # --- Transformation ---
    message("Applying arcsinh transformation...")
    asinh_trans <- arcsinhTransform(transformationId = "arcsinh-transform", a = 1, b = 1, c = 1)
    nc_trans <- transform(nc_subset, `FL1-H` = asinh_trans(`FL1-H`), `FL2-H` = asinh_trans(`FL2-H`))
    
    # --- Splitting ---
    message("Splitting dataset by quad gate...")
    # Define a quad gate based on spatial coordinates and intensity
    mean_fsc <- mean(range(nc_trans[[1]])[, "FSC-H"])
    q_gate <- quadGate(filterId = "SpatialQuad", "FSC-H" = mean_fsc, "FL1-H" = 0.5)
    split_results <- filter(nc_trans, q_gate)
    nc_list <- split(nc_trans, split_results)
    
    # --- Exporting Results and Visualisation ---
    message("Exporting summary statistics and diagnostic plots...")
    
    # Extract summary statistics
    stats_list <- lapply(sampleNames(nc_trans), function(sn) {
      ff_orig <- nc[[sn]]
      ff_trans <- nc_trans[[sn]]
      data.frame(
        Sample = sn,
        Original_Pixels = nrow(exprs(ff_orig)),
        Gated_Pixels = nrow(exprs(ff_trans)),
        Mean_FL1_Original = mean(exprs(ff_orig)[, "FL1-H"]),
        Mean_FL1_Transformed = mean(exprs(ff_trans)[, "FL1-H"])
      )
    })
    stats_df <- do.call(rbind, stats_list)
    write.csv(stats_df, "pixel_flow_summary.csv", row.names = FALSE)
    
    # Generate diagnostic plots
    pdf("pixel_intensity_plots.pdf", width = 10, height = 6)
    par(mfrow = c(2, 3))
    for (sn in sampleNames(nc)) {
      hist(exprs(nc[[sn]])[, "FL1-H"], 
           main = paste("Original FL1-H\n", sn), 
           xlab = "Intensity", col = "skyblue", breaks = 30)
    }
    for (sn in sampleNames(nc_trans)) {
      hist(exprs(nc_trans[[sn]])[, "FL1-H"], 
           main = paste("Transformed FL1-H\n", sn), 
           xlab = "Transformed Intensity", col = "tomato", breaks = 30)
    }
    dev.off()
    
    # Save the final processed ncdfFlowSet
    if (dir.exists("ncfs_output")) {
      unlink("ncfs_output", recursive = TRUE)
    }
    save_ncfs(nc_trans, outdir = "ncfs_output")
    
    # --- Cleanup temporary files ---
    message("Cleaning up temporary files...")
    unlink(nc)
    unlink(nc_comp)
    unlink(nc_subset)
    unlink(nc_trans)
    file.remove(fcs_files)
    file.remove("image_flow.nc")
    
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_NCDFFLOW_NCDF_FLOW_IMAGE_CYTOMETRY":',
        paste0('    ncdfFlow: ', as.character(packageVersion('ncdfFlow')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ncdf_flow_image_cytometry.csv versions.yml
    """
}

workflow BIOC_NCDFFLOW_NCDF_FLOW_IMAGE_CYTOMETRY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_NCDFFLOW_NCDF_FLOW_IMAGE_CYTOMETRY(ch_input)

    emit:
    tables   = BIOC_NCDFFLOW_NCDF_FLOW_IMAGE_CYTOMETRY.out.tables
    plots    = BIOC_NCDFFLOW_NCDF_FLOW_IMAGE_CYTOMETRY.out.plots
    objects  = BIOC_NCDFFLOW_NCDF_FLOW_IMAGE_CYTOMETRY.out.objects
    versions = BIOC_NCDFFLOW_NCDF_FLOW_IMAGE_CYTOMETRY.out.versions
}
