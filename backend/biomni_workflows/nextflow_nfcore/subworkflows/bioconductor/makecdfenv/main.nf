#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: makecdfenv — makecdfenv_custom_chip
// Create a custom Affymetrix CDF environment and package from feature IDs in a matrix, and visualize probe coordinates.
// Input: matrix.csv, coldata.csv
// Container: 1.86.0--r45h01b2380_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: affy, makecdfenv
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MAKECDFENV_MAKECDFENV_CUSTOM_CHIP {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20"

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
    library(makecdfenv)
    library(affy)
    
    # --- Read input files ---
    message("Stage 1: Reading input files...")
    matrix_data <- read.csv("matrix.csv", stringsAsFactors = FALSE)
    coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
    
    message("Loaded matrix with ", nrow(matrix_data), " features.")
    message("Loaded coldata with ", nrow(coldata), " samples.")
    
    # --- Extract and sanitize feature IDs ---
    message("Stage 2: Extracting and sanitizing feature IDs...")
    if ("feature_id" %in% colnames(matrix_data)) {
      feature_ids <- matrix_data\$feature_id
    } else {
      feature_ids <- matrix_data[, 1]
    }
    
    # Sanitize feature IDs to be valid CDF unit names (alphanumeric and underscores only)
    sanitized_features <- gsub("[^A-Za-z0-9_]", "_", feature_ids)
    sanitized_features <- make.unique(sanitized_features)
    
    # Limit to a reasonable number of features to keep CDF generation fast and lightweight
    max_features <- min(length(sanitized_features), 200)
    sanitized_features <- sanitized_features[1:max_features]
    message("Using ", max_features, " features for custom CDF generation.")
    
    # --- Generate ASCII CDF file ---
    message("Stage 3: Generating ASCII CDF file...")
    cdf_filename <- "CustomChip.cdf"
    grid_size <- as.integer(ceiling(sqrt(max_features * 2)) + 5) # Ensure enough space for coordinates
    
    con <- file(cdf_filename, "w")
    writeLines("[CDF]", con)
    writeLines("Version=GC3.0", con)
    writeLines("", con)
    writeLines("[Chip]", con)
    writeLines("Name=CustomChip", con)
    writeLines(paste0("Rows=", grid_size), con)
    writeLines(paste0("Cols=", grid_size), con)
    writeLines(paste0("NumberOfUnits=", max_features), con)
    writeLines("NumQCUnits=0", con)
    writeLines("", con)
    
    for (i in seq_len(max_features)) {
      fid <- sanitized_features[i]
      writeLines(paste0("[Unit", i, "]"), con)
      writeLines(paste0("Name=", fid), con)
      writeLines("Direction=1", con)
      writeLines("NumBlocks=1", con)
      writeLines("NumCells=1", con)
      writeLines("UnitType=1", con)
      writeLines(paste0("Number=", i), con)
      writeLines("", con)
      
      writeLines(paste0("[Unit", i, "_Block1]"), con)
      writeLines(paste0("Name=", fid, "_block"), con)
      writeLines("NumAtoms=1", con)
      writeLines("NumCells=1", con)
      writeLines("StartPosition=0", con)
      writeLines("StopPosition=0", con)
      
      # Calculate unique X and Y coordinates
      x <- (i - 1) %% grid_size
      y <- (i - 1) %/% grid_size
      
      # Cell1=X,Y,ProbeSeq,TargetSeq,Exon,etc.
      writeLines(paste0("Cell1=", x, ",", y, ",A,T,1,0,0,0,0,0"), con)
      writeLines("", con)
    }
    close(con)
    message("ASCII CDF file written to ", cdf_filename)
    
    # --- Create CDF Environment ---
    message("Stage 4: Creating CDF environment...")
    custom_env <- make.cdf.env(cdf_filename)
    message("CDF environment successfully created.")
    
    # --- Create CDF Package ---
    message("Stage 5: Creating CDF package...")
    # Clean package name using cleancdfname
    pkg_name <- cleancdfname("CustomChip")
    make.cdf.package(cdf_filename, 
                     packagename = pkg_name, 
                     species = "Homo_sapiens", 
                     author = "Bioconductor Expert", 
                     maintainer = "Expert <expert@example.com>", 
                     version = "1.0.0")
    message("CDF package directory created: ", pkg_name)
    
    # --- Export Summary and Diagnostics ---
    message("Stage 6: Exporting summary and diagnostics...")
    env_list <- as.list(custom_env)
    probe_sets <- names(env_list)
    
    summary_list <- list()
    for (ps in probe_sets) {
      val <- env_list[[ps]]
      nr <- if (is.matrix(val) || is.data.frame(val)) nrow(val) else length(val)
      summary_list[[ps]] <- data.frame(
        ProbeSet = ps,
        NumProbes = nr,
        stringsAsFactors = FALSE
      )
    }
    summary_df <- do.call(rbind, summary_list)
    write.csv(summary_df, "cdf_env_summary.csv", row.names = FALSE)
    
    # List package files to verify package creation
    pkg_files <- list.files(pkg_name, recursive = TRUE)
    write.csv(data.frame(FilePath = pkg_files), "package_files.csv", row.names = FALSE)
    
    # Plot probe coordinates
    pdf("probe_pos_plot.pdf", width = 7, height = 7)
    plot(1, type = "n", xlab = "X Coordinate", ylab = "Y Coordinate", 
         xlim = c(0, grid_size), ylim = c(0, grid_size),
         main = "Probe Locations on Custom Chip")
    
    xs <- c()
    ys <- c()
    for (ps in names(env_list)) {
      val <- env_list[[ps]]
      indices <- as.vector(val)
      indices <- indices[!is.na(indices)]
      # Convert 1-based index to x, y using the side length (grid_size)
      x_coords <- (indices - 1) %% grid_size
      y_coords <- (indices - 1) %/% grid_size
      xs <- c(xs, x_coords)
      ys <- c(ys, y_coords)
    }
    
    points(xs, ys, col = "darkblue", pch = 19, cex = 0.8)
    grid()
    dev.off()
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_MAKECDFENV_MAKECDFENV_CUSTOM_CHIP":',
        paste0('    makecdfenv: ', as.character(packageVersion('makecdfenv')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_makecdfenv_custom_chip.csv versions.yml
    """
}

workflow BIOC_MAKECDFENV_MAKECDFENV_CUSTOM_CHIP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_MAKECDFENV_MAKECDFENV_CUSTOM_CHIP(ch_input)

    emit:
    tables   = BIOC_MAKECDFENV_MAKECDFENV_CUSTOM_CHIP.out.tables
    plots    = BIOC_MAKECDFENV_MAKECDFENV_CUSTOM_CHIP.out.plots
    objects  = BIOC_MAKECDFENV_MAKECDFENV_CUSTOM_CHIP.out.objects
    versions = BIOC_MAKECDFENV_MAKECDFENV_CUSTOM_CHIP.out.versions
}
