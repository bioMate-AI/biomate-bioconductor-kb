#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: gtrellis — gtrellis_genome_visualization
// Visualize genomic intervals and associated scores across custom chromosomes using a multi-track genome-level Trellis layout.
// Input: regions.bed, coldata.csv
// Container: 1.42.1--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, gtrellis, rtracklayer
// Visualizations: plot (ggplot/base)
// QC: missing-value handling
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GTRELLIS_GTRELLIS_GENOME_VISUALIZATION {
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
    .bm_deps <- c("gtrellis", "GenomicRanges", "rtracklayer")
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
    library(gtrellis)
    library(GenomicRanges)
    library(rtracklayer)
    library(grid)
    
    # --- Import and preprocess input data ---
    message("Reading input files...")
    if (!file.exists("regions.bed")) {
      stop("Required input file 'regions.bed' is missing.")
    }
    
    # Import BED file
    gr <- rtracklayer::import("regions.bed", format = "BED")
    
    # Ensure essential columns exist
    if (!"score" %in% colnames(mcols(gr)) || all(is.na(gr\$score))) {
      message("Score column missing or empty; generating dummy scores for visualization.")
      gr\$score <- seq_len(length(gr))
    }
    if (!"name" %in% colnames(mcols(gr))) {
      gr\$name <- paste0("region_", seq_len(length(gr)))
    }
    
    # Read optional metadata
    coldata <- NULL
    if (file.exists("coldata.csv")) {
      tryCatch({
        coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
        message("Successfully loaded coldata.csv metadata.")
      }, error = function(e) {
        warning("Failed to read coldata.csv: ", e\$message)
      })
    }
    
    # Integrate metadata if available
    pt_cols <- rep("blue", length(gr))
    if (!is.null(coldata) && "name" %in% colnames(coldata)) {
      # Match metadata by region name
      m <- match(gr\$name, coldata\$name)
      
      # If a 'group' column exists, use it for color mapping
      if ("group" %in% colnames(coldata)) {
        gr\$group <- coldata\$group[m]
        unique_groups <- unique(na.omit(gr\$group))
        if (length(unique_groups) > 0) {
          group_cols <- rainbow(length(unique_groups))
          names(group_cols) <- unique_groups
          pt_cols <- group_cols[gr\$group]
          pt_cols[is.na(pt_cols)] <- "grey"
        }
      }
    }
    gr\$pt_color <- pt_cols
    
    # --- Define custom genomic categories (chromosomes) ---
    chroms <- as.character(unique(seqnames(gr)))
    chrom_lengths <- sapply(chroms, function(chr) {
      max(end(gr[seqnames(gr) == chr]))
    })
    
    # Create GRanges representing the genome layout
    category_gr <- GRanges(seqnames = chroms, ranges = IRanges(start = 1, end = chrom_lengths))
    
    # --- Compute and write summary statistics ---
    message("Computing genomic summary statistics...")
    summary_df <- data.frame(
      chromosome = chroms,
      region_count = as.integer(table(seqnames(gr))[chroms]),
      total_coverage_bp = sapply(chroms, function(chr) sum(width(gr[seqnames(gr) == chr]))),
      mean_score = sapply(chroms, function(chr) mean(gr[seqnames(gr) == chr]\$score, na.rm = TRUE)),
      max_score = sapply(chroms, function(chr) max(gr[seqnames(gr) == chr]\$score, na.rm = TRUE))
    )
    write.csv(summary_df, "genomic_summary.csv", row.names = FALSE)
    message("Saved summary statistics to 'genomic_summary.csv'.")
    
    # --- Initialize and plot Trellis layout ---
    message("Generating Trellis visualization...")
    pdf("gtrellis_genome_plot.pdf", width = 12, height = 8)
    
    tryCatch({
      # Initialize layout with 2 tracks:
      # Track 1: Region scores (points)
      # Track 2: Region intervals (rectangles)
      gtrellis_layout(
        category = category_gr,
        n_track = 2,
        track_height = c(1.5, 1),
        ncol = 3,
        byrow = TRUE,
        title = "Genome-wide Trellis Visualization of Genomic Regions",
        track_axis = c(TRUE, FALSE),
        track_margin = unit(c(2, 2), "mm")
      )
      
      # Track 1: Plot scores as points
      ylim_score <- range(gr\$score, na.rm = TRUE)
      if (any(is.na(ylim_score)) || ylim_score[1] == ylim_score[2]) {
        ylim_score <- c(0, 1)
      }
      
      add_track(gr, track = 1, ylim = ylim_score, panel_fun = function(gr_sub) {
        if (length(gr_sub) > 0) {
          x <- (start(gr_sub) + end(gr_sub)) / 2
          y <- gr_sub\$score
          cols <- gr_sub\$pt_color
          grid.points(x, y, gp = gpar(col = cols, cex = 0.6, pch = 16), default.units = "native")
        }
      })
      
      # Track 2: Plot intervals as rectangles
      add_track(gr, track = 2, ylim = c(0, 1), panel_fun = function(gr_sub) {
        if (length(gr_sub) > 0) {
          # Draw a baseline
          grid.lines(c(0, 1), c(0.5, 0.5), default.units = "npc", gp = gpar(col = "grey80", lty = "dashed"))
          
          # Draw rectangles for each interval
          x_start <- start(gr_sub)
          x_end <- end(gr_sub)
          
          # Color code by strand if available
          rect_cols <- rep("orange", length(gr_sub))
          if ("strand" %in% colnames(mcols(gr_sub))) {
            rect_cols[strand(gr_sub) == "+"] <- "firebrick"
            rect_cols[strand(gr_sub) == "-"] <- "darkgreen"
          }
          
          grid.rect(
            x = (x_start + x_end) / 2,
            y = 0.5,
            width = (x_end - x_start + 1),
            height = 0.4,
            default.units = "native",
            gp = gpar(fill = rect_cols, col = NA)
          )
        }
      })
      
      message("Successfully rendered Trellis plot.")
    }, error = function(e) {
      message("Error during Trellis plotting: ", e\$message)
    })
    
    dev.off()
    message("Saved visualization to 'gtrellis_genome_plot.pdf'.")

    writeLines(c(
        '"BIOC_GTRELLIS_GTRELLIS_GENOME_VISUALIZATION":',
        paste0('    gtrellis: ', as.character(packageVersion('gtrellis')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gtrellis_genome_visualization.csv versions.yml
    """
}

workflow BIOC_GTRELLIS_GTRELLIS_GENOME_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_GTRELLIS_GTRELLIS_GENOME_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_GTRELLIS_GTRELLIS_GENOME_VISUALIZATION.out.tables
    plots    = BIOC_GTRELLIS_GTRELLIS_GENOME_VISUALIZATION.out.plots
    objects  = BIOC_GTRELLIS_GTRELLIS_GENOME_VISUALIZATION.out.objects
    versions = BIOC_GTRELLIS_GTRELLIS_GENOME_VISUALIZATION.out.versions
}
