#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ggcyto — ggcyto_pixel_flow_analysis
// Convert a microscopy image into a flow cytometry data structure (flowSet) to perform multi-sample 1D/2D density profiling, gating, and logicle transformations u
// Input: image.tif
// Container: 1.38.1--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: EBImage, flowCore, ggcyto, ggplot2
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GGCYTO_GGCYTO_PIXEL_FLOW_ANALYSIS {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(EBImage)
    library(flowCore)
    library(ggcyto)
    library(ggplot2)
    
    # --- Read image and convert to flow cytometry data structures ---
    message("Reading image.tif...")
    img <- tryCatch({
      EBImage::readImage("image.tif")
    }, error = function(e) {
      stop("Failed to read image.tif: ", e\$message)
    })
    
    img_mat <- as.array(img)
    dims <- dim(img_mat)
    message(paste("Image dimensions:", paste(dims, collapse = "x")))
    
    # Scale intensities to a typical flow cytometry range (0 - 10000)
    scale_factor <- 10000
    
    # Extract pixel coordinates and intensities
    if (length(dims) == 2) {
      df <- expand.grid(X = 1:dims[1], Y = 1:dims[2])
      df\$Ch1 <- as.vector(img_mat) * scale_factor
      df\$Ch2 <- as.vector(img_mat) * scale_factor * 0.8 # Mock second channel
    } else if (length(dims) >= 3) {
      df <- expand.grid(X = 1:dims[1], Y = 1:dims[2])
      df\$Ch1 <- as.vector(img_mat[,,1]) * scale_factor
      df\$Ch2 <- if (dims[3] >= 2) as.vector(img_mat[,,2]) * scale_factor else df\$Ch1 * 0.8
    }
    
    # Split the image into 4 quadrants to simulate a multi-sample flowSet
    mid_x <- mean(df\$X)
    mid_y <- mean(df\$Y)
    
    q1 <- df[df\$X <= mid_x & df\$Y <= mid_y, ]
    q2 <- df[df\$X > mid_x & df\$Y <= mid_y, ]
    q3 <- df[df\$X <= mid_x & df\$Y > mid_y, ]
    q4 <- df[df\$X > mid_x & df\$Y > mid_y, ]
    
    # Create flowFrames
    ff1 <- flowCore::flowFrame(as.matrix(q1))
    ff2 <- flowCore::flowFrame(as.matrix(q2))
    ff3 <- flowCore::flowFrame(as.matrix(q3))
    ff4 <- flowCore::flowFrame(as.matrix(q4))
    
    # Combine into a flowSet
    fs <- flowCore::flowSet(list(
      "Quadrant_1" = ff1, 
      "Quadrant_2" = ff2, 
      "Quadrant_3" = ff3, 
      "Quadrant_4" = ff4
    ))
    
    # Stage 2: 1D Density Plotting with ggcyto
    message("Generating 1D density plots...")
    p_1d <- ggcyto(fs, aes(x = Ch1)) + 
      geom_density(fill = "blue", alpha = 0.5) +
      labs_cyto("marker") +
      theme_minimal()
    
    # Stage 3: 2D Hexbin Plotting with ggcyto
    message("Generating 2D hexbin plots...")
    p_2d <- ggcyto(fs, aes(x = Ch1, y = Ch2)) + 
      geom_hex(bins = 64) +
      scale_fill_gradientn(colours = rainbow(7)) +
      theme_bw()
    
    # --- Gating and Statistics ---
    message("Applying rectangle gate and calculating statistics...")
    # Define a rectangle gate to capture high-intensity pixels
    rect_gate <- flowCore::rectangleGate(
      filterId = "High_Intensity", 
      "Ch1" = c(5000, 10000), 
      "Ch2" = c(5000, 10000)
    )
    
    # Add gate and stats to the 2D plot
    p_gated <- p_2d + 
      geom_gate(rect_gate) + 
      geom_stats(size = 4, color = "white", fill = "black")
    
    # --- In-line Transformations ---
    message("Applying logicle transformations...")
    p_transformed <- p_gated + 
      scale_x_logicle() + 
      scale_y_logicle()
    
    # --- Exporting Plots and Statistics ---
    message("Converting to pure ggplot objects and saving...")
    gg_1d <- as.ggplot(p_1d)
    gg_transformed <- as.ggplot(p_transformed)
    
    # Save plots to PDF
    pdf("ggcyto_analysis_plots.pdf", width = 8, height = 6)
    print(gg_1d)
    print(gg_transformed)
    dev.off()
    
    # Calculate and save gating statistics
    filter_results <- flowCore::filter(fs, rect_gate)
    percentages <- sapply(filter_results, function(res) {
      sum(res@subSet) / length(res@subSet) * 100
    })
    
    stats_df <- data.frame(
      Quadrant = names(percentages),
      Gated_Percentage = percentages
    )
    write.csv(stats_df, "gating_statistics.csv", row.names = FALSE)
    message("Analysis complete. Outputs saved to 'ggcyto_analysis_plots.pdf' and 'gating_statistics.csv'.")

    writeLines(c(
        '"BIOC_GGCYTO_GGCYTO_PIXEL_FLOW_ANALYSIS":',
        paste0('    ggcyto: ', as.character(packageVersion('ggcyto')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ggcyto_pixel_flow_analysis.csv versions.yml
    """
}

workflow BIOC_GGCYTO_GGCYTO_PIXEL_FLOW_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_GGCYTO_GGCYTO_PIXEL_FLOW_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_GGCYTO_GGCYTO_PIXEL_FLOW_ANALYSIS.out.tables
    plots    = BIOC_GGCYTO_GGCYTO_PIXEL_FLOW_ANALYSIS.out.plots
    objects  = BIOC_GGCYTO_GGCYTO_PIXEL_FLOW_ANALYSIS.out.objects
    versions = BIOC_GGCYTO_GGCYTO_PIXEL_FLOW_ANALYSIS.out.versions
}
