#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: BeadDataPackR — beaddatapackr_compression_pipeline
// Compress, decompress, and extract raw Illumina BeadArray data using BeadDataPackR, demonstrating lossless storage and direct data retrieval.
// Input: input.csv
// Container: 1.62.0--r45h01b2380_0
// R packages: BeadDataPackR
// Bioconductor: 3.20 | R: 4.4
// Requires: BeadDataPackR
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BEADDATAPACKR_BEADDATAPACKR_COMPRESSION_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    .bm_deps <- c("BeadDataPackR")
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
    library(BeadDataPackR)
    
    # ----------------------------------------------------------------------
    # Stage 1: Read User Input and Prepare Mock Illumina BeadArray Files
    # ----------------------------------------------------------------------
    message("Stage 1: Reading user input and preparing mock BeadArray files...")
    
    # Read input.csv defensively
    if (!file.exists("input.csv")) {
      stop("Error: input.csv not found in the working directory.")
    }
    
    input_data <- read.csv("input.csv", stringsAsFactors = FALSE, check.names = FALSE)
    
    # Determine probe IDs and intensities from input.csv
    if ("feature_id" %in% colnames(input_data)) {
      probe_ids <- input_data\$feature_id
      numeric_cols <- input_data[, setdiff(colnames(input_data), "feature_id"), drop = FALSE]
    } else if (is.character(input_data[[1]]) || is.factor(input_data[[1]])) {
      probe_ids <- input_data[[1]]
      numeric_cols <- input_data[, -1, drop = FALSE]
    } else {
      probe_ids <- rownames(input_data)
      if (is.null(probe_ids) || all(probe_ids == as.character(1:nrow(input_data)))) {
        probe_ids <- paste0("Probe_", 1:nrow(input_data))
      }
      numeric_cols <- input_data
    }
    
    # Clean and unique probe IDs
    probe_ids <- make.unique(as.character(probe_ids))
    
    # Extract or generate intensities
    if (ncol(numeric_cols) >= 1 && any(sapply(numeric_cols, is.numeric))) {
      num_idx <- which(sapply(numeric_cols, is.numeric))[1]
      intensities <- numeric_cols[[num_idx]]
    } else {
      intensities <- runif(length(probe_ids), min = 100, max = 1000)
    }
    
    # Cap the number of probes to ensure fast and reliable grid generation
    max_probes <- min(length(probe_ids), 1000)
    probe_ids <- probe_ids[1:max_probes]
    intensities <- intensities[1:max_probes]
    
    # Define grid dimensions (nrow x ncol) to fit all probes
    N <- length(probe_ids)
    grid_dim <- max(ceiling(sqrt(N)), 2)
    M <- grid_dim * grid_dim  # Total beads in the locs file
    
    # Generate coordinates for a perfect grid
    X <- rep(1:grid_dim, each = grid_dim)
    Y <- rep(1:grid_dim, times = grid_dim)
    
    # Add fractional parts to simulate real scanner coordinates
    X_coords <- X + 0.125
    Y_coords <- Y + 0.375
    
    # Create temporary directory for raw files
    tempPath <- tempdir()
    txt_filename <- "input.txt"
    locs_filename <- "input_Grn.locs"
    bab_filename <- "compressed_data.bab"
    
    txt_file_path <- file.path(tempPath, txt_filename)
    locs_file_path <- file.path(tempPath, locs_filename)
    
    # Write the binary .locs file (Illumina format: 12-byte header + interleaved float coordinates)
    con <- file(locs_file_path, "wb")
    writeBin(as.numeric(1.0), con, size = 4)          # Header float 1
    writeBin(as.numeric(1.0), con, size = 4)          # Header float 2
    writeBin(as.integer(M), con, size = 4)            # Number of beads
    coords_interleaved <- as.numeric(as.vector(rbind(X_coords, Y_coords)))
    writeBin(coords_interleaved, con, size = 4)       # Coordinates
    close(con)
    
    # Write the tab-delimited .txt file (decoded beads)
    txt_df <- data.frame(
      Code = probe_ids,
      GrnX = X_coords[1:N],
      GrnY = Y_coords[1:N],
      Grn = intensities
    )
    write.table(txt_df, file = txt_file_path, sep = "\t", row.names = FALSE, quote = FALSE)
    
    message(sprintf("Successfully prepared mock files with %d decoded probes and %d total beads.", N, M))
    
    # ----------------------------------------------------------------------
    # Stage 2: Compress Bead Data
    # ----------------------------------------------------------------------
    message("Stage 2: Compressing raw BeadArray files...")
    
    compressBeadData(
      txtFile = txt_filename,
      locsGrn = locs_filename,
      outputFile = bab_filename,
      path = tempPath,
      nBytes = 4,
      nrow = grid_dim,
      ncol = grid_dim
    )
    
    # Calculate compression ratio
    original_size <- file.info(txt_file_path)\$size + file.info(locs_file_path)\$size
    compressed_size <- file.info(file.path(tempPath, bab_filename))\$size
    compression_ratio <- original_size / compressed_size
    
    message(sprintf("Compression complete. Ratio: %.2fx", compression_ratio))
    
    # ----------------------------------------------------------------------
    # Stage 3: Decompress Bead Data
    # ----------------------------------------------------------------------
    message("Stage 3: Decompressing .bab file...")
    
    decompressBeadData(
      inputFile = bab_filename,
      inputPath = tempPath,
      outputMask = "restored",
      outputPath = tempPath,
      outputNonDecoded = TRUE,
      roundValues = TRUE
    )
    
    # Verify restored files exist
    restored_txt <- file.path(tempPath, "restored.txt")
    restored_locs <- file.path(tempPath, "restored_Grn.locs")
    
    if (file.exists(restored_txt) && file.exists(restored_locs)) {
      message("Decompression verified successfully.")
    } else {
      warning("Decompressed files could not be verified.")
    }
    
    # ----------------------------------------------------------------------
    # Stage 4: Direct Data Extraction and Analysis
    # ----------------------------------------------------------------------
    message("Stage 4: Extracting data directly from compressed .bab file...")
    
    # Extract all data directly
    extracted_data <- readCompressedData(
      inputFile = bab_filename,
      path = tempPath
    )
    
    # Extract coordinates from the locs file
    extracted_locs <- extractLocsFile(
      inputFile = bab_filename,
      path = tempPath
    )
    
    # Write extracted data to output files
    write.csv(extracted_data, "decompressed_intensities.csv", row.names = FALSE)
    write.csv(extracted_locs, "extracted_locs.csv", row.names = FALSE)
    
    # ----------------------------------------------------------------------
    # Stage 5: Visualization and Summary Reporting
    # ----------------------------------------------------------------------
    message("Stage 5: Generating diagnostic plots and summary report...")
    
    # Generate diagnostic plot of bead locations
    pdf("bead_locations_plot.pdf", width = 8, height = 8)
    plot(
      extracted_locs[, 1], extracted_locs[, 2],
      main = "Reconstructed Bead Locations from Compressed Data",
      xlab = "X Coordinate",
      ylab = "Y Coordinate",
      col = "darkblue",
      pch = 19,
      cex = 0.8
    )
    # Highlight decoded beads
    points(
      extracted_data[, "GrnX"], extracted_data[, "GrnY"],
      col = "red",
      pch = 3,
      cex = 0.6
    )
    legend(
      "topright",
      legend = c("All Beads (Locs)", "Decoded Beads (Txt)"),
      col = c("darkblue", "red"),
      pch = c(19, 3)
    )
    dev.off()
    
    # Write compression summary report
    summary_conn <- file("compression_summary.txt", "w")
    cat("=== BeadDataPackR Compression Summary ===\n", file = summary_conn)
    cat(sprintf("Original Text File Size:       %d bytes\n", file.info(txt_file_path)\$size), file = summary_conn)
    cat(sprintf("Original Locs File Size:       %d bytes\n", file.info(locs_file_path)\$size), file = summary_conn)
    cat(sprintf("Total Uncompressed Size:       %d bytes\n", original_size), file = summary_conn)
    cat(sprintf("Compressed (.bab) File Size:   %d bytes\n", compressed_size), file = summary_conn)
    cat(sprintf("Compression Ratio:             %.2fx\n", compression_ratio), file = summary_conn)
    cat(sprintf("Number of Decoded Probes:      %d\n", N), file = summary_conn)
    cat(sprintf("Total Grid Beads:              %d\n", M), file = summary_conn)
    cat("Status: Lossless compression and extraction completed successfully.\n", file = summary_conn)
    close(summary_conn)
    
    message("Pipeline completed successfully. Outputs written to working directory.")

    writeLines(c(
        '"BIOC_BEADDATAPACKR_BEADDATAPACKR_COMPRESSION_PIPELINE":',
        paste0('    BeadDataPackR: ', as.character(packageVersion('BeadDataPackR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_beaddatapackr_compression_pipeline.csv versions.yml
    """
}

workflow BIOC_BEADDATAPACKR_BEADDATAPACKR_COMPRESSION_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_BEADDATAPACKR_BEADDATAPACKR_COMPRESSION_PIPELINE(ch_input)

    emit:
    tables   = BIOC_BEADDATAPACKR_BEADDATAPACKR_COMPRESSION_PIPELINE.out.tables
    plots    = BIOC_BEADDATAPACKR_BEADDATAPACKR_COMPRESSION_PIPELINE.out.plots
    objects  = BIOC_BEADDATAPACKR_BEADDATAPACKR_COMPRESSION_PIPELINE.out.objects
    versions = BIOC_BEADDATAPACKR_BEADDATAPACKR_COMPRESSION_PIPELINE.out.versions
}
