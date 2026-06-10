#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ecolitk — circular_genome_visualization
// Visualize genomic regions of interest (such as genes, peaks, or operons) on a circular genome map using ecolitk's circular plotting primitives.
// Input: regions.bed, coldata.csv
// Container: 1.82.0--r45h1f0d9b5_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ecolitk
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ECOLITK_CIRCULAR_GENOME_VISUALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
    library(ecolitk)
    library(graphics)
    library(grDevices)
    library(utils)
    
    # ==========================================
    # Stage 1: Import and Preprocess Input Data
    # ==========================================
    
    # Read the genomic regions from the BED file
    if (!file.exists("regions.bed")) {
      stop("Required input file 'regions.bed' is missing.")
    }
    
    # Read BED file (handling potential absence of header)
    regions <- read.table("regions.bed", header=FALSE, sep="\t", stringsAsFactors=FALSE)
    colnames(regions)[1:min(6, ncol(regions))] <- c("chrom", "start", "end", "name", "score", "strand")[1:min(6, ncol(regions))]
    
    # Ensure standard columns exist
    if (!"strand" %in% colnames(regions)) {
      regions\$strand <- "*"
    }
    if (!"score" %in% colnames(regions)) {
      regions\$score <- 1
    }
    if (!"name" %in% colnames(regions)) {
      regions\$name <- paste0("Region_", seq_len(nrow(regions)))
    }
    
    # Read optional metadata if available
    if (file.exists("coldata.csv")) {
      coldata <- read.csv("coldata.csv", stringsAsFactors=FALSE)
      if ("name" %in% colnames(coldata)) {
        regions <- merge(regions, coldata, by="name", all.x=TRUE)
      }
    }
    
    # Determine the genome length dynamically
    # Use ecolitk's built-in ecoli.len if available, otherwise infer from data
    g_len <- if (exists("ecoli.len")) ecoli.len else 4639221
    max_coord <- max(regions\$end, na.rm=TRUE)
    if (max_coord > g_len) {
      g_len <- as.numeric(max_coord) * 1.02 # Add 2% padding
    }
    
    # ==========================================
    # Stage 2: Calculate Circular Coordinates
    # ==========================================
    
    # Convert genomic positions to angles (radians) using ecolitk's chromPos2angle
    regions\$theta_start <- chromPos2angle(regions\$start, g_len)
    regions\$theta_end <- chromPos2angle(regions\$end, g_len)
    
    # Assign colors based on strand or metadata
    regions\$color <- "gray50" # Default
    regions\$color[regions\$strand == "+" | regions\$strand == ">"] <- "firebrick"
    regions\$color[regions\$strand == "-" | regions\$strand == "<"] <- "navyblue"
    
    # If custom color is provided in coldata, override
    if ("color" %in% colnames(regions)) {
      valid_colors <- !is.na(regions\$color.y) & regions\$color.y != ""
      regions\$color[valid_colors] <- regions\$color.y[valid_colors]
    }
    
    # Save the mapped coordinates to a CSV file
    write.csv(regions, "circular_coordinates.csv", row.names=FALSE)
    
    # ==========================================
    # Stage 3: Generate Circular Genome Plots
    # ==========================================
    
    pdf("circular_genome_map.pdf", width=10, height=10)
    
    # --- Plot 1: Global Circular Genome Map ---
    # Initialize the circular plot
    cPlotCircle(main.inside = "E. coli Genome", main = "Global Genomic Regions Map")
    
    # Plot positive strand regions on an outer ring (radius 1.1 to 1.3)
    pos_idx <- which(regions\$strand == "+" | regions\$strand == ">")
    if (length(pos_idx) > 0) {
      polygonChrom(regions\$start[pos_idx], regions\$end[pos_idx], g_len, 1.1, 1.3, 
                   col=regions\$color[pos_idx], border=NA)
    }
    
    # Plot negative strand regions on an inner ring (radius 0.8 to 1.0)
    neg_idx <- which(regions\$strand == "-" | regions\$strand == "<")
    if (length(neg_idx) > 0) {
      polygonChrom(regions\$start[neg_idx], regions\$end[neg_idx], g_len, 0.8, 1.0, 
                   col=regions\$color[neg_idx], border=NA)
    }
    
    # Plot unstranded or other regions on a middle ring (radius 1.0 to 1.1)
    other_idx <- which(!seq_len(nrow(regions)) %in% c(pos_idx, neg_idx))
    if (length(other_idx) > 0) {
      polygonChrom(regions\$start[other_idx], regions\$end[other_idx], g_len, 1.0, 1.1, 
                   col=regions\$color[other_idx], border=NA)
    }
    
    # Add a reference circle
    linesCircle(1.0, col="gray80", lty=2)
    
    
    # --- Plot 2: Zoomed-in View of the Top Region ---
    if (nrow(regions) > 0) {
      # Identify the region with the highest score to zoom in on
      zoom_idx <- which.max(regions\$score)
      zoom_region <- regions[zoom_idx, ]
      
      # Define a window around the region (e.g., +/- 100 kb)
      window_size <- 100000
      win_start <- max(0, zoom_region\$start - window_size)
      win_end <- min(g_len, zoom_region\$end + window_size)
      
      # Calculate the angular span of the window to determine plot limits
      t_start <- chromPos2angle(win_start, g_len)
      t_end <- chromPos2angle(win_end, g_len)
      
      # Generate points along the arc at the outer radius to find the bounding box
      t_seq <- seq(t_start, t_end, length.out=100)
      pts <- polar2xy(rep(1.4, length(t_seq)), t_seq)
      
      # Initialize a zoomed circular plot using the calculated limits
      cPlotCircle(xlim=range(pts\$x), ylim=range(pts\$y), 
                  main = paste("Zoomed View: Region", zoom_region\$name))
      
      # Draw reference grid lines
      linesCircle(1.0, col="gray80", lty=2)
      
      # Plot all regions falling within this window
      in_window <- which(regions\$start >= win_start & regions\$end <= win_end)
      if (length(in_window) > 0) {
        polygonChrom(regions\$start[in_window], regions\$end[in_window], g_len, 1.0, 1.2, 
                     col=regions\$color[in_window], border="black")
        
        # Add text labels for the regions in the zoomed view
        for (idx in in_window) {
          mid_pos <- (regions\$start[idx] + regions\$end[idx]) / 2
          mid_angle <- chromPos2angle(mid_pos, g_len)
          # Convert polar label position to Cartesian
          label_xy <- polar2xy(1.25, mid_angle)
          text(label_xy\$x, label_xy\$y, labels=regions\$name[idx], cex=0.8, srt=mid_angle * (180/pi))
        }
      }
    }
    
    dev.off()
    
    cat("Analysis completed successfully. Outputs written to 'circular_coordinates.csv' and 'circular_genome_map.pdf'.\n")

    writeLines(c(
        '"BIOC_ECOLITK_CIRCULAR_GENOME_VISUALIZATION":',
        paste0('    ecolitk: ', as.character(packageVersion('ecolitk')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_circular_genome_visualization.csv versions.yml
    """
}

workflow BIOC_ECOLITK_CIRCULAR_GENOME_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_ECOLITK_CIRCULAR_GENOME_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_ECOLITK_CIRCULAR_GENOME_VISUALIZATION.out.tables
    plots    = BIOC_ECOLITK_CIRCULAR_GENOME_VISUALIZATION.out.plots
    objects  = BIOC_ECOLITK_CIRCULAR_GENOME_VISUALIZATION.out.objects
    versions = BIOC_ECOLITK_CIRCULAR_GENOME_VISUALIZATION.out.versions
}
