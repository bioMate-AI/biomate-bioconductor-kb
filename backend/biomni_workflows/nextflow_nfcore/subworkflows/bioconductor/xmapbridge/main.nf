#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: xmapbridge — xmapbridge_genome_browser_export
// Import genomic regions and sample metadata to generate structured multi-track genome browser visualization files for the X:Map genome browser.
// Input: regions.bed, coldata.csv
// Container: 1.68.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, rtracklayer, xmapbridge
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_XMAPBRIDGE_XMAPBRIDGE_GENOME_BROWSER_EXPORT {
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
    .bm_deps <- c("xmapbridge", "rtracklayer", "GenomicRanges")
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
    
    # --- Load libraries and set up local cache environment ---
    library(xmapbridge)
    library(rtracklayer)
    library(GenomicRanges)
    
    # Set the XMAP_BRIDGE_CACHE environment variable to a local directory
    # so that the generated files are written directly to the working directory.
    cache_dir <- file.path(getwd(), "xmb_cache")
    if (!dir.exists(cache_dir)) {
      dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
    }
    Sys.setenv(XMAP_BRIDGE_CACHE = cache_dir)
    
    message("Using XMAP_BRIDGE_CACHE directory: ", cache_dir)
    
    # --- Import and preprocess input genomic data ---
    if (!file.exists("regions.bed")) {
      stop("Required input file 'regions.bed' is missing.")
    }
    
    message("Importing genomic regions from regions.bed...")
    regions <- rtracklayer::import("regions.bed")
    
    # Ensure we have valid scores
    if (is.null(score(regions)) || all(is.na(score(regions)))) {
      score(regions) <- rep(1.0, length(regions))
    }
    
    # Read optional coldata metadata
    coldata <- NULL
    if (file.exists("coldata.csv")) {
      message("Importing sample metadata from coldata.csv...")
      coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
    }
    
    # Determine sample columns to plot
    # If coldata has numeric columns matching the number of regions, we treat them as sample tracks.
    # Otherwise, we fall back to using the BED score.
    if (!is.null(coldata) && nrow(coldata) == length(regions)) {
      numeric_cols <- sapply(coldata, is.numeric)
      if (any(numeric_cols)) {
        sample_data <- coldata[, numeric_cols, drop = FALSE]
        message("Using numeric columns from coldata.csv as sample tracks: ", paste(colnames(sample_data), collapse = ", "))
      } else {
        message("No numeric columns found in coldata.csv. Falling back to BED scores.")
        sample_data <- data.frame(Score = score(regions))
      }
    } else {
      message("No matching coldata.csv found or row count mismatch. Using BED scores as the single track.")
      sample_data <- data.frame(Score = score(regions))
    }
    
    # --- Generate X:Map Project, Graphs, and Plots ---
    message("Initializing new X:Map project...")
    project_name <- "Genomic Regions Analysis Project"
    pid <- xmap.project.new(project_name)
    
    # Group regions by chromosome to create separate graphs per chromosome
    chromosomes <- unique(as.character(seqnames(regions)))
    
    for (chr in chromosomes) {
      message("Processing chromosome: ", chr)
      chr_idx <- which(as.character(seqnames(regions)) == chr)
      
      chr_regions <- regions[chr_idx]
      chr_samples <- sample_data[chr_idx, , drop = FALSE]
      
      # Calculate midpoints for x-coordinates
      x_coords <- start(chr_regions) + (end(chr_regions) - start(chr_regions)) / 2
      
      # Define genomic boundaries for the graph
      start_pos <- min(start(chr_regions))
      stop_pos <- max(end(chr_regions))
      
      # Determine y-axis limits across all samples on this chromosome
      y_min <- min(chr_samples, na.rm = TRUE)
      y_max <- max(chr_samples, na.rm = TRUE)
      if (y_min == y_max) {
        y_min <- y_min - 1
        y_max <- y_max + 1
      }
      
      # Create a new graph for this chromosome
      gph <- xmap.graph.new(
        projectid = pid,
        name = paste0("Chr_", chr),
        desc = paste("Visualizing regions on chromosome", chr),
        min = y_min,
        max = y_max,
        chr = chr,
        start = start_pos,
        stop = stop_pos,
        ylab = "Signal Intensity",
        species = "homo_sapiens"
      )
      
      # Generate distinct colors for each sample track
      num_samples <- ncol(chr_samples)
      colors_raw <- rainbow(num_samples)
      colors_fg <- xmap.col(colors_raw, alpha = 0xff) # Opaque lines
      colors_bg <- xmap.col(colors_raw, alpha = 0x33) # Transparent area fills
      
      # Plot each sample track onto the chromosome graph
      for (i in seq_len(num_samples)) {
        sample_name <- colnames(chr_samples)[i]
        y_vals <- chr_samples[[sample_name]]
        
        # Add transparent area plot
        xmap.points(
          graphid = gph,
          x = x_coords,
          y = y_vals,
          type = "area",
          col = colors_bg[i],
          xlab = sample_name
        )
        
        # Add opaque line plot on top
        xmap.points(
          graphid = gph,
          x = x_coords,
          y = y_vals,
          type = "line",
          col = colors_fg[i],
          xlab = sample_name
        )
      }
    }
    
    # Save the project structure to the cache
    tryCatch({
      xmap.project.save(pid)
      message("Project successfully saved to cache.")
    }, error = function(e) {
      warning("Could not explicitly save project, files may have been auto-written: ", e\$message)
    })
    
    # --- Export summaries and file lists ---
    message("Generating output summaries...")
    
    # Retrieve lists of generated objects
    projects_list <- tryCatch(xmap.project.list(), error = function(e) project_name)
    graphs_list <- tryCatch(xmap.graph.list(), error = function(e) paste0("Chr_", chromosomes))
    plots_list <- tryCatch(xmap.plot.list(), error = function(e) "Multiple Plots")
    
    summary_df <- data.frame(
      Category = c("Projects", "Graphs", "Plots"),
      Count = c(length(projects_list), length(graphs_list), length(plots_list)),
      Details = c(
        paste(projects_list, collapse = "; "),
        paste(graphs_list, collapse = "; "),
        paste(plots_list, collapse = "; ")
      ),
      stringsAsFactors = FALSE
    )
    
    write.csv(summary_df, "xmb_cache_summary.csv", row.names = FALSE)
    
    # List all files written to the cache directory
    cache_files <- list.files(cache_dir, recursive = TRUE)
    writeLines(cache_files, "xmb_files_list.txt")
    
    message("Pipeline complete. Cache files are ready for XMapBridge visualization.")

    writeLines(c(
        '"BIOC_XMAPBRIDGE_XMAPBRIDGE_GENOME_BROWSER_EXPORT":',
        paste0('    xmapbridge: ', as.character(packageVersion('xmapbridge')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_xmapbridge_genome_browser_export.csv versions.yml
    """
}

workflow BIOC_XMAPBRIDGE_XMAPBRIDGE_GENOME_BROWSER_EXPORT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_XMAPBRIDGE_XMAPBRIDGE_GENOME_BROWSER_EXPORT(ch_input)

    emit:
    tables   = BIOC_XMAPBRIDGE_XMAPBRIDGE_GENOME_BROWSER_EXPORT.out.tables
    plots    = BIOC_XMAPBRIDGE_XMAPBRIDGE_GENOME_BROWSER_EXPORT.out.plots
    objects  = BIOC_XMAPBRIDGE_XMAPBRIDGE_GENOME_BROWSER_EXPORT.out.objects
    versions = BIOC_XMAPBRIDGE_XMAPBRIDGE_GENOME_BROWSER_EXPORT.out.versions
}
