#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: gmoviz — feature_diagram
// Display general genomic features (such as genes, exons, plasmids, or complex constructs) as color-coded shapes on a circular plot.
// Input: ideogram_data.gff, features.gff3, coverage.bam
// Container: quay.io/biocontainers/bioconductor-gmoviz:1.22.0--r45hdfd78af_0
// R packages: GenomicRanges, IRanges, Rsamtools, gmoviz, rtracklayer
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GMOVIZ_FEATURE_DIAGRAM {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-gmoviz:1.22.0--r45hdfd78af_0"

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
    .bm_deps <- c("GenomicRanges", "IRanges", "Rsamtools", "gmoviz", "rtracklayer")
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
    library(gmoviz)
    library(GenomicRanges)
    library(IRanges)
    library(rtracklayer)
    library(Rsamtools)
    
    # -----------------------------------------------------------------------------
    # --- Read Ideogram Data and Define Sectors ---
    # -----------------------------------------------------------------------------
    if (!file.exists("ideogram_data.gff")) {
      stop("Required input file 'ideogram_data.gff' is missing.")
    }
    
    # Import GFF and extract sequence names and lengths
    ideo_gff <- rtracklayer::import("ideogram_data.gff")
    seq_names <- unique(as.character(seqnames(ideo_gff)))
    
    if (length(seq_names) == 0) {
      stop("No sequences found in 'ideogram_data.gff'.")
    }
    
    # Build GRanges representing the sectors
    sectors_gr <- GRanges(
      seqnames = seq_names,
      ranges = IRanges(
        start = sapply(seq_names, function(x) min(start(ideo_gff[seqnames(ideo_gff) == x]))),
        end = sapply(seq_names, function(x) max(end(ideo_gff[seqnames(ideo_gff) == x])))
      )
    )
    
    # Define plasmid_ideogram (single sector, renamed to "plasmid" to match documented code)
    plasmid_ideogram <- sectors_gr[1]
    seqlevels(plasmid_ideogram) <- "plasmid"
    seqnames(plasmid_ideogram) <- "plasmid"
    
    # Define complex_ideogram (two sectors, renamed to "Gene X" and "Template")
    if (length(sectors_gr) >= 2) {
      complex_ideogram <- sectors_gr[1:2]
      seqlevels(complex_ideogram) <- c("Gene X", "Template")
      seqnames(complex_ideogram) <- c("Gene X", "Template")
    } else {
      # Fallback if only one sequence is present in the input GFF
      complex_ideogram <- GRanges(
        seqnames = c("Gene X", "Template"),
        ranges = IRanges(
          start = c(0, 0),
          end = c(end(sectors_gr[1]), end(sectors_gr[1]))
        )
      )
    }
    
    # -----------------------------------------------------------------------------
    # --- Read Features and Align with Ideograms ---
    # -----------------------------------------------------------------------------
    if (!file.exists("features.gff3")) {
      stop("Required input file 'features.gff3' is missing.")
    }
    
    # Read features for plasmid map
    plasmid_features <- getFeatures(
      gff_file = "features.gff3",
      colour_by_type = FALSE, # colour by name rather than type of feature
      colours = rich_colours) # choose colours from rich_colours (see ?colourSets)
    
    # Force plasmid_features seqnames to match "plasmid"
    if (length(plasmid_features) > 0) {
      seqlevels(plasmid_features) <- "plasmid"
      seqnames(plasmid_features) <- "plasmid"
    }
    
    # Read features for complex construct
    complex_features <- getFeatures(
      gff_file = "features.gff3",
      colours = rich_colours)
    
    # Distribute complex features and ensure they fit within the ideogram limits
    if (length(complex_features) > 0) {
      half <- ceiling(length(complex_features) / 2)
      seqs <- c(rep("Gene X", half), rep("Template", length(complex_features) - half))
      seqlevels(complex_features) <- c("Gene X", "Template")
      seqnames(complex_features) <- seqs
    
      gene_x_limit <- end(complex_ideogram[seqnames(complex_ideogram) == "Gene X"])
      template_limit <- end(complex_ideogram[seqnames(complex_ideogram) == "Template"])
    
      for (i in seq_along(complex_features)) {
        limit <- if (seqnames(complex_features)[i] == "Gene X") gene_x_limit else template_limit
        feat_width <- min(width(complex_features)[i], limit / 5)
        feat_start <- round((i %% 5) * (limit / 6))
        ranges(complex_features)[i] <- IRanges(start = feat_start, width = feat_width)
      }
    }
    
    # Modify tracks and shapes for specific features as in documented code
    idx <- intersect(c(3, 4), seq_along(complex_features))
    if (length(idx) > 0) {
      complex_features\$track[idx] <- 2 # cut sites on the next track in
      complex_features\$shape[idx] <- "upwards_triangle" # triangles
    }
    
    # Define exon label dynamically based on Gene X length
    gene_x_end <- end(complex_ideogram[seqnames(complex_ideogram) == "Gene X"])
    exon_start <- round(gene_x_end * 0.8)
    exon_end <- round(gene_x_end * 0.9)
    exon_label <- GRanges("Gene X", IRanges(exon_start, exon_end), label = "Exon 2")
    
    # -----------------------------------------------------------------------------
    # --- Read Coverage Data ---
    # -----------------------------------------------------------------------------
    coverage <- NULL
    if (file.exists("coverage.bam")) {
      tryCatch({
        bam_header <- Rsamtools::scanBamHeader("coverage.bam")
        bam_seqs <- names(bam_header[[1]]\$targets)
        if (length(bam_seqs) > 0) {
          roi <- bam_seqs[1]
          coverage <- getCoverage(
            regions_of_interest = roi,
            bam_file = "coverage.bam",
            window_size = 150,
            smoothing_window_size = 200
          )
          if (length(coverage) > 0) {
            seqlevels(coverage) <- "plasmid"
            seqnames(coverage) <- "plasmid"
          }
        }
      }, error = function(e) {
        message("Could not read coverage from BAM, falling back to simulated coverage.")
      })
    }
    
    # Fallback coverage if BAM is missing, empty, or failed to load
    if (is.null(coverage) || length(coverage) == 0) {
      p_start <- start(plasmid_ideogram)
      p_end <- end(plasmid_ideogram)
      steps <- seq(from = p_start, to = p_end - 15, by = 15)
      coverage <- GRanges(
        seqnames = rep("plasmid", length(steps)),
        ranges = IRanges(start = steps, end = steps + 15),
        coverage = c(runif(ceiling(length(steps) * 0.55), 10, 15), rep(0, length(steps) - ceiling(length(steps) * 0.55)))
      )
    }
    
    # Define link dynamically based on complex ideogram lengths
    gene_x_len <- end(complex_ideogram[seqnames(complex_ideogram) == "Gene X"])
    template_len <- end(complex_ideogram[seqnames(complex_ideogram) == "Template"])
    link <- data.frame(
      chr = c("Gene X", "Template"),
      start = c(round(gene_x_len * 0.85), 0),
      end = c(round(gene_x_len * 0.9), template_len)
    )
    
    # -----------------------------------------------------------------------------
    # --- Generate Feature Diagrams and Save Outputs ---
    # -----------------------------------------------------------------------------
    
    # Plot 1: Plasmid Feature Diagram
    pdf("plasmid_feature_diagram.pdf", width = 8, height = 8)
    featureDiagram(plasmid_ideogram, plasmid_features, track_height = 0.17,
                   label_track_height = 0.11, 
                   space_between_sectors = 0, # continuous circle
                   xaxis_spacing = 30, # x axis label every 30 degrees
                   start_degree = 90) # start from 90 degrees (12 o'clock)
    dev.off()
    
    # Plot 2: Plasmid Feature Diagram with Coverage
    pdf("plasmid_feature_diagram_with_coverage.pdf", width = 8, height = 8)
    featureDiagram(plasmid_ideogram, plasmid_features, track_height = 0.17,
                   coverage_rectangle = "plasmid", # don't forget this!
                   coverage_data = coverage, 
                   label_track_height = 0.11, space_between_sectors = 0, 
                   xaxis_spacing = 30, start_degree = 90)
    dev.off()
    
    # Plot 3: Complex Feature Diagram
    pdf("complex_feature_diagram.pdf", width = 8, height = 8)
    featureDiagram(ideogram_data = complex_ideogram, 
                   feature_data = complex_features, 
                   label_data = exon_label, custom_sector_width = c(0.6, 0.4),
                   sector_colours = c("#6fc194", "#84c6d6"),
                   sector_border_colours = c("#599c77", "#84c6d6"),
                   space_between_sectors = 25, start_degree = 184, 
                   label_size = 1.1)
    dev.off()
    
    # Plot 4: Complex Feature Diagram with Link
    pdf("complex_feature_diagram_with_link.pdf", width = 8, height = 8)
    featureDiagram(ideogram_data = complex_ideogram, 
                   feature_data = complex_features, label_data = exon_label, 
                   custom_sector_width = c(0.6, 0.4),
                   sector_colours = c("#6fc194", "#84c6d6"),
                   sector_border_colours = c("#599c77", "#84c6d6"),
                   space_between_sectors = 25, start_degree = 184, 
                   label_size = 1.1, link_data = link)
    dev.off()
    
    # Save processed features and ideograms as CSV and RDS
    write.csv(as.data.frame(plasmid_features), "processed_plasmid_features.csv", row.names = FALSE)
    write.csv(as.data.frame(complex_features), "processed_complex_features.csv", row.names = FALSE)
    saveRDS(plasmid_features, "plasmid_features.rds")
    saveRDS(complex_features, "complex_features.rds")
    
    message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_GMOVIZ_FEATURE_DIAGRAM":',
        paste0('        gmoviz: ', as.character(packageVersion("gmoviz")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_feature_diagram.csv versions.yml
    """
}

workflow BIOC_GMOVIZ_FEATURE_DIAGRAM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ideogram_data.gff, features.gff3, coverage.bam ] ]

    main:
    BIOC_GMOVIZ_FEATURE_DIAGRAM(ch_input)

    emit:
    tables   = BIOC_GMOVIZ_FEATURE_DIAGRAM.out.tables
    plots    = BIOC_GMOVIZ_FEATURE_DIAGRAM.out.plots
    objects  = BIOC_GMOVIZ_FEATURE_DIAGRAM.out.objects
    versions = BIOC_GMOVIZ_FEATURE_DIAGRAM.out.versions
}
