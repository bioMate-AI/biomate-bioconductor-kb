#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: gmoviz — incremental_plotting
// Build a highly customized circular plot track-by-track, combining features, scatterplots, line graphs, and legends.
// Input: coverage.bam, features.gff3, numeric_data.txt
// Container: quay.io/biocontainers/bioconductor-gmoviz:1.22.0--r45hdfd78af_0
// R packages: GenomicRanges, IRanges, Rsamtools, gmoviz
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GMOVIZ_INCREMENTAL_PLOTTING {
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
    .bm_deps <- c("GenomicRanges", "IRanges", "Rsamtools", "gmoviz")
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
    library(Rsamtools)
    
    # 1. Determine target chromosome from BAM file dynamically (defaulting to chr4 if present)
    bam_file_path <- "coverage.bam"
    bam_header <- Rsamtools::scanBamHeader(bam_file_path)
    targets <- names(bam_header[[1]]\$targets)
    target_chr <- if ("chr4" %in% targets) "chr4" else targets[1]
    
    # 2. Read ideogram, coverage, labels, and features from files
    fly_ideogram_chr4_only <- getIdeogramData(
      bam_file = bam_file_path,
      wanted_chr = target_chr
    )
    
    chr4_coverage <- getCoverage(
      regions_of_interest = target_chr, 
      bam_file = bam_file_path,
      window_size = 350, smoothing_window_size = 400
    )
    
    labels_from_file <- getLabels(
      gff_file = "features.gff3",
      colour_code = TRUE
    )
    
    features <- getFeatures(
      gff_file = "features.gff3", 
      colours = gmoviz::rich_colours
    )
    
    # 3. Read numeric data from file and construct GRanges object
    numeric_df <- read.table("numeric_data.txt", header = TRUE, stringsAsFactors = FALSE)
    start_col <- if ("start" %in% colnames(numeric_df)) "start" else colnames(numeric_df)[1]
    value_col <- if ("value" %in% colnames(numeric_df)) "value" else {
      val_idx <- which(colnames(numeric_df) != start_col)[1]
      colnames(numeric_df)[val_idx]
    }
    
    numeric_data <- GRanges(
      seqnames = rep(target_chr, nrow(numeric_df)),
      ranges = IRanges(start = numeric_df[[start_col]], width = 1),
      value = numeric_df[[value_col]]
    )
    
    # 4. Create legend objects
    legend <- makeLegends(
        feature_legend = TRUE, feature_data = features, 
        feature_legend_title = "Regions of interest", scatterplot_legend = TRUE,
        scatterplot_legend_title = "Numeric data", 
        scatterplot_legend_labels = "value"
    )
    
    # 5. Initialize the plot and draw tracks incrementally inside gmovizPlot
    gmovizPlot(file_name = "example.svg", file_type = "svg", 
               plotting_functions = {
        gmovizInitialise(
            fly_ideogram_chr4_only, space_between_sectors = 25, start_degree = 78,
            xaxis_spacing = 30, sector_label_size = 1)
        drawScatterplotTrack(
            numeric_data, track_height = 0.14, yaxis_increment = 12)
        drawFeatureTrack(
            features, feature_label_cutoff = 80000, track_height = 0.15)
    }, legends = legend, title = "Chromosome 4", background_colour = "white",
    width = 8, height = 5.33, units = "in")
    
    # 6. Write named output files for the meaningful results
    write.csv(as.data.frame(labels_from_file), "labels.csv", row.names = FALSE)
    write.csv(as.data.frame(features), "features.csv", row.names = FALSE)
    saveRDS(chr4_coverage, "coverage.rds")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_GMOVIZ_INCREMENTAL_PLOTTING":
        gmoviz: \$(Rscript -e 'cat(as.character(packageVersion("gmoviz")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_incremental_plotting.csv versions.yml
    """
}

workflow BIOC_GMOVIZ_INCREMENTAL_PLOTTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ coverage.bam, features.gff3, numeric_data.txt ] ]

    main:
    BIOC_GMOVIZ_INCREMENTAL_PLOTTING(ch_input)

    emit:
    tables   = BIOC_GMOVIZ_INCREMENTAL_PLOTTING.out.tables
    plots    = BIOC_GMOVIZ_INCREMENTAL_PLOTTING.out.plots
    objects  = BIOC_GMOVIZ_INCREMENTAL_PLOTTING.out.objects
    versions = BIOC_GMOVIZ_INCREMENTAL_PLOTTING.out.versions
}
