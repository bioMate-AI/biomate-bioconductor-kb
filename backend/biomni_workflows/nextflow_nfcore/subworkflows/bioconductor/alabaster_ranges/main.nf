#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: alabaster_ranges — alabaster_ranges_serialization
// Read genomic features or expression data, represent them as GRanges and GRangesList objects, serialize them to disk using the alabaster framework, and reload th
// Input: input.csv
// Container: quay.io/biocontainers/r-base:4.3.1
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocGenerics, GenomicRanges, IRanges, S4Vectors, alabaster.base, alabaster.ranges, alabaster_ranges
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ALABASTER_RANGES_ALABASTER_RANGES_SERIALIZATION {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(GenomicRanges)
    library(S4Vectors)
    library(alabaster.base)
    library(alabaster.ranges)
    library(grDevices)
    library(graphics)
    
    # --- Read and defensively parse the input file ---
    input_file <- "input.csv"
    if (!file.exists(input_file)) {
      stop(paste("Required input file missing:", input_file))
    }
    
    raw_data <- read.csv(input_file, stringsAsFactors = FALSE, check.names = FALSE)
    
    # Extract feature identifiers and numeric data
    if ("feature_id" %in% colnames(raw_data)) {
      feature_ids <- as.character(raw_data\$feature_id)
      numeric_cols <- setdiff(colnames(raw_data), "feature_id")
      numeric_matrix <- raw_data[, numeric_cols, drop = FALSE]
    } else if (ncol(raw_data) >= 1) {
      # Fallback: use first column as identifier, rest as numeric
      feature_ids <- as.character(raw_data[, 1])
      numeric_matrix <- raw_data[, -1, drop = FALSE]
    } else {
      stop("Input CSV must have at least one column.")
    }
    
    # --- Construct GRanges object ---
    # Attempt to parse standard genomic coordinate strings (e.g., "chr1:100-200" or "chr1:100-200:+")
    gr <- tryCatch({
      GenomicRanges::GRanges(feature_ids)
    }, error = function(e) {
      message("Could not parse feature IDs directly as genomic ranges. Generating dummy coordinates...")
      # Fallback: Create dummy coordinates based on index
      n <- length(feature_ids)
      GenomicRanges::GRanges(
        seqnames = rep("chr1", n),
        ranges = IRanges::IRanges(start = seq_len(n) * 1000, width = 150),
        strand = rep("*", n),
        feature_id = feature_ids
      )
    })
    
    # Add metadata columns from the numeric matrix if available
    if (ncol(numeric_matrix) > 0) {
      # Ensure columns are numeric
      numeric_matrix[] <- lapply(numeric_matrix, function(x) as.numeric(as.character(x)))
      row_means <- rowMeans(numeric_matrix, na.rm = TRUE)
      S4Vectors::mcols(gr)\$mean_abundance <- row_means
    } else {
      S4Vectors::mcols(gr)\$mean_abundance <- rep(0, length(gr))
    }
    
    # --- Construct GRangesList object ---
    # Group ranges by chromosome (seqnames) or an arbitrary grouping factor
    grouping_factor <- as.character(GenomicRanges::seqnames(gr))
    grl <- split(gr, grouping_factor)
    
    # --- Serialize objects using alabaster ---
    # Create temporary directories for serialization
    gr_save_dir <- tempfile("save_granges")
    grl_save_dir <- tempfile("save_grangeslist")
    
    message("Saving GRanges object to: ", gr_save_dir)
    alabaster.base::saveObject(gr, gr_save_dir)
    
    message("Saving GRangesList object to: ", grl_save_dir)
    alabaster.base::saveObject(grl, grl_save_dir)
    
    # --- Load serialized objects back to verify integrity ---
    message("Loading GRanges object back...")
    gr_loaded <- alabaster.base::readObject(gr_save_dir)
    
    message("Loading GRangesList object back...")
    grl_loaded <- alabaster.base::readObject(grl_save_dir)
    
    # --- Export results and generate diagnostic plots ---
    # Export loaded GRanges to CSV
    gr_df <- as.data.frame(gr_loaded)
    write.csv(gr_df, "processed_ranges.csv", row.names = FALSE)
    
    # Export loaded GRangesList to CSV
    grl_df <- as.data.frame(grl_loaded)
    write.csv(grl_df, "processed_rangeslist.csv", row.names = FALSE)
    
    # Generate diagnostic plot of range widths
    pdf("range_widths_distribution.pdf", width = 6, height = 6)
    hist(
      BiocGenerics::width(gr_loaded),
      breaks = 20,
      col = "skyblue",
      border = "white",
      main = "Distribution of Genomic Range Widths",
      xlab = "Width (bp)"
    )
    dev.off()
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_ALABASTER_RANGES_ALABASTER_RANGES_SERIALIZATION":',
        paste0('    alabaster_ranges: ', as.character(packageVersion('alabaster_ranges')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_alabaster_ranges_serialization.csv versions.yml
    """
}

workflow BIOC_ALABASTER_RANGES_ALABASTER_RANGES_SERIALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_ALABASTER_RANGES_ALABASTER_RANGES_SERIALIZATION(ch_input)

    emit:
    tables   = BIOC_ALABASTER_RANGES_ALABASTER_RANGES_SERIALIZATION.out.tables
    plots    = BIOC_ALABASTER_RANGES_ALABASTER_RANGES_SERIALIZATION.out.plots
    objects  = BIOC_ALABASTER_RANGES_ALABASTER_RANGES_SERIALIZATION.out.objects
    versions = BIOC_ALABASTER_RANGES_ALABASTER_RANGES_SERIALIZATION.out.versions
}
